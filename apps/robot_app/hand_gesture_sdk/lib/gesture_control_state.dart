import 'dart:math' as math;

import 'hand_gesture_sdk_command.dart';
import 'hand_gesture_sdk_event.dart';

enum GestureControlMode { command, follow }

class GestureControlConfig {
  const GestureControlConfig({
    this.openPalmEnterFollowHold = const Duration(seconds: 2),
    this.fistReturnCommandHold = const Duration(seconds: 2),
    this.lowConfidence = 0.4,
    this.highConfidence = 0.85,
    this.defaultNeutralArea = 0.18,
    this.neutralAreaMin = 0.08,
    this.neutralAreaMax = 0.45,
    this.areaDeadZone = 0.04,
    this.lateralDeadZone = 0.10,
    this.commandSideDeadZone = 0.05,
    this.maxAreaOffset = 0.30,
    this.maxXOffset = 0.35,
    this.maxLinearVel = 0.5,
    this.maxLateralVel = 0.35,
    this.maxYawVel = 0.9,
    this.lateralCommandVy = 0.25,
    this.fuseEnterArea = 0.6,
    this.fuseReleaseArea = 0.3,
    this.fuseReleaseDuration = const Duration(seconds: 2),
  });

  final Duration openPalmEnterFollowHold;
  final Duration fistReturnCommandHold;
  final double lowConfidence;
  final double highConfidence;
  final double defaultNeutralArea;
  final double neutralAreaMin;
  final double neutralAreaMax;
  final double areaDeadZone;
  final double lateralDeadZone;
  final double commandSideDeadZone;
  final double maxAreaOffset;
  final double maxXOffset;
  final double maxLinearVel;
  final double maxLateralVel;
  final double maxYawVel;
  final double lateralCommandVy;
  final double fuseEnterArea;
  final double fuseReleaseArea;
  final Duration fuseReleaseDuration;
}

class GestureControlState {
  GestureControlState({
    this.config = const GestureControlConfig(),
    DateTime Function()? nowProvider,
  }) : _now = nowProvider ?? DateTime.now;

  final GestureControlConfig config;
  final DateTime Function() _now;

  GestureControlMode currentMode = GestureControlMode.command;
  double? _neutralHandArea;
  bool _fuseActive = false;
  DateTime? _fuseReleaseSince;
  DateTime? _openPalmStartedAt;
  DateTime? _followFistStartedAt;

  DateTime? get cooldownUntil => null;
  double? get neutralHandArea => _neutralHandArea;
  bool get fuseActive => _fuseActive;

  HandGestureCommand? interpret(HandGestureEvent event) {
    // 状态机只消费手势事件；姿态 / 状态 / 错误等事件直接忽略，
    // 避免它们在命令模式 / 跟随模式下重置长按计时器或下发零速命令。
    if (event.type != 'gesture') {
      return null;
    }

    final now = _now();
    final input = _FrameInput.fromEvent(event);

    if (currentMode == GestureControlMode.command) {
      return _processCommandMode(event, input, now);
    }
    return _processFollowMode(event, input, now);
  }

  void reset() {
    currentMode = GestureControlMode.command;
    _neutralHandArea = null;
    _fuseActive = false;
    _fuseReleaseSince = null;
    _openPalmStartedAt = null;
    _followFistStartedAt = null;
  }

  HandGestureCommand? _processCommandMode(
    HandGestureEvent event,
    _FrameInput input,
    DateTime now,
  ) {
    _followFistStartedAt = null;
    if (!_isHighConfidenceGesture(input)) {
      _openPalmStartedAt = null;
      return null;
    }

    switch (input.gesture) {
      case '张开手掌':
        _openPalmStartedAt ??= now;
        if (now.difference(_openPalmStartedAt!) >=
            config.openPalmEnterFollowHold) {
          return _enterMode(GestureControlMode.follow, event);
        }
        return null;
      case '握拳':
        _openPalmStartedAt = null;
        return _stopCommand(event);
      case '指向':
        _openPalmStartedAt = null;
        return _pointingCommand(event, input);
      default:
        _openPalmStartedAt = null;
        return null;
    }
  }

  HandGestureCommand? _processFollowMode(
    HandGestureEvent event,
    _FrameInput input,
    DateTime now,
  ) {
    _openPalmStartedAt = null;

    if (_isHighConfidenceGesture(input) && input.gesture == '握拳') {
      _followFistStartedAt ??= now;
      if (now.difference(_followFistStartedAt!) >=
          config.fistReturnCommandHold) {
        return _enterMode(GestureControlMode.command, event);
      }
      return _stopCommand(event);
    }
    _followFistStartedAt = null;

    if (!input.handDetected || input.handBBoxArea <= 0) {
      return _followMove(event, vx: 0, vy: 0, message: '跟随零速');
    }

    _neutralHandArea ??= _clamp(
      input.handBBoxArea,
      config.neutralAreaMin,
      config.neutralAreaMax,
    );

    // 优先级：先看横向位置，手掌偏离屏幕中心则只输出左右平移；
    // 仅当手掌在中心横向死区内时，才用手掌大小映射前后。
    // 这样做是因为 RobotClient.move 对手动控制是 last-wins 语义，
    // 同一帧里同时下发 vx 与 vy，前一帧零横向 vy 会反复覆盖横向意图，
    // 造成"只能前后、几乎不能左右"。
    final dx = input.handCenterX - 0.5;
    if (dx.abs() > config.lateralDeadZone) {
      final yawVel = _mapYawVelocity(dx);
      return _followMove(
        event,
        vx: 0,
        vy: 0,
        yaw: yawVel,
        message: '跟随转向',
      );
    }

    final areaError = input.handBBoxArea - _neutralHandArea!;
    final linearVel = _mapAreaVelocity(areaError);
    final fusedLinearVel = _applyAreaFuse(input.handBBoxArea, linearVel, now);
    return _followMove(
      event,
      vx: fusedLinearVel,
      vy: 0,
      message: '跟随前后',
    );
  }

  bool _isHighConfidenceGesture(_FrameInput input) {
    return input.handDetected && input.confidence >= config.highConfidence;
  }

  HandGestureCommand? _pointingCommand(
    HandGestureEvent event,
    _FrameInput input,
  ) {
    if (input.handCenterX < 0.5 - config.commandSideDeadZone) {
      return HandGestureCommand.move(
        message: '指向左侧平移左',
        vx: 0,
        vy: config.lateralCommandVy,
        yaw: 0,
        confidence: event.confidence,
        source: 'hand',
        gesture: event.gesture,
        metrics: event.metrics,
        raw: event.raw,
      );
    }
    if (input.handCenterX > 0.5 + config.commandSideDeadZone) {
      return HandGestureCommand.move(
        message: '指向右侧平移右',
        vx: 0,
        vy: -config.lateralCommandVy,
        yaw: 0,
        confidence: event.confidence,
        source: 'hand',
        gesture: event.gesture,
        metrics: event.metrics,
        raw: event.raw,
      );
    }
    return null;
  }

  HandGestureCommand _stopCommand(HandGestureEvent event) {
    return HandGestureCommand.stop(
      message: '握拳停止移动',
      confidence: event.confidence,
      source: 'hand',
      gesture: event.gesture,
      metrics: event.metrics,
      raw: event.raw,
    );
  }

  HandGestureCommand _followMove(
    HandGestureEvent event, {
    required double vx,
    required double vy,
    double yaw = 0,
    required String message,
  }) {
    return HandGestureCommand.move(
      message: message,
      vx: vx,
      vy: vy,
      yaw: yaw,
      confidence: event.confidence,
      source: 'follow',
      gesture: event.gesture,
      metrics: event.metrics,
      raw: event.raw,
    );
  }

  HandGestureCommand _enterMode(
    GestureControlMode mode,
    HandGestureEvent event,
  ) {
    currentMode = mode;
    _neutralHandArea = null;
    _fuseActive = false;
    _fuseReleaseSince = null;
    _openPalmStartedAt = null;
    _followFistStartedAt = null;
    return HandGestureCommand.modeChanged(
      mode: currentMode.name,
      message: currentMode == GestureControlMode.follow ? '进入跟随模式' : '进入指令模式',
      confidence: event.confidence,
      source: 'hand',
      gesture: event.gesture,
      metrics: event.metrics,
      raw: event.raw,
    );
  }

  double _mapAreaVelocity(double areaError) {
    if (areaError.abs() <= config.areaDeadZone) {
      return 0;
    }
    final effectiveArea =
        (areaError.abs() - config.areaDeadZone) * areaError.sign;
    final denom = config.maxAreaOffset - config.areaDeadZone;
    final norm = _clamp(effectiveArea.abs() / denom, 0, 1);
    // 面积变大（手靠近）→ vx < 0 后退让开；面积变小（手远离）→ vx > 0 跟进。
    return -math.sqrt(norm) * config.maxLinearVel * areaError.sign;
  }

  double _mapYawVelocity(double dx) {
    if (dx.abs() <= config.lateralDeadZone) {
      return 0;
    }
    final effectiveDx = (dx.abs() - config.lateralDeadZone) * dx.sign;
    final denom = config.maxXOffset - config.lateralDeadZone;
    final norm = _clamp(effectiveDx.abs() / denom, 0, 1);
    // 画面左侧(dx<0) → yaw>0(左转)，画面右侧(dx>0) → yaw<0(右转)，与转向摇杆语义一致。
    return -math.sqrt(norm) * config.maxYawVel * dx.sign;
  }

  double _applyAreaFuse(double area, double linearVel, DateTime now) {
    if (area >= config.fuseEnterArea) {
      _fuseActive = true;
      _fuseReleaseSince = null;
    }

    if (_fuseActive) {
      if (area < config.fuseReleaseArea) {
        _fuseReleaseSince ??= now;
        if (now.difference(_fuseReleaseSince!) >= config.fuseReleaseDuration) {
          _fuseActive = false;
          _fuseReleaseSince = null;
        }
      } else {
        _fuseReleaseSince = null;
      }
    }

    if (_fuseActive) {
      return math.min(linearVel, 0);
    }
    return linearVel;
  }

  double _clamp(double value, double min, double max) {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }
}

class _FrameInput {
  const _FrameInput({
    required this.handDetected,
    required this.gesture,
    required this.confidence,
    required this.handCenterX,
    required this.handBBoxArea,
  });

  factory _FrameInput.fromEvent(HandGestureEvent event) {
    final metrics = event.metrics ?? const <String, dynamic>{};
    final handDetected = _toBool(metrics['handDetected']);
    return _FrameInput(
      handDetected: handDetected,
      gesture: event.gesture ?? '',
      confidence: event.confidence ?? 0,
      handCenterX: _toDouble(metrics['handCenterX']) ?? 0.5,
      handBBoxArea: _toDouble(metrics['handBBoxArea']) ?? 0,
    );
  }

  final bool handDetected;
  final String gesture;
  final double confidence;
  final double handCenterX;
  final double handBBoxArea;

  static bool _toBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final normalized = value?.toString().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }

  static double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }
}
