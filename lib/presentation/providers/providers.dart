import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_reader/core/services/article_cache_service.dart';
import 'package:web_reader/data/repositories/article_repository_impl.dart';
import 'package:web_reader/data/repositories/reading_state_repository_impl.dart';
import 'package:web_reader/data/repositories/settings_repository_impl.dart';
import 'package:web_reader/domain/entities/article.dart';
import 'package:web_reader/domain/entities/settings.dart';
import 'package:web_reader/domain/entities/title_group.dart';
import 'package:web_reader/domain/repositories/article_repository.dart';
import 'package:web_reader/domain/repositories/reading_state_repository.dart';
import 'package:web_reader/domain/repositories/settings_repository.dart';
import 'package:web_reader/presentation/providers/article_reader_notifier.dart';
import 'package:web_reader/presentation/providers/tts_notifier.dart';

// ─── Repositories ────────────────────────────────────────────────────────────

final articleRepositoryProvider = Provider<ArticleRepository>((ref) {
  return ArticleRepositoryImpl();
});

final articleCacheServiceProvider = Provider<ArticleCacheService>((ref) {
  final service = ArticleCacheService(ref.read(articleRepositoryProvider));
  ref.onDispose(service.dispose);
  return service;
});

// ─── Cache Log ───────────────────────────────────────────────────────────────

final cacheLogProvider = StateNotifierProvider<CacheLogNotifier, List<String>>((
  ref,
) {
  final service = ref.watch(articleCacheServiceProvider);
  return CacheLogNotifier(service.logStream);
});

class CacheLogNotifier extends StateNotifier<List<String>> {
  static const _maxLines = 200;

  late final StreamSubscription<String> _sub;

  CacheLogNotifier(Stream<String> logStream) : super([]) {
    _sub = logStream.listen((line) {
      final next = [...state, line];
      state =
          next.length > _maxLines
              ? next.sublist(next.length - _maxLines)
              : next;
    });
  }

  void clear() => state = [];

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final readingStateRepositoryProvider = Provider<ReadingStateRepository>((ref) {
  return ReadingStateRepositoryImpl();
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepositoryImpl();
});

// ─── Cached Articles ─────────────────────────────────────────────────────────

final cachedArticlesProvider =
    StateNotifierProvider<CachedArticlesNotifier, AsyncValue<List<Article>>>((
      ref,
    ) {
      return CachedArticlesNotifier(ref.read(articleRepositoryProvider));
    });

class CachedArticlesNotifier extends StateNotifier<AsyncValue<List<Article>>> {
  final ArticleRepository _repo;

  CachedArticlesNotifier(this._repo) : super(const AsyncLoading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.getAllCached());
  }
}

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

// ─── Recent Grouped ───────────────────────────────────────────────────────────

final recentGroupedProvider =
    StateNotifierProvider<RecentGroupedNotifier, AsyncValue<List<TitleGroup>>>(
      (ref) => RecentGroupedNotifier(ref.read(articleRepositoryProvider)),
    );

class RecentGroupedNotifier
    extends StateNotifier<AsyncValue<List<TitleGroup>>> {
  final ArticleRepository _repo;

  RecentGroupedNotifier(this._repo) : super(const AsyncLoading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.getRecentGrouped());
  }

  Future<void> removeTitle(String titleId) async {
    await _repo.removeHistoryForTitle(titleId);
    await load();
  }

  Future<void> renameTitle(String titleId, String newName) async {
    await _repo.updateTitleName(titleId, newName);
    await load();
  }
}

// ─── Bookmarks Grouped ────────────────────────────────────────────────────────

final bookmarksGroupedProvider = StateNotifierProvider<
  BookmarksGroupedNotifier,
  AsyncValue<List<TitleGroup>>
>((ref) => BookmarksGroupedNotifier(ref.read(articleRepositoryProvider)));

class BookmarksGroupedNotifier
    extends StateNotifier<AsyncValue<List<TitleGroup>>> {
  final ArticleRepository _repo;

  BookmarksGroupedNotifier(this._repo) : super(const AsyncLoading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.getBookmarksGrouped());
  }

  Future<void> removeTitle(String titleId) async {
    await _repo.removeBookmarksForTitle(titleId);
    await load();
  }

  Future<void> renameTitle(String titleId, String newName) async {
    await _repo.updateTitleName(titleId, newName);
    await load();
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

// ─── Article Reader ───────────────────────────────────────────────────────────

/// Single provider that owns the full lifecycle of the currently-read article:
/// loading, position restore, auto-play, auto-next, and saving reading state.
final articleReaderProvider =
    NotifierProvider<ArticleReaderNotifier, ArticleReaderState>(
      ArticleReaderNotifier.new,
    );
