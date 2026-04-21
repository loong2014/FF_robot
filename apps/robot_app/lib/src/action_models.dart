enum ActionCommandType { stand, move, sit, stop }

enum ActionStepStatus { pending, running, done, failed, skipped }

enum ActionEngineStatus { idle, running, paused, stopped, completed }

class ActionStep {
  const ActionStep._({
    required this.id,
    required this.type,
    this.vx = 0,
    this.vy = 0,
    this.yaw = 0,
    this.duration,
    this.maxRetries = 0,
  });

  factory ActionStep.stand({String? id, int maxRetries = 0}) => ActionStep._(
    id: id ?? _generateId(),
    type: ActionCommandType.stand,
    maxRetries: maxRetries,
  );

  factory ActionStep.sit({String? id, int maxRetries = 0}) => ActionStep._(
    id: id ?? _generateId(),
    type: ActionCommandType.sit,
    maxRetries: maxRetries,
  );

  factory ActionStep.stop({String? id, int maxRetries = 0}) => ActionStep._(
    id: id ?? _generateId(),
    type: ActionCommandType.stop,
    maxRetries: maxRetries,
  );

  factory ActionStep.move({
    String? id,
    required double vx,
    double vy = 0,
    double yaw = 0,
    required Duration duration,
    int maxRetries = 0,
  }) => ActionStep._(
    id: id ?? _generateId(),
    type: ActionCommandType.move,
    vx: vx,
    vy: vy,
    yaw: yaw,
    duration: duration,
    maxRetries: maxRetries,
  );

  final String id;
  final ActionCommandType type;
  final double vx;
  final double vy;
  final double yaw;
  final Duration? duration;
  final int maxRetries;

  ActionStep copyWith({
    double? vx,
    double? vy,
    double? yaw,
    Duration? duration,
    int? maxRetries,
  }) {
    return ActionStep._(
      id: id,
      type: type,
      vx: vx ?? this.vx,
      vy: vy ?? this.vy,
      yaw: yaw ?? this.yaw,
      duration: duration ?? this.duration,
      maxRetries: maxRetries ?? this.maxRetries,
    );
  }

  String get title {
    switch (type) {
      case ActionCommandType.stand:
        return '站立 · stand';
      case ActionCommandType.sit:
        return '坐下 · sit';
      case ActionCommandType.stop:
        return '停止 · stop';
      case ActionCommandType.move:
        return '移动 · move';
    }
  }

  String get summary {
    switch (type) {
      case ActionCommandType.stand:
      case ActionCommandType.sit:
      case ActionCommandType.stop:
        return maxRetries > 0 ? '重试 $maxRetries 次' : '无参数';
      case ActionCommandType.move:
        final ms = duration?.inMilliseconds ?? 0;
        final retry = maxRetries > 0 ? ' · 重试 $maxRetries 次' : '';
        return 'vx=${_fmt(vx)} vy=${_fmt(vy)} yaw=${_fmt(yaw)} · ${ms}ms$retry';
    }
  }

  static String _fmt(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(1);
    }
    return value.toStringAsFixed(2);
  }

  static int _idCounter = 0;
  static String _generateId() {
    _idCounter += 1;
    return 'step_${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }
}

class ActionStepProgress {
  const ActionStepProgress({
    required this.stepId,
    required this.status,
    this.attempts = 0,
    this.errorMessage,
  });

  const ActionStepProgress.pending(String stepId)
    : this(stepId: stepId, status: ActionStepStatus.pending);

  final String stepId;
  final ActionStepStatus status;
  final int attempts;
  final String? errorMessage;

  ActionStepProgress copyWith({
    ActionStepStatus? status,
    int? attempts,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ActionStepProgress(
      stepId: stepId,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ActionProgress {
  const ActionProgress({
    required this.engineStatus,
    required this.currentIndex,
    required this.steps,
  });

  const ActionProgress.idle()
    : engineStatus = ActionEngineStatus.idle,
      currentIndex = -1,
      steps = const <ActionStepProgress>[];

  final ActionEngineStatus engineStatus;
  final int currentIndex;
  final List<ActionStepProgress> steps;

  ActionStepProgress? progressFor(String stepId) {
    for (final step in steps) {
      if (step.stepId == stepId) {
        return step;
      }
    }
    return null;
  }
}
