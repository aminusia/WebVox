enum ThemePreference { system, light, dark }

/// Text decoration identifier — stored as a plain string so the domain layer
/// stays Flutter-free.  Presentation layer converts via [highlightDecorationFromId].
enum HighlightDecoration { none, underline, lineThrough, overline }

class Settings {
  final String ttsLanguage;
  final double ttsSpeed;
  final double fontSize;
  final bool autoNext;
  final bool autoRead;
  final ThemePreference themePreference;

  /// Empty string means use the system default voice.
  final String ttsVoice;

  // ── Paragraph highlight style ─────────────────────────────────────────────
  /// ARGB int for paragraph text color when highlighted. Default: 0xFF2196F3 (blue).
  final int paragraphHighlightColor;

  /// ARGB int for paragraph background when highlighted, or null for no background.
  final int? paragraphHighlightBackground;

  /// Text decoration applied to the highlighted paragraph.
  final HighlightDecoration paragraphHighlightDecoration;

  // ── Word highlight style ──────────────────────────────────────────────────
  /// ARGB int for the currently spoken word. Default: 0xFFB8860B (dark gold).
  final int wordHighlightColor;

  /// ARGB int for word background, or null for no background.
  final int? wordHighlightBackground;

  /// Text decoration applied to the highlighted word.
  final HighlightDecoration wordHighlightDecoration;

  // ── Caching ───────────────────────────────────────────────────────────────
  /// Whether background caching of next articles is enabled.
  final bool cachingEnabled;

  /// Whether caching continues when the app is in the background.
  final bool cacheInBackground;

  const Settings({
    required this.ttsLanguage,
    required this.ttsSpeed,
    required this.fontSize,
    this.autoNext = true,
    this.autoRead = true,
    this.themePreference = ThemePreference.system,
    this.ttsVoice = '',
    this.paragraphHighlightColor = 0xFF2196F3,
    this.paragraphHighlightBackground,
    this.paragraphHighlightDecoration = HighlightDecoration.none,
    this.wordHighlightColor = 0xFFB8860B,
    this.wordHighlightBackground,
    this.wordHighlightDecoration = HighlightDecoration.underline,
    this.cachingEnabled = true,
    this.cacheInBackground = false,
  });

  Settings copyWith({
    String? ttsLanguage,
    double? ttsSpeed,
    double? fontSize,
    bool? autoNext,
    bool? autoRead,
    ThemePreference? themePreference,
    String? ttsVoice,
    int? paragraphHighlightColor,
    Object? paragraphHighlightBackground = _sentinel,
    HighlightDecoration? paragraphHighlightDecoration,
    int? wordHighlightColor,
    Object? wordHighlightBackground = _sentinel,
    HighlightDecoration? wordHighlightDecoration,
    bool? cachingEnabled,
    bool? cacheInBackground,
  }) => Settings(
    ttsLanguage: ttsLanguage ?? this.ttsLanguage,
    ttsSpeed: ttsSpeed ?? this.ttsSpeed,
    fontSize: fontSize ?? this.fontSize,
    autoNext: autoNext ?? this.autoNext,
    autoRead: autoRead ?? this.autoRead,
    themePreference: themePreference ?? this.themePreference,
    ttsVoice: ttsVoice ?? this.ttsVoice,
    paragraphHighlightColor:
        paragraphHighlightColor ?? this.paragraphHighlightColor,
    paragraphHighlightBackground:
        identical(paragraphHighlightBackground, _sentinel)
            ? this.paragraphHighlightBackground
            : paragraphHighlightBackground as int?,
    paragraphHighlightDecoration:
        paragraphHighlightDecoration ?? this.paragraphHighlightDecoration,
    wordHighlightColor: wordHighlightColor ?? this.wordHighlightColor,
    wordHighlightBackground:
        identical(wordHighlightBackground, _sentinel)
            ? this.wordHighlightBackground
            : wordHighlightBackground as int?,
    wordHighlightDecoration:
        wordHighlightDecoration ?? this.wordHighlightDecoration,
    cachingEnabled: cachingEnabled ?? this.cachingEnabled,
    cacheInBackground: cacheInBackground ?? this.cacheInBackground,
  );
}

const Object _sentinel = Object();
