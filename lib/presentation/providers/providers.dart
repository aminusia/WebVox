import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_reader/data/repositories/article_repository_impl.dart';
import 'package:web_reader/data/repositories/reading_state_repository_impl.dart';
import 'package:web_reader/data/repositories/settings_repository_impl.dart';
import 'package:web_reader/domain/entities/article.dart';
import 'package:web_reader/domain/entities/settings.dart';
import 'package:web_reader/domain/repositories/article_repository.dart';
import 'package:web_reader/domain/repositories/reading_state_repository.dart';
import 'package:web_reader/domain/repositories/settings_repository.dart';
import 'package:web_reader/presentation/providers/tts_notifier.dart';

// ─── Repositories ────────────────────────────────────────────────────────────

final articleRepositoryProvider = Provider<ArticleRepository>((ref) {
  return ArticleRepositoryImpl();
});

final readingStateRepositoryProvider = Provider<ReadingStateRepository>((ref) {
  return ReadingStateRepositoryImpl();
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepositoryImpl();
});

// ─── Settings ────────────────────────────────────────────────────────────────

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AsyncValue<Settings>>((ref) {
      return SettingsNotifier(ref.read(settingsRepositoryProvider));
    });

class SettingsNotifier extends StateNotifier<AsyncValue<Settings>> {
  final SettingsRepository _repo;

  SettingsNotifier(this._repo) : super(const AsyncLoading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.getSettings());
  }

  Future<void> update(Settings settings) async {
    await _repo.saveSettings(settings);
    state = AsyncData(settings);
  }
}

// ─── Bookmarks ───────────────────────────────────────────────────────────────

final bookmarksProvider =
    StateNotifierProvider<BookmarksNotifier, AsyncValue<List<Article>>>((ref) {
      return BookmarksNotifier(ref.read(articleRepositoryProvider));
    });

class BookmarksNotifier extends StateNotifier<AsyncValue<List<Article>>> {
  final ArticleRepository _repo;

  BookmarksNotifier(this._repo) : super(const AsyncLoading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.getBookmarks());
  }

  Future<void> toggleBookmark(String articleId) async {
    await _repo.toggleBookmark(articleId);
    await load();
  }
}

// ─── Recent Articles ─────────────────────────────────────────────────────────

final recentArticlesProvider =
    StateNotifierProvider<RecentArticlesNotifier, AsyncValue<List<Article>>>((
      ref,
    ) {
      return RecentArticlesNotifier(ref.read(articleRepositoryProvider));
    });

class RecentArticlesNotifier extends StateNotifier<AsyncValue<List<Article>>> {
  final ArticleRepository _repo;

  RecentArticlesNotifier(this._repo) : super(const AsyncLoading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.getRecentArticles());
  }
}

// ─── Current Article Loading ─────────────────────────────────────────────────

final currentArticleProvider =
    StateNotifierProvider<CurrentArticleNotifier, AsyncValue<Article?>>((ref) {
      return CurrentArticleNotifier(ref.read(articleRepositoryProvider));
    });

class CurrentArticleNotifier extends StateNotifier<AsyncValue<Article?>> {
  final ArticleRepository _repo;

  CurrentArticleNotifier(this._repo) : super(const AsyncData(null));

  Future<void> load(String url) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.fetchArticle(url));
  }

  void clear() => state = const AsyncData(null);
}

// ─── TTS Audio Handler ─────────────────────────────────────────────────────────
/// Overridden in main.dart with the AudioService-initialized handler.
final ttsAudioHandlerProvider = Provider<TtsAudioHandler>(
  (_) => throw UnimplementedError('ttsAudioHandlerProvider must be overridden'),
);

// ─── TTS ─────────────────────────────────────────────────────────────────────────────

final ttsProvider = StateNotifierProvider<TtsNotifier, TtsState>((ref) {
  return TtsNotifier(
    ref.read(ttsAudioHandlerProvider),
    ref.read(settingsRepositoryProvider),
  );
});

/// Voices available on the device for a given locale (e.g. 'en-US').
final voicesProvider = FutureProvider.family<List<Map<String, String>>, String>(
  (ref, locale) {
    return ref.read(ttsAudioHandlerProvider).getVoicesForLocale(locale);
  },
);
