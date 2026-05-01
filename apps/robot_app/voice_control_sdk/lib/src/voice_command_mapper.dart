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
  VoiceCommandMapper({
    DateTime Function()? clock,
    this.minConfidence = 0.70,
    this.dedupeWindow = const Duration(seconds: 1),
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final DateTime Function() _clock;
  final double minConfidence;
  final Duration dedupeWindow;

  VoiceCommand? _lastCommand;
  DateTime? _lastCommandAt;

  static final List<_CommandRule> _rules = <_CommandRule>[
    _CommandRule(
      command: VoiceCommand.stop,
      phrases: const <String>[
        '停止',
        '停下',
        '别动',
        'stop',
      ],
    ),
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
        '蹲下',
        'sit down',
        'sit',
      ],
    ),
    _CommandRule(
      command: VoiceCommand.forward,
      phrases: const <String>[
        '前进',
        '向前',
        '往前',
        '走',
        'forward',
        'go forward',
        'move forward',
      ],
    ),
    _CommandRule(
      command: VoiceCommand.backward,
      phrases: const <String>[
        '后退',
        '向后',
        '往后',
        'backward',
        'go backward',
        'go back',
        'move back',
      ],
    ),
    _CommandRule(
      command: VoiceCommand.left,
      phrases: const <String>[
        '左移',
        '向左',
        '往左',
        'left',
        'move left',
      ],
    ),
    _CommandRule(
      command: VoiceCommand.right,
      phrases: const <String>[
        '右移',
        '向右',
        '往右',
        'right',
        'move right',
      ],
    ),
  ];

  VoiceCommandMatch? matchFinalTranscript(
    String transcript, {
    double confidence = 1.0,
    bool bilingualCommands = true,
  }) {
    final match = matchTranscript(
      transcript,
      confidence: confidence,
      bilingualCommands: bilingualCommands,
      minConfidence: minConfidence,
    );
    if (match == null) {
      return null;
    }

    final now = _clock();
    if (_lastCommand == match.command &&
        _lastCommandAt != null &&
        now.difference(_lastCommandAt!) < dedupeWindow) {
      return null;
    }
    _lastCommand = match.command;
    _lastCommandAt = now;
    return match;
  }

  void resetDedupe() {
    _lastCommand = null;
    _lastCommandAt = null;
  }

  static VoiceCommandMatch? matchTranscript(
    String transcript, {
    double confidence = 1.0,
    bool bilingualCommands = true,
    double minConfidence = 0.70,
  }) {
    if (confidence < minConfidence) {
      return null;
    }
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
