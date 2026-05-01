import 'hand_gesture_sdk_event.dart';
import 'hand_gesture_sdk_command.dart';
import 'hand_gesture_sdk_command_interpreter.dart';
import 'hand_gesture_sdk_platform_interface.dart';

export 'hand_gesture_sdk_event.dart';
export 'hand_gesture_sdk_command.dart';
export 'gesture_control_state.dart';
export 'hand_gesture_sdk_command_interpreter.dart';

/// 事件类型常量，避免上层散落字符串字面量。
class HandGestureEventType {
  HandGestureEventType._();

  static const String gesture = 'gesture';
  static const String pose = 'pose';
  static const String status = 'status';
  static const String ready = 'ready';
  static const String error = 'error';
  static const String closed = 'closed';
}

class HandGestureSdk {
  HandGestureSdk([HandGestureSdkPlatform? platform])
    : _platform = platform ?? HandGestureSdkPlatform.instance {
    final interpreter = GestureCommandInterpreter();
    _events = _platform.events.asBroadcastStream();
    _gestureEvents = _events
        .where((event) => event.type == HandGestureEventType.gesture)
        .asBroadcastStream();
    _poseEvents = _events
        .where((event) => event.type == HandGestureEventType.pose)
        .asBroadcastStream();
    _statusEvents = _events
        .where(
          (event) =>
              event.type != HandGestureEventType.gesture &&
              event.type != HandGestureEventType.pose,
        )
        .asBroadcastStream();
    _commands = _gestureEvents
        .map(interpreter.interpret)
        .where((command) => command != null)
        .cast<HandGestureCommand>()
        .asBroadcastStream();
  }

  static final HandGestureSdk instance = HandGestureSdk();

  final HandGestureSdkPlatform _platform;
  late final Stream<HandGestureEvent> _events;
  late final Stream<HandGestureEvent> _gestureEvents;
  late final Stream<HandGestureEvent> _poseEvents;
  late final Stream<HandGestureEvent> _statusEvents;
  late final Stream<HandGestureCommand> _commands;

  Future<String?> getPlatformVersion() {
    return _platform.getPlatformVersion();
  }

  Future<void> startRecognition() {
    return _platform.startRecognition();
  }

  Future<void> stopRecognition() {
    return _platform.stopRecognition();
  }

  Future<void> updateRecognitionDebugInfo(Map<String, String> info) {
    return _platform.updateRecognitionDebugInfo(info);
  }

  /// 全量事件流（手势 / 姿态 / 状态 / 错误 / 关闭）。
  ///
  /// 适合事件审计、日志面板等需要看到全部事件的场景；
  /// 业务消费方建议按职责订阅 [gestureEvents] / [poseEvents] / [statusEvents]，
  /// 避免把姿态事件喂进手势命令状态机。
  Stream<HandGestureEvent> get events => _events;

  /// 仅手势事件流（`type=='gesture'`），驱动手势命令解释器。
  Stream<HandGestureEvent> get gestureEvents => _gestureEvents;

  /// 仅姿态事件流（`type=='pose'`），用于 UI 展示或独立的姿态映射，
  /// 不会进入手势命令状态机。
  Stream<HandGestureEvent> get poseEvents => _poseEvents;

  /// 状态类事件流（status / ready / error / closed 等），不含手势 / 姿态。
  Stream<HandGestureEvent> get statusEvents => _statusEvents;

  /// 经状态机解释后的手势命令流（仅来源于 [gestureEvents]）。
  Stream<HandGestureCommand> get commands => _commands;
}
