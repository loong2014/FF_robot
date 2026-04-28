import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture_sdk/hand_gesture_sdk.dart';

void main() {
  test('parses rich hand gesture events', () {
    final event = HandGestureEvent.fromMap(<dynamic, dynamic>{
      'type': 'gesture',
      'message': '张开手掌',
      'gesture': '张开手掌',
      'pose': '站起',
      'confidence': 0.91,
      'metrics': <String, dynamic>{'handArea': 0.42, 'handCenterX': 0.31},
    });

    expect(event.type, 'gesture');
    expect(event.gesture, '张开手掌');
    expect(event.pose, '站起');
    expect(event.confidence, 0.91);
    expect(event.metrics?['handArea'], 0.42);
  });

  test('maps pose events to discrete commands', () {
    final interpreter = GestureCommandInterpreter(
      nowProvider: () => DateTime(2026, 4, 26, 12, 0, 0),
    );

    final command = interpreter.interpret(
      const HandGestureEvent(
        type: 'pose',
        message: '站起',
        pose: '站起',
        confidence: 0.88,
      ),
    );

    expect(command?.type, HandGestureCommandType.stand);
    expect(command?.message, '站起');
  });

  test('maps fist gesture to stop command', () {
    final interpreter = GestureCommandInterpreter(
      nowProvider: () => DateTime(2026, 4, 26, 12, 0, 0),
    );

    final command = interpreter.interpret(
      const HandGestureEvent(
        type: 'gesture',
        message: '握拳',
        gesture: '握拳',
        confidence: 0.95,
      ),
    );

    expect(command?.type, HandGestureCommandType.stop);
    expect(command?.message, '握拳停止');
  });

  test('uses hand area growth for approach and left position for strafe', () {
    var now = DateTime(2026, 4, 26, 12, 0, 0);
    final interpreter = GestureCommandInterpreter(nowProvider: () => now);

    final baseline = interpreter.interpret(
      const HandGestureEvent(
        type: 'gesture',
        message: '张开手掌',
        gesture: '张开手掌',
        confidence: 0.8,
        metrics: <String, dynamic>{'handArea': 0.30, 'handCenterX': 0.50},
      ),
    );

    expect(baseline, isNull);

    now = now.add(const Duration(milliseconds: 400));
    final approach = interpreter.interpret(
      const HandGestureEvent(
        type: 'gesture',
        message: '张开手掌',
        gesture: '张开手掌',
        confidence: 0.8,
        metrics: <String, dynamic>{'handArea': 0.42, 'handCenterX': 0.50},
      ),
    );

    expect(approach?.type, HandGestureCommandType.move);
    expect(approach?.message, '接近');

    now = now.add(const Duration(milliseconds: 400));
    final strafe = interpreter.interpret(
      const HandGestureEvent(
        type: 'gesture',
        message: '张开手掌',
        gesture: '张开手掌',
        confidence: 0.8,
        metrics: <String, dynamic>{'handArea': 0.31, 'handCenterX': 0.20},
      ),
    );

    expect(strafe?.type, HandGestureCommandType.move);
    expect(strafe?.message, '平移左');
  });
}
