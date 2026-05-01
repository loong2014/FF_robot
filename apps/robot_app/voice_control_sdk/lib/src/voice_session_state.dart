import 'voice_models.dart';
import 'voice_wake_mapper.dart';

enum VoiceSessionFinishReason {
  none,
  silenceTimeout,
  noSpeechTimeout,
  maxActiveDuration,
}

class VoiceSessionWakeDecision {
  const VoiceSessionWakeDecision({
    required this.accepted,
    this.match,
  });

  final bool accepted;
  final VoiceWakeMatch? match;
}

class VoiceSessionVadDecision {
  const VoiceSessionVadDecision({
    required this.finishReason,
  });

  final VoiceSessionFinishReason finishReason;

  bool get shouldFinish => finishReason != VoiceSessionFinishReason.none;
}

class VoiceSessionStateMachine {
  VoiceSessionStateMachine({
    required VoiceConfig config,
    DateTime Function()? clock,
    this.speechMinDuration = const Duration(milliseconds: 300),
  })  : _config = config,
        _clock = clock ?? (() => DateTime.now().toUtc());

  final VoiceConfig _config;
  final DateTime Function() _clock;
  final Duration speechMinDuration;

  VoiceRecognitionState _state = VoiceRecognitionState.stopped;
  DateTime _wakeDebounceUntil =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  DateTime? _activeStartedAt;
  DateTime? _lastSpeechEndedAt;
  Duration _speechCandidateDuration = Duration.zero;
  bool _speechActive = false;
  bool _hasEffectiveSpeech = false;

  VoiceRecognitionState get state => _state;

  DateTime get wakeDebounceUntil => _wakeDebounceUntil;

  bool get hasEffectiveSpeech => _hasEffectiveSpeech;

  void markStarting() {
    _state = VoiceRecognitionState.starting;
    _resetActive();
  }

  void markWaitingForWake() {
    _state = VoiceRecognitionState.waitingForWake;
    _resetActive();
  }

  void stop() {
    _state = VoiceRecognitionState.stopped;
    _resetActive();
  }

  void markError() {
    _state = VoiceRecognitionState.error;
    _resetActive();
  }

  VoiceSessionWakeDecision handleWakeCandidate(VoiceWakeMatch match) {
    final now = _clock();
    if (_state != VoiceRecognitionState.waitingForWake ||
        now.isBefore(_wakeDebounceUntil)) {
      return const VoiceSessionWakeDecision(accepted: false);
    }

    _wakeDebounceUntil = now.add(_config.wakeDebounce);
    _state = VoiceRecognitionState.wakeDetected;
    return VoiceSessionWakeDecision(accepted: true, match: match);
  }

  void beginActiveListening() {
    _state = VoiceRecognitionState.activeListening;
    _activeStartedAt = _clock();
    _lastSpeechEndedAt = null;
    _speechCandidateDuration = Duration.zero;
    _speechActive = false;
    _hasEffectiveSpeech = false;
  }

  VoiceSessionVadDecision observeVad({
    required bool speechDetected,
    required Duration chunkDuration,
  }) {
    if (_state != VoiceRecognitionState.activeListening ||
        _activeStartedAt == null) {
      return const VoiceSessionVadDecision(
        finishReason: VoiceSessionFinishReason.none,
      );
    }

    final now = _clock();
    if (speechDetected) {
      _speechCandidateDuration += chunkDuration;
      if (_speechCandidateDuration >= speechMinDuration) {
        _speechActive = true;
        _hasEffectiveSpeech = true;
        _lastSpeechEndedAt = null;
      }
    } else {
      if (_speechActive) {
        _lastSpeechEndedAt = now;
      }
      _speechActive = false;
      _speechCandidateDuration = Duration.zero;
    }

    final activeDuration = now.difference(_activeStartedAt!);
    if (activeDuration >= _config.maxActiveDuration) {
      return const VoiceSessionVadDecision(
        finishReason: VoiceSessionFinishReason.maxActiveDuration,
      );
    }

    if (!_hasEffectiveSpeech &&
        activeDuration >= _config.activeNoSpeechTimeout) {
      return const VoiceSessionVadDecision(
        finishReason: VoiceSessionFinishReason.noSpeechTimeout,
      );
    }

    final lastSpeechEndedAt = _lastSpeechEndedAt;
    if (_hasEffectiveSpeech &&
        !_speechActive &&
        lastSpeechEndedAt != null &&
        now.difference(lastSpeechEndedAt) >= _config.vadSilence) {
      return const VoiceSessionVadDecision(
        finishReason: VoiceSessionFinishReason.silenceTimeout,
      );
    }

    return const VoiceSessionVadDecision(
      finishReason: VoiceSessionFinishReason.none,
    );
  }

  void beginProcessingCommand() {
    _state = VoiceRecognitionState.processingCommand;
  }

  void finishProcessingCommand() {
    markWaitingForWake();
  }

  String messageFor(VoiceRecognitionState state) {
    switch (state) {
      case VoiceRecognitionState.stopped:
        return '语音服务已停止';
      case VoiceRecognitionState.starting:
        return '正在启动语音控制';
      case VoiceRecognitionState.waitingForWake:
        return '等待 Lumi / 鲁米 唤醒';
      case VoiceRecognitionState.wakeDetected:
        return '已唤醒，请说指令';
      case VoiceRecognitionState.activeListening:
        return '正在识别语音指令';
      case VoiceRecognitionState.processingCommand:
        return '正在处理指令';
      case VoiceRecognitionState.error:
        return '语音控制异常';
    }
  }

  void _resetActive() {
    _activeStartedAt = null;
    _lastSpeechEndedAt = null;
    _speechCandidateDuration = Duration.zero;
    _speechActive = false;
    _hasEffectiveSpeech = false;
  }
}
