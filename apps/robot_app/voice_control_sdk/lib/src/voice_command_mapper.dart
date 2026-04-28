import 'voice_models.dart';

class VoiceCommandMatch {
  const VoiceCommandMatch({
    required this.command,
    required this.language,
    required this.rawText,
    required this.normalizedText,
    required this.confidence,
  });

  final VoiceCommand command;
  final VoiceLanguage language;
  final String rawText;
  final String normalizedText;
  final double confidence;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'command': command.wireName,
      'language': language.wireName,
      'rawText': rawText,
      'normalizedText': normalizedText,
      'confidence': confidence,
    };
  }
}

class VoiceCommandMapper {
  static final List<_CommandRule> _rules = <_CommandRule>[
    _CommandRule(
      command: VoiceCommand.standUp,
      phrases: const <String>[
        '站起来',
        '站起',
        '起立',
        'stand up',
        'stand',
      ],
    ),
    _CommandRule(
      command: VoiceCommand.sitDown,
      phrases: const <String>[
        '坐下',
        '坐下来',
        'sit down',
        'sit',
      ],
    ),
    _CommandRule(
      command: VoiceCommand.forward,
      phrases: const <String>[
        '前进',
        '向前',
        'forward',
      ],
    ),
    _CommandRule(
      command: VoiceCommand.backward,
      phrases: const <String>[
        '后退',
        '向后',
        'backward',
        'go back',
        'move back',
      ],
    ),
  ];

  static VoiceCommandMatch? matchTranscript(
    String transcript, {
    double confidence = 1.0,
    bool bilingualCommands = true,
  }) {
    final String normalized = _normalizeTranscript(transcript);
    if (normalized.isEmpty) {
      return null;
    }

    if (!bilingualCommands) {
      final VoiceLanguage language = _detectLanguage(normalized, normalized);
      if (language == VoiceLanguage.en) {
        return null;
      }
    }

    final List<String> tokens = normalized
        .split(' ')
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    final String compact = tokens.join('');

    for (final rule in _rules) {
      if (rule.matches(tokens: tokens, compact: compact)) {
        return VoiceCommandMatch(
          command: rule.command,
          language: _detectLanguage(normalized, compact),
          rawText: transcript,
          normalizedText: normalized,
          confidence: confidence,
        );
      }
    }

    return null;
  }

  static VoiceCommand commandFromWire(String? value) {
    return voiceCommandFromWire(value);
  }

  static String normalizeTranscript(String transcript) {
    return _normalizeTranscript(transcript);
  }

  static bool isLikelyCommand(String transcript) {
    return matchTranscript(transcript) != null;
  }

  static VoiceLanguage _detectLanguage(String normalized, String compact) {
    final bool hasChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(compact);
    final bool hasLatin = RegExp(r'[a-z]').hasMatch(normalized);
    if (hasChinese && hasLatin) {
      return VoiceLanguage.mixed;
    }
    if (hasChinese) {
      return VoiceLanguage.zh;
    }
    if (hasLatin) {
      return VoiceLanguage.en;
    }
    return VoiceLanguage.unknown;
  }
}

class _CommandRule {
  const _CommandRule({
    required this.command,
    required this.phrases,
  });

  final VoiceCommand command;
  final List<String> phrases;

  bool matches({
    required List<String> tokens,
    required String compact,
  }) {
    for (final phrase in phrases) {
      final List<String> phraseTokens = _splitPhrase(phrase);
      if (phraseTokens.isEmpty) {
        continue;
      }

      if (phraseTokens.length == 1) {
        final String phraseCompact = phraseTokens.single;
        final bool containsChinese =
            RegExp(r'[\u4e00-\u9fff]').hasMatch(phraseCompact);
        if (containsChinese) {
          if (compact.contains(phraseCompact)) {
            return true;
          }
          continue;
        }

        if (compact == phraseCompact || tokens.contains(phraseCompact)) {
          return true;
        }
        continue;
      }

      if (_containsTokenSequence(tokens, phraseTokens)) {
        return true;
      }
    }
    return false;
  }
}

String _normalizeTranscript(String transcript) {
  final String lower = transcript.toLowerCase().trim();
  if (lower.isEmpty) {
    return '';
  }

  final String replaced =
      lower.replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), ' ');
  return replaced.replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<String> _splitPhrase(String phrase) {
  final String normalized = _normalizeTranscript(phrase);
  if (normalized.isEmpty) {
    return const <String>[];
  }
  return normalized
      .split(' ')
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
}

bool _containsTokenSequence(List<String> tokens, List<String> phraseTokens) {
  if (phraseTokens.isEmpty || tokens.length < phraseTokens.length) {
    return false;
  }

  for (var index = 0; index <= tokens.length - phraseTokens.length; index++) {
    var matched = true;
    for (var offset = 0; offset < phraseTokens.length; offset++) {
      if (tokens[index + offset] != phraseTokens[offset]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      return true;
    }
  }

  return false;
}
