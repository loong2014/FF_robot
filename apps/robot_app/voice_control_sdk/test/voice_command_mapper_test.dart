import 'package:flutter_test/flutter_test.dart';
import 'package:voice_control_sdk/voice_control_sdk.dart';

void main() {
  group('VoiceCommandMapper', () {
    test('matches Chinese commands', () {
      final wake = VoiceCommandMapper.matchTranscript('  站起来  ');
      expect(wake, isNotNull);
      expect(wake!.command, VoiceCommand.standUp);
      expect(wake.language, VoiceLanguage.zh);

      final sit = VoiceCommandMapper.matchTranscript('请坐下');
      expect(sit, isNotNull);
      expect(sit!.command, VoiceCommand.sitDown);
      expect(sit.language, VoiceLanguage.zh);

      final forward = VoiceCommandMapper.matchTranscript('前进');
      expect(forward, isNotNull);
      expect(forward!.command, VoiceCommand.forward);
      expect(forward.language, VoiceLanguage.zh);

      final backward = VoiceCommandMapper.matchTranscript('后退');
      expect(backward, isNotNull);
      expect(backward!.command, VoiceCommand.backward);
      expect(backward.language, VoiceLanguage.zh);
    });

    test('matches English commands', () {
      final stand = VoiceCommandMapper.matchTranscript('stand up');
      expect(stand, isNotNull);
      expect(stand!.command, VoiceCommand.standUp);
      expect(stand.language, VoiceLanguage.en);

      final sit = VoiceCommandMapper.matchTranscript('sit down');
      expect(sit, isNotNull);
      expect(sit!.command, VoiceCommand.sitDown);
      expect(sit.language, VoiceLanguage.en);

      final forward = VoiceCommandMapper.matchTranscript('move forward');
      expect(forward, isNotNull);
      expect(forward!.command, VoiceCommand.forward);
      expect(forward.language, VoiceLanguage.en);

      final backward = VoiceCommandMapper.matchTranscript('go backward');
      expect(backward, isNotNull);
      expect(backward!.command, VoiceCommand.backward);
      expect(backward.language, VoiceLanguage.en);
    });

    test('can disable English command matching', () {
      expect(
        VoiceCommandMapper.matchTranscript(
          'stand up',
          bilingualCommands: false,
        ),
        isNull,
      );
      expect(
        VoiceCommandMapper.matchTranscript(
          '坐下',
          bilingualCommands: false,
        ),
        isNotNull,
      );
    });

    test('returns null for unrelated text', () {
      expect(VoiceCommandMapper.matchTranscript('hello robot'), isNull);
    });

    test('normalizes transcript text', () {
      expect(
        VoiceCommandMapper.normalizeTranscript('  Stand!!   UP  '),
        'stand up',
      );
    });
  });
}
