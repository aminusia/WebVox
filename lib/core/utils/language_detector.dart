class LanguageDetector {
  static const Map<String, String> _ttsMap = {
    'en-US': 'en-US',
    'en-GB': 'en-GB',
    'en-AU': 'en-AU',
    'de-DE': 'de-DE',
    'fr-FR': 'fr-FR',
    'es-ES': 'es-ES',
    'es-MX': 'es-MX',
    'it-IT': 'it-IT',
    'pt-BR': 'pt-BR',
    'pt-PT': 'pt-PT',
    'ru-RU': 'ru-RU',
    'zh-CN': 'zh-CN',
    'zh-TW': 'zh-TW',
    'ja-JP': 'ja-JP',
    'ko-KR': 'ko-KR',
    'ar-SA': 'ar-SA',
    'nl-NL': 'nl-NL',
    'pl-PL': 'pl-PL',
    'sv-SE': 'sv-SE',
    'da-DK': 'da-DK',
    'nb-NO': 'nb-NO',
    'fi-FI': 'fi-FI',
    'tr-TR': 'tr-TR',
    'hi-IN': 'hi-IN',
  };

  static String toTtsLanguage(String bcp47) {
    if (_ttsMap.containsKey(bcp47)) return bcp47;
    // Try matching just the language code
    final lang = bcp47.split('-').first.toLowerCase();
    for (final key in _ttsMap.keys) {
      if (key.toLowerCase().startsWith(lang)) return key;
    }
    return 'en-US';
  }

  static List<String> get supportedLanguages => List.unmodifiable(_ttsMap.keys);
}
