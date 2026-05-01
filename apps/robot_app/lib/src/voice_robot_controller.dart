import 'dart:async';

import 'package:mobile_sdk/mobile_sdk.dart';
import 'package:voice_control_sdk/voice_control_sdk.dart';

class VoiceRobotController {
  VoiceRobotController({
    required RobotClient client,
    VoiceController? voiceController,
    Future<void> Function(Duration duration)? delay,
  })  : _client = client,
        voiceController = voiceController ?? VoiceController(),
        _delay = delay ?? ((duration) => Future<void>.delayed(duration)) {
    _commandSubscription = this
        .voiceController
        .onCommand
        .listen((event) => unawaited(_execute(event)));
  }

  final RobotClient _client;
  final Future<void> Function(Duration duration) _delay;
  final VoiceController voiceController;
  final StreamController<String> _feedbackController =
      StreamController<String>.broadcast();

  StreamSubscription<VoiceCommandEvent>? _commandSubscription;
  int _motionToken = 0;
  bool _running = false;

  Stream<VoiceEvent> get events => voiceController.events;

  Stream<String> get feedback => _feedbackController.stream;

  bool get isRunning => _running;

  Future<bool> ensurePermissions() {
    return voiceController.ensurePermissions();
  }

  Future<void> start() async {
    await voiceController.startListening(config: const VoiceConfig());
    _running = true;
  }

  Future<void> stop() async {
    _motionToken++;
    _running = false;
    await voiceController.stopListening();
  }

  Future<void> dispose() async {
    await _commandSubscription?.cancel();
    await stop();
    await voiceController.dispose();
    await _feedbackController.close();
  }

  Future<void> _execute(VoiceCommandEvent event) async {
    if (!_client.isConnected) {
      _feedbackController.add('未连接机器人，已识别但未执行');
      return;
    }

    try {
      switch (event.command) {
        case VoiceCommand.standUp:
          _motionToken++;
          await _client.stand();
          _feedbackController.add('已执行：站起');
          return;
        case VoiceCommand.sitDown:
          _motionToken++;
          await _client.sit();
          _feedbackController.add('已执行：坐下');
          return;
        case VoiceCommand.stop:
          _motionToken++;
          await _client.stop();
          _feedbackController.add('已执行：停止');
          return;
        case VoiceCommand.forward:
          await _burstMove(
            vx: 0.32,
            vy: 0,
            yaw: 0,
            duration: const Duration(milliseconds: 800),
            label: '前进',
          );
          return;
        case VoiceCommand.backward:
          await _burstMove(
            vx: -0.26,
            vy: 0,
            yaw: 0,
            duration: const Duration(milliseconds: 800),
            label: '后退',
          );
          return;
        case VoiceCommand.left:
          await _burstMove(
            vx: 0,
            vy: 0.25,
            yaw: 0,
            duration: const Duration(milliseconds: 500),
            label: '左移',
          );
          return;
        case VoiceCommand.right:
          await _burstMove(
            vx: 0,
            vy: -0.25,
            yaw: 0,
            duration: const Duration(milliseconds: 500),
            label: '右移',
          );
          return;
        case VoiceCommand.unknown:
          _feedbackController.add('语音命令未识别');
          return;
      }
    } catch (error) {
      _feedbackController.add('语音命令执行失败: $error');
    }
  }

  Future<void> _burstMove({
    required double vx,
    required double vy,
    required double yaw,
    required Duration duration,
    required String label,
  }) async {
    final token = ++_motionToken;
    await _client.move(vx, vy, yaw);
    _feedbackController.add('已执行：$label');
    await _delay(duration);
    if (token == _motionToken && _client.isConnected) {
      await _client.stop();
    }
  }
}
