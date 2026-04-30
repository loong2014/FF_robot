import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sdk/mobile_sdk.dart';

void main() {
  group('RobotClient connection management', () {
    test('connect selects first configured transport and emits state stream',
        () async {
      final bleTransport = _FakeTransport();
      final tcpTransport = _FakeTransport();
      final client = RobotClient(
        transportFactory: (transport, options) {
          if (transport == TransportKind.ble) {
            return bleTransport;
          }
          if (transport == TransportKind.tcp) {
            return tcpTransport;
          }
          throw UnsupportedError('Unexpected transport: $transport');
        },
      );
      final states = <RobotConnectionState>[];
      final subscription = client.connectionState.listen(states.add);

      await _flushAsync();
      await client.connect(
        const RobotConnectionConfig(
          priority: <TransportKind>[TransportKind.ble, TransportKind.tcp],
          ble: BleConnectionOptions(deviceId: 'robot-1'),
          tcp: TcpConnectionOptions(host: '10.0.0.2', port: 9000),
        ),
      );
      await _flushAsync();

      expect(bleTransport.connectCount, 1);
      expect(tcpTransport.connectCount, 0);
      expect(
        states.map((state) => '${state.transport}:${state.status}'),
        <String>[
          '${TransportKind.none}:${ConnectionStatus.idle}',
          '${TransportKind.ble}:${ConnectionStatus.connecting}',
          '${TransportKind.ble}:${ConnectionStatus.connected}',
        ],
      );

      await subscription.cancel();
      await client.dispose();
    });

    test('connect failure does not auto-fallback and emits failed state',
        () async {
      final bleTransport = _FakeTransport(
        connectError: StateError('ble unavailable'),
      );
      final tcpTransport = _FakeTransport();
      final client = RobotClient(
        transportFactory: (transport, options) {
          if (transport == TransportKind.ble) {
            return bleTransport;
          }
          if (transport == TransportKind.tcp) {
            return tcpTransport;
          }
          throw UnsupportedError('Unexpected transport: $transport');
        },
      );
      final states = <RobotConnectionState>[];
      final subscription = client.connectionState.listen(states.add);

      await _flushAsync();
      await expectLater(
        client.connect(
          const RobotConnectionConfig(
            priority: <TransportKind>[TransportKind.ble, TransportKind.tcp],
            ble: BleConnectionOptions(deviceId: 'robot-1'),
            tcp: TcpConnectionOptions(host: '10.0.0.2', port: 9000),
          ),
        ),
        throwsA(isA<StateError>()),
      );
      await _flushAsync();

      expect(bleTransport.connectCount, 1);
      expect(tcpTransport.connectCount, 0);
      expect(states.last.transport, TransportKind.ble);
      expect(states.last.status, ConnectionStatus.failed);
      expect(states.last.errorCode, connectionErrorBleFailed);

      await subscription.cancel();
      await client.dispose();
    });

    test('connect reports missing options when priority has no matching config',
        () async {
      final client = RobotClient(
        transportFactory: (transport, options) {
          throw UnsupportedError('Factory should not be called');
        },
      );
      final states = <RobotConnectionState>[];
      final subscription = client.connectionState.listen(states.add);

      await _flushAsync();
      await expectLater(
        client.connect(
          const RobotConnectionConfig(
            priority: <TransportKind>[TransportKind.tcp],
            ble: BleConnectionOptions(deviceId: 'robot-1'),
          ),
        ),
        throwsA(isA<StateError>()),
      );
      await _flushAsync();

      expect(states.last.transport, TransportKind.none);
      expect(states.last.status, ConnectionStatus.failed);
      expect(states.last.errorCode, connectionErrorMissingOptions);

      await subscription.cancel();
      await client.dispose();
    });

    test(
        'switchTransport preserves inflight command and resends on new transport',
        () async {
      final tcpTransport = _FakeTransport();
      final mqttTransport = _FakeTransport();
      final client = RobotClient(
        ackTimeout: const Duration(seconds: 5),
        transportFactory: (transport, options) {
          if (transport == TransportKind.tcp) {
            return tcpTransport;
          }
          if (transport == TransportKind.mqtt) {
            return mqttTransport;
          }
          throw UnsupportedError('Unexpected transport: $transport');
        },
      );
      final states = <RobotConnectionState>[];
      final subscription = client.connectionState.listen(states.add);

      await client.connectTCP(
        options: const TcpConnectionOptions(host: '10.0.0.2', port: 9000),
      );
      await client.move(0.2, 0.0, 0.1);
      expect(tcpTransport.sentPayloads, hasLength(1));

      await client.switchTransport(
        target: TransportKind.mqtt,
        mqtt: const MqttConnectionOptions(
          host: 'broker.local',
          port: 1883,
          robotId: 'dog-001',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(states.last.transport, TransportKind.mqtt);
      expect(states.last.status, ConnectionStatus.connected);
      expect(mqttTransport.sentPayloads, hasLength(1));
      expect(
        mqttTransport.sentPayloads.single,
        orderedEquals(tcpTransport.sentPayloads.single),
      );

      await subscription.cancel();
      await client.dispose();
    });

    test('failed switch keeps inflight command for a later successful switch',
        () async {
      final tcpTransport = _FakeTransport();
      final failingMqttTransport = _FakeTransport(
        connectError: UnsupportedError('mqtt stub'),
      );
      final bleTransport = _FakeTransport();
      var mqttFactoryCalls = 0;
      final client = RobotClient(
        ackTimeout: const Duration(seconds: 5),
        transportFactory: (transport, options) {
          if (transport == TransportKind.tcp) {
            return tcpTransport;
          }
          if (transport == TransportKind.mqtt) {
            mqttFactoryCalls += 1;
            return failingMqttTransport;
          }
          if (transport == TransportKind.ble) {
            return bleTransport;
          }
          throw UnsupportedError('Unexpected transport: $transport');
        },
      );
      final states = <RobotConnectionState>[];
      final subscription = client.connectionState.listen(states.add);

      await client.connectTCP();
      await client.move(0.3, 0.0, 0.0);
      expect(tcpTransport.sentPayloads, hasLength(1));

      await expectLater(
        client.switchTransport(
          target: TransportKind.mqtt,
          mqtt: const MqttConnectionOptions(robotId: 'dog-001'),
        ),
        throwsA(isA<UnsupportedError>()),
      );
      await _flushAsync();
      expect(mqttFactoryCalls, 1);
      expect(states.last.transport, TransportKind.mqtt);
      expect(states.last.status, ConnectionStatus.failed);

      await client.switchTransport(
        target: TransportKind.ble,
        ble: const BleConnectionOptions(deviceId: 'robot-1'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(states.last.transport, TransportKind.ble);
      expect(states.last.status, ConnectionStatus.connected);
      expect(bleTransport.sentPayloads, hasLength(1));

      await subscription.cancel();
      await client.dispose();
    });

    test('connectBLE stays available and emits BLE connected state', () async {
      final bleTransport = _FakeTransport();
      final client = RobotClient(
        transportFactory: (transport, options) {
          expect(transport, TransportKind.ble);
          expect(options, isA<BleConnectionOptions>());
          return bleTransport;
        },
      );
      final states = <RobotConnectionState>[];
      final subscription = client.connectionState.listen(states.add);

      await client.connectBLE(
        options: const BleConnectionOptions(deviceId: 'robot-1'),
      );
      await _flushAsync();

      expect(bleTransport.connectCount, 1);
      expect(states.last.transport, TransportKind.ble);
      expect(states.last.status, ConnectionStatus.connected);

      await subscription.cancel();
      await client.dispose();
    });

    test('unexpected BLE disconnect enters reconnecting and reconnects',
        () async {
      final firstTransport = _FakeTransport();
      final secondTransport = _FakeTransport();
      var transportFactoryCalls = 0;
      final client = RobotClient(
        reconnectPolicy: const _ImmediateReconnectPolicy(),
        transportFactory: (transport, options) {
          expect(transport, TransportKind.ble);
          expect(options, isA<BleConnectionOptions>());
          final nextTransport =
              transportFactoryCalls == 0 ? firstTransport : secondTransport;
          transportFactoryCalls += 1;
          return nextTransport;
        },
      );
      final states = <RobotConnectionState>[];
      final subscription = client.connectionState.listen(states.add);

      await client.connectBLE(
        options: const BleConnectionOptions(deviceId: 'robot-1'),
      );
      firstTransport.simulateUnexpectedDisconnect();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(transportFactoryCalls, 2);
      expect(secondTransport.connectCount, 1);
      expect(
        states.any((state) => state.status == ConnectionStatus.reconnecting),
        isTrue,
      );
      expect(states.last.transport, TransportKind.ble);
      expect(states.last.status, ConnectionStatus.connected);

      await subscription.cancel();
      await client.dispose();
    });

    test('transient BLE send failure does not reconnect while link stays up',
        () async {
      final bleTransport = _FakeTransport()
        ..sendError = StateError('transient write failed');
      final client = RobotClient(
        ackTimeout: const Duration(milliseconds: 1),
        maxRetries: 1,
        reconnectPolicy: const _ImmediateReconnectPolicy(),
        transportFactory: (transport, options) {
          expect(transport, TransportKind.ble);
          return bleTransport;
        },
      );
      final errors = <Object>[];
      final states = <RobotConnectionState>[];
      final errorSubscription = client.errors.listen(errors.add);
      final stateSubscription = client.connectionState.listen(states.add);

      await client.connectBLE(
        options: const BleConnectionOptions(deviceId: 'robot-1'),
      );
      await client.move(0.2, 0, 0);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(errors, isNotEmpty);
      expect(bleTransport.connectCount, 1);
      expect(bleTransport.isConnected, isTrue);
      expect(bleTransport.sentPayloads, hasLength(1));
      expect(states.last.status, ConnectionStatus.connected);

      await errorSubscription.cancel();
      await stateSubscription.cancel();
      await client.dispose();
    });

    test('incoming state frame is exposed on frameStream and stateStream',
        () async {
      final bleTransport = _FakeTransport();
      final client = RobotClient(
        transportFactory: (transport, options) => bleTransport,
      );
      final frames = <RobotFrame>[];
      final states = <RobotState>[];
      final frameSubscription = client.frameStream.listen(frames.add);
      final stateSubscription = client.stateStream.listen(states.add);

      await client.connectBLE(
        options: const BleConnectionOptions(deviceId: 'robot-1'),
      );
      final frame = buildStateFrame(
        const RobotState(battery: 92, roll: 0.12, pitch: -0.08, yaw: 0.2),
        7,
      );

      bleTransport.emitFrame(frame);
      await _flushAsync();

      expect(frames, hasLength(1));
      expect(frames.single.seq, 7);
      expect(frames.single.type, FrameType.state);
      expect(states, hasLength(1));
      expect(states.single.battery, 92);
      expect(states.single.roll, closeTo(0.12, 0.001));
      expect(states.single.pitch, closeTo(-0.08, 0.001));
      expect(states.single.yaw, closeTo(0.2, 0.001));

      await frameSubscription.cancel();
      await stateSubscription.cancel();
      await client.dispose();
    });

    test('doAction sends skill invoke frame', () async {
      final bleTransport = _FakeTransport();
      final client = RobotClient(
        transportFactory: (transport, options) => bleTransport,
      );

      await client.connectBLE(
        options: const BleConnectionOptions(deviceId: 'robot-1'),
      );
      await client.doAction(20593);

      expect(bleTransport.sentPayloads, hasLength(1));
      final frame =
          decodeFrame(Uint8List.fromList(bleTransport.sentPayloads[0]));
      final command = parseCommandPayload(frame.payload);
      expect(command, isA<SkillInvokeCommand>());
      expect((command as SkillInvokeCommand).actionId, 20593);

      await client.dispose();
    });

    test('doDogBehavior sends skill invoke frame', () async {
      final bleTransport = _FakeTransport();
      final client = RobotClient(
        transportFactory: (transport, options) => bleTransport,
      );

      await client.connectBLE(
        options: const BleConnectionOptions(deviceId: 'robot-1'),
      );
      await client.doDogBehavior(DogBehavior.waveHand);

      expect(bleTransport.sentPayloads, hasLength(1));
      final frame =
          decodeFrame(Uint8List.fromList(bleTransport.sentPayloads[0]));
      final command = parseCommandPayload(frame.payload);
      expect(command, isA<SkillInvokeCommand>());
      expect((command as SkillInvokeCommand).behaviorId, DogBehavior.waveHand);

      await client.dispose();
    });

    test('queued control commands preserve FIFO for programs', () async {
      final bleTransport = _FakeTransport();
      final client = RobotClient(
        transportFactory: (transport, options) => bleTransport,
      );

      await client.connectBLE(
        options: const BleConnectionOptions(deviceId: 'robot-1'),
      );
      await client.standQueued();
      await client.sitQueued();
      await client.doActionQueued(20593);

      expect(bleTransport.sentPayloads, hasLength(1));
      var frame = decodeFrame(Uint8List.fromList(bleTransport.sentPayloads[0]));
      var command = parseCommandPayload(frame.payload);
      expect(command, isA<DiscreteCommand>());
      expect((command as DiscreteCommand).commandId, CommandId.stand);

      bleTransport.emitFrame(buildAckFrame(frame.seq));
      await _flushAsync();
      expect(bleTransport.sentPayloads, hasLength(2));
      frame = decodeFrame(Uint8List.fromList(bleTransport.sentPayloads[1]));
      command = parseCommandPayload(frame.payload);
      expect(command, isA<DiscreteCommand>());
      expect((command as DiscreteCommand).commandId, CommandId.sit);

      bleTransport.emitFrame(buildAckFrame(frame.seq));
      await _flushAsync();
      expect(bleTransport.sentPayloads, hasLength(3));
      frame = decodeFrame(Uint8List.fromList(bleTransport.sentPayloads[2]));
      command = parseCommandPayload(frame.payload);
      expect(command, isA<SkillInvokeCommand>());
      expect((command as SkillInvokeCommand).actionId, 20593);

      await client.dispose();
    });

    test('default control commands replace unsent pending commands', () async {
      final bleTransport = _FakeTransport();
      final client = RobotClient(
        transportFactory: (transport, options) => bleTransport,
      );

      await client.connectBLE(
        options: const BleConnectionOptions(deviceId: 'robot-1'),
      );
      await client.stand();
      await client.sit();
      await client.doAction(20593);

      expect(bleTransport.sentPayloads, hasLength(1));
      final firstFrame =
          decodeFrame(Uint8List.fromList(bleTransport.sentPayloads[0]));
      final firstCommand = parseCommandPayload(firstFrame.payload);
      expect(firstCommand, isA<DiscreteCommand>());
      expect((firstCommand as DiscreteCommand).commandId, CommandId.stand);

      bleTransport.emitFrame(buildAckFrame(firstFrame.seq));
      await _flushAsync();

      expect(bleTransport.sentPayloads, hasLength(2));
      final secondFrame =
          decodeFrame(Uint8List.fromList(bleTransport.sentPayloads[1]));
      final secondCommand = parseCommandPayload(secondFrame.payload);
      expect(secondCommand, isA<SkillInvokeCommand>());
      expect((secondCommand as SkillInvokeCommand).actionId, 20593);

      await client.dispose();
    });

    test('superseded default command is not retried before newer command',
        () async {
      final bleTransport = _FakeTransport();
      final client = RobotClient(
        ackTimeout: const Duration(milliseconds: 1),
        transportFactory: (transport, options) => bleTransport,
      );

      await client.connectBLE(
        options: const BleConnectionOptions(deviceId: 'robot-1'),
      );
      await client.stand();
      await client.doAction(20593);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(bleTransport.sentPayloads, hasLength(2));
      final firstFrame =
          decodeFrame(Uint8List.fromList(bleTransport.sentPayloads[0]));
      final secondFrame =
          decodeFrame(Uint8List.fromList(bleTransport.sentPayloads[1]));
      final firstCommand = parseCommandPayload(firstFrame.payload);
      final secondCommand = parseCommandPayload(secondFrame.payload);

      expect(firstCommand, isA<DiscreteCommand>());
      expect((firstCommand as DiscreteCommand).commandId, CommandId.stand);
      expect(secondCommand, isA<SkillInvokeCommand>());
      expect((secondCommand as SkillInvokeCommand).actionId, 20593);

      await client.dispose();
    });
  });
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
}

class _FakeTransport implements RobotTransport {
  _FakeTransport({this.connectError});

  final Object? connectError;
  final StreamController<RobotFrame> _frames =
      StreamController<RobotFrame>.broadcast();
  final List<List<int>> sentPayloads = <List<int>>[];
  Object? sendError;
  bool _isConnected = false;
  int connectCount = 0;

  @override
  Stream<RobotFrame> get frames => _frames.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    connectCount += 1;
    if (connectError != null) {
      throw connectError!;
    }
    _isConnected = true;
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
  }

  @override
  Future<void> send(Uint8List bytes) async {
    if (!_isConnected) {
      throw StateError('transport is disconnected');
    }
    final error = sendError;
    if (error != null) {
      sendError = null;
      throw error;
    }
    sentPayloads.add(bytes.toList(growable: false));
  }

  void emitFrame(RobotFrame frame) {
    _frames.add(frame);
  }

  void simulateUnexpectedDisconnect() {
    _isConnected = false;
  }
}

class _ImmediateReconnectPolicy implements ReconnectPolicy {
  const _ImmediateReconnectPolicy();

  @override
  Future<Duration?> nextDelay({
    required TransportKind transport,
    required int attempt,
    Object? lastError,
  }) async {
    return const Duration(milliseconds: 1);
  }
}
