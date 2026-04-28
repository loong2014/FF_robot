import 'dart:async';

import 'package:mobile_sdk/mobile_sdk.dart';
import 'package:voice_control_sdk/voice_control_sdk.dart';

class VoiceActionMapper {
  static Future<String> execute(
    VoiceCommand command,
    RobotClient client, {
    bool executeMotionBurst = true,
  }) async {
    switch (command) {
      case VoiceCommand.standUp:
        await client.stand();
        return '已执行：站立';
      case VoiceCommand.sitDown:
        await client.sit();
        return '已执行：坐下';
      case VoiceCommand.forward:
        if (executeMotionBurst) {
          await _burstMove(client, vx: 0.32, duration: const Duration(milliseconds: 800));
          return '已执行：前进';
        }
        await client.move(0.32, 0, 0);
        return '已执行：前进';
      case VoiceCommand.backward:
        if (executeMotionBurst) {
          await _burstMove(client, vx: -0.26, duration: const Duration(milliseconds: 800));
          return '已执行：后退';
        }
        await client.move(-0.26, 0, 0);
        return '已执行：后退';
      case VoiceCommand.unknown:
        throw StateError('语音命令未识别');
    }
  }

  static Future<void> _burstMove(
    RobotClient client, {
    required double vx,
    required Duration duration,
  }) async {
    await client.move(vx, 0, 0);
    await Future<void>.delayed(duration);
    await client.stop();
  }
}
