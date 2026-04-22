import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_reader/core/constants/app_constants.dart';
import 'package:web_reader/domain/entities/settings.dart';

class LocalSettingsSource {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<Settings> getSettings() async {
    final prefs = await _prefs;
    final themeModeValue =
        prefs.getString(AppConstants.prefThemeMode) ??
        AppConstants.defaultThemeMode;

    return Settings(
      ttsLanguage:
          prefs.getString(AppConstants.prefTtsLanguage) ??
          AppConstants.defaultTtsLanguage,
      ttsSpeed:
          prefs.getDouble(AppConstants.prefTtsSpeed) ??
          AppConstants.defaultTtsSpeed,
      fontSize:
          prefs.getDouble(AppConstants.prefFontSize) ??
          AppConstants.defaultFontSize,
      autoNext:
          prefs.getBool(AppConstants.prefAutoNext) ??
          AppConstants.defaultAutoNext,
      autoRead:
          prefs.getBool(AppConstants.prefAutoRead) ??
          AppConstants.defaultAutoRead,
      themePreference: ThemePreference.values.firstWhere(
        (pref) => pref.name == themeModeValue,
        orElse: () => ThemePreference.system,
      ),
      ttsVoice: prefs.getString(AppConstants.prefTtsVoice) ?? '',
      paragraphHighlightColor:
          prefs.getInt(AppConstants.prefParagraphHighlightColor) ??
          AppConstants.defaultParagraphHighlightColor,
      paragraphHighlightBackground:
          prefs.containsKey(AppConstants.prefParagraphHighlightBackground)
              ? prefs.getInt(AppConstants.prefParagraphHighlightBackground)
              : null,
      paragraphHighlightDecoration: HighlightDecoration.values.firstWhere(
        (d) =>
            d.name ==
            (prefs.getString(AppConstants.prefParagraphHighlightDecoration) ??
                AppConstants.defaultParagraphHighlightDecoration),
        orElse: () => HighlightDecoration.none,
      ),
      wordHighlightColor:
          prefs.getInt(AppConstants.prefWordHighlightColor) ??
          AppConstants.defaultWordHighlightColor,
      wordHighlightBackground:
          prefs.containsKey(AppConstants.prefWordHighlightBackground)
              ? prefs.getInt(AppConstants.prefWordHighlightBackground)
              : null,
      wordHighlightDecoration: HighlightDecoration.values.firstWhere(
        (d) =>
            d.name ==
            (prefs.getString(AppConstants.prefWordHighlightDecoration) ??
                AppConstants.defaultWordHighlightDecoration),
        orElse: () => HighlightDecoration.underline,
      ),
    );
  }

  Future<void> saveSettings(Settings settings) async {
    final prefs = await _prefs;
    await prefs.setString(AppConstants.prefTtsLanguage, settings.ttsLanguage);
    await prefs.setDouble(AppConstants.prefTtsSpeed, settings.ttsSpeed);
    await prefs.setDouble(AppConstants.prefFontSize, settings.fontSize);
    await prefs.setBool(AppConstants.prefAutoNext, settings.autoNext);
    await prefs.setBool(AppConstants.prefAutoRead, settings.autoRead);
    await prefs.setString(
      AppConstants.prefThemeMode,
      settings.themePreference.name,
    );
    await prefs.setString(AppConstants.prefTtsVoice, settings.ttsVoice);
    await prefs.setInt(
      AppConstants.prefParagraphHighlightColor,
      settings.paragraphHighlightColor,
    );
    if (settings.paragraphHighlightBackground != null) {
      await prefs.setInt(
        AppConstants.prefParagraphHighlightBackground,
        settings.paragraphHighlightBackground!,
      );
    } else {
      await prefs.remove(AppConstants.prefParagraphHighlightBackground);
    }
    await prefs.setString(
      AppConstants.prefParagraphHighlightDecoration,
      settings.paragraphHighlightDecoration.name,
    );
    await prefs.setInt(
      AppConstants.prefWordHighlightColor,
      settings.wordHighlightColor,
    );
    if (settings.wordHighlightBackground != null) {
      await prefs.setInt(
        AppConstants.prefWordHighlightBackground,
        settings.wordHighlightBackground!,
      );
    } else {
      await prefs.remove(AppConstants.prefWordHighlightBackground);
    }
    await prefs.setString(
      AppConstants.prefWordHighlightDecoration,
      settings.wordHighlightDecoration.name,
    );
  }

  Future<String?> getLastArticleUrl() async {
    final prefs = await _prefs;
    return prefs.getString(AppConstants.prefLastArticleUrl);
  }

  Future<void> setLastArticleUrl(String? url) async {
    final prefs = await _prefs;
    if (url == null) {
      await prefs.remove(AppConstants.prefLastArticleUrl);
    } else {
      await prefs.setString(AppConstants.prefLastArticleUrl, url);
    }
  }
}
