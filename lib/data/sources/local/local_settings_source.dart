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
      themePreference: ThemePreference.values.firstWhere(
        (pref) => pref.name == themeModeValue,
        orElse: () => ThemePreference.system,
      ),
      ttsVoice: prefs.getString(AppConstants.prefTtsVoice) ?? '',
    );
  }

  Future<void> saveSettings(Settings settings) async {
    final prefs = await _prefs;
    await prefs.setString(AppConstants.prefTtsLanguage, settings.ttsLanguage);
    await prefs.setDouble(AppConstants.prefTtsSpeed, settings.ttsSpeed);
    await prefs.setDouble(AppConstants.prefFontSize, settings.fontSize);
    await prefs.setBool(AppConstants.prefAutoNext, settings.autoNext);
    await prefs.setString(
      AppConstants.prefThemeMode,
      settings.themePreference.name,
    );
    await prefs.setString(AppConstants.prefTtsVoice, settings.ttsVoice);
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
