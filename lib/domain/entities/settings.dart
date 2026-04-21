enum ThemePreference { system, light, dark }

class Settings {
  final String ttsLanguage;
  final double ttsSpeed;
  final double fontSize;
  final bool autoNext;
  final bool autoRead;
  final ThemePreference themePreference;

  /// Empty string means use the system default voice.
  final String ttsVoice;

  const Settings({
    required this.ttsLanguage,
    required this.ttsSpeed,
    required this.fontSize,
    this.autoNext = true,
    this.autoRead = true,
    this.themePreference = ThemePreference.system,
    this.ttsVoice = '',
  });

  Settings copyWith({
    String? ttsLanguage,
    double? ttsSpeed,
    double? fontSize,
    bool? autoNext,
    bool? autoRead,
    ThemePreference? themePreference,
    String? ttsVoice,
  }) => Settings(
    ttsLanguage: ttsLanguage ?? this.ttsLanguage,
    ttsSpeed: ttsSpeed ?? this.ttsSpeed,
    fontSize: fontSize ?? this.fontSize,
    autoNext: autoNext ?? this.autoNext,
    autoRead: autoRead ?? this.autoRead,
    themePreference: themePreference ?? this.themePreference,
    ttsVoice: ttsVoice ?? this.ttsVoice,
  );
}
