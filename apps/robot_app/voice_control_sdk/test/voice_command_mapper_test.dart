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

      final stop = VoiceCommandMapper.matchTranscript('别动');
      expect(stop, isNotNull);
      expect(stop!.command, VoiceCommand.stop);
      expect(stop.language, VoiceLanguage.zh);

      final forward = VoiceCommandMapper.matchTranscript('前进');
      expect(forward, isNotNull);
      expect(forward!.command, VoiceCommand.forward);
      expect(forward.language, VoiceLanguage.zh);

      final backward = VoiceCommandMapper.matchTranscript('后退');
      expect(backward, isNotNull);
      expect(backward!.command, VoiceCommand.backward);
      expect(backward.language, VoiceLanguage.zh);

      final left = VoiceCommandMapper.matchTranscript('向左');
      expect(left, isNotNull);
      expect(left!.command, VoiceCommand.left);

      final right = VoiceCommandMapper.matchTranscript('右移');
      expect(right, isNotNull);
      expect(right!.command, VoiceCommand.right);
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

      final stop = VoiceCommandMapper.matchTranscript('stop');
      expect(stop, isNotNull);
      expect(stop!.command, VoiceCommand.stop);
      expect(stop.language, VoiceLanguage.en);

      final forward = VoiceCommandMapper.matchTranscript('move forward');
      expect(forward, isNotNull);
      expect(forward!.command, VoiceCommand.forward);
      expect(forward.language, VoiceLanguage.en);

      final backward = VoiceCommandMapper.matchTranscript('go backward');
      expect(backward, isNotNull);
      expect(backward!.command, VoiceCommand.backward);
      expect(backward.language, VoiceLanguage.en);

      final left = VoiceCommandMapper.matchTranscript('move left');
      expect(left, isNotNull);
      expect(left!.command, VoiceCommand.left);

      final right = VoiceCommandMapper.matchTranscript('right');
      expect(right, isNotNull);
      expect(right!.command, VoiceCommand.right);
    });

    test('uses priority order when one transcript contains multiple commands',
        () {
      final match = VoiceCommandMapper.matchTranscript('先前进然后停止');
      expect(match, isNotNull);
      expect(match!.command, VoiceCommand.stop);
    });

    test('drops low-confidence final transcripts', () {
      expect(
        VoiceCommandMapper.matchTranscript('站起来', confidence: 0.69),
        isNull,
      );
    });

    test('deduplicates the same final command within one second', () {
      var now = DateTime.utc(2026);
      final mapper = VoiceCommandMapper(clock: () => now);

      expect(
        mapper.matchFinalTranscript('站起来')?.command,
        VoiceCommand.standUp,
      );
      now = now.add(const Duration(milliseconds: 800));
      expect(mapper.matchFinalTranscript('stand'), isNull);
      expect(
        mapper.matchFinalTranscript('坐下')?.command,
        VoiceCommand.sitDown,
      );
      now = now.add(const Duration(milliseconds: 1000));
      expect(
        mapper.matchFinalTranscript('站起来')?.command,
        VoiceCommand.standUp,
      );
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
