import 'dart:collection';

enum VoiceEngineType { sherpa, native, unknown }

enum VoiceRecognitionState {
  stopped,
  starting,
  listening,
  wakeDetected,
  activeListening,
  cooldown,
  error,
}

enum VoiceEventSource { android, ios, unknown }

enum VoiceLanguage { zh, en, mixed, unknown }

enum VoiceCommand { standUp, sitDown, forward, backward, unknown }

extension VoiceEngineTypeWire on VoiceEngineType {
  String get wireName => switch (this) {
        VoiceEngineType.sherpa => 'sherpa',
        VoiceEngineType.native => 'native',
        VoiceEngineType.unknown => 'unknown',
      };
}

extension VoiceRecognitionStateWire on VoiceRecognitionState {
  String get wireName => switch (this) {
        VoiceRecognitionState.stopped => 'stopped',
        VoiceRecognitionState.starting => 'starting',
        VoiceRecognitionState.listening => 'listening',
        VoiceRecognitionState.wakeDetected => 'wake_detected',
        VoiceRecognitionState.activeListening => 'active_listening',
        VoiceRecognitionState.cooldown => 'cooldown',
        VoiceRecognitionState.error => 'error',
      };
}

extension VoiceEventSourceWire on VoiceEventSource {
  String get wireName => switch (this) {
        VoiceEventSource.android => 'android',
        VoiceEventSource.ios => 'ios',
        VoiceEventSource.unknown => 'unknown',
      };
}

extension VoiceLanguageWire on VoiceLanguage {
  String get wireName => switch (this) {
        VoiceLanguage.zh => 'zh',
        VoiceLanguage.en => 'en',
        VoiceLanguage.mixed => 'mixed',
        VoiceLanguage.unknown => 'unknown',
      };
}

extension VoiceCommandWire on VoiceCommand {
  String get wireName => switch (this) {
        VoiceCommand.standUp => 'stand_up',
        VoiceCommand.sitDown => 'sit_down',
        VoiceCommand.forward => 'forward',
        VoiceCommand.backward => 'backward',
        VoiceCommand.unknown => 'unknown',
      };
}

VoiceEngineType voiceEngineTypeFromWire(String? value) {
  switch (value) {
    case 'sherpa':
      return VoiceEngineType.sherpa;
    case 'native':
      return VoiceEngineType.native;
    default:
      return VoiceEngineType.unknown;
  }
}

VoiceRecognitionState voiceRecognitionStateFromWire(String? value) {
  switch (value) {
    case 'stopped':
      return VoiceRecognitionState.stopped;
    case 'starting':
      return VoiceRecognitionState.starting;
    case 'listening':
      return VoiceRecognitionState.listening;
    case 'wake_detected':
      return VoiceRecognitionState.wakeDetected;
    case 'active_listening':
      return VoiceRecognitionState.activeListening;
    case 'cooldown':
      return VoiceRecognitionState.cooldown;
    case 'error':
      return VoiceRecognitionState.error;
    default:
      return VoiceRecognitionState.stopped;
  }
}

VoiceEventSource voiceEventSourceFromWire(String? value) {
  switch (value) {
    case 'android':
      return VoiceEventSource.android;
    case 'ios':
      return VoiceEventSource.ios;
    default:
      return VoiceEventSource.unknown;
  }
}

VoiceLanguage voiceLanguageFromWire(String? value) {
  switch (value) {
    case 'zh':
      return VoiceLanguage.zh;
    case 'en':
      return VoiceLanguage.en;
    case 'mixed':
      return VoiceLanguage.mixed;
    default:
      return VoiceLanguage.unknown;
  }
}

VoiceCommand voiceCommandFromWire(String? value) {
  switch (value) {
    case 'stand_up':
      return VoiceCommand.standUp;
    case 'sit_down':
      return VoiceCommand.sitDown;
    case 'forward':
      return VoiceCommand.forward;
    case 'backward':
      return VoiceCommand.backward;
    default:
      return VoiceCommand.unknown;
  }
}

DateTime voiceTimestampFromMap(Map<String, Object?> map) {
  final Object? timestampMs = map['timestampMs'] ?? map['timestamp_ms'];
  if (timestampMs is int) {
    return DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true);
  }
  if (timestampMs is num) {
    return DateTime.fromMillisecondsSinceEpoch(timestampMs.round(),
        isUtc: true);
  }
  final Object? timestampIso = map['timestamp'] ?? map['timestamp_iso'];
  if (timestampIso is String && timestampIso.isNotEmpty) {
    return DateTime.tryParse(timestampIso)?.toUtc() ?? DateTime.now().toUtc();
  }
  return DateTime.now().toUtc();
}

Map<String, Object?> _unmodifiablePayload(Map<String, Object?> payload) {
  return Map<String, Object?>.unmodifiable(payload);
}

double _readDouble(
  Map<String, Object?> map,
  String key, {
  required double fallback,
}) {
  final Object? value = map[key];
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return fallback;
}

int _readInt(
  Map<String, Object?> map,
  String key, {
  required int fallback,
}) {
  final Object? value = map[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return fallback;
}

bool _readBool(
  Map<String, Object?> map,
  String key, {
  required bool fallback,
}) {
  final Object? value = map[key];
  if (value is bool) {
    return value;
  }
  return fallback;
}

Map<String, Object?> _readMap(Map<String, Object?> map, String key) {
  final Object? value = map[key];
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      result[entry.key.toString()] = entry.value;
    }
    return UnmodifiableMapView<String, Object?>(result);
  }
  return const <String, Object?>{};
}

abstract class VoiceEvent {
  const VoiceEvent({
    required this.type,
    required this.timestamp,
    required this.source,
    required this.payload,
  });

  final String type;
  final DateTime timestamp;
  final VoiceEventSource source;
  final Map<String, Object?> payload;
}

VoiceEvent voiceEventFromMap(Map<String, Object?> map) {
  switch ((map['type'] ?? '').toString()) {
    case 'wake':
      return VoiceWakeEvent.fromMap(map);
    case 'asr':
      return VoiceAsrEvent.fromMap(map);
    case 'command':
      return VoiceCommandEvent.fromMap(map);
    case 'state':
      return VoiceStateEvent.fromMap(map);
    case 'error':
      return VoiceErrorEvent.fromMap(map);
    case 'telemetry':
    case 'audio':
      return VoiceTelemetryEvent.fromMap(map);
    default:
      return VoiceTelemetryEvent.fromMap(map);
  }
}

class VoiceWakeEvent extends VoiceEvent {
  const VoiceWakeEvent({
    required super.timestamp,
    required super.source,
    required super.payload,
    required this.wakeWord,
    required this.recognizedText,
    required this.resultLabel,
    required this.language,
    required this.confidence,
  }) : super(type: 'wake');

  final String wakeWord;
  final String recognizedText;
  final String resultLabel;
  final VoiceLanguage language;
  final double confidence;

  factory VoiceWakeEvent.fromMap(Map<String, Object?> map) {
    return VoiceWakeEvent(
      timestamp: voiceTimestampFromMap(map),
      source: voiceEventSourceFromWire(map['source'] as String?),
      wakeWord: (map['wakeWord'] ?? map['wake_word'] ?? 'D-Dog').toString(),
      recognizedText: (map['recognizedText'] ??
              map['recognized_text'] ??
              map['wakeWord'] ??
              map['wake_word'] ??
              'D-Dog')
          .toString(),
      resultLabel: (map['resultLabel'] ?? map['result_label'] ?? '').toString(),
      language: voiceLanguageFromWire(map['language'] as String?),
      confidence: _readDouble(map, 'confidence', fallback: 1.0),
      payload: _unmodifiablePayload(map),
    );
  }
}

class VoiceAsrEvent extends VoiceEvent {
  const VoiceAsrEvent({
    required super.timestamp,
    required super.source,
    required super.payload,
    required this.text,
    required this.language,
    required this.confidence,
    required this.isFinal,
  }) : super(type: 'asr');

  final String text;
  final VoiceLanguage language;
  final double confidence;
  final bool isFinal;

  factory VoiceAsrEvent.fromMap(Map<String, Object?> map) {
    return VoiceAsrEvent(
      timestamp: voiceTimestampFromMap(map),
      source: voiceEventSourceFromWire(map['source'] as String?),
      text: (map['text'] ?? map['transcript'] ?? '').toString(),
      language: voiceLanguageFromWire(map['language'] as String?),
      confidence: _readDouble(map, 'confidence', fallback: 1.0),
      isFinal: _readBool(map, 'isFinal', fallback: false) ||
          _readBool(map, 'is_final', fallback: false),
      payload: _unmodifiablePayload(map),
    );
  }
}

class VoiceCommandEvent extends VoiceEvent {
  const VoiceCommandEvent({
    required super.timestamp,
    required super.source,
    required super.payload,
    required this.command,
    required this.language,
    required this.rawText,
    required this.normalizedText,
    required this.confidence,
  }) : super(type: 'command');

  final VoiceCommand command;
  final VoiceLanguage language;
  final String rawText;
  final String normalizedText;
  final double confidence;

  factory VoiceCommandEvent.fromMap(Map<String, Object?> map) {
    final Object? commandValue = map['command'];
    final Object? rawTextValue = map['rawText'] ?? map['raw_text'];
    final String rawText = rawTextValue?.toString() ?? '';
    final VoiceCommand command = commandValue is String
        ? voiceCommandFromWire(commandValue)
        : VoiceCommand.unknown;
    final VoiceLanguage language = voiceLanguageFromWire(
      map['language'] as String?,
    );
    final double confidence = _readDouble(map, 'confidence', fallback: 1.0);
    final String normalizedText =
        (map['normalizedText'] ?? map['normalized_text'] ?? rawText).toString();
    return VoiceCommandEvent(
      timestamp: voiceTimestampFromMap(map),
      source: voiceEventSourceFromWire(map['source'] as String?),
      command: command,
      language: language,
      rawText: rawText,
      normalizedText: normalizedText,
      confidence: confidence,
      payload: _unmodifiablePayload(map),
    );
  }
}

class VoiceStateEvent extends VoiceEvent {
  const VoiceStateEvent({
    required super.timestamp,
    required super.source,
    required super.payload,
    required this.state,
    required this.message,
    required this.engine,
    required this.listening,
    required this.activeListening,
  }) : super(type: 'state');

  final VoiceRecognitionState state;
  final String message;
  final VoiceEngineType engine;
  final bool listening;
  final bool activeListening;

  factory VoiceStateEvent.fromMap(Map<String, Object?> map) {
    return VoiceStateEvent(
      timestamp: voiceTimestampFromMap(map),
      source: voiceEventSourceFromWire(map['source'] as String?),
      state: voiceRecognitionStateFromWire(map['state'] as String?),
      message: (map['message'] ?? '').toString(),
      engine: voiceEngineTypeFromWire(map['engine'] as String?),
      listening: _readBool(map, 'listening', fallback: false),
      activeListening: _readBool(map, 'activeListening', fallback: false) ||
          _readBool(map, 'active_listening', fallback: false),
      payload: _unmodifiablePayload(map),
    );
  }
}

class VoiceErrorEvent extends VoiceEvent {
  const VoiceErrorEvent({
    required super.timestamp,
    required super.source,
    required super.payload,
    required this.code,
    required this.message,
  }) : super(type: 'error');

  final String code;
  final String message;

  factory VoiceErrorEvent.fromMap(Map<String, Object?> map) {
    return VoiceErrorEvent(
      timestamp: voiceTimestampFromMap(map),
      source: voiceEventSourceFromWire(map['source'] as String?),
      code: (map['code'] ?? 'voice_error').toString(),
      message: (map['message'] ?? 'Unknown voice error').toString(),
      payload: _unmodifiablePayload(map),
    );
  }
}

extension VoiceErrorEventRecovery on VoiceErrorEvent {
  bool get isPermissionDenied =>
      code == 'microphone_permission_denied' ||
      code == 'speech_permission_denied';

  bool get isRecognizerUnavailable =>
      code == 'recognizer_unavailable' || code == 'speech_unavailable';

  bool get requiresManualRecovery =>
      isPermissionDenied ||
      isRecognizerUnavailable ||
      code == 'audio_session_error' ||
      code == 'audio_engine_start_failed' ||
      code == 'audio_capture_failed' ||
      code == 'audio_stream_error' ||
      code == 'sherpa_backend_init_failed' ||
      code == 'sherpa_asset_missing' ||
      code == 'kws_model_load_failed' ||
      code == 'asr_model_load_failed' ||
      code == 'vad_model_load_failed' ||
      code == 'sherpa_decode_failed' ||
      code == 'start_listening_failed';

  bool get isTransient => !requiresManualRecovery;

  String get recoveryHint {
    switch (code) {
      case 'microphone_permission_denied':
      case 'speech_permission_denied':
        return '请到系统设置打开麦克风权限后再重试';
      case 'recognizer_unavailable':
      case 'speech_unavailable':
        return '当前设备的语音能力不可用，建议切换设备或稍后重试';
      case 'audio_session_error':
      case 'audio_engine_start_failed':
        return '请先关闭其他占用麦克风的应用，然后重新启动监听';
      case 'audio_capture_failed':
      case 'audio_stream_error':
        return '麦克风音频流异常，请重新启动监听';
      case 'sherpa_backend_init_failed':
      case 'sherpa_asset_missing':
      case 'kws_model_load_failed':
      case 'asr_model_load_failed':
      case 'vad_model_load_failed':
        return 'Sherpa 模型加载失败，请检查 App assets 是否已正确打包';
      case 'sherpa_decode_failed':
        return '语音识别过程出现异常，请重新启动监听';
      case 'start_listening_failed':
        return '监听启动失败，系统会继续尝试恢复；如果持续失败，请手动重新启动';
      case 'speech_timeout':
        return '本次没有识别到有效语音，保持监听后重新说出唤醒词即可';
      default:
        return '可先重新启动监听；如果仍然失败，请检查系统权限和麦克风占用';
    }
  }
}

class VoiceTelemetryEvent extends VoiceEvent {
  const VoiceTelemetryEvent({
    required super.timestamp,
    required super.source,
    required super.payload,
    required this.message,
  }) : super(type: 'telemetry');

  final String message;

  factory VoiceTelemetryEvent.fromMap(Map<String, Object?> map) {
    return VoiceTelemetryEvent(
      timestamp: voiceTimestampFromMap(map),
      source: voiceEventSourceFromWire(map['source'] as String?),
      message: (map['message'] ?? map['type'] ?? '').toString(),
      payload: _unmodifiablePayload(map),
    );
  }
}

class VoiceConfig {
  const VoiceConfig({
    this.engine = VoiceEngineType.sherpa,
    this.wakeWord = 'D-Dog',
    this.sensitivity = 0.65,
    this.wakeDebounce = const Duration(milliseconds: 1200),
    this.modelLanguage = VoiceLanguage.mixed,
    this.sampleRate = 16000,
    this.preRoll = const Duration(milliseconds: 500),
    this.vadSilence = const Duration(milliseconds: 700),
    this.maxActiveDuration = const Duration(seconds: 8),
    this.kwsAssetBasePath =
        'packages/voice_control_sdk/assets/voice_models/kws/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20',
    this.asrAssetBasePath =
        'packages/voice_control_sdk/assets/voice_models/asr/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16',
    this.vadAssetPath =
        'packages/voice_control_sdk/assets/voice_models/vad/silero_vad.onnx',
    this.extras = const <String, Object?>{},
  });

  final VoiceEngineType engine;
  final String wakeWord;
  final double sensitivity;
  final Duration wakeDebounce;
  final VoiceLanguage modelLanguage;
  final int sampleRate;
  final Duration preRoll;
  final Duration vadSilence;
  final Duration maxActiveDuration;
  final String kwsAssetBasePath;
  final String asrAssetBasePath;
  final String vadAssetPath;
  final Map<String, Object?> extras;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'engine': engine.wireName,
      'wakeWord': wakeWord,
      'sensitivity': sensitivity,
      'wakeDebounceMs': wakeDebounce.inMilliseconds,
      'modelLanguage': modelLanguage.wireName,
      'sampleRate': sampleRate,
      'preRollMs': preRoll.inMilliseconds,
      'vadSilenceMs': vadSilence.inMilliseconds,
      'maxActiveDurationMs': maxActiveDuration.inMilliseconds,
      'kwsAssetBasePath': kwsAssetBasePath,
      'asrAssetBasePath': asrAssetBasePath,
      'vadAssetPath': vadAssetPath,
      'extras': Map<String, Object?>.unmodifiable(extras),
    };
  }

  factory VoiceConfig.fromMap(Map<String, Object?> map) {
    return VoiceConfig(
      engine: voiceEngineTypeFromWire(map['engine'] as String?),
      wakeWord: (map['wakeWord'] ?? map['wake_word'] ?? 'D-Dog').toString(),
      sensitivity: _readDouble(map, 'sensitivity', fallback: 0.65),
      wakeDebounce: Duration(
        milliseconds: _readInt(map, 'wakeDebounceMs', fallback: 1200),
      ),
      modelLanguage: voiceLanguageFromWire(
        map['modelLanguage'] as String? ?? map['language'] as String?,
      ),
      sampleRate: _readInt(map, 'sampleRate', fallback: 16000),
      preRoll: Duration(milliseconds: _readInt(map, 'preRollMs', fallback: 500)),
      vadSilence:
          Duration(milliseconds: _readInt(map, 'vadSilenceMs', fallback: 700)),
      maxActiveDuration: Duration(
        milliseconds: _readInt(map, 'maxActiveDurationMs', fallback: 8000),
      ),
      kwsAssetBasePath: _readString(
            map,
            'kwsAssetBasePath',
          ) ??
          'packages/voice_control_sdk/assets/voice_models/kws/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20',
      asrAssetBasePath: _readString(
            map,
            'asrAssetBasePath',
          ) ??
          'packages/voice_control_sdk/assets/voice_models/asr/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16',
      vadAssetPath: _readString(
            map,
            'vadAssetPath',
          ) ??
          'packages/voice_control_sdk/assets/voice_models/vad/silero_vad.onnx',
      extras: _readMap(map, 'extras'),
    );
  }

  VoiceConfig copyWith({
    VoiceEngineType? engine,
    String? wakeWord,
    double? sensitivity,
    Duration? wakeDebounce,
    VoiceLanguage? modelLanguage,
    int? sampleRate,
    Duration? preRoll,
    Duration? vadSilence,
    Duration? maxActiveDuration,
    String? kwsAssetBasePath,
    String? asrAssetBasePath,
    String? vadAssetPath,
    Map<String, Object?>? extras,
  }) {
    return VoiceConfig(
      engine: engine ?? this.engine,
      wakeWord: wakeWord ?? this.wakeWord,
      sensitivity: sensitivity ?? this.sensitivity,
      wakeDebounce: wakeDebounce ?? this.wakeDebounce,
      modelLanguage: modelLanguage ?? this.modelLanguage,
      sampleRate: sampleRate ?? this.sampleRate,
      preRoll: preRoll ?? this.preRoll,
      vadSilence: vadSilence ?? this.vadSilence,
      maxActiveDuration: maxActiveDuration ?? this.maxActiveDuration,
      kwsAssetBasePath: kwsAssetBasePath ?? this.kwsAssetBasePath,
      asrAssetBasePath: asrAssetBasePath ?? this.asrAssetBasePath,
      vadAssetPath: vadAssetPath ?? this.vadAssetPath,
      extras: extras ?? this.extras,
    );
  }
}

String? _readString(Map<String, Object?> map, String key) {
  final Object? value = map[key];
  if (value == null) {
    return null;
  }
  final String text = value.toString().trim();
  if (text.isEmpty) {
    return null;
  }
  return text;
}
