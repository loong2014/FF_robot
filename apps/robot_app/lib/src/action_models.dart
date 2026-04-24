import 'package:mobile_sdk/mobile_sdk.dart';

enum ActionCommandType { stand, move, sit, stop, doAction, doDogBehavior }

enum ActionStepStatus { pending, running, done, failed, skipped }

enum ActionEngineStatus { idle, running, paused, stopped, completed }

class ActionStep {
  const ActionStep._({
    required this.id,
    required this.type,
    this.vx = 0,
    this.vy = 0,
    this.yaw = 0,
    this.actionId,
    this.behavior,
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

  factory ActionStep.doAction({
    String? id,
    required int actionId,
    int maxRetries = 0,
  }) => ActionStep._(
    id: id ?? _generateId(),
    type: ActionCommandType.doAction,
    actionId: actionId,
    maxRetries: maxRetries,
  );

  factory ActionStep.doDogBehavior({
    String? id,
    required DogBehavior behavior,
    int maxRetries = 0,
  }) => ActionStep._(
    id: id ?? _generateId(),
    type: ActionCommandType.doDogBehavior,
    behavior: behavior,
    maxRetries: maxRetries,
  );

  final String id;
  final ActionCommandType type;
  final double vx;
  final double vy;
  final double yaw;
  final int? actionId;
  final DogBehavior? behavior;
  final Duration? duration;
  final int maxRetries;

  ActionStep copyWith({
    double? vx,
    double? vy,
    double? yaw,
    int? actionId,
    DogBehavior? behavior,
    Duration? duration,
    int? maxRetries,
  }) {
    return ActionStep._(
      id: id,
      type: type,
      vx: vx ?? this.vx,
      vy: vy ?? this.vy,
      yaw: yaw ?? this.yaw,
      actionId: actionId ?? this.actionId,
      behavior: behavior ?? this.behavior,
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
      case ActionCommandType.doAction:
        return '动作 · do_action';
      case ActionCommandType.doDogBehavior:
        return '行为 · do_dog_behavior';
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
      case ActionCommandType.doAction:
        final retry = maxRetries > 0 ? ' · 重试 $maxRetries 次' : '';
        return 'action_id=${actionId ?? 0}$retry';
      case ActionCommandType.doDogBehavior:
        final retry = maxRetries > 0 ? ' · 重试 $maxRetries 次' : '';
        return 'behavior=${(behavior ?? DogBehavior.waveHand).displayLabel}$retry';
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

extension DogBehaviorLabel on DogBehavior {
  String get displayLabel {
    switch (this) {
      case DogBehavior.confused:
        return 'confused';
      case DogBehavior.confusedAgain:
        return 'confused_again';
      case DogBehavior.recoveryBalanceStand1:
        return 'recovery_balance_stand_1';
      case DogBehavior.recoveryBalanceStand:
        return 'recovery_balance_stand';
      case DogBehavior.recoveryBalanceStandHigh:
        return 'recovery_balance_stand_high';
      case DogBehavior.forceRecoveryBalanceStand:
        return 'force_recovery_balance_stand';
      case DogBehavior.forceRecoveryBalanceStandHigh:
        return 'force_recovery_balance_stand_high';
      case DogBehavior.recoveryDanceStandAndParams:
        return 'recovery_dance_stand_and_params';
      case DogBehavior.recoveryDanceStand:
        return 'recovery_dance_stand';
      case DogBehavior.recoveryDanceStandHigh:
        return 'recovery_dance_stand_high';
      case DogBehavior.recoveryDanceStandHighAndParams:
        return 'recovery_dance_stand_high_and_params';
      case DogBehavior.recoveryDanceStandPose:
        return 'recovery_dance_stand_pose';
      case DogBehavior.recoveryDanceStandHighPose:
        return 'recovery_dance_stand_high_pose';
      case DogBehavior.recoveryStandPose:
        return 'recovery_stand_pose';
      case DogBehavior.recoveryStandHighPose:
        return 'recovery_stand_high_pose';
      case DogBehavior.wait:
        return 'wait';
      case DogBehavior.cute:
        return 'cute';
      case DogBehavior.cute2:
        return 'cute_2';
      case DogBehavior.enjoyTouch:
        return 'enjoy_touch';
      case DogBehavior.veryEnjoy:
        return 'very_enjoy';
      case DogBehavior.eager:
        return 'eager';
      case DogBehavior.excited2:
        return 'excited_2';
      case DogBehavior.excited:
        return 'excited';
      case DogBehavior.crawl:
        return 'crawl';
      case DogBehavior.standAtEase:
        return 'stand_at_ease';
      case DogBehavior.rest:
        return 'rest';
      case DogBehavior.shakeSelf:
        return 'shake_self';
      case DogBehavior.backFlip:
        return 'back_flip';
      case DogBehavior.frontFlip:
        return 'front_flip';
      case DogBehavior.leftFlip:
        return 'left_flip';
      case DogBehavior.rightFlip:
        return 'right_flip';
      case DogBehavior.expressAffection:
        return 'express_affection';
      case DogBehavior.yawn:
        return 'yawn';
      case DogBehavior.danceInPlace:
        return 'dance_in_place';
      case DogBehavior.shakeHand:
        return 'shake_hand';
      case DogBehavior.waveHand:
        return 'wave_hand';
      case DogBehavior.drawHeart:
        return 'draw_heart';
      case DogBehavior.pushUp:
        return 'push_up';
      case DogBehavior.bow:
        return 'bow';
    }
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
