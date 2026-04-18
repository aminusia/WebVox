enum ThemePreference { system, light, dark }

class Settings {
  final String ttsLanguage;
  final double ttsSpeed;
  final double fontSize;
  final bool autoNext;
  final ThemePreference themePreference;

  /// Empty string means use the system default voice.
  final String ttsVoice;

  const Settings({
    required this.ttsLanguage,
    required this.ttsSpeed,
    required this.fontSize,
    this.autoNext = true,
    this.themePreference = ThemePreference.system,
    this.ttsVoice = '',
  });

  Settings copyWith({
    String? ttsLanguage,
    double? ttsSpeed,
    double? fontSize,
    bool? autoNext,
    ThemePreference? themePreference,
    String? ttsVoice,
  }) => Settings(
    ttsLanguage: ttsLanguage ?? this.ttsLanguage,
    ttsSpeed: ttsSpeed ?? this.ttsSpeed,
    fontSize: fontSize ?? this.fontSize,
    autoNext: autoNext ?? this.autoNext,
    themePreference: themePreference ?? this.themePreference,
    ttsVoice: ttsVoice ?? this.ttsVoice,
  );
}
