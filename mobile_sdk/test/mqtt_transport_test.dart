import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sdk/mobile_sdk.dart';

void main() {
  group('MqttTransport', () {
    late _FakeMqttClientSession session;
    late MqttTransport transport;

    const options = MqttConnectionOptions(
      host: 'broker',
      port: 1883,
      robotId: 'dog-1',
      connectTimeout: Duration(milliseconds: 200),
    );

    setUp(() {
      session = _FakeMqttClientSession();
      transport = MqttTransport(
        options,
        sessionFactory: (_) => session,
      );
    });

    tearDown(() async {
      await transport.dispose();
    });

    test('connect subscribes to state and event topics', () async {
      await transport.connect();

      expect(transport.isConnected, isTrue);
      expect(
        session.subscriptions,
        containsAll(<String>['robot/dog-1/state', 'robot/dog-1/event']),
      );
    });

    test('state topic bytes are decoded into RobotFrames', () async {
      await transport.connect();

      final collected = <RobotFrame>[];
      final sub = transport.frames.listen(collected.add);

      final ackFrame = encodeFrame(buildAckFrame(42));
      session.deliver('robot/dog-1/state', Uint8List.fromList(ackFrame));

      await _eventually(() => collected.isNotEmpty);
      expect(collected.first.type, FrameType.ack);
      expect(parseAckPayload(collected.first.payload), 42);

      await sub.cancel();
    });

    test('event topic payloads are exposed as JSON maps', () async {
      await transport.connect();

      final events = <Map<String, dynamic>>[];
      final sub = transport.events.listen(events.add);

      session.deliver(
        'robot/dog-1/event',
        Uint8List.fromList(utf8.encode('{"type":"battery_low","level":15}')),
      );

      await _eventually(() => events.isNotEmpty);
      expect(events.first, {'type': 'battery_low', 'level': 15});

      await sub.cancel();
    });

    test('malformed event JSON does not surface on events stream', () async {
      await transport.connect();

      final events = <Map<String, dynamic>>[];
      final errors = <Object>[];
      final sub = transport.events.listen(events.add, onError: errors.add);

      session.deliver(
        'robot/dog-1/event',
        Uint8List.fromList(utf8.encode('not-a-json')),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events, isEmpty);
      expect(errors, isEmpty);

      await sub.cancel();
    });

    test('send publishes to the control topic with configured QoS', () async {
      await transport.connect();

      final payload = Uint8List.fromList(<int>[0xAA, 0x55, 0x01]);
      await transport.send(payload);

      expect(session.publishes, hasLength(1));
      final published = session.publishes.single;
      expect(published.topic, 'robot/dog-1/control');
      expect(published.payload, orderedEquals(payload));
      expect(published.qos, MqttQosLevel.atLeastOnce);
    });

    test('send while disconnected throws StateError', () async {
      expect(() => transport.send(Uint8List(0)), throwsStateError);
    });

    test('disconnect releases session and drops isConnected flag', () async {
      await transport.connect();
      expect(session.disconnected, isFalse);

      await transport.disconnect();
      expect(session.disconnected, isTrue);
      expect(transport.isConnected, isFalse);
    });

    test('connect failure propagates via Future and emits frames error',
        () async {
      final failing = _FakeMqttClientSession(connectError: 'auth rejected');
      final failingTransport = MqttTransport(
        options,
        sessionFactory: (_) => failing,
      );
      final errors = <Object>[];
      final sub = failingTransport.frames.listen((_) {}, onError: errors.add);

      await expectLater(failingTransport.connect(), throwsStateError);
      expect(failingTransport.isConnected, isFalse);
      await _eventually(() => errors.isNotEmpty);
      expect(errors.first, isA<StateError>());

      await sub.cancel();
      await failingTransport.dispose();
    });
  });
}

Future<void> _eventually(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 1),
  Duration step = const Duration(milliseconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('condition not met within $timeout');
    }
    await Future<void>.delayed(step);
  }
}

class _Publish {
  const _Publish({
    required this.topic,
    required this.payload,
    required this.qos,
  });

  final String topic;
  final Uint8List payload;
  final MqttQosLevel qos;
}

class _FakeMqttClientSession implements MqttClientSession {
  _FakeMqttClientSession({this.connectError});

  final String? connectError;
  final StreamController<MqttInboundMessage> _messages =
      StreamController<MqttInboundMessage>.broadcast();
  final List<String> subscriptions = <String>[];
  final List<_Publish> publishes = <_Publish>[];
  bool _connected = false;
  bool disconnected = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<MqttInboundMessage> get messages => _messages.stream;

  @override
  Future<void> connect() async {
    if (connectError != null) {
      throw StateError(connectError!);
    }
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
    _connected = false;
    if (!_messages.isClosed) {
      await _messages.close();
    }
  }

  @override
  Future<void> publish(
    String topic,
    Uint8List payload,
    MqttQosLevel qos,
  ) async {
    publishes.add(_Publish(topic: topic, payload: payload, qos: qos));
  }

  @override
  Future<void> subscribe(String topic, MqttQosLevel qos) async {
    subscriptions.add(topic);
  }

  void deliver(String topic, Uint8List payload) {
    _messages.add(MqttInboundMessage(topic: topic, payload: payload));
  }
}
