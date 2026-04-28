library hand_gesture_sdk;

import 'hand_gesture_sdk_event.dart';
import 'hand_gesture_sdk_command.dart';
import 'hand_gesture_sdk_command_interpreter.dart';
import 'hand_gesture_sdk_platform_interface.dart';

export 'hand_gesture_sdk_event.dart';
export 'hand_gesture_sdk_command.dart';
export 'hand_gesture_sdk_command_interpreter.dart';

class HandGestureSdk {
  HandGestureSdk([HandGestureSdkPlatform? platform])
    : _platform = platform ?? HandGestureSdkPlatform.instance;

  static final HandGestureSdk instance = HandGestureSdk();

  final HandGestureSdkPlatform _platform;

  Future<String?> getPlatformVersion() {
    return _platform.getPlatformVersion();
  }

  Future<void> startRecognition() {
    return _platform.startRecognition();
  }

  Future<void> stopRecognition() {
    return _platform.stopRecognition();
  }

  Stream<HandGestureEvent> get events => _platform.events;

  Stream<HandGestureCommand> get commands {
    final interpreter = GestureCommandInterpreter();
    return _platform.events
        .map(interpreter.interpret)
        .where((command) => command != null)
        .cast<HandGestureCommand>();
  }
}
