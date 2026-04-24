import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:robot_protocol/robot_protocol.dart';

import 'connection/reconnect_policy.dart';
import 'models/connection_options.dart';
import 'models/connection_state.dart';
import 'queue/command_queue.dart';
import 'transports/ble_discovered_device.dart';
import 'transports/ble_transport.dart';
import 'transports/mqtt_transport.dart';
import 'transports/tcp_transport.dart';
import 'transports/transport.dart';

typedef RobotTransportFactory = RobotTransport Function(
  TransportKind transport,
  Object options,
);

class RobotClient {
  RobotClient({
    this.ackTimeout = const Duration(milliseconds: 100),
    this.maxRetries = 3,
    ReconnectPolicy? reconnectPolicy,
    @visibleForTesting RobotTransportFactory? transportFactory,
  })  : reconnectPolicy = reconnectPolicy ?? const NoReconnectPolicy(),
        _transportFactory = transportFactory ?? _defaultTransportFactory;

  final Duration ackTimeout;
  final int maxRetries;
  final ReconnectPolicy reconnectPolicy;
  final CommandQueue _queue = CommandQueue();
  final StreamController<RobotState> _stateController =
      StreamController<RobotState>.broadcast();
  final StreamController<RobotFrame> _frameController =
      StreamController<RobotFrame>.broadcast();
  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast();
  final StreamController<RobotConnectionState> _connectionController =
      StreamController<RobotConnectionState>.broadcast();
  final RobotTransportFactory _transportFactory;

  RobotTransport? _transport;
  StreamSubscription<RobotFrame>? _frameSubscription;
  Timer? _retryTimer;
  Timer? _reconnectTimer;
  RobotConnectionState _connection = RobotConnectionState.idle();
  TransportKind _transportKind = TransportKind.none;
  Object? _transportOptions;
  bool _manualDisconnect = false;
  bool _handlingTransportFailure = false;
  int _reconnectAttempt = 0;
  int _nextSeq = 0;

  Stream<RobotState> get stateStream => _stateController.stream;

  Stream<RobotFrame> get frameStream => _frameController.stream;

  Stream<Object> get errors => _errorController.stream;

  Stream<RobotConnectionState> get connectionState =>
      Stream<RobotConnectionState>.multi(
        (controller) {
          controller.add(_connection);
          final subscription = _connectionController.stream.listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
          controller.onCancel = subscription.cancel;
        },
        isBroadcast: true,
      );

  RobotConnectionState get currentConnection => _connection;

  bool get isConnected => _connection.status == ConnectionStatus.connected;

  Stream<BleDiscoveredDevice> scanBLE({
    Duration timeout = const Duration(seconds: 10),
    Set<String>? withServices,
  }) {
    return BleTransport.scan(
      withServices: withServices,
      timeout: timeout,
    );
  }

  Future<void> connectBLE({
    BleConnectionOptions options = const BleConnectionOptions(),
  }) async {
    await _connectWith(TransportKind.ble, options);
  }

  Future<void> connectTCP({
    TcpConnectionOptions options = const TcpConnectionOptions(),
  }) async {
    await _connectWith(TransportKind.tcp, options);
  }

  Future<void> connectMQTT({
    MqttConnectionOptions options = const MqttConnectionOptions(),
  }) async {
    await _connectWith(TransportKind.mqtt, options);
  }

  Future<void> connect(RobotConnectionConfig config) async {
    final selection = _selectTransport(config);
    if (selection == null) {
      final error = StateError(
        'RobotConnectionConfig does not contain options for the requested priority list',
      );
      _errorController.add(error);
      _emitConnectionState(
        transport: TransportKind.none,
        status: ConnectionStatus.failed,
        errorCode: connectionErrorMissingOptions,
        errorMessage: error.toString(),
      );
      throw error;
    }

    await _connectWith(selection.transport, selection.options);
  }

  Future<void> switchTransport({
    required TransportKind target,
    BleConnectionOptions? ble,
    TcpConnectionOptions? tcp,
    MqttConnectionOptions? mqtt,
  }) async {
    final options = _optionsForTransport(
      target,
      ble: ble,
      tcp: tcp,
      mqtt: mqtt,
    );
    if (options == null) {
      final error = StateError(
        'Missing connection options for transport $target',
      );
      _errorController.add(error);
      _emitConnectionState(
        transport: target,
        status: ConnectionStatus.failed,
        errorCode: connectionErrorMissingOptions,
        errorMessage: error.toString(),
      );
      throw error;
    }

    await _connectWith(target, options);
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _cancelReconnectTimer();
    _reconnectAttempt = 0;
    await _detachTransport(clearTransportContext: true);
    _emitConnectionState(
      transport: TransportKind.none,
      status: ConnectionStatus.idle,
      clearError: true,
    );
    _manualDisconnect = false;
  }

  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
    await _frameController.close();
    await _errorController.close();
    await _connectionController.close();
  }

  Future<void> move(double vx, double vy, double yaw) async {
    await _enqueueCommand(MoveCommand(vx: vx, vy: vy, yaw: yaw));
  }

  Future<void> stand() async {
    await _enqueueCommand(const DiscreteCommand(CommandId.stand));
  }

  Future<void> sit() async {
    await _enqueueCommand(const DiscreteCommand(CommandId.sit));
  }

  Future<void> stop() async {
    await _enqueueCommand(const DiscreteCommand(CommandId.stop));
  }

  Future<void> doAction(
    int actionId, {
    bool requireAck = true,
  }) async {
    await _enqueueCommand(
      SkillInvokeCommand.doAction(
        actionId: actionId,
        requireAck: requireAck,
      ),
    );
  }

  Future<void> doDogBehavior(
    DogBehavior behavior, {
    bool requireAck = true,
  }) async {
    await _enqueueCommand(
      SkillInvokeCommand.doDogBehavior(
        behavior: behavior,
        requireAck: requireAck,
      ),
    );
  }

  Future<void> _enqueueCommand(RobotCommand command) async {
    final seq = _nextSequence();
    final frameBytes = encodeFrame(buildCommandFrame(command, seq));
    _queue.enqueue(
      QueuedCommand(
        seq: seq,
        command: command,
        frameBytes: frameBytes,
        isMove: command.isMove,
      ),
    );
    await _pumpQueue();
  }

  Future<void> _pumpQueue() async {
    final transport = _transport;
    if (transport == null ||
        !transport.isConnected ||
        _queue.inflight != null) {
      return;
    }

    final next = _queue.promoteNext(DateTime.now());
    if (next == null) {
      return;
    }

    try {
      await transport.send(next.frameBytes);
    } catch (error) {
      _errorController.add(error);
      await _handleTransportFailure(error);
    }
  }

  void _handleFrame(RobotFrame frame) {
    _frameController.add(frame);
    if (frame.type == FrameType.state) {
      _stateController.add(parseStatePayload(frame.payload));
      return;
    }

    if (frame.type == FrameType.ack) {
      final ackSeq = parseAckPayload(frame.payload);
      if (_queue.acknowledge(ackSeq)) {
        unawaited(_pumpQueue());
      }
    }
  }

  void _handleFrameError(Object error, StackTrace _) {
    _errorController.add(error);
    unawaited(_handleTransportFailure(error));
  }

  void _onRetryTick(Timer _) {
    final transport = _transport;
    if (transport == null) {
      return;
    }
    if (!transport.isConnected) {
      unawaited(
        _handleTransportFailure(
          StateError('Transport $_transportKind disconnected unexpectedly'),
        ),
      );
      return;
    }

    final current = _queue.inflight;
    if (current == null) {
      if (_queue.hasPending) {
        unawaited(_pumpQueue());
      }
      return;
    }

    final lastSentAt = current.lastSentAt;
    if (lastSentAt != null &&
        DateTime.now().difference(lastSentAt) < ackTimeout) {
      return;
    }

    final retried = _queue.retryCurrent(DateTime.now(), maxRetries);
    if (retried == null) {
      _errorController.add(
        StateError(
          'Command seq=${current.seq} failed after $maxRetries retries',
        ),
      );
      unawaited(_pumpQueue());
      return;
    }

    unawaited(
      transport.send(retried.frameBytes).catchError((
        Object error,
        StackTrace stackTrace,
      ) async {
        _errorController.add(error);
        await _handleTransportFailure(error);
      }),
    );
  }

  Future<void> _connectWith(TransportKind transport, Object options) async {
    _manualDisconnect = false;
    _cancelReconnectTimer();
    _reconnectAttempt = 0;
    _emitConnectionState(
      transport: transport,
      status: ConnectionStatus.connecting,
      clearError: true,
    );

    await _detachTransport(clearTransportContext: false);
    _transportKind = transport;
    _transportOptions = options;

    final nextTransport = _transportFactory(transport, options);
    _transport = nextTransport;
    _frameSubscription = nextTransport.frames.listen(
      _handleFrame,
      onError: _handleFrameError,
    );

    try {
      await nextTransport.connect();
      _startRetryTimer();
      _queue.resetInflightTiming();
      _emitConnectionState(
        transport: transport,
        status: ConnectionStatus.connected,
        clearError: true,
      );
      await _pumpQueue();
    } catch (error) {
      _errorController.add(error);
      await _detachTransport(clearTransportContext: false);
      _emitConnectionState(
        transport: transport,
        status: ConnectionStatus.failed,
        errorCode: _errorCodeForTransport(transport),
        errorMessage: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> _handleTransportFailure(Object error) async {
    if (_manualDisconnect || _handlingTransportFailure) {
      return;
    }

    final transport = _transportKind;
    final options = _transportOptions;
    if (transport == TransportKind.none || options == null) {
      return;
    }

    _handlingTransportFailure = true;
    try {
      _cancelReconnectTimer();
      await _detachTransport(clearTransportContext: false);

      final attempt = _reconnectAttempt + 1;
      final delay = await reconnectPolicy.nextDelay(
        transport: transport,
        attempt: attempt,
        lastError: error,
      );

      if (delay == null) {
        _emitConnectionState(
          transport: transport,
          status: ConnectionStatus.failed,
          errorCode: connectionErrorDisconnectedByPeer,
          errorMessage: error.toString(),
        );
        return;
      }

      _reconnectAttempt = attempt;
      _emitConnectionState(
        transport: transport,
        status: ConnectionStatus.reconnecting,
        errorCode: connectionErrorDisconnectedByPeer,
        errorMessage: error.toString(),
      );
      _reconnectTimer = Timer(delay, () {
        unawaited(_reconnect(transport, options));
      });
    } finally {
      _handlingTransportFailure = false;
    }
  }

  Future<void> _reconnect(TransportKind transport, Object options) async {
    if (_manualDisconnect) {
      return;
    }

    final nextTransport = _transportFactory(transport, options);
    _transport = nextTransport;
    _frameSubscription = nextTransport.frames.listen(
      _handleFrame,
      onError: _handleFrameError,
    );

    try {
      await nextTransport.connect();
      _startRetryTimer();
      _queue.resetInflightTiming();
      _reconnectAttempt = 0;
      _emitConnectionState(
        transport: transport,
        status: ConnectionStatus.connected,
        clearError: true,
      );
      await _pumpQueue();
    } catch (error) {
      _errorController.add(error);
      await _detachTransport(clearTransportContext: false);
      await _handleTransportFailure(error);
    }
  }

  Future<void> _detachTransport({
    required bool clearTransportContext,
  }) async {
    _retryTimer?.cancel();
    _retryTimer = null;

    final subscription = _frameSubscription;
    final transport = _transport;
    _frameSubscription = null;
    _transport = null;

    await subscription?.cancel();
    if (transport != null) {
      try {
        await transport.disconnect();
      } catch (error) {
        _errorController.add(error);
      }
    }

    if (clearTransportContext) {
      _transportKind = TransportKind.none;
      _transportOptions = null;
    }
  }

  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(
      const Duration(milliseconds: 20),
      _onRetryTick,
    );
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _emitConnectionState({
    required TransportKind transport,
    required ConnectionStatus status,
    String? errorCode,
    String? errorMessage,
    bool clearError = false,
  }) {
    _connection = RobotConnectionState(
      transport: transport,
      status: status,
      updatedAt: DateTime.now(),
      errorCode: clearError ? null : errorCode,
      errorMessage: clearError ? null : errorMessage,
    );
    _connectionController.add(_connection);
  }

  _TransportSelection? _selectTransport(RobotConnectionConfig config) {
    for (final transport in config.priority) {
      final options = _optionsForTransport(
        transport,
        ble: config.ble,
        tcp: config.tcp,
        mqtt: config.mqtt,
      );
      if (options != null) {
        return _TransportSelection(transport: transport, options: options);
      }
    }
    return null;
  }

  Object? _optionsForTransport(
    TransportKind transport, {
    BleConnectionOptions? ble,
    TcpConnectionOptions? tcp,
    MqttConnectionOptions? mqtt,
  }) {
    switch (transport) {
      case TransportKind.none:
        return null;
      case TransportKind.ble:
        return ble;
      case TransportKind.tcp:
        return tcp;
      case TransportKind.mqtt:
        return mqtt;
    }
  }

  static RobotTransport _defaultTransportFactory(
    TransportKind transport,
    Object options,
  ) {
    switch (transport) {
      case TransportKind.none:
        throw UnsupportedError('TransportKind.none cannot create a transport');
      case TransportKind.ble:
        return BleTransport(options as BleConnectionOptions);
      case TransportKind.tcp:
        return TcpTransport(options as TcpConnectionOptions);
      case TransportKind.mqtt:
        return MqttTransport(options as MqttConnectionOptions);
    }
  }

  String _errorCodeForTransport(TransportKind transport) {
    switch (transport) {
      case TransportKind.none:
        return connectionErrorUnsupportedTransport;
      case TransportKind.ble:
        return connectionErrorBleFailed;
      case TransportKind.tcp:
        return connectionErrorTcpFailed;
      case TransportKind.mqtt:
        return connectionErrorMqttFailed;
    }
  }

  int _nextSequence() {
    final seq = _nextSeq;
    _nextSeq = (_nextSeq + 1) & 0xFF;
    return seq;
  }
}

class _TransportSelection {
  const _TransportSelection({
    required this.transport,
    required this.options,
  });

  final TransportKind transport;
  final Object options;
}
