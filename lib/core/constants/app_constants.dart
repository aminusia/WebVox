class AppConstants {
  static const String dbName = 'web_reader.db';
  static const int dbVersion = 3;

  static const String prefTtsLanguage = 'tts_language';
  static const String prefTtsSpeed = 'tts_speed';
  static const String prefFontSize = 'font_size';
  static const String prefLastArticleUrl = 'last_article_url';
  static const String prefAutoNext = 'auto_next';
  static const String prefTtsVoice = 'tts_voice';
  static const String prefThemeMode = 'theme_mode';

  static const String defaultTtsLanguage = 'en-US';
  static const double defaultTtsSpeed = 0.5;
  static const double defaultFontSize = 18.0;
  static const bool defaultAutoNext = true;
  static const String defaultThemeMode = 'system';

  static const int maxCachedArticles = 50;

  static const Duration fetchTimeout = Duration(seconds: 20);
}
