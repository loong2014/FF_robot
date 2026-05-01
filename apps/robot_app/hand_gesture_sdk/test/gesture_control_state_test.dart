import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture_sdk/hand_gesture_sdk.dart';

void main() {
  test('parses rich hand gesture events with MVP metrics', () {
    final event = HandGestureEvent.fromMap(<dynamic, dynamic>{
      'type': 'gesture',
      'message': '张开手掌',
      'gesture': '张开手掌',
      'confidence': 0.91,
      'metrics': <String, dynamic>{
        'handDetected': true,
        'handBBoxArea': 0.42,
        'handCenterX': 0.31,
        'handCenterY': 0.48,
        'bboxWidth': 0.6,
        'bboxHeight': 0.7,
      },
    });

    expect(event.type, 'gesture');
    expect(event.gesture, '张开手掌');
    expect(event.confidence, 0.91);
    expect(event.metrics?['handDetected'], isTrue);
    expect(event.metrics?['handBBoxArea'], 0.42);
  });

  test('open palm held for two seconds enters follow mode', () {
    final clock = _TestClock();
    final state = GestureControlState(nowProvider: clock.now);

    expect(state.interpret(_event(gesture: '张开手掌')), isNull);
    clock.advance(const Duration(milliseconds: 1999));
    expect(state.interpret(_event(gesture: '张开手掌')), isNull);

    clock.advance(const Duration(milliseconds: 2));
    final command = state.interpret(_event(gesture: '张开手掌'));

    expect(command?.type, HandGestureCommandType.modeChanged);
    expect(command?.mode, GestureControlMode.follow.name);
    expect(state.currentMode, GestureControlMode.follow);
    expect(state.cooldownUntil, isNull);
  });

  test('open palm in follow mode does not repeat mode switch', () {
    final clock = _TestClock();
    final state = GestureControlState(nowProvider: clock.now)
      ..currentMode = GestureControlMode.follow;

    state.interpret(_event(gesture: '张开手掌', area: 0.18));
    clock.advance(const Duration(seconds: 3));
    final command = state.interpret(_event(gesture: '张开手掌', area: 0.18));

    expect(command?.type, HandGestureCommandType.move);
    expect(command?.source, 'follow');
    expect(command?.mode, isNull);
    expect(state.currentMode, GestureControlMode.follow);
  });

  test('victory and other command gestures are ignored', () {
    final clock = _TestClock();
    final state = GestureControlState(nowProvider: clock.now);

    for (final gesture in <String>['胜利', 'OK', '点赞', '一指', '两指', '三指']) {
      expect(state.interpret(_event(gesture: gesture)), isNull);
      clock.advance(const Duration(milliseconds: 500));
    }

    expect(state.currentMode, GestureControlMode.command);
  });

  test('command mode fist stops movement without entering follow', () {
    final state = GestureControlState(nowProvider: _TestClock().now);

    final command = state.interpret(_event(gesture: '握拳'));

    expect(command?.type, HandGestureCommandType.stop);
    expect(command?.message, '握拳停止移动');
    expect(state.currentMode, GestureControlMode.command);
  });

  test(
    'follow fist stops immediately and returns to command after two seconds',
    () {
      final clock = _TestClock();
      final state = GestureControlState(nowProvider: clock.now)
        ..currentMode = GestureControlMode.follow;

      final stop = state.interpret(_event(gesture: '握拳'));
      expect(stop?.type, HandGestureCommandType.stop);
      expect(state.currentMode, GestureControlMode.follow);

      clock.advance(const Duration(milliseconds: 1999));
      expect(
        state.interpret(_event(gesture: '握拳'))?.type,
        HandGestureCommandType.stop,
      );

      clock.advance(const Duration(milliseconds: 2));
      final command = state.interpret(_event(gesture: '握拳'));

      expect(command?.type, HandGestureCommandType.modeChanged);
      expect(command?.mode, GestureControlMode.command.name);
      expect(state.currentMode, GestureControlMode.command);
    },
  );

  test('pointing hand left and right positions trigger lateral commands', () {
    final leftState = GestureControlState(nowProvider: _TestClock().now);
    final left = leftState.interpret(_event(gesture: '指向', x: 0.25));

    expect(left?.type, HandGestureCommandType.move);
    expect(left?.vy, greaterThan(0));
    expect(left?.vx, 0);

    final rightState = GestureControlState(nowProvider: _TestClock().now);
    final right = rightState.interpret(_event(gesture: '指向', x: 0.75));

    expect(right?.type, HandGestureCommandType.move);
    expect(right?.vy, lessThan(0));
    expect(right?.vx, 0);
  });

  test('pointing hand near center is ignored', () {
    final state = GestureControlState(nowProvider: _TestClock().now);

    expect(state.interpret(_event(gesture: '指向', x: 0.52)), isNull);
  });

  test(
    'follow mode maps area growth to backward and shrink to forward vx',
    () {
      // 跟随维距：手变大(靠近) → 机器狗后退；手变小(远离) → 机器狗跟进前进。
      final clock = _TestClock();
      final state = GestureControlState(nowProvider: clock.now)
        ..currentMode = GestureControlMode.follow;

      final zero = state.interpret(_event(area: 0.18));
      expect(zero?.vx, 0);

      final backward = state.interpret(_event(area: 0.30)); // 手变大 → 后退
      expect(backward?.vx, lessThan(0));
      expect(backward?.vy, 0);

      final forward = state.interpret(_event(area: 0.08)); // 手变小 → 跟进
      expect(forward?.vx, greaterThan(0));
    },
  );

  test('follow mode maps x offset to yaw with vy fixed at zero', () {
    final clock = _TestClock();
    final leftState = GestureControlState(nowProvider: clock.now)
      ..currentMode = GestureControlMode.follow;

    leftState.interpret(_event(area: 0.18, x: 0.5));
    final left = leftState.interpret(_event(area: 0.18, x: 0.25));
    expect(left?.vx, 0);
    expect(left?.vy, 0);
    expect(left?.yaw, greaterThan(0)); // 画面左侧 → 左转(yaw>0)，与转向摇杆一致

    final rightState = GestureControlState(nowProvider: clock.now)
      ..currentMode = GestureControlMode.follow;
    rightState.interpret(_event(area: 0.18, x: 0.5));
    final right = rightState.interpret(_event(area: 0.18, x: 0.75));
    expect(right?.vy, 0);
    expect(right?.yaw, lessThan(0)); // 画面右侧 → 右转(yaw<0)
  });

  test(
    'follow mode prioritizes yaw turn over forward when hand is off-center',
    () {
      final clock = _TestClock();
      final state = GestureControlState(nowProvider: clock.now)
        ..currentMode = GestureControlMode.follow;

      // 先用居中帧建立 neutral hand area。
      state.interpret(_event(area: 0.18, x: 0.5));

      // 手既偏左又比基准面积大很多：优先输出转向 yaw，前后 vx 必须为 0，
      // vy 也必须为 0（跟随模式左右用 yaw 而非 vy）。
      final leftAndLarge = state.interpret(_event(area: 0.40, x: 0.25));
      expect(leftAndLarge?.vx, 0);
      expect(leftAndLarge?.vy, 0);
      expect(leftAndLarge?.yaw, greaterThan(0)); // 左偏 → 左转
      expect(leftAndLarge?.message, '跟随转向');

      // 偏右 + 较小面积同理：只输出右转 yaw<0。
      final rightAndSmall = state.interpret(_event(area: 0.05, x: 0.85));
      expect(rightAndSmall?.vx, 0);
      expect(rightAndSmall?.vy, 0);
      expect(rightAndSmall?.yaw, lessThan(0)); // 右偏 → 右转
    },
  );

  test(
    'follow mode falls back to forward/backward only when hand is centered',
    () {
      final clock = _TestClock();
      final state = GestureControlState(nowProvider: clock.now)
        ..currentMode = GestureControlMode.follow;

      state.interpret(_event(area: 0.18, x: 0.5));

      // 中心横向死区内 (|dx| <= 0.10)：才允许前后。
      // 手变大(area>neutral) → 后退；手变小(area<neutral) → 跟进前进。
      final backward = state.interpret(_event(area: 0.30, x: 0.55));
      expect(backward?.vy, 0);
      expect(backward?.vx, lessThan(0));
      expect(backward?.message, '跟随前后');

      final forward = state.interpret(_event(area: 0.08, x: 0.46));
      expect(forward?.vy, 0);
      expect(forward?.vx, greaterThan(0));
    },
  );

  test('follow mode outputs zero move inside combined dead zones', () {
    final clock = _TestClock();
    final state = GestureControlState(nowProvider: clock.now)
      ..currentMode = GestureControlMode.follow;

    state.interpret(_event(area: 0.18, x: 0.5));
    final command = state.interpret(_event(area: 0.20, x: 0.56));

    expect(command?.vx, 0);
    expect(command?.vy, 0);
    expect(command?.yaw, 0);
  });

  test('area fuse blocks forward motion and recovers after two seconds', () {
    final clock = _TestClock();
    final state = GestureControlState(nowProvider: clock.now)
      ..currentMode = GestureControlMode.follow;

    state.interpret(_event(area: 0.18));
    final fused = state.interpret(_event(area: 0.65));
    expect(state.fuseActive, isTrue);
    expect(fused?.vx, lessThanOrEqualTo(0));

    state.interpret(_event(area: 0.25));
    clock.advance(const Duration(milliseconds: 1999));
    state.interpret(_event(area: 0.25));
    expect(state.fuseActive, isTrue);

    clock.advance(const Duration(milliseconds: 2));
    state.interpret(_event(area: 0.25));
    expect(state.fuseActive, isFalse);

    final recovered = state.interpret(_event(area: 0.10)); // 手变小 → 跟进前进
    expect(recovered?.vx, greaterThan(0));
  });

  test('yaw turn output stays continuous across consecutive frames', () {
    // 连续帧中同样的 x 偏移应产生同样的 yaw，不应被抑制或衰减。
    final clock = _TestClock();
    final state = GestureControlState(nowProvider: clock.now)
      ..currentMode = GestureControlMode.follow;

    state.interpret(_event(area: 0.18, x: 0.5));
    final first = state.interpret(_event(area: 0.18, x: 0.85));
    clock.advance(const Duration(milliseconds: 50));
    final second = state.interpret(_event(area: 0.18, x: 0.85));
    clock.advance(const Duration(milliseconds: 50));
    final third = state.interpret(_event(area: 0.18, x: 0.85));

    expect(first?.yaw, isNot(0));
    expect(second?.yaw, first?.yaw);
    expect(third?.yaw, first?.yaw);
    // vy 全程为 0，不再走横向平移。
    expect(first?.vy, 0);
  });

  test('pose events do not reset open-palm hold timer in command mode', () {
    final clock = _TestClock();
    final state = GestureControlState(nowProvider: clock.now);

    expect(state.interpret(_event(gesture: '张开手掌')), isNull);
    clock.advance(const Duration(milliseconds: 1000));
    // Pose 事件穿插过来，理论上不应清空 _openPalmStartedAt 计时器。
    expect(state.interpret(_poseEvent(pose: '站起')), isNull);
    expect(state.interpret(_poseEvent(pose: '蹲下')), isNull);
    clock.advance(const Duration(milliseconds: 1001));
    final command = state.interpret(_event(gesture: '张开手掌'));

    expect(command?.type, HandGestureCommandType.modeChanged);
    expect(command?.mode, GestureControlMode.follow.name);
    expect(state.currentMode, GestureControlMode.follow);
  });

  test(
    'pose events do not reset fist hold timer or emit zero-velocity in follow mode',
    () {
      final clock = _TestClock();
      final state = GestureControlState(nowProvider: clock.now)
        ..currentMode = GestureControlMode.follow;

      // 先建立 neutral hand area，确保后续 follow 行为可预期。
      state.interpret(_event(area: 0.18));

      final stop = state.interpret(_event(gesture: '握拳'));
      expect(stop?.type, HandGestureCommandType.stop);

      clock.advance(const Duration(milliseconds: 1000));
      // 在长按计时窗口内插入 pose 事件，不应被状态机消费。
      expect(state.interpret(_poseEvent(pose: '站起')), isNull);
      expect(state.interpret(_poseEvent(pose: '未知')), isNull);

      clock.advance(const Duration(milliseconds: 1001));
      final command = state.interpret(_event(gesture: '握拳'));

      expect(command?.type, HandGestureCommandType.modeChanged);
      expect(command?.mode, GestureControlMode.command.name);
      expect(state.currentMode, GestureControlMode.command);
    },
  );

  test('non-gesture events such as status/closed are ignored', () {
    final state = GestureControlState(nowProvider: _TestClock().now);

    final statusEvent = HandGestureEvent(
      type: 'status',
      message: '相机已就绪',
    );
    final closedEvent = HandGestureEvent(
      type: 'closed',
      message: '识别页关闭',
    );
    final readyEvent = HandGestureEvent(
      type: 'ready',
      message: '相机已就绪',
    );

    expect(state.interpret(statusEvent), isNull);
    expect(state.interpret(closedEvent), isNull);
    expect(state.interpret(readyEvent), isNull);
    expect(state.currentMode, GestureControlMode.command);
  });
}

HandGestureEvent _event({
  String gesture = '张开手掌',
  double confidence = 0.95,
  bool detected = true,
  double area = 0.18,
  double x = 0.5,
  double y = 0.5,
  double width = 0.3,
  double height = 0.3,
}) {
  return HandGestureEvent(
    type: 'gesture',
    message: detected ? gesture : '未检测到手部',
    gesture: detected ? gesture : null,
    confidence: confidence,
    metrics: <String, dynamic>{
      'handDetected': detected,
      'handBBoxArea': area,
      'handCenterX': x,
      'handCenterY': y,
      'bboxWidth': math.max(width, 0.001),
      'bboxHeight': height,
    },
  );
}

HandGestureEvent _poseEvent({
  String pose = '站起',
  double confidence = 0.8,
  double leftKnee = 170,
  double rightKnee = 170,
  double leftHip = 170,
  double rightHip = 170,
}) {
  return HandGestureEvent(
    type: 'pose',
    message: pose,
    pose: pose,
    confidence: confidence,
    metrics: <String, dynamic>{
      'leftKneeAngle': leftKnee,
      'rightKneeAngle': rightKnee,
      'leftHipAngle': leftHip,
      'rightHipAngle': rightHip,
      'confidence': confidence,
    },
  );
}

class _TestClock {
  DateTime _now = DateTime(2026, 5, 1, 12, 0, 0);

  DateTime now() => _now;

  void advance([Duration duration = const Duration(milliseconds: 100)]) {
    _now = _now.add(duration);
  }
}
