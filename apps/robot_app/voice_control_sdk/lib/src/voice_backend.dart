import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

import 'voice_command_mapper.dart';
import 'voice_control_sdk_platform_interface.dart';
import 'voice_models.dart';
import 'voice_session_state.dart';
import 'voice_wake_mapper.dart';

abstract class VoiceBackend {
  Stream<VoiceEvent> get events;

  Future<String?> getPlatformVersion();

  Future<bool> ensurePermissions();

  Future<void> start({VoiceConfig config = const VoiceConfig()});

  Future<void> stop();

  Future<void> dispose();
}

class SherpaVoiceBackend implements VoiceBackend {
  SherpaVoiceBackend({
    VoiceControlSdkPlatform? platform,
    AssetBundle? assetBundle,
    Future<Directory> Function()? supportDirectoryProvider,
  })  : _platform = platform ?? VoiceControlSdkPlatform.instance,
        _assetBundle = assetBundle ?? rootBundle,
        _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory;

  static const List<String> _kwsAssetFiles = <String>[
    'encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx',
    'decoder-epoch-13-avg-2-chunk-16-left-64.onnx',
    'joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx',
    'tokens.txt',
  ];

  static const List<String> _asrAssetFiles = <String>[
    'encoder-epoch-99-avg-1.int8.onnx',
    'decoder-epoch-99-avg-1.int8.onnx',
    'joiner-epoch-99-avg-1.int8.onnx',
    'tokens.txt',
    'bpe.model',
  ];

  final VoiceControlSdkPlatform _platform;
  final AssetBundle _assetBundle;
  final Future<Directory> Function() _supportDirectoryProvider;

  final StreamController<VoiceEvent> _events =
      StreamController<VoiceEvent>.broadcast();

  StreamSubscription<Map<String, Object?>>? _platformSubscription;

  VoiceConfig _config = const VoiceConfig();
  bool _starting = false;
  bool _disposed = false;
  bool _listening = false;
  bool _activeListening = false;
  bool _sherpaInitialized = false;
  int _generation = 0;
  DateTime _lastAudioTelemetryAt =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  late VoiceSessionStateMachine _session =
      VoiceSessionStateMachine(config: _config);
  late VoiceCommandMapper _commandMapper = VoiceCommandMapper();

  KeywordSpotter? _keywordSpotter;
  OnlineRecognizer? _asrRecognizer;
  VoiceActivityDetector? _vad;
  OnlineStream? _kwsStream;
  OnlineStream? _asrStream;

  String? _lastAsrText;
  String? _lastFinalAsrText;
  List<_AudioChunk> _preRoll = <_AudioChunk>[];
  int _preRollSamples = 0;
  int _audioChunkCount = 0;
  int _audioSampleCount = 0;

  @override
  Stream<VoiceEvent> get events => _events.stream;

  @override
  Future<String?> getPlatformVersion() async {
    return 'sherpa';
  }

  @override
  Future<bool> ensurePermissions() {
    return _platform.ensurePermissions();
  }

  @override
  Future<void> start({VoiceConfig config = const VoiceConfig()}) async {
    if (_disposed) {
      throw StateError('Voice backend is disposed');
    }
    if (_starting) {
      return;
    }

    _starting = true;
    final int generation = ++_generation;
    try {
      await _stopRuntime(emitStopped: false);
      _config = config.copyWith(wakeWord: 'Lumi');
      _session = VoiceSessionStateMachine(config: _config);
      _commandMapper = VoiceCommandMapper();
      _session.markStarting();
      _events.add(
        VoiceStateEvent(
          timestamp: DateTime.now().toUtc(),
          source: _platformSource(),
          payload: const <String, Object?>{
            'type': 'state',
            'state': 'starting',
            'message': '正在加载 Sherpa 模型',
          },
          state: VoiceRecognitionState.starting,
          message: '正在加载 Sherpa 模型',
          engine: VoiceEngineType.sherpa,
          listening: true,
          activeListening: false,
        ),
      );

      await _ensureSherpaInitialized();
      final _SherpaModelPaths paths = await _prepareModelPaths(_config);
      _createModels(paths, _config);
      _listenToPlatformEvents();
      await _platform.startListening(config: _config);
      _listening = true;
      _session.markWaitingForWake();
      _emitState(
        generation: generation,
        state: VoiceRecognitionState.waitingForWake,
        message: _session.messageFor(VoiceRecognitionState.waitingForWake),
        listening: true,
        activeListening: false,
      );
    } catch (error) {
      await _stopRuntime(emitStopped: false);
      _emitError(
        code: _mapErrorCode(error),
        message: _mapErrorMessage(error),
      );
      _emitState(
        generation: generation,
        state: VoiceRecognitionState.error,
        message: _session.messageFor(VoiceRecognitionState.error),
        listening: false,
        activeListening: false,
      );
      _listening = false;
      rethrow;
    } finally {
      _starting = false;
    }
  }

  @override
  Future<void> stop() async {
    await _stopRuntime(emitStopped: true);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _stopRuntime(emitStopped: true);
    await _events.close();
  }

  Future<void> _stopRuntime({required bool emitStopped}) async {
    final int generation = ++_generation;
    _listening = false;
    _activeListening = false;
    _session.stop();
    _lastAsrText = null;
    _lastFinalAsrText = null;
    _preRoll = <_AudioChunk>[];
    _preRollSamples = 0;
    _audioChunkCount = 0;
    _audioSampleCount = 0;
    _lastAudioTelemetryAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    await _platformSubscription?.cancel();
    _platformSubscription = null;

    try {
      await _platform.stopListening();
    } catch (error) {
      if (emitStopped) {
        _emitError(
          code: 'audio_capture_failed',
          message: error.toString(),
        );
      }
    }

    _disposeSessionModels();

    if (emitStopped) {
      _emitState(
        generation: generation,
        state: VoiceRecognitionState.stopped,
        message: _session.messageFor(VoiceRecognitionState.stopped),
        listening: false,
        activeListening: false,
        allowStale: true,
      );
    }
  }

  void _disposeSessionModels() {
    _kwsStream?.free();
    _kwsStream = null;
    _asrStream?.free();
    _asrStream = null;
    _keywordSpotter?.free();
    _keywordSpotter = null;
    _asrRecognizer?.free();
    _asrRecognizer = null;
    _vad?.free();
    _vad = null;
  }

  Future<void> _ensureSherpaInitialized() async {
    if (_sherpaInitialized) {
      return;
    }
    initBindings();
    _sherpaInitialized = true;
  }

  void _createModels(
    _SherpaModelPaths paths,
    VoiceConfig config,
  ) {
    try {
      _keywordSpotter = KeywordSpotter(
        KeywordSpotterConfig(
          feat: FeatureConfig(sampleRate: config.sampleRate, featureDim: 80),
          model: OnlineModelConfig(
            transducer: OnlineTransducerModelConfig(
              encoder: paths.kwsEncoderPath,
              decoder: paths.kwsDecoderPath,
              joiner: paths.kwsJoinerPath,
            ),
            tokens: paths.kwsTokensPath,
            numThreads: 2,
            provider: 'cpu',
            debug: false,
            modelType: '',
            modelingUnit: 'cjkchar',
            bpeVocab: '',
          ),
          maxActivePaths: 4,
          numTrailingBlanks: 1,
          keywordsScore: 1.0,
          keywordsThreshold: _keywordsThreshold(config.sensitivity),
          keywordsFile: paths.keywordsFilePath,
        ),
      );

      _asrRecognizer = OnlineRecognizer(
        OnlineRecognizerConfig(
          feat: FeatureConfig(sampleRate: config.sampleRate, featureDim: 80),
          model: OnlineModelConfig(
            transducer: OnlineTransducerModelConfig(
              encoder: paths.asrEncoderPath,
              decoder: paths.asrDecoderPath,
              joiner: paths.asrJoinerPath,
            ),
            tokens: paths.asrTokensPath,
            numThreads: 2,
            provider: 'cpu',
            debug: false,
            modelType: 'zipformer',
            modelingUnit: 'bpe',
            bpeVocab: paths.asrBpeVocabPath,
          ),
          decodingMethod: 'greedy_search',
          maxActivePaths: 4,
          enableEndpoint: false,
          rule1MinTrailingSilence: 0.6,
          rule2MinTrailingSilence: 0.6,
          rule3MinUtteranceLength: 1.0,
        ),
      );

      _vad = VoiceActivityDetector(
        config: VadModelConfig(
          sileroVad: SileroVadModelConfig(
            model: paths.vadModelPath,
            threshold: 0.5,
            minSilenceDuration: 0.35,
            minSpeechDuration: 0.3,
            windowSize: 512,
            maxSpeechDuration:
                max(config.maxActiveDuration.inMilliseconds / 1000.0, 4.0)
                    .toDouble(),
          ),
          sampleRate: config.sampleRate,
          numThreads: 1,
          provider: 'cpu',
          debug: false,
        ),
        bufferSizeInSeconds:
            max(config.maxActiveDuration.inMilliseconds / 1000.0, 8.0)
                .toDouble(),
      );

      _kwsStream = _keywordSpotter!.createStream(
        keywords: VoiceWakeMapper.buildKeywordsFileContent(
          wakeWord: config.wakeWord,
          modelLanguage: config.modelLanguage,
        ),
      );
    } catch (error) {
      _disposeSessionModels();
      throw StateError('sherpa model load failed: $error');
    }
  }

  Future<_SherpaModelPaths> _prepareModelPaths(VoiceConfig config) async {
    final Directory supportDir = await _supportDirectoryProvider();
    final Directory baseDir = Directory(
      p.join(supportDir.path, 'voice_control_sdk', 'sherpa_models'),
    );
    await baseDir.create(recursive: true);

    final Directory kwsDir = Directory(
      p.join(baseDir.path, 'kws', _bundleNameFromPath(config.kwsAssetBasePath)),
    );
    final Directory asrDir = Directory(
      p.join(baseDir.path, 'asr', _bundleNameFromPath(config.asrAssetBasePath)),
    );
    final Directory vadDir = Directory(p.join(baseDir.path, 'vad'));
    await kwsDir.create(recursive: true);
    await asrDir.create(recursive: true);
    await vadDir.create(recursive: true);

    final String kwsAssetPrefix = config.kwsAssetBasePath;
    final String asrAssetPrefix = config.asrAssetBasePath;

    for (final fileName in _kwsAssetFiles) {
      await _materializeAsset(
        assetPath: '$kwsAssetPrefix/$fileName',
        destinationPath: p.join(kwsDir.path, fileName),
      );
    }

    for (final fileName in _asrAssetFiles) {
      await _materializeAsset(
        assetPath: '$asrAssetPrefix/$fileName',
        destinationPath: p.join(asrDir.path, fileName),
      );
    }

    await _materializeAsset(
      assetPath: config.vadAssetPath,
      destinationPath: p.join(vadDir.path, 'silero_vad.onnx'),
    );

    final String keywordsContent = VoiceWakeMapper.buildKeywordsFileContent(
      wakeWord: config.wakeWord,
      modelLanguage: config.modelLanguage,
    );
    final String keywordsFilePath = p.join(kwsDir.path, 'keywords.txt');
    await File(keywordsFilePath).writeAsString(keywordsContent, flush: true);

    return _SherpaModelPaths(
      kwsEncoderPath: p.join(
        kwsDir.path,
        'encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx',
      ),
      kwsDecoderPath: p.join(
        kwsDir.path,
        'decoder-epoch-13-avg-2-chunk-16-left-64.onnx',
      ),
      kwsJoinerPath: p.join(
        kwsDir.path,
        'joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx',
      ),
      kwsTokensPath: p.join(kwsDir.path, 'tokens.txt'),
      keywordsFilePath: keywordsFilePath,
      asrEncoderPath: p.join(
        asrDir.path,
        'encoder-epoch-99-avg-1.int8.onnx',
      ),
      asrDecoderPath: p.join(asrDir.path, 'decoder-epoch-99-avg-1.int8.onnx'),
      asrJoinerPath: p.join(
        asrDir.path,
        'joiner-epoch-99-avg-1.int8.onnx',
      ),
      asrTokensPath: p.join(asrDir.path, 'tokens.txt'),
      asrBpeVocabPath: p.join(asrDir.path, 'bpe.model'),
      vadModelPath: p.join(vadDir.path, 'silero_vad.onnx'),
    );
  }

  Future<void> _materializeAsset({
    required String assetPath,
    required String destinationPath,
  }) async {
    final File destination = File(destinationPath);
    if (await destination.exists() && await destination.length() > 0) {
      return;
    }

    final ByteData data;
    try {
      data = await _assetBundle.load(assetPath);
    } catch (error) {
      throw StateError('Missing Sherpa asset: $assetPath ($error)');
    }

    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }

  void _listenToPlatformEvents() {
    _platformSubscription?.cancel();
    _platformSubscription = _platform.events.listen(
      _handlePlatformEvent,
      onError: (Object error, StackTrace stackTrace) {
        _emitError(
          code: 'audio_stream_error',
          message: error.toString(),
        );
        _emitState(
          generation: _generation,
          state: VoiceRecognitionState.error,
          message: '音频流发生异常',
          listening: false,
          activeListening: false,
        );
      },
    );
  }

  void _handlePlatformEvent(Map<String, Object?> event) {
    switch ((event['type'] ?? '').toString()) {
      case 'audio':
        _handleAudioEvent(event);
        return;
      case 'error':
        final VoiceErrorEvent error = VoiceErrorEvent.fromMap(event);
        _events.add(error);
        return;
      case 'telemetry':
        _events.add(VoiceTelemetryEvent.fromMap(event));
        return;
      case 'state':
        _events.add(_normalizePlatformState(event));
        return;
      default:
        _events.add(VoiceTelemetryEvent.fromMap(event));
        return;
    }
  }

  VoiceStateEvent _normalizePlatformState(Map<String, Object?> event) {
    final normalized = Map<String, Object?>.from(event);
    if (normalized['state'] == 'listening') {
      normalized['state'] = VoiceRecognitionState.waitingForWake.wireName;
      normalized['message'] = _session.messageFor(
        VoiceRecognitionState.waitingForWake,
      );
    }
    return VoiceStateEvent.fromMap(normalized);
  }

  void _handleAudioEvent(Map<String, Object?> event) {
    if (!_listening || _keywordSpotter == null || _kwsStream == null) {
      return;
    }

    final _AudioChunk chunk = _decodeAudioChunk(event);
    if (chunk.samples.isEmpty) {
      return;
    }
    _emitAudioTelemetryIfNeeded(chunk);

    if (_activeListening) {
      _processActiveAudio(chunk);
    } else {
      _appendPreRoll(chunk);
      _processIdleAudio(chunk);
    }
  }

  void _processIdleAudio(_AudioChunk chunk) {
    if (_kwsStream == null || _keywordSpotter == null) {
      return;
    }

    _kwsStream!.acceptWaveform(
      samples: chunk.samples,
      sampleRate: chunk.sampleRate,
    );

    while (_keywordSpotter!.isReady(_kwsStream!)) {
      _keywordSpotter!.decode(_kwsStream!);
      final KeywordResult result = _keywordSpotter!.getResult(_kwsStream!);
      if (result.keyword.isEmpty) {
        continue;
      }

      final VoiceWakeMatch? match = VoiceWakeMapper.matchResultLabel(
        result.keyword,
        wakeWord: _config.wakeWord,
        modelLanguage: _config.modelLanguage,
        confidence: _config.sensitivity,
      );
      if (match == null) {
        continue;
      }
      final decision = _session.handleWakeCandidate(match);
      if (!decision.accepted) {
        continue;
      }

      _emitWake(match);
      _startActiveSession();
      return;
    }
  }

  void _startActiveSession() {
    if (_asrRecognizer == null || _vad == null) {
      return;
    }

    _activeListening = true;
    _session.beginActiveListening();
    _lastAsrText = null;
    _lastFinalAsrText = null;

    _asrStream?.free();
    _asrStream = _asrRecognizer!.createStream();
    _vad!.reset();

    for (final _AudioChunk chunk in _preRoll) {
      _asrStream!.acceptWaveform(
        samples: chunk.samples,
        sampleRate: chunk.sampleRate,
      );
      _vad!.acceptWaveform(chunk.samples);
    }
    _preRoll = <_AudioChunk>[];
    _preRollSamples = 0;

    _emitState(
      generation: _generation,
      state: VoiceRecognitionState.activeListening,
      message: _session.messageFor(VoiceRecognitionState.activeListening),
      listening: true,
      activeListening: true,
    );
  }

  void _processActiveAudio(_AudioChunk chunk) {
    if (_asrRecognizer == null || _asrStream == null || _vad == null) {
      return;
    }

    _asrStream!.acceptWaveform(
      samples: chunk.samples,
      sampleRate: chunk.sampleRate,
    );
    _vad!.acceptWaveform(chunk.samples);

    final bool detected = _vad!.isDetected();
    final VoiceSessionVadDecision vadDecision = _session.observeVad(
      speechDetected: detected,
      chunkDuration: _chunkDuration(chunk),
    );

    while (_asrRecognizer!.isReady(_asrStream!)) {
      _asrRecognizer!.decode(_asrStream!);
      _emitPartialAsr();
    }

    if (vadDecision.shouldFinish) {
      _finishActiveSession(vadDecision.finishReason);
    }
  }

  void _emitPartialAsr() {
    if (_asrRecognizer == null || _asrStream == null) {
      return;
    }
    final OnlineRecognizerResult result =
        _asrRecognizer!.getResult(_asrStream!);
    final String text = result.text.trim();
    if (text.isEmpty || text == _lastAsrText) {
      return;
    }
    _lastAsrText = text;
    _events.add(
      VoiceAsrEvent(
        timestamp: DateTime.now().toUtc(),
        source: _platformSource(),
        payload: <String, Object?>{
          'type': 'asr',
          'text': text,
          'language': _config.modelLanguage.wireName,
          'confidence': 1.0,
          'isFinal': false,
        },
        text: text,
        language: _config.modelLanguage,
        confidence: 1.0,
        isFinal: false,
      ),
    );
  }

  void _finishActiveSession(VoiceSessionFinishReason finishReason) {
    if (_asrRecognizer == null || _asrStream == null) {
      return;
    }

    _session.beginProcessingCommand();
    _emitState(
      generation: _generation,
      state: VoiceRecognitionState.processingCommand,
      message: _session.messageFor(VoiceRecognitionState.processingCommand),
      listening: true,
      activeListening: false,
    );

    _asrStream!.inputFinished();
    while (_asrRecognizer!.isReady(_asrStream!)) {
      _asrRecognizer!.decode(_asrStream!);
    }
    final OnlineRecognizerResult result =
        _asrRecognizer!.getResult(_asrStream!);
    final String transcript = result.text.trim();
    if (transcript.isNotEmpty && transcript != _lastFinalAsrText) {
      _lastFinalAsrText = transcript;
      _events.add(
        VoiceAsrEvent(
          timestamp: DateTime.now().toUtc(),
          source: _platformSource(),
          payload: <String, Object?>{
            'type': 'asr',
            'text': transcript,
            'language': _config.modelLanguage.wireName,
            // Sherpa streaming result does not expose confidence here. The
            // MVP treats local final ASR as trusted and keeps low-confidence
            // filtering for engines that can provide a real score.
            'confidence': 1.0,
            'isFinal': true,
          },
          text: transcript,
          language: _config.modelLanguage,
          confidence: 1.0,
          isFinal: true,
        ),
      );

      final VoiceCommandMatch? commandMatch =
          _commandMapper.matchFinalTranscript(
        transcript,
        confidence: 1.0,
        bilingualCommands: true,
      );
      if (commandMatch != null) {
        _events.add(
          VoiceCommandEvent(
            timestamp: DateTime.now().toUtc(),
            source: _platformSource(),
            payload: commandMatch.toMap(),
            command: commandMatch.command,
            language: commandMatch.language,
            rawText: commandMatch.rawText,
            normalizedText: commandMatch.normalizedText,
            confidence: commandMatch.confidence,
          ),
        );
      }
    }

    _asrRecognizer!.reset(_asrStream!);
    _asrStream!.free();
    _asrStream = null;
    _vad!.reset();

    _activeListening = false;
    _session.finishProcessingCommand();

    if (finishReason == VoiceSessionFinishReason.noSpeechTimeout) {
      _events.add(
        VoiceTelemetryEvent(
          timestamp: DateTime.now().toUtc(),
          source: _platformSource(),
          payload: const <String, Object?>{
            'type': 'telemetry',
            'message': 'speech_timeout',
          },
          message: 'speech_timeout',
        ),
      );
    }

    if (_kwsStream != null) {
      _keywordSpotter!.reset(_kwsStream!);
    } else {
      _kwsStream = _keywordSpotter!.createStream(
        keywords: VoiceWakeMapper.buildKeywordsFileContent(
          wakeWord: _config.wakeWord,
          modelLanguage: _config.modelLanguage,
        ),
      );
    }
    _emitState(
      generation: _generation,
      state: VoiceRecognitionState.waitingForWake,
      message: _session.messageFor(VoiceRecognitionState.waitingForWake),
      listening: true,
      activeListening: false,
    );
  }

  void _appendPreRoll(_AudioChunk chunk) {
    _preRoll.add(chunk);
    _preRollSamples += chunk.samples.length;
    final int maxSamples = max(
      (_config.preRoll.inMilliseconds * _config.sampleRate / 1000).round(),
      _config.sampleRate,
    );
    while (_preRoll.isNotEmpty && _preRollSamples > maxSamples) {
      final _AudioChunk removed = _preRoll.removeAt(0);
      _preRollSamples -= removed.samples.length;
    }
  }

  void _emitAudioTelemetryIfNeeded(_AudioChunk chunk) {
    _audioChunkCount += 1;
    _audioSampleCount += chunk.samples.length;

    final DateTime now = DateTime.now().toUtc();
    if (now.difference(_lastAudioTelemetryAt) <
        const Duration(milliseconds: 1200)) {
      return;
    }
    _lastAudioTelemetryAt = now;

    double sumSquares = 0;
    double peak = 0;
    for (final sample in chunk.samples) {
      final abs = sample.abs();
      if (abs > peak) {
        peak = abs;
      }
      sumSquares += sample * sample;
    }
    final double rms = chunk.samples.isEmpty
        ? 0
        : sqrt(sumSquares / chunk.samples.length).clamp(0, 1).toDouble();

    _events.add(
      VoiceTelemetryEvent(
        timestamp: now,
        source: _platformSource(),
        payload: <String, Object?>{
          'type': 'telemetry',
          'message':
              'audio chunks=$_audioChunkCount samples=$_audioSampleCount rate=${chunk.sampleRate} rms=${rms.toStringAsFixed(4)} peak=${peak.toStringAsFixed(4)}',
          'audioChunks': _audioChunkCount,
          'audioSamples': _audioSampleCount,
          'sampleRate': chunk.sampleRate,
          'rms': rms,
          'peak': peak,
        },
        message:
            'audio chunks=$_audioChunkCount samples=$_audioSampleCount rate=${chunk.sampleRate} rms=${rms.toStringAsFixed(4)} peak=${peak.toStringAsFixed(4)}',
      ),
    );
  }

  _AudioChunk _decodeAudioChunk(Map<String, Object?> event) {
    final Object? samplesValue = event['samples'] ??
        event['pcm'] ??
        event['pcm16le'] ??
        event['pcm_f32le'];
    if (samplesValue is! Uint8List) {
      return _AudioChunk(
          samples: Float32List(0), sampleRate: _config.sampleRate);
    }

    final int rawSampleRate = (event['sampleRate'] as num?)?.toInt() ?? 0;
    final int sampleRate =
        rawSampleRate > 0 ? rawSampleRate : _config.sampleRate;
    final String format = (event['format'] ?? 'pcm16le').toString();
    if (format == 'f32le' || format == 'float32') {
      final Float32List samples = Float32List.view(
        samplesValue.buffer,
        samplesValue.offsetInBytes,
        samplesValue.lengthInBytes ~/ 4,
      );
      return _AudioChunk(
          samples: Float32List.fromList(samples), sampleRate: sampleRate);
    }

    final ByteData data = ByteData.sublistView(samplesValue);
    final int count = samplesValue.lengthInBytes ~/ 2;
    final Float32List samples = Float32List(count);
    var index = 0;
    for (var offset = 0; offset < samplesValue.lengthInBytes; offset += 2) {
      final int value = data.getInt16(offset, Endian.little);
      samples[index++] = value / 32768.0;
    }
    return _AudioChunk(samples: samples, sampleRate: sampleRate);
  }

  Duration _chunkDuration(_AudioChunk chunk) {
    if (chunk.sampleRate <= 0) {
      return const Duration(milliseconds: 20);
    }
    final double seconds = chunk.samples.length / chunk.sampleRate;
    return Duration(microseconds: (seconds * 1000000).round());
  }

  double _keywordsThreshold(double sensitivity) {
    final double threshold = 1.0 - sensitivity;
    return threshold.clamp(0.05, 0.95).toDouble();
  }

  void _emitWake(VoiceWakeMatch match) {
    _events.add(
      VoiceWakeEvent(
        timestamp: DateTime.now().toUtc(),
        source: _platformSource(),
        payload: <String, Object?>{
          'type': 'wake',
          'wakeWord': match.wakeWord,
          'recognizedText': match.recognizedText,
          'resultLabel': match.resultLabel,
          'language': match.language.wireName,
          'confidence': match.confidence,
        },
        wakeWord: match.wakeWord,
        recognizedText: match.recognizedText,
        resultLabel: match.resultLabel,
        language: match.language,
        confidence: match.confidence,
      ),
    );
    _emitState(
      generation: _generation,
      state: VoiceRecognitionState.wakeDetected,
      message: '已唤醒，开始识别语音',
      listening: true,
      activeListening: true,
    );
  }

  void _emitState({
    required int generation,
    required VoiceRecognitionState state,
    required String message,
    required bool listening,
    required bool activeListening,
    bool allowStale = false,
  }) {
    if (!allowStale && generation != _generation) {
      return;
    }
    _events.add(
      VoiceStateEvent(
        timestamp: DateTime.now().toUtc(),
        source: _platformSource(),
        payload: <String, Object?>{
          'type': 'state',
          'state': state.wireName,
          'message': message,
          'listening': listening,
          'activeListening': activeListening,
          'engine': VoiceEngineType.sherpa.wireName,
        },
        state: state,
        message: message,
        engine: VoiceEngineType.sherpa,
        listening: listening,
        activeListening: activeListening,
      ),
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      unawaited(
        _platform.updateServiceState(state: state, message: message).catchError(
              (_) {},
            ),
      );
    }
  }

  void _emitError({
    required String code,
    required String message,
  }) {
    _events.add(
      VoiceErrorEvent(
        timestamp: DateTime.now().toUtc(),
        source: _platformSource(),
        payload: <String, Object?>{
          'type': 'error',
          'code': code,
          'message': message,
        },
        code: code,
        message: message,
      ),
    );
  }

  VoiceEventSource _platformSource() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return VoiceEventSource.android;
      case TargetPlatform.iOS:
        return VoiceEventSource.ios;
      default:
        return VoiceEventSource.unknown;
    }
  }

  String _mapErrorCode(Object error) {
    final String message = error.toString().toLowerCase();
    if (message.contains('missing sherpa asset')) {
      return 'sherpa_asset_missing';
    }
    if (message.contains('load failed')) {
      return 'kws_model_load_failed';
    }
    if (message.contains('permission')) {
      return 'microphone_permission_denied';
    }
    if (message.contains('audio')) {
      return 'audio_capture_failed';
    }
    if (message.contains('sherpa')) {
      return 'sherpa_backend_init_failed';
    }
    return 'voice_error';
  }

  String _mapErrorMessage(Object error) {
    return error.toString();
  }

  String _bundleNameFromPath(String path) {
    return path.split('/').where((segment) => segment.isNotEmpty).last;
  }
}

class _AudioChunk {
  const _AudioChunk({
    required this.samples,
    required this.sampleRate,
  });

  final Float32List samples;
  final int sampleRate;
}

class _SherpaModelPaths {
  const _SherpaModelPaths({
    required this.kwsEncoderPath,
    required this.kwsDecoderPath,
    required this.kwsJoinerPath,
    required this.kwsTokensPath,
    required this.keywordsFilePath,
    required this.asrEncoderPath,
    required this.asrDecoderPath,
    required this.asrJoinerPath,
    required this.asrTokensPath,
    required this.asrBpeVocabPath,
    required this.vadModelPath,
  });

  final String kwsEncoderPath;
  final String kwsDecoderPath;
  final String kwsJoinerPath;
  final String kwsTokensPath;
  final String keywordsFilePath;
  final String asrEncoderPath;
  final String asrDecoderPath;
  final String asrJoinerPath;
  final String asrTokensPath;
  final String asrBpeVocabPath;
  final String vadModelPath;
}
