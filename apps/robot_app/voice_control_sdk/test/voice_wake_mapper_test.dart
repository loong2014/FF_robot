import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_control_sdk/voice_control_sdk.dart';

void main() {
  group('VoiceWakeMapper', () {
    test('builds mixed wake grammar for Lumi', () {
      final grammar = VoiceWakeMapper.buildGrammar(
        wakeWord: 'Lumi',
        modelLanguage: VoiceLanguage.mixed,
      );
      final keywords = VoiceWakeMapper.buildKeywordsFileContent(
        wakeWord: 'Lumi',
        modelLanguage: VoiceLanguage.mixed,
      );

      expect(grammar, contains('Lumi'));
      expect(grammar, contains('loo me'));
      expect(grammar, contains('露米'));
      expect(grammar, contains('卢米'));
      expect(grammar, contains('lu mi'));
      expect(keywords, contains('@lumi__en_main'));
      expect(keywords, contains('@lumi__zh_lu4'));
      expect(keywords, contains('L UW1 M IY0 @lumi__en_main'));
      expect(keywords, contains('l ù m ǐ @lumi__zh_lu4'));
      expect(keywords, contains('l ú m ǐ @lumi__zh_lu2'));
      expect(keywords, isNot(contains('露 米')));
      expect(keywords, isNot(contains('卢 米')));
    });

    test('builds keywords with tokens available in the bundled KWS model', () {
      final tokenFile = File(
        'assets/voice_models/kws/'
        'sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20/tokens.txt',
      );
      final modelTokens = tokenFile
          .readAsLinesSync()
          .map((line) => line.split(' ').first)
          .where((token) => token.isNotEmpty)
          .toSet();
      final keywords = VoiceWakeMapper.buildKeywordsFileContent(
        wakeWord: 'Lumi',
        modelLanguage: VoiceLanguage.mixed,
      );

      for (final line in keywords.split('\n')) {
        if (line.trim().isEmpty) {
          continue;
        }
        final tokens = line.split('@').first.trim().split(' ');
        for (final token in tokens.where((token) => token.isNotEmpty)) {
          expect(modelTokens, contains(token), reason: line);
        }
      }
    });

    test('matches english wake aliases', () {
      final match = VoiceWakeMapper.matchTranscript(
        'loo me',
        wakeWord: 'Lumi',
        modelLanguage: VoiceLanguage.mixed,
      );

      expect(match, isNotNull);
      expect(match!.wakeWord, 'Lumi');
      expect(match.recognizedText, 'loo me');
      expect(match.resultLabel, 'lumi__en_loome');
      expect(match.language, VoiceLanguage.en);
      expect(match.normalizedText, 'loo me');
    });

    test('matches chinese wake aliases', () {
      final match = VoiceWakeMapper.matchTranscript(
        '露米',
        wakeWord: 'Lumi',
        modelLanguage: VoiceLanguage.mixed,
      );

      expect(match, isNotNull);
      expect(match!.wakeWord, 'Lumi');
      expect(match.recognizedText, '露米');
      expect(match.resultLabel, 'lumi__zh_lu4');
      expect(match.language, VoiceLanguage.zh);
      expect(match.normalizedText, '露米');
    });

    test('keeps custom wake words separate from Lumi aliases', () {
      final grammar = VoiceWakeMapper.buildGrammar(
        wakeWord: 'Hello Robot',
        modelLanguage: VoiceLanguage.mixed,
      );

      expect(grammar, contains('Hello Robot'));
      expect(grammar.where((item) => item.toLowerCase().contains('lumi')),
          isEmpty);
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
