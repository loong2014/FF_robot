import 'dart:math' as math;

import 'hand_gesture_sdk_command.dart';
import 'hand_gesture_sdk_event.dart';

class GestureCommandInterpreter {
  GestureCommandInterpreter({DateTime Function()? nowProvider})
    : _now = nowProvider ?? DateTime.now;

  static const Duration _commandCooldown = Duration(milliseconds: 350);
  static const Duration _followHold = Duration(milliseconds: 900);
  static const double _ratioApproachThreshold = 1.18;
  static const double _ratioRetreatThreshold = 0.82;
  static const double _strafeLeftThreshold = 0.42;
  static const double _strafeRightThreshold = 0.58;

  final DateTime Function() _now;
  DateTime? _lastCommandAt;
  DateTime? _victoryStartedAt;
  double? _baselineHandArea;

  HandGestureCommand? interpret(HandGestureEvent event) {
    final now = _now();
    if (_lastCommandAt != null &&
        now.difference(_lastCommandAt!) < _commandCooldown) {
      return null;
    }

    final poseCommand = _interpretPose(event);
    if (poseCommand != null) {
      _lastCommandAt = now;
      return poseCommand;
    }

    final handCommand = _interpretHand(event, now);
    if (handCommand != null) {
      _lastCommandAt = now;
      return handCommand;
    }

    return null;
  }

  void reset() {
    _lastCommandAt = null;
    _victoryStartedAt = null;
    _baselineHandArea = null;
  }

  HandGestureCommand? _interpretPose(HandGestureEvent event) {
    final pose = event.pose;
    if (pose == null || pose.isEmpty) {
      return null;
    }

    if (pose == '站起') {
      return HandGestureCommand.stand(
        message: '站起',
        confidence: event.confidence,
        source: 'pose',
        pose: pose,
        metrics: event.metrics,
        raw: event.raw,
      );
    }

    if (pose == '蹲下') {
      return HandGestureCommand.sit(
        message: '蹲下',
        confidence: event.confidence,
        source: 'pose',
        pose: pose,
        metrics: event.metrics,
        raw: event.raw,
      );
    }

    return null;
  }

  HandGestureCommand? _interpretHand(HandGestureEvent event, DateTime now) {
    final gesture = event.gesture;
    if (gesture == null || gesture.isEmpty) {
      if (event.type == 'status' &&
          (event.message.contains('未检测到手部') ||
              event.message.contains('请展示手部') ||
              event.message.contains('不可用'))) {
        _victoryStartedAt = null;
        _baselineHandArea = null;
      }
      return null;
    }

    if (gesture == '握拳') {
      _victoryStartedAt = null;
      return HandGestureCommand.stop(
        message: '握拳停止',
        confidence: event.confidence,
        source: 'hand',
        gesture: gesture,
        metrics: event.metrics,
        raw: event.raw,
      );
    }

    if (gesture == '胜利') {
      _victoryStartedAt ??= now;
      if (now.difference(_victoryStartedAt!) >= _followHold) {
        _victoryStartedAt = null;
        return HandGestureCommand.follow(
          message: '跟随',
          confidence: event.confidence,
          source: 'hand',
          gesture: gesture,
          metrics: event.metrics,
          raw: event.raw,
        );
      }
      return null;
    }

    _victoryStartedAt = null;

    if (gesture != '张开手掌') {
      return null;
    }

    final metrics = event.metrics ?? const <String, dynamic>{};
    final handArea = _toDouble(metrics['handArea']);
    final handCenterX = _toDouble(metrics['handCenterX']);
    final confidence = event.confidence ?? 0.85;

    if (handArea != null && handArea > 0) {
      _baselineHandArea = _updateBaseline(_baselineHandArea, handArea);
      if (_baselineHandArea != null && _baselineHandArea! > 0) {
        final ratio = handArea / _baselineHandArea!;
        if (ratio >= _ratioApproachThreshold) {
          return HandGestureCommand.move(
            message: '接近',
            vx: _scaleRatio(ratio - 1.0),
            vy: 0,
            yaw: 0,
            confidence: confidence,
            source: 'hand',
            gesture: gesture,
            metrics: metrics,
            raw: event.raw,
          );
        }
        if (ratio <= _ratioRetreatThreshold) {
          return HandGestureCommand.move(
            message: '远离',
            vx: -_scaleRatio(1.0 - ratio),
            vy: 0,
            yaw: 0,
            confidence: confidence,
            source: 'hand',
            gesture: gesture,
            metrics: metrics,
            raw: event.raw,
          );
        }
      }
    }

    if (handCenterX != null) {
      if (handCenterX <= _strafeLeftThreshold) {
        return HandGestureCommand.move(
          message: '平移左',
          vx: 0,
          vy: 0.3,
          yaw: 0,
          confidence: confidence,
          source: 'hand',
          gesture: gesture,
          metrics: metrics,
          raw: event.raw,
        );
      }
      if (handCenterX >= _strafeRightThreshold) {
        return HandGestureCommand.move(
          message: '平移右',
          vx: 0,
          vy: -0.3,
          yaw: 0,
          confidence: confidence,
          source: 'hand',
          gesture: gesture,
          metrics: metrics,
          raw: event.raw,
        );
      }
    }

    return null;
  }

  double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  double _scaleRatio(double delta) {
    return math.max(0.18, math.min(0.45, delta * 0.8));
  }

  double _updateBaseline(double? baseline, double sample) {
    if (baseline == null || baseline <= 0) {
      return sample;
    }
    return baseline * 0.9 + sample * 0.1;
  }
}
