import 'package:flutter_test/flutter_test.dart';
import 'package:voice_control_sdk/voice_control_sdk.dart';

void main() {
  group('VoiceSessionStateMachine', () {
    test('accepts Lumi wake then debounces repeated wake for two seconds', () {
      var now = DateTime.utc(2026);
      final machine = VoiceSessionStateMachine(
        config: const VoiceConfig(),
        clock: () => now,
      )..markWaitingForWake();
      final match = VoiceWakeMapper.matchTranscript(
        '鲁米',
        wakeWord: 'Lumi',
        modelLanguage: VoiceLanguage.mixed,
      )!;

      final first = machine.handleWakeCandidate(match);
      expect(first.accepted, isTrue);
      expect(machine.state, VoiceRecognitionState.wakeDetected);

      machine.markWaitingForWake();
      now = now.add(const Duration(milliseconds: 1900));
      final second = machine.handleWakeCandidate(match);
      expect(second.accepted, isFalse);

      now = now.add(const Duration(milliseconds: 100));
      final third = machine.handleWakeCandidate(match);
      expect(third.accepted, isTrue);
    });

    test('returns to waiting after five seconds of silence after valid speech',
        () {
      var now = DateTime.utc(2026);
      final machine = VoiceSessionStateMachine(
        config: const VoiceConfig(),
        clock: () => now,
      )
        ..markWaitingForWake()
        ..beginActiveListening();

      expect(
        machine
            .observeVad(
              speechDetected: true,
              chunkDuration: const Duration(milliseconds: 150),
            )
            .shouldFinish,
        isFalse,
      );
      expect(
        machine
            .observeVad(
              speechDetected: true,
              chunkDuration: const Duration(milliseconds: 150),
            )
            .shouldFinish,
        isFalse,
      );
      expect(machine.hasEffectiveSpeech, isTrue);

      now = now.add(const Duration(milliseconds: 500));
      expect(
        machine
            .observeVad(
              speechDetected: false,
              chunkDuration: const Duration(milliseconds: 20),
            )
            .shouldFinish,
        isFalse,
      );

      now = now.add(const Duration(seconds: 5));
      final decision = machine.observeVad(
        speechDetected: false,
        chunkDuration: const Duration(milliseconds: 20),
      );
      expect(decision.finishReason, VoiceSessionFinishReason.silenceTimeout);
    });

    test('ignores noise shorter than 300ms and uses no-speech timeout', () {
      var now = DateTime.utc(2026);
      final machine = VoiceSessionStateMachine(
        config: const VoiceConfig(),
        clock: () => now,
      )
        ..markWaitingForWake()
        ..beginActiveListening();

      machine.observeVad(
        speechDetected: true,
        chunkDuration: const Duration(milliseconds: 200),
      );
      now = now.add(const Duration(milliseconds: 220));
      machine.observeVad(
        speechDetected: false,
        chunkDuration: const Duration(milliseconds: 20),
      );
      expect(machine.hasEffectiveSpeech, isFalse);

      now = now.add(const Duration(seconds: 5));
      final decision = machine.observeVad(
        speechDetected: false,
        chunkDuration: const Duration(milliseconds: 20),
      );
      expect(decision.finishReason, VoiceSessionFinishReason.noSpeechTimeout);
    });
  });
}
