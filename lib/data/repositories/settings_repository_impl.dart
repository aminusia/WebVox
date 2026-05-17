import 'package:webvox/data/sources/local/local_settings_source.dart';
import 'package:webvox/domain/entities/settings.dart';
import 'package:webvox/domain/repositories/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final LocalSettingsSource _source;

  SettingsRepositoryImpl({LocalSettingsSource? source})
    : _source = source ?? LocalSettingsSource();

  @override
  Future<Settings> getSettings() => _source.getSettings();

  @override
  Future<void> saveSettings(Settings settings) =>
      _source.saveSettings(settings);

  @override
  Future<String?> getLastArticleUrl() => _source.getLastArticleUrl();

  @override
  Future<void> setLastArticleUrl(String? url) => _source.setLastArticleUrl(url);
}
