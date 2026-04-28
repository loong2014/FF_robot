class HandGestureEvent {
  const HandGestureEvent({
    required this.type,
    required this.message,
    this.gesture,
    this.pose,
    this.confidence,
    this.metrics,
    this.raw,
  });

  final String type;
  final String message;
  final String? gesture;
  final String? pose;
  final double? confidence;
  final Map<String, dynamic>? metrics;
  final Map<String, dynamic>? raw;

  factory HandGestureEvent.fromMap(Map<dynamic, dynamic> map) {
    final typed = Map<String, dynamic>.from(map);
    final metricsValue = typed['metrics'];
    return HandGestureEvent(
      type: typed['type']?.toString() ?? 'status',
      message: typed['message']?.toString() ?? '',
      gesture: typed['gesture']?.toString(),
      pose: typed['pose']?.toString(),
      confidence: typed['confidence'] is num
          ? (typed['confidence'] as num).toDouble()
          : double.tryParse(typed['confidence']?.toString() ?? ''),
      metrics: metricsValue is Map
          ? Map<String, dynamic>.from(metricsValue)
          : null,
      raw: typed,
    );
  }
}
