class AppConstants {
  static const String dbName = 'web_reader.db';
  static const int dbVersion = 8;

  static const String prefTtsLanguage = 'tts_language';
  static const String prefTtsSpeed = 'tts_speed';
  static const String prefFontSize = 'font_size';
  static const String prefLastArticleUrl = 'last_article_url';
  static const String prefAutoNext = 'auto_next';
  static const String prefAutoRead = 'auto_read';
  static const String prefTtsVoice = 'tts_voice';
  static const String prefThemeMode = 'theme_mode';

  // Highlight style prefs
  static const String prefParagraphHighlightColor = 'para_highlight_color';
  static const String prefParagraphHighlightBackground = 'para_highlight_bg';
  static const String prefParagraphHighlightDecoration = 'para_highlight_deco';
  static const String prefWordHighlightColor = 'word_highlight_color';
  static const String prefWordHighlightBackground = 'word_highlight_bg';
  static const String prefWordHighlightDecoration = 'word_highlight_deco';

  // Caching prefs
  static const String prefCachingEnabled = 'caching_enabled';
  static const String prefCacheInBackground = 'cache_in_background';

  static const String defaultTtsLanguage = 'en-US';
  static const double defaultTtsSpeed = 0.5;
  static const double defaultFontSize = 18.0;
  static const bool defaultAutoNext = true;
  static const bool defaultAutoRead = false;
  static const String defaultThemeMode = 'system';
  static const bool defaultCachingEnabled = true;
  static const bool defaultCacheInBackground = false;

  // Highlight style defaults
  static const int defaultParagraphHighlightColor = 0xFF2196F3; // Colors.blue
  static const int defaultWordHighlightColor = 0xFFB8860B; // dark golden yellow
  static const String defaultParagraphHighlightDecoration = 'none';
  static const String defaultWordHighlightDecoration = 'underline';

  static const int maxCachedArticles = 50;

  static const Duration fetchTimeout = Duration(seconds: 20);
}
