import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:robot_protocol/robot_protocol.dart';

import '../models/connection_options.dart';
import 'transport.dart';

/// Abstraction over an MQTT client connection so that [MqttTransport] can
/// be unit-tested without touching `mqtt_client`'s concrete types.
abstract class MqttClientSession {
  /// Completes when the connection handshake has finished. Throws on
  /// failure (auth rejected, broker unreachable, timeout).
  Future<void> connect();

  Future<void> disconnect();

  bool get isConnected;

  /// Resolves subscription acknowledgements, surfaced for logs/tests.
  Future<void> subscribe(String topic, MqttQosLevel qos);

  /// Publishes a binary payload to the control topic.
  Future<void> publish(String topic, Uint8List payload, MqttQosLevel qos);

  /// Stream of (topic, payload) pairs for every message received after
  /// [connect] succeeded, regardless of topic. [MqttTransport] filters.
  Stream<MqttInboundMessage> get messages;
}

class MqttInboundMessage {
  const MqttInboundMessage({required this.topic, required this.payload});

  final String topic;
  final Uint8List payload;
}

typedef MqttSessionFactory =
    MqttClientSession Function(MqttConnectionOptions options);

class MqttTransport implements RobotTransport {
  MqttTransport(this.options, {MqttSessionFactory? sessionFactory})
    : _sessionFactory = sessionFactory ?? _defaultSessionFactory;

  final MqttConnectionOptions options;
  final MqttSessionFactory _sessionFactory;
  final StreamController<RobotFrame> _frames =
      StreamController<RobotFrame>.broadcast();
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamFrameDecoder _decoder = StreamFrameDecoder();

  MqttClientSession? _session;
  StreamSubscription<MqttInboundMessage>? _subscription;
  bool _isConnected = false;
  bool _disposed = false;

  @override
  Stream<RobotFrame> get frames => _frames.stream;

  /// JSON events delivered on `robot/{id}/event`. Consumers outside of
  /// [RobotClient] can use this to surface low-volume async events
  /// without leaking MQTT details.
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    if (_disposed) {
      throw StateError('MqttTransport has been disposed');
    }
    await disconnect();

    final session = _sessionFactory(options);
    _session = session;
    _subscription = session.messages.listen(_onMessage, onError: _onError);

    try {
      await session.connect().timeout(options.connectTimeout);
    } on TimeoutException catch (error, stackTrace) {
      await _releaseSession();
      _frames.addError(error, stackTrace);
      rethrow;
    } catch (error, stackTrace) {
      await _releaseSession();
      _frames.addError(error, stackTrace);
      rethrow;
    }

    _isConnected = session.isConnected;
    if (!_isConnected) {
      await _releaseSession();
      throw StateError('MQTT broker did not confirm connection');
    }

    await session.subscribe(options.stateTopic, options.qos);
    if (options.subscribeEvents) {
      await session.subscribe(options.eventTopic, options.qos);
    }
  }

  @override
  Future<void> disconnect() async {
    if (_session == null && !_isConnected) {
      return;
    }
    await _releaseSession();
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await disconnect();
    if (!_frames.isClosed) {
      await _frames.close();
    }
    if (!_events.isClosed) {
      await _events.close();
    }
  }

  @override
  Future<void> send(Uint8List bytes) async {
    final session = _session;
    if (session == null || !_isConnected) {
      throw StateError('MQTT transport is not connected');
    }
    await session.publish(options.controlTopic, bytes, options.qos);
  }

  void _onMessage(MqttInboundMessage message) {
    if (_frames.isClosed) {
      return;
    }
    if (message.topic == options.stateTopic) {
      try {
        for (final frame in _decoder.feed(message.payload)) {
          _frames.add(frame);
        }
      } catch (error, stackTrace) {
        _frames.addError(error, stackTrace);
      }
      return;
    }
    if (message.topic == options.eventTopic) {
      if (_events.isClosed) {
        return;
      }
      try {
        final decoded = jsonDecode(utf8.decode(message.payload));
        if (decoded is Map<String, dynamic>) {
          _events.add(decoded);
        }
      } catch (_) {
        // Ignore malformed JSON events silently; events are optional.
      }
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    _isConnected = false;
    if (!_frames.isClosed) {
      _frames.addError(error, stackTrace);
    }
  }

  Future<void> _releaseSession() async {
    final subscription = _subscription;
    final session = _session;
    _subscription = null;
    _session = null;
    _isConnected = false;

    await subscription?.cancel();
    if (session != null) {
      try {
        await session.disconnect();
      } catch (_) {
        // Disconnect is best-effort; brokers may have already dropped us.
      }
    }
  }

  static MqttClientSession _defaultSessionFactory(
    MqttConnectionOptions options,
  ) {
    return _MqttClientSessionImpl(options);
  }
}

class _MqttClientSessionImpl implements MqttClientSession {
  _MqttClientSessionImpl(this.options) {
    final clientId = options.clientId.isNotEmpty
        ? options.clientId
        : 'mobile-sdk-${options.robotId}-${_randomNonce()}';
    _client = MqttServerClient.withPort(options.host, clientId, options.port)
      ..keepAlivePeriod = options.keepAlive.inSeconds
      ..autoReconnect = true
      ..setProtocolV311()
      ..secure = options.useTls
      ..logging(on: false);
    _client.onDisconnected = _handleDisconnected;
  }

  final MqttConnectionOptions options;
  late final MqttServerClient _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;
  final StreamController<MqttInboundMessage> _messages =
      StreamController<MqttInboundMessage>.broadcast();

  @override
  bool get isConnected =>
      _client.connectionStatus?.state == MqttConnectionState.connected;

  @override
  Stream<MqttInboundMessage> get messages => _messages.stream;

  @override
  Future<void> connect() async {
    final status = await _client.connect(options.username, options.password);
    if (status == null ||
        status.state != MqttConnectionState.connected) {
      _client.disconnect();
      throw StateError(
        'MQTT connect failed: state=${status?.state} returnCode=${status?.returnCode}',
      );
    }
    _updatesSub = _client.updates?.listen(_handleUpdates);
  }

  @override
  Future<void> disconnect() async {
    await _updatesSub?.cancel();
    _updatesSub = null;
    _client.disconnect();
    if (!_messages.isClosed) {
      await _messages.close();
    }
  }

  @override
  Future<void> subscribe(String topic, MqttQosLevel qos) async {
    _client.subscribe(topic, _mapQos(qos));
  }

  @override
  Future<void> publish(
    String topic,
    Uint8List payload,
    MqttQosLevel qos,
  ) async {
    final builder = MqttClientPayloadBuilder();
    for (final byte in payload) {
      builder.addByte(byte);
    }
    _client.publishMessage(topic, _mapQos(qos), builder.payload!);
  }

  void _handleUpdates(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final message = event.payload;
      if (message is MqttPublishMessage) {
        final bytes = Uint8List.fromList(message.payload.message);
        _messages.add(MqttInboundMessage(topic: event.topic, payload: bytes));
      }
    }
  }

  void _handleDisconnected() {
    if (_messages.isClosed) {
      return;
    }
    _messages.addError(
      StateError('MQTT broker closed the connection'),
      StackTrace.current,
    );
  }

  MqttQos _mapQos(MqttQosLevel level) {
    switch (level) {
      case MqttQosLevel.atMostOnce:
        return MqttQos.atMostOnce;
      case MqttQosLevel.atLeastOnce:
        return MqttQos.atLeastOnce;
      case MqttQosLevel.exactlyOnce:
        return MqttQos.exactlyOnce;
    }
  }

  static String _randomNonce() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 6; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }
}
