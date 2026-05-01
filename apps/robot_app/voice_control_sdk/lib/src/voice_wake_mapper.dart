import 'voice_command_mapper.dart';
import 'voice_models.dart';

class VoiceWakeMatch {
  const VoiceWakeMatch({
    required this.wakeWord,
    required this.recognizedText,
    required this.resultLabel,
    required this.normalizedText,
    required this.language,
    required this.confidence,
  });

  final String wakeWord;
  final String recognizedText;
  final String resultLabel;
  final String normalizedText;
  final VoiceLanguage language;
  final double confidence;
}

class VoiceWakeMapper {
  static VoiceWakeMatch? matchTranscript(
    String transcript, {
    required String wakeWord,
    required VoiceLanguage modelLanguage,
    double confidence = 1.0,
  }) {
    final String normalizedTranscript =
        VoiceCommandMapper.normalizeTranscript(transcript);
    if (normalizedTranscript.isEmpty) {
      return null;
    }

    final List<_WakeAlias> aliases =
        _buildWakeAliases(wakeWord: wakeWord, modelLanguage: modelLanguage);
    for (final alias in aliases) {
      if (_matchesAlias(
        transcript: normalizedTranscript,
        alias: alias.normalizedAlias,
      )) {
        return alias.toMatch(
          wakeWord: wakeWord,
          normalizedText: normalizedTranscript,
          confidence: confidence,
        );
      }
    }

    return null;
  }

  static VoiceWakeMatch? matchResultLabel(
    String resultLabel, {
    required String wakeWord,
    required VoiceLanguage modelLanguage,
    double confidence = 1.0,
  }) {
    final String normalizedResultLabel = resultLabel.trim().replaceFirst(
          RegExp(r'^@+'),
          '',
        );
    final List<_WakeAlias> aliases =
        _buildWakeAliases(wakeWord: wakeWord, modelLanguage: modelLanguage);
    for (final alias in aliases) {
      if (alias.resultLabel == normalizedResultLabel) {
        return alias.toMatch(
          wakeWord: wakeWord,
          normalizedText:
              VoiceCommandMapper.normalizeTranscript(alias.displayAlias),
          confidence: confidence,
        );
      }
    }

    return matchTranscript(
      normalizedResultLabel,
      wakeWord: wakeWord,
      modelLanguage: modelLanguage,
      confidence: confidence,
    );
  }

  static String buildKeywordsFileContent({
    required String wakeWord,
    required VoiceLanguage modelLanguage,
  }) {
    final List<_WakeAlias> aliases =
        _buildWakeAliases(wakeWord: wakeWord, modelLanguage: modelLanguage);
    final buffer = StringBuffer();
    for (final alias in aliases) {
      final tokens = alias.kwsTokens;
      if (tokens.isEmpty) {
        continue;
      }
      buffer.writeln('$tokens @${alias.resultLabel}');
    }
    return buffer.toString();
  }

  static List<String> buildGrammar({
    required String wakeWord,
    required VoiceLanguage modelLanguage,
  }) {
    return _buildWakeAliases(
      wakeWord: wakeWord,
      modelLanguage: modelLanguage,
    ).map((alias) => alias.displayAlias).toList(growable: false);
  }

  static List<_WakeAlias> _buildWakeAliases({
    required String wakeWord,
    required VoiceLanguage modelLanguage,
  }) {
    final Set<_WakeAlias> aliases = <_WakeAlias>{};
    const fixedWakeWord = 'Lumi';
    final List<_WakeAlias> english = <_WakeAlias>[
      _wakeAlias(fixedWakeWord, 'Lumi', 'lumi', VoiceLanguage.en, 'en_main',
          'L UW1 M IY0'),
      _wakeAlias(fixedWakeWord, 'lumi', 'lumi', VoiceLanguage.en, 'en_lower',
          'L UW1 M IY0'),
      _wakeAlias(fixedWakeWord, 'loo me', 'loo me', VoiceLanguage.en,
          'en_loome', 'L UW1 M IY0'),
      _wakeAlias(fixedWakeWord, 'lu mi', 'lu mi', VoiceLanguage.en, 'en_lumi',
          'L UW1 M IY0'),
    ];
    final List<_WakeAlias> chinese = <_WakeAlias>[
      _wakeAlias(
          fixedWakeWord, '鲁米', '鲁米', VoiceLanguage.zh, 'zh_lu3', 'l ǔ m ǐ'),
      _wakeAlias(
          fixedWakeWord, '露米', '露米', VoiceLanguage.zh, 'zh_lu4', 'l ù m ǐ'),
      _wakeAlias(
          fixedWakeWord, '卢米', '卢米', VoiceLanguage.zh, 'zh_lu2', 'l ú m ǐ'),
      _wakeAlias(
          fixedWakeWord, '噜米', '噜米', VoiceLanguage.zh, 'zh_lu1', 'l ū m ǐ'),
    ];

    switch (modelLanguage) {
      case VoiceLanguage.en:
        aliases.addAll(english);
        aliases.addAll(chinese);
        break;
      case VoiceLanguage.zh:
        aliases.addAll(chinese);
        aliases.addAll(english);
        break;
      case VoiceLanguage.mixed:
      case VoiceLanguage.unknown:
        aliases.addAll(english);
        aliases.addAll(chinese);
        break;
    }

    return aliases.toList(growable: false);
  }

  static _WakeAlias _wakeAlias(
    String wakeWord,
    String displayAlias,
    String normalizedAlias,
    VoiceLanguage language,
    String suffix,
    String kwsTokens,
  ) {
    return _WakeAlias(
      displayAlias: displayAlias,
      normalizedAlias: normalizedAlias,
      language: language,
      resultLabel: _resultLabel(wakeWord, suffix),
      kwsTokens: kwsTokens,
    );
  }

  static String _resultLabel(String wakeWord, String suffix) {
    final String normalizedWakeWord =
        VoiceCommandMapper.normalizeTranscript(wakeWord).replaceAll(' ', '_');
    return '${normalizedWakeWord}__$suffix';
  }

  static bool _matchesAlias({
    required String transcript,
    required String alias,
  }) {
    final String compactTranscript = transcript.replaceAll(' ', '');
    final String compactAlias = alias.replaceAll(' ', '');

    if (transcript == alias || compactTranscript == compactAlias) {
      return true;
    }

    if (_containsChinese(compactAlias)) {
      return compactTranscript.contains(compactAlias);
    }

    if (compactTranscript.contains(compactAlias)) {
      return true;
    }

    final List<String> transcriptTokens = transcript
        .split(' ')
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    final List<String> aliasTokens = alias
        .split(' ')
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (aliasTokens.isEmpty || transcriptTokens.length < aliasTokens.length) {
      return false;
    }

    for (var index = 0;
        index <= transcriptTokens.length - aliasTokens.length;
        index++) {
      var matched = true;
      for (var offset = 0; offset < aliasTokens.length; offset++) {
        if (transcriptTokens[index + offset] != aliasTokens[offset]) {
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

  static bool _containsChinese(String text) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
  }
}

class _WakeAlias {
  const _WakeAlias({
    required this.displayAlias,
    required this.normalizedAlias,
    required this.language,
    required this.resultLabel,
    required this.kwsTokens,
  });

  final String displayAlias;
  final String normalizedAlias;
  final VoiceLanguage language;
  final String resultLabel;
  final String kwsTokens;

  VoiceWakeMatch toMatch({
    required String wakeWord,
    required String normalizedText,
    required double confidence,
  }) {
    return VoiceWakeMatch(
      wakeWord: wakeWord,
      recognizedText: displayAlias,
      resultLabel: resultLabel,
      normalizedText: normalizedText,
      language: language,
      confidence: confidence,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _WakeAlias &&
        other.displayAlias == displayAlias &&
        other.normalizedAlias == normalizedAlias &&
        other.language == language &&
        other.resultLabel == resultLabel &&
        other.kwsTokens == kwsTokens;
  }

  @override
  int get hashCode => Object.hash(
      displayAlias, normalizedAlias, language, resultLabel, kwsTokens);
}
