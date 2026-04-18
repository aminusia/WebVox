import 'package:web_reader/domain/entities/settings.dart';

abstract class SettingsRepository {
  Future<Settings> getSettings();
  Future<void> saveSettings(Settings settings);
  Future<String?> getLastArticleUrl();
  Future<void> setLastArticleUrl(String? url);
}
