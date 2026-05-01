import 'gesture_control_state.dart';
import 'hand_gesture_sdk_command.dart';
import 'hand_gesture_sdk_event.dart';

class GestureCommandInterpreter {
  GestureCommandInterpreter({
    DateTime Function()? nowProvider,
    GestureControlConfig config = const GestureControlConfig(),
    GestureControlState? state,
  }) : _state =
           state ??
           GestureControlState(config: config, nowProvider: nowProvider);

  final GestureControlState _state;

  GestureControlMode get currentMode => _state.currentMode;

  HandGestureCommand? interpret(HandGestureEvent event) {
    return _state.interpret(event);
  }

  void reset() {
    _state.reset();
  }
}
