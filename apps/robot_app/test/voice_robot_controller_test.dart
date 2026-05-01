import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sdk/mobile_sdk.dart';
import 'package:robot_app/src/voice_robot_controller.dart';
import 'package:voice_control_sdk/voice_control_sdk.dart';

class FakeVoiceBackend implements VoiceBackend {
  final StreamController<VoiceEvent> controller =
      StreamController<VoiceEvent>.broadcast();

  bool started = false;
  bool stopped = false;

  @override
  Stream<VoiceEvent> get events => controller.stream;

  @override
  Future<void> dispose() async {
    await controller.close();
  }

  @override
  Future<bool> ensurePermissions() async => true;

  @override
  Future<String?> getPlatformVersion() async => 'test';

  @override
  Future<void> start({VoiceConfig config = const VoiceConfig()}) async {
    started = true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  void emitCommand(VoiceCommand command) {
    controller.add(
      VoiceCommandEvent(
        timestamp: DateTime.utc(2026),
        source: VoiceEventSource.unknown,
        payload: <String, Object?>{'command': command.wireName},
        command: command,
        language: VoiceLanguage.zh,
        rawText: command.wireName,
        normalizedText: command.wireName,
        confidence: 1,
      ),
    );
  }
}

class FakeRobotClient extends RobotClient {
  FakeRobotClient({this.connected = true});

  bool connected;
  final List<String> calls = <String>[];

  @override
  bool get isConnected => connected;

  @override
  Future<void> stand() async {
    calls.add('stand');
  }

  @override
  Future<void> sit() async {
    calls.add('sit');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> move(double vx, double vy, double yaw) async {
    calls.add('move:$vx,$vy,$yaw');
  }

  @override
  Future<void> moveQueued(double vx, double vy, double yaw) {
    throw StateError('queued API must not be used for voice control');
  }

  @override
  Future<void> standQueued() {
    throw StateError('queued API must not be used for voice control');
  }

  @override
  Future<void> sitQueued() {
    throw StateError('queued API must not be used for voice control');
  }

  @override
  Future<void> stopQueued() {
    throw StateError('queued API must not be used for voice control');
  }
}

void main() {
  test('VoiceRobotController maps all voice commands to last-wins APIs',
      () async {
    final backend = FakeVoiceBackend();
    final robot = FakeRobotClient();
    final controller = VoiceRobotController(
      client: robot,
      voiceController: VoiceController(backend),
      delay: (_) async {},
    );
    addTearDown(controller.dispose);

    Future<void> emitAndSettle(VoiceCommand command) async {
      backend.emitCommand(command);
      await pumpEventQueue(times: 3);
    }

    await emitAndSettle(VoiceCommand.standUp);
    await emitAndSettle(VoiceCommand.sitDown);
    await emitAndSettle(VoiceCommand.stop);
    await emitAndSettle(VoiceCommand.forward);
    await emitAndSettle(VoiceCommand.backward);
    await emitAndSettle(VoiceCommand.left);
    await emitAndSettle(VoiceCommand.right);

    expect(robot.calls, <String>[
      'stand',
      'sit',
      'stop',
      'move:0.32,0.0,0.0',
      'stop',
      'move:-0.26,0.0,0.0',
      'stop',
      'move:0.0,0.25,0.0',
      'stop',
      'move:0.0,-0.25,0.0',
      'stop',
    ]);
  });

  test('VoiceRobotController reports recognized command when robot is offline',
      () async {
    final backend = FakeVoiceBackend();
    final robot = FakeRobotClient(connected: false);
    final controller = VoiceRobotController(
      client: robot,
      voiceController: VoiceController(backend),
      delay: (_) async {},
    );
    addTearDown(controller.dispose);
    final feedback = <String>[];
    final sub = controller.feedback.listen(feedback.add);
    addTearDown(sub.cancel);

    backend.emitCommand(VoiceCommand.forward);
    await pumpEventQueue(times: 3);

    expect(robot.calls, isEmpty);
    expect(feedback, contains('未连接机器人，已识别但未执行'));
  });
}
