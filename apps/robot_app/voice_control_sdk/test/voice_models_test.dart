import 'package:flutter_test/flutter_test.dart';
import 'package:voice_control_sdk/voice_control_sdk.dart';

void main() {
  group('VoiceConfig', () {
    test('defaults to Sherpa mixed wake and round-trips asset fields', () {
      const config = VoiceConfig(
        wakeWord: 'D-Dog',
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
      expect(config.wakeWord, 'D-Dog');
      expect(config.preRoll.inMilliseconds, 500);
      expect(config.vadSilence.inMilliseconds, 700);

      final roundTrip = VoiceConfig.fromMap(config.toMap());
      expect(roundTrip.engine, VoiceEngineType.sherpa);
      expect(roundTrip.wakeWord, 'D-Dog');
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
    });
  });

  group('VoiceWakeEvent', () {
    test('round-trips recognized wake metadata', () {
      final event = VoiceWakeEvent.fromMap(<String, Object?>{
        'type': 'wake',
        'wakeWord': 'D-Dog',
        'recognizedText': '滴狗',
        'resultLabel': 'd_dog__zh_di2',
        'language': 'zh',
        'confidence': 0.91,
        'source': 'android',
        'timestampMs': 1710000000000,
      });

      expect(event.wakeWord, 'D-Dog');
      expect(event.recognizedText, '滴狗');
      expect(event.resultLabel, 'd_dog__zh_di2');
      expect(event.language, VoiceLanguage.zh);
      expect(event.confidence, 0.91);
      expect(event.source, VoiceEventSource.android);
      expect(event.timestamp.millisecondsSinceEpoch, 1710000000000);
    });
  });
}
