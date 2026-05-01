enum HandGestureCommandType {
  move,
  stand,
  sit,
  follow,
  stop,
  modeChanged,
  unknown,
}

class HandGestureCommand {
  const HandGestureCommand({
    required this.type,
    required this.message,
    this.vx,
    this.vy,
    this.yaw,
    this.confidence,
    this.source,
    this.gesture,
    this.pose,
    this.mode,
    this.metrics,
    this.raw,
  });

  final HandGestureCommandType type;
  final String message;
  final double? vx;
  final double? vy;
  final double? yaw;
  final double? confidence;
  final String? source;
  final String? gesture;
  final String? pose;
  final String? mode;
  final Map<String, dynamic>? metrics;
  final Map<String, dynamic>? raw;

  bool get isMove => type == HandGestureCommandType.move;

  factory HandGestureCommand.move({
    required String message,
    double vx = 0,
    double vy = 0,
    double yaw = 0,
    double? confidence,
    String? source,
    String? gesture,
    String? pose,
    String? mode,
    Map<String, dynamic>? metrics,
    Map<String, dynamic>? raw,
  }) {
    return HandGestureCommand(
      type: HandGestureCommandType.move,
      message: message,
      vx: vx,
      vy: vy,
      yaw: yaw,
      confidence: confidence,
      source: source,
      gesture: gesture,
      pose: pose,
      mode: mode,
      metrics: metrics,
      raw: raw,
    );
  }

  factory HandGestureCommand.stand({
    String message = '站起',
    double? confidence,
    String? source,
    String? gesture,
    String? pose,
    String? mode,
    Map<String, dynamic>? metrics,
    Map<String, dynamic>? raw,
  }) {
    return HandGestureCommand(
      type: HandGestureCommandType.stand,
      message: message,
      confidence: confidence,
      source: source,
      gesture: gesture,
      pose: pose,
      mode: mode,
      metrics: metrics,
      raw: raw,
    );
  }

  factory HandGestureCommand.sit({
    String message = '蹲下',
    double? confidence,
    String? source,
    String? gesture,
    String? pose,
    String? mode,
    Map<String, dynamic>? metrics,
    Map<String, dynamic>? raw,
  }) {
    return HandGestureCommand(
      type: HandGestureCommandType.sit,
      message: message,
      confidence: confidence,
      source: source,
      gesture: gesture,
      pose: pose,
      mode: mode,
      metrics: metrics,
      raw: raw,
    );
  }

  factory HandGestureCommand.follow({
    String message = '跟随',
    double? confidence,
    String? source,
    String? gesture,
    String? pose,
    String? mode,
    Map<String, dynamic>? metrics,
    Map<String, dynamic>? raw,
  }) {
    return HandGestureCommand(
      type: HandGestureCommandType.follow,
      message: message,
      confidence: confidence,
      source: source,
      gesture: gesture,
      pose: pose,
      mode: mode,
      metrics: metrics,
      raw: raw,
    );
  }

  factory HandGestureCommand.stop({
    String message = '停止',
    double? confidence,
    String? source,
    String? gesture,
    String? pose,
    String? mode,
    Map<String, dynamic>? metrics,
    Map<String, dynamic>? raw,
  }) {
    return HandGestureCommand(
      type: HandGestureCommandType.stop,
      message: message,
      confidence: confidence,
      source: source,
      gesture: gesture,
      pose: pose,
      mode: mode,
      metrics: metrics,
      raw: raw,
    );
  }

  factory HandGestureCommand.modeChanged({
    required String mode,
    required String message,
    double? confidence,
    String? source,
    String? gesture,
    String? pose,
    Map<String, dynamic>? metrics,
    Map<String, dynamic>? raw,
  }) {
    return HandGestureCommand(
      type: HandGestureCommandType.modeChanged,
      message: message,
      confidence: confidence,
      source: source,
      gesture: gesture,
      pose: pose,
      mode: mode,
      metrics: metrics,
      raw: raw,
    );
  }

  factory HandGestureCommand.unknown({
    required String message,
    double? confidence,
    String? source,
    String? gesture,
    String? pose,
    String? mode,
    Map<String, dynamic>? metrics,
    Map<String, dynamic>? raw,
  }) {
    return HandGestureCommand(
      type: HandGestureCommandType.unknown,
      message: message,
      confidence: confidence,
      source: source,
      gesture: gesture,
      pose: pose,
      mode: mode,
      metrics: metrics,
      raw: raw,
    );
  }
}
