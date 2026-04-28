import 'dart:math' as math;

import 'package:flutter/material.dart';

class JoystickPad extends StatefulWidget {
  const JoystickPad({
    super.key,
    required this.onMove,
    required this.onEnd,
    this.size = 196,
    this.showArrows = true,
    this.isRotation = false,
  });

  final void Function(double dx, double dy) onMove;
  final VoidCallback onEnd;
  final double size;
  final bool showArrows;
  final bool isRotation;

  @override
  State<JoystickPad> createState() => _JoystickPadState();
}

class _JoystickPadState extends State<JoystickPad> {
  Offset _knobOffset = Offset.zero;
  bool _dragging = false;

  double get _radius => widget.size / 2;
  double get _knobRadius => _radius * 0.24;

  void _updateKnob(Offset localPosition) {
    final center = Offset(_radius, _radius);
    var delta = localPosition - center;
    final distance = delta.distance;
    final maxDistance = _radius - _knobRadius - 10;
    if (distance > maxDistance) {
      delta = delta / distance * maxDistance;
    }

    setState(() {
      _knobOffset = delta;
      _dragging = true;
    });

    widget.onMove(delta.dx / maxDistance, -delta.dy / maxDistance);
  }

  void _resetKnob() {
    setState(() {
      _knobOffset = Offset.zero;
      _dragging = false;
    });
    widget.onEnd();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => _updateKnob(details.localPosition),
        onPanUpdate: (details) => _updateKnob(details.localPosition),
        onPanEnd: (_) => _resetKnob(),
        onPanCancel: _resetKnob,
        child: CustomPaint(
          painter: _JoystickPainter(
            knobOffset: _knobOffset,
            knobRadius: _knobRadius,
            dragging: _dragging,
            showArrows: widget.showArrows,
            isRotation: widget.isRotation,
          ),
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  const _JoystickPainter({
    required this.knobOffset,
    required this.knobRadius,
    required this.dragging,
    required this.showArrows,
    required this.isRotation,
  });

  final Offset knobOffset;
  final double knobRadius;
  final bool dragging;
  final bool showArrows;
  final bool isRotation;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    final cardPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[Color(0xFFFFFFFF), Color(0xFFF3F5FA)],
      ).createShader(Offset.zero & size);
    final cardRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(32),
    );
    canvas.drawRRect(cardRect, cardPaint);

    final ringPaint = Paint()
      ..color = const Color(0xFF3E86FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    canvas.drawCircle(center, radius - 16, ringPaint);

    if (isRotation) {
      _drawRotationMarks(canvas, center, radius - 28);
    } else if (showArrows) {
      _drawArrows(canvas, center, radius - 28);
    }

    final glowPaint = Paint()
      ..color = const Color(0xFF6CA7FF).withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(center + knobOffset, knobRadius + 10, glowPaint);

    final knobPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[Color(0xFF5DA0FF), Color(0xFF2E78F6)],
      ).createShader(
        Rect.fromCircle(center: center + knobOffset, radius: knobRadius),
      );
    canvas.drawCircle(center + knobOffset, knobRadius, knobPaint);

    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: dragging ? 0.28 : 0.2);
    canvas.drawCircle(
      center + knobOffset - Offset(knobRadius * 0.22, knobRadius * 0.22),
      knobRadius * 0.36,
      highlightPaint,
    );
  }

  void _drawArrows(Canvas canvas, Offset center, double radius) {
    final arrowPaint = Paint()
      ..color = const Color(0xFF3E86FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const arrowSize = 10.0;
    _drawArrow(canvas, center + Offset(0, -radius), -math.pi / 2, arrowSize,
        arrowPaint);
    _drawArrow(canvas, center + Offset(radius, 0), 0, arrowSize, arrowPaint);
    _drawArrow(
        canvas, center + Offset(0, radius), math.pi / 2, arrowSize, arrowPaint);
    _drawArrow(
        canvas, center + Offset(-radius, 0), math.pi, arrowSize, arrowPaint);
  }

  void _drawRotationMarks(Canvas canvas, Offset center, double radius) {
    final markPaint = Paint()
      ..color = const Color(0xFF3E86FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (final angle in <double>[
      -math.pi / 2,
      0,
      math.pi / 2,
      math.pi,
    ]) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        angle - 0.42,
        0.84,
        false,
        markPaint,
      );
    }
  }

  void _drawArrow(
    Canvas canvas,
    Offset tip,
    double angle,
    double size,
    Paint paint,
  ) {
    final left = tip +
        Offset(
          math.cos(angle + 2.42) * size,
          math.sin(angle + 2.42) * size,
        );
    final right = tip +
        Offset(
          math.cos(angle - 2.42) * size,
          math.sin(angle - 2.42) * size,
        );
    canvas.drawLine(left, tip, paint);
    canvas.drawLine(right, tip, paint);
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) {
    return oldDelegate.knobOffset != knobOffset ||
        oldDelegate.dragging != dragging ||
        oldDelegate.showArrows != showArrows ||
        oldDelegate.isRotation != isRotation;
  }
}
