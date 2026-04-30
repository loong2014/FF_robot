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
    final String normalized =
        VoiceCommandMapper.normalizeTranscript(wakeWord).trim();
    final String compact = normalized.replaceAll(' ', '');
    final bool looksLikeDdog = _looksLikeDdogWakeWord(
      wakeWord: wakeWord,
      normalized: normalized,
      compact: compact,
    );
    final bool looksLikeLumi = _looksLikeLumiWakeWord(
      wakeWord: wakeWord,
      normalized: normalized,
      compact: compact,
    );

    void addAlias(String value, VoiceLanguage language, String resultLabel) {
      final String normalizedAlias =
          VoiceCommandMapper.normalizeTranscript(value);
      if (normalizedAlias.isEmpty) {
        return;
      }
      aliases.add(
        _WakeAlias(
          displayAlias: value.trim(),
          normalizedAlias: normalizedAlias,
          language: language,
          resultLabel: resultLabel,
          kwsTokens: _tokenizeForKws(value),
        ),
      );
    }

    addAlias(wakeWord, VoiceLanguage.unknown, _resultLabel(wakeWord, 'base'));
    addAlias(
        normalized, VoiceLanguage.unknown, _resultLabel(wakeWord, 'base2'));
    addAlias(compact, VoiceLanguage.unknown, _resultLabel(wakeWord, 'base3'));

    if (!looksLikeDdog && !looksLikeLumi) {
      return aliases.toList(growable: false);
    }

    if (looksLikeLumi) {
      final List<_WakeAlias> english = <_WakeAlias>[
        _wakeAlias(wakeWord, 'Lumi', 'lumi', VoiceLanguage.en, 'en_main',
            'L UW1 M IY0'),
        _wakeAlias(wakeWord, 'lumi', 'lumi', VoiceLanguage.en, 'en_lower',
            'L UW1 M IY0'),
        _wakeAlias(wakeWord, 'loo me', 'loo me', VoiceLanguage.en, 'en_loome',
            'L UW1 M IY0'),
        _wakeAlias(wakeWord, 'lu mi', 'lu mi', VoiceLanguage.en, 'en_lumi',
            'L UW1 M IY0'),
      ];

      final List<_WakeAlias> chinese = <_WakeAlias>[
        _wakeAlias(wakeWord, '露米', '露米', VoiceLanguage.zh, 'zh_lu4', 'l ù m ǐ'),
        _wakeAlias(
            wakeWord, '路米', '路米', VoiceLanguage.zh, 'zh_lu4_2', 'l ù m ǐ'),
        _wakeAlias(wakeWord, '卢米', '卢米', VoiceLanguage.zh, 'zh_lu2', 'l ú m ǐ'),
        _wakeAlias(
            wakeWord, '鲁米', '鲁米', VoiceLanguage.zh, 'zh_lu2_2', 'l ú m ǐ'),
        _wakeAlias(
            wakeWord, '噜米', '噜米', VoiceLanguage.zh, 'zh_lu2_3', 'l ú m ǐ'),
        _wakeAlias(
            wakeWord, '鹿米', '鹿米', VoiceLanguage.zh, 'zh_lu4_3', 'l ù m ǐ'),
        _wakeAlias(
            wakeWord, '陆米', '陆米', VoiceLanguage.zh, 'zh_lu4_4', 'l ù m ǐ'),
        _wakeAlias(
            wakeWord, '录米', '录米', VoiceLanguage.zh, 'zh_lu4_5', 'l ù m ǐ'),
        _wakeAlias(
            wakeWord, '绿米', '绿米', VoiceLanguage.zh, 'zh_lv4', 'l ǜ m ǐ'),
        _wakeAlias(
            wakeWord, '如米', '如米', VoiceLanguage.zh, 'zh_ru2', 'r ú m ǐ'),
        _wakeAlias(wakeWord, 'lu mi', 'lu mi', VoiceLanguage.zh, 'zh_lu_mi',
            'l ù m ǐ'),
      ];

      switch (modelLanguage) {
        case VoiceLanguage.en:
          aliases.addAll(english);
          aliases.add(_wakeAlias(
              wakeWord, '露米', '露米', VoiceLanguage.zh, 'zh_lu4', 'l ù m ǐ'));
          aliases.add(_wakeAlias(
              wakeWord, '卢米', '卢米', VoiceLanguage.zh, 'zh_lu2', 'l ú m ǐ'));
          break;
        case VoiceLanguage.zh:
          aliases.addAll(chinese);
          aliases.add(_wakeAlias(wakeWord, 'Lumi', 'lumi', VoiceLanguage.en,
              'en_main', 'L UW1 M IY0'));
          break;
        case VoiceLanguage.mixed:
        case VoiceLanguage.unknown:
          aliases.addAll(english);
          aliases.addAll(chinese);
          break;
      }

      return aliases.toList(growable: false);
    }

    final List<_WakeAlias> english = <_WakeAlias>[
      _wakeAlias(wakeWord, 'D-Dog', 'd dog', VoiceLanguage.en, 'en_main',
          'D IY1 D AO1 G'),
      _wakeAlias(wakeWord, 'D Dog', 'd dog', VoiceLanguage.en, 'en_spaced',
          'D IY1 D AO1 G'),
      _wakeAlias(wakeWord, 'd dog', 'd dog', VoiceLanguage.en, 'en_lower',
          'D IY1 D AO1 G'),
      _wakeAlias(wakeWord, 'd-dog', 'd dog', VoiceLanguage.en, 'en_hyphen',
          'D IY1 D AO1 G'),
      _wakeAlias(wakeWord, 'dee dog', 'dee dog', VoiceLanguage.en, 'en_dee',
          'D IY1 D AO1 G'),
    ];

    final List<_WakeAlias> chinese = <_WakeAlias>[
      _wakeAlias(wakeWord, '迪狗', '迪狗', VoiceLanguage.zh, 'zh_di', 'd ī g ǒu'),
      _wakeAlias(wakeWord, '滴狗', '滴狗', VoiceLanguage.zh, 'zh_di2', 'd ī g ǒu'),
      _wakeAlias(wakeWord, '嘀狗', '嘀狗', VoiceLanguage.zh, 'zh_di3', 'd ī g ǒu'),
      _wakeAlias(wakeWord, '帝狗', '帝狗', VoiceLanguage.zh, 'zh_di4', 'd ì g ǒu'),
      _wakeAlias(wakeWord, '弟狗', '弟狗', VoiceLanguage.zh, 'zh_di5', 'd ì g ǒu'),
      _wakeAlias(wakeWord, '地狗', '地狗', VoiceLanguage.zh, 'zh_di6', 'd ì g ǒu'),
      _wakeAlias(
          wakeWord, 'd狗', 'd狗', VoiceLanguage.zh, 'zh_dog', 'D IY1 g ǒu'),
      _wakeAlias(wakeWord, 'di gou', 'di gou', VoiceLanguage.zh, 'zh_di_gou',
          'd ī g ǒu'),
      _wakeAlias(wakeWord, 'di-dog', 'di dog', VoiceLanguage.zh, 'zh_di_dog',
          'd ī D AO1 G'),
      _wakeAlias(wakeWord, 'di dog', 'di dog', VoiceLanguage.zh, 'zh_di_dog2',
          'd ī D AO1 G'),
    ];

    switch (modelLanguage) {
      case VoiceLanguage.en:
        aliases.addAll(english);
        aliases.add(_wakeAlias(
            wakeWord, '迪狗', '迪狗', VoiceLanguage.zh, 'zh_di', 'd ī g ǒu'));
        aliases.add(_wakeAlias(
            wakeWord, '滴狗', '滴狗', VoiceLanguage.zh, 'zh_di2', 'd ī g ǒu'));
        break;
      case VoiceLanguage.zh:
        aliases.addAll(chinese);
        aliases.add(_wakeAlias(wakeWord, 'D-Dog', 'd dog', VoiceLanguage.en,
            'en_main', 'D IY1 D AO1 G'));
        aliases.add(_wakeAlias(wakeWord, 'D Dog', 'd dog', VoiceLanguage.en,
            'en_spaced', 'D IY1 D AO1 G'));
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

  static bool _looksLikeDdogWakeWord({
    required String wakeWord,
    required String normalized,
    required String compact,
  }) {
    if (wakeWord == 'D-Dog') {
      return true;
    }

    final String lowerWakeWord = wakeWord.toLowerCase().trim();
    return compact.contains('ddog') ||
        compact == 'ddog' ||
        normalized == 'd dog' ||
        normalized == 'dee dog' ||
        lowerWakeWord == 'd-dog' ||
        lowerWakeWord == 'd dog' ||
        lowerWakeWord == 'dee dog';
  }

  static bool _looksLikeLumiWakeWord({
    required String wakeWord,
    required String normalized,
    required String compact,
  }) {
    if (wakeWord == 'Lumi') {
      return true;
    }

    final String lowerWakeWord = wakeWord.toLowerCase().trim();
    return compact == 'lumi' ||
        compact == 'loome' ||
        normalized == 'lu mi' ||
        normalized == 'loo me' ||
        lowerWakeWord == 'lumi' ||
        lowerWakeWord == 'lu mi' ||
        lowerWakeWord == 'loo me';
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

  static String _tokenizeForKws(String text) {
    final String normalized = VoiceCommandMapper.normalizeTranscript(text);
    if (normalized.isEmpty) {
      return '';
    }

    final tokens = <String>[];
    for (final int rune in normalized.runes) {
      final String char = String.fromCharCode(rune);
      if (char == ' ') {
        continue;
      }
      if (_isChinese(char) || RegExp(r'[a-z0-9]').hasMatch(char)) {
        tokens.add(char);
      }
    }
    return tokens.join(' ');
  }

  static bool _isChinese(String text) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
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
