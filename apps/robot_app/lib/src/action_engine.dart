import 'dart:async';

import 'package:mobile_sdk/mobile_sdk.dart';

import 'action_models.dart';

typedef _SleepFn = Future<void> Function(Duration);
typedef _NowFn = DateTime Function();

class ActionEngine {
  ActionEngine(
    this.client, {
    @pragma('vm:prefer-inline') _SleepFn? sleep,
    _NowFn? now,
  }) : _sleep = sleep ?? _defaultSleep,
       _now = now ?? DateTime.now;

  final RobotClient client;
  final _SleepFn _sleep;
  final _NowFn _now;

  final StreamController<ActionEngineStatus> _statusController =
      StreamController<ActionEngineStatus>.broadcast();
  final StreamController<ActionProgress> _progressController =
      StreamController<ActionProgress>.broadcast();

  ActionEngineStatus _status = ActionEngineStatus.idle;
  bool _pauseRequested = false;
  bool _stopRequested = false;
  Completer<void>? _resumeCompleter;

  List<ActionStep> _program = const <ActionStep>[];
  List<ActionStepProgress> _stepProgress = const <ActionStepProgress>[];
  int _currentIndex = -1;

  Stream<ActionEngineStatus> get statusStream => _statusController.stream;

  Stream<ActionProgress> get progressStream => _progressController.stream;

  ActionEngineStatus get status => _status;

  ActionProgress get currentProgress => ActionProgress(
    engineStatus: _status,
    currentIndex: _currentIndex,
    steps: List<ActionStepProgress>.unmodifiable(_stepProgress),
  );

  Future<void> run(List<ActionStep> program) async {
    if (_status == ActionEngineStatus.running ||
        _status == ActionEngineStatus.paused) {
      return;
    }

    _stopRequested = false;
    _pauseRequested = false;
    _program = List<ActionStep>.unmodifiable(program);
    _stepProgress = List<ActionStepProgress>.from(
      program.map<ActionStepProgress>(
        (step) => ActionStepProgress.pending(step.id),
      ),
    );
    _currentIndex = -1;
    _setStatus(ActionEngineStatus.running);
    _emitProgress();

    bool failedEarly = false;
    for (var i = 0; i < _program.length; i++) {
      _currentIndex = i;
      _updateStep(i, status: ActionStepStatus.running, attempts: 0);
      await _waitIfPaused();
      if (_stopRequested) {
        _markRemainingSkipped(from: i);
        break;
      }

      final step = _program[i];
      final ok = await _executeStepWithRetry(step, i);
      if (!ok) {
        failedEarly = true;
        _markRemainingSkipped(from: i + 1);
        break;
      }
    }

    _currentIndex = -1;
    if (_stopRequested) {
      _setStatus(ActionEngineStatus.stopped);
    } else if (failedEarly) {
      _setStatus(ActionEngineStatus.stopped);
    } else {
      _setStatus(ActionEngineStatus.completed);
    }
    _emitProgress();
  }

  void pause() {
    if (_status != ActionEngineStatus.running) {
      return;
    }
    _pauseRequested = true;
    _setStatus(ActionEngineStatus.paused);
    _emitProgress();
  }

  void resume() {
    if (_status != ActionEngineStatus.paused) {
      return;
    }
    _pauseRequested = false;
    _resumeCompleter?.complete();
    _resumeCompleter = null;
    _setStatus(ActionEngineStatus.running);
    _emitProgress();
  }

  Future<void> stop() async {
    _stopRequested = true;
    _pauseRequested = false;
    _resumeCompleter?.complete();
    _resumeCompleter = null;

    try {
      await client.stop();
    } catch (_) {
      // 忽略停止期间的失败，主要是尽量让机器人停下来。
    }

    if (_status == ActionEngineStatus.idle ||
        _status == ActionEngineStatus.completed ||
        _status == ActionEngineStatus.stopped) {
      _setStatus(ActionEngineStatus.stopped);
      _emitProgress();
    }
  }

  Future<void> dispose() async {
    await _statusController.close();
    await _progressController.close();
  }

  Future<bool> _executeStepWithRetry(ActionStep step, int index) async {
    final maxAttempts = step.maxRetries + 1;
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      _updateStep(
        index,
        status: ActionStepStatus.running,
        attempts: attempt,
        clearError: true,
      );
      try {
        await _runOne(step);
        if (_stopRequested) {
          return false;
        }
        _updateStep(
          index,
          status: ActionStepStatus.done,
          attempts: attempt,
          clearError: true,
        );
        return true;
      } catch (error) {
        lastError = error;
        if (_stopRequested) {
          _updateStep(
            index,
            status: ActionStepStatus.failed,
            attempts: attempt,
            errorMessage: error.toString(),
          );
          return false;
        }
        if (attempt >= maxAttempts) {
          _updateStep(
            index,
            status: ActionStepStatus.failed,
            attempts: attempt,
            errorMessage: error.toString(),
          );
          return false;
        }
        _updateStep(
          index,
          status: ActionStepStatus.running,
          attempts: attempt,
          errorMessage: error.toString(),
        );
      }
    }

    _updateStep(
      index,
      status: ActionStepStatus.failed,
      attempts: maxAttempts,
      errorMessage: lastError?.toString() ?? 'unknown error',
    );
    return false;
  }

  Future<void> _runOne(ActionStep step) async {
    switch (step.type) {
      case ActionCommandType.stand:
        await client.stand();
        break;
      case ActionCommandType.sit:
        await client.sit();
        break;
      case ActionCommandType.stop:
        await client.stop();
        break;
      case ActionCommandType.move:
        await _runMove(step);
        break;
    }
  }

  Future<void> _runMove(ActionStep step) async {
    final duration = step.duration ?? Duration.zero;
    final deadline = _now().add(duration);

    do {
      await _waitIfPaused();
      if (_stopRequested) {
        return;
      }
      await client.move(step.vx, step.vy, step.yaw);
      if (duration == Duration.zero) {
        break;
      }
      await _sleep(const Duration(milliseconds: 100));
    } while (_now().isBefore(deadline));

    await client.stop();
  }

  Future<void> _waitIfPaused() async {
    while (_pauseRequested && !_stopRequested) {
      _resumeCompleter ??= Completer<void>();
      await _resumeCompleter!.future;
    }
  }

  void _markRemainingSkipped({required int from}) {
    for (var i = from; i < _stepProgress.length; i++) {
      final current = _stepProgress[i];
      if (current.status == ActionStepStatus.pending ||
          current.status == ActionStepStatus.running) {
        _stepProgress[i] = current.copyWith(
          status: ActionStepStatus.skipped,
          clearError: true,
        );
      }
    }
  }

  void _updateStep(
    int index, {
    required ActionStepStatus status,
    required int attempts,
    String? errorMessage,
    bool clearError = false,
  }) {
    if (index < 0 || index >= _stepProgress.length) {
      return;
    }
    _stepProgress[index] = _stepProgress[index].copyWith(
      status: status,
      attempts: attempts,
      errorMessage: errorMessage,
      clearError: clearError,
    );
    _emitProgress();
  }

  void _setStatus(ActionEngineStatus status) {
    _status = status;
    _statusController.add(status);
  }

  void _emitProgress() {
    _progressController.add(currentProgress);
  }

  static Future<void> _defaultSleep(Duration duration) =>
      Future<void>.delayed(duration);
}
