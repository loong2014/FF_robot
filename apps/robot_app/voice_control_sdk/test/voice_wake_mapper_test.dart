import 'package:flutter_test/flutter_test.dart';
import 'package:voice_control_sdk/voice_control_sdk.dart';

void main() {
  group('VoiceWakeMapper', () {
    test('builds mixed wake grammar for D-Dog', () {
      final grammar = VoiceWakeMapper.buildGrammar(
        wakeWord: 'D-Dog',
        modelLanguage: VoiceLanguage.mixed,
      );
      final keywords = VoiceWakeMapper.buildKeywordsFileContent(
        wakeWord: 'D-Dog',
        modelLanguage: VoiceLanguage.mixed,
      );

      expect(grammar, contains('D-Dog'));
      expect(grammar, contains('dee dog'));
      expect(grammar, contains('迪狗'));
      expect(grammar, contains('滴狗'));
      expect(grammar, contains('di gou'));
      expect(keywords, contains('@d_dog__en_main'));
      expect(keywords, contains('@d_dog__zh_di2'));
    });

    test('matches english wake aliases', () {
      final match = VoiceWakeMapper.matchTranscript(
        'dee dog',
        wakeWord: 'D-Dog',
        modelLanguage: VoiceLanguage.mixed,
      );

      expect(match, isNotNull);
      expect(match!.wakeWord, 'D-Dog');
      expect(match.recognizedText, 'dee dog');
      expect(match.resultLabel, 'd_dog__en_dee');
      expect(match.language, VoiceLanguage.en);
      expect(match.normalizedText, 'dee dog');
    });

    test('matches chinese wake aliases', () {
      final match = VoiceWakeMapper.matchTranscript(
        '滴狗',
        wakeWord: 'D-Dog',
        modelLanguage: VoiceLanguage.mixed,
      );

      expect(match, isNotNull);
      expect(match!.wakeWord, 'D-Dog');
      expect(match.recognizedText, '滴狗');
      expect(match.resultLabel, 'd_dog__zh_di2');
      expect(match.language, VoiceLanguage.zh);
      expect(match.normalizedText, '滴狗');
    });

    test('keeps custom wake words separate from D-Dog aliases', () {
      final grammar = VoiceWakeMapper.buildGrammar(
        wakeWord: 'Hello Robot',
        modelLanguage: VoiceLanguage.mixed,
      );

      expect(grammar, contains('Hello Robot'));
      expect(grammar.where((item) => item.contains('dog')), isEmpty);
      expect(
        VoiceWakeMapper.matchTranscript(
          'hello robot',
          wakeWord: 'Hello Robot',
          modelLanguage: VoiceLanguage.mixed,
        ),
        isNotNull,
      );
    });
  });
}
