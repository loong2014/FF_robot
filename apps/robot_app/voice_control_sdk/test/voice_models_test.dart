import 'package:flutter_test/flutter_test.dart';
import 'package:voice_control_sdk/voice_control_sdk.dart';

void main() {
  group('VoiceConfig', () {
    test('defaults to Sherpa mixed wake and round-trips asset fields', () {
      const config = VoiceConfig(
        modelLanguage: VoiceLanguage.mixed,
        kwsAssetBasePath:
            'packages/voice_control_sdk/assets/voice_models/kws/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20',
        asrAssetBasePath:
            'packages/voice_control_sdk/assets/voice_models/asr/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16',
        vadAssetPath:
            'packages/voice_control_sdk/assets/voice_models/vad/silero_vad.onnx',
      );

      expect(config.engine, VoiceEngineType.sherpa);
      expect(config.sampleRate, 16000);
      expect(config.wakeWord, 'Lumi');
      expect(config.sensitivity, 0.82);
      expect(config.preRoll.inMilliseconds, 500);
      expect(config.wakeDebounce.inSeconds, 2);
      expect(config.vadSilence.inSeconds, 5);
      expect(config.activeNoSpeechTimeout.inSeconds, 5);
      expect(config.maxActiveDuration.inSeconds, 12);

      final roundTrip = VoiceConfig.fromMap(config.toMap());
      expect(roundTrip.engine, VoiceEngineType.sherpa);
      expect(roundTrip.wakeWord, 'Lumi');
      expect(roundTrip.modelLanguage, VoiceLanguage.mixed);
      expect(
        roundTrip.kwsAssetBasePath,
        'packages/voice_control_sdk/assets/voice_models/kws/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20',
      );
      expect(
        roundTrip.asrAssetBasePath,
        'packages/voice_control_sdk/assets/voice_models/asr/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16',
      );
      expect(
        roundTrip.vadAssetPath,
        'packages/voice_control_sdk/assets/voice_models/vad/silero_vad.onnx',
      );
      expect(roundTrip.sampleRate, 16000);
      expect(roundTrip.activeNoSpeechTimeout.inSeconds, 5);
      expect(roundTrip.vadSilence.inSeconds, 5);
      expect(roundTrip.maxActiveDuration.inSeconds, 12);
    });
  });

  group('VoiceWakeEvent', () {
    test('round-trips recognized wake metadata', () {
      final event = VoiceWakeEvent.fromMap(<String, Object?>{
        'type': 'wake',
        'wakeWord': 'Lumi',
        'recognizedText': '露米',
        'resultLabel': 'lumi__zh_lu4',
        'language': 'zh',
        'confidence': 0.91,
        'source': 'android',
        'timestampMs': 1710000000000,
      });

      expect(event.wakeWord, 'Lumi');
      expect(event.recognizedText, '露米');
      expect(event.resultLabel, 'lumi__zh_lu4');
      expect(event.language, VoiceLanguage.zh);
      expect(event.confidence, 0.91);
      expect(event.source, VoiceEventSource.android);
      expect(event.timestamp.millisecondsSinceEpoch, 1710000000000);
    });
  });
}
