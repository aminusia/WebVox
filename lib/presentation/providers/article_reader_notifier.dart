import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webvox/domain/entities/article.dart';
import 'package:webvox/domain/entities/reading_state.dart';
import 'package:webvox/presentation/providers/providers.dart';
import 'package:webvox/presentation/providers/tts_notifier.dart';

// ─── State ────────────────────────────────────────────────────────────────────

class ArticleReaderState {
  /// The article currently displayed.
  final Article? article;

  /// True while loading a new article (prev/next navigation or URL open).
  final bool isLoading;

  /// Reflects the bookmark state of the current article.
  final bool isBookmarked;

  /// Currently highlighted (or TTS-reading) paragraph index.
  final int highlightedIndex;

  /// Char offset within the highlighted paragraph used as TTS resume point.
  final int savedWordOffset;

  /// Whether the TTS control bar is visible.
  final bool showTts;

  /// Whether the scroll-to-top FAB should be shown.
  final bool showScrollToTop;

  /// When set the scroll view should jump to this fraction (0–1) on the next
  /// frame, then the notifier should be told to clear it.
  final double? savedScrollPosition;

  /// One-shot flag: widget shows "Automatically continued" snackbar then calls
  /// [ArticleReaderNotifier.clearAutoNextSnackbar].
  final bool showAutoNextSnackbar;

  const ArticleReaderState({
    this.article,
    this.isLoading = false,
    this.isBookmarked = false,
    this.highlightedIndex = 0,
    this.savedWordOffset = 0,
    this.showTts = true,
    this.showScrollToTop = false,
    this.savedScrollPosition,
    this.showAutoNextSnackbar = false,
  });

  ArticleReaderState copyWith({
    Article? article,
    bool? isLoading,
    bool? isBookmarked,
    int? highlightedIndex,
    int? savedWordOffset,
    bool? showTts,
    bool? showScrollToTop,
    // Use a sentinel to allow setting savedScrollPosition to null explicitly.
    Object? savedScrollPosition = _keep,
    bool? showAutoNextSnackbar,
    // When true, clears savedScrollPosition to null.
    bool clearSavedScroll = false,
  }) => ArticleReaderState(
    article: article ?? this.article,
    isLoading: isLoading ?? this.isLoading,
    isBookmarked: isBookmarked ?? this.isBookmarked,
    highlightedIndex: highlightedIndex ?? this.highlightedIndex,
    savedWordOffset: savedWordOffset ?? this.savedWordOffset,
    showTts: showTts ?? this.showTts,
    showScrollToTop: showScrollToTop ?? this.showScrollToTop,
    savedScrollPosition:
        clearSavedScroll
            ? null
            : (savedScrollPosition == _keep
                ? this.savedScrollPosition
                : savedScrollPosition as double?),
    showAutoNextSnackbar: showAutoNextSnackbar ?? this.showAutoNextSnackbar,
  );
}

const _keep = Object();

// ─── Notifier ────────────────────────────────────────────────────────────────

/// Manages the full lifecycle of an article being read:
///   • loading articles (initial, prev/next, URL, refresh)
///   • auto-play TTS and reading-position restore
///   • auto-next countdown and background retry
///   • saving reading state
///
/// Does not depend on any render frame or BuildContext — pure Riverpod logic.
class ArticleReaderNotifier extends Notifier<ArticleReaderState> {
  Timer? _saveTimer;
  Timer? _backgroundRetryTimer;
  String? _pendingAutoNextUrl;
  bool _autoPlayScheduled = false;

  @override
  ArticleReaderState build() {
    // Listen to TTS changes so this notifier drives auto-next + paragraph sync.
    ref.listen(ttsProvider, _onTtsStateChanged);
    ref.onDispose(_onDispose);
    return const ArticleReaderState();
  }

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Called once from the widget's initState when the screen opens.
  /// [article] is the initial article; [resetProgress] skips position restore.
  Future<void> initWithArticle(
    Article article, {
    bool resetProgress = false,
  }) async {
    // Only cancel an in-progress countdown when switching articles.
    if (state.article != null) _cancelAutoNextInternal();
    _autoPlayScheduled = false;
    state = ArticleReaderState(
      article: article,
      isBookmarked: article.isBookmarked,
      showTts: state.showTts, // preserve the user's TTS-bar preference
    );

    await ref.read(articleRepositoryProvider).markArticleRead(article.id);
    ref.read(recentArticlesProvider.notifier).load();

    final cacheService = ref.read(articleCacheServiceProvider);
    cacheService.resetDelaySchedule();
    _maybeStartCache(article);

    if (resetProgress) {
      _maybeAutoPlay();
    } else {
      await _restorePosition(article);
    }
  }

  /// Fetch a URL and navigate to the resulting article (prev/next/URL editor).
  /// Throws on network error so the caller can show a SnackBar.
  Future<void> loadUrl(
    String url, {
    bool resetProgress = false,
    bool markCurrentCompleted = false,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final current = state.article;
      final repo = ref.read(articleRepositoryProvider);
      if (current != null && markCurrentCompleted) {
        await repo.markArticleCompleted(current.id);
      }
      final newArticle = await repo.fetchArticle(url);

      // Seamless TTS hand-off — keeps audio focus and notification alive.
      ref
          .read(ttsProvider.notifier)
          .transitionToContent(
            newArticle.paragraphs,
            language: newArticle.language,
            articleTitle: newArticle.title,
          );

      await saveState(scrollFraction: 0); // save before switching
      await ref.read(settingsRepositoryProvider).setLastArticleUrl(url);
      ref.read(recentArticlesProvider.notifier).load();
      await _switchToArticle(newArticle, resetProgress: resetProgress);
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  /// Re-fetch the current article URL.
  Future<void> refreshCurrentArticle() async {
    final current = state.article;
    if (current == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final newArticle = await ref
          .read(articleRepositoryProvider)
          .fetchArticle(current.url);
      await _switchToArticle(newArticle, resetProgress: false);
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  /// Persist the current reading position. [scrollFraction] (0–1) is provided
  /// by the widget since it owns the ScrollController.
  Future<void> saveState({required double scrollFraction}) async {
    final article = state.article;
    if (article == null) return;
    final ttsState = ref.read(ttsProvider);
    final rs = ReadingState(
      articleId: article.id,
      scrollPosition: scrollFraction,
      lastReadIndex:
          ttsState.isActive ? ttsState.currentIndex : state.highlightedIndex,
      lastWordOffset:
          ttsState.isActive
              ? ttsState.wordStart.clamp(0, 9999)
              : state.savedWordOffset,
    );
    await ref.read(readingStateRepositoryProvider).saveReadingState(rs);
  }

  void cancelAutoNext() => _cancelAutoNextInternal();

  Future<void> toggleBookmark() async {
    final article = state.article;
    if (article == null) return;
    final newVal = !state.isBookmarked;
    state = state.copyWith(isBookmarked: newVal);
    await ref.read(articleRepositoryProvider).toggleBookmark(article.id);
    ref.read(bookmarksProvider.notifier).load();
  }

  void setHighlightedIndex(int index) {
    state = state.copyWith(highlightedIndex: index, savedWordOffset: 0);
  }

  void setScrollTopVisibility(bool show) {
    if (state.showScrollToTop == show) return;
    state = state.copyWith(showScrollToTop: show);
  }

  void setShowTts(bool show) => state = state.copyWith(showTts: show);

  /// Called by the widget after it has scrolled to the saved position.
  void clearSavedScrollPosition() =>
      state = state.copyWith(clearSavedScroll: true);

  /// Called by the widget after it has shown the auto-next snackbar.
  void clearAutoNextSnackbar() =>
      state = state.copyWith(showAutoNextSnackbar: false);

  // ─── App lifecycle (delegated from WidgetsBindingObserver in widget) ──────

  void onAppResumed() {
    ref.read(articleCacheServiceProvider).resume();
    _backgroundRetryTimer?.cancel();
    _backgroundRetryTimer = null;

    if (_pendingAutoNextUrl != null) {
      final url = _pendingAutoNextUrl!;
      _pendingAutoNextUrl = null;
      _navigateToUrlAutoNext(url: url);
    }
  }

  void onAppPaused({required bool cacheInBackground}) {
    if (!cacheInBackground) {
      ref.read(articleCacheServiceProvider).pause();
    }
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  void _onTtsStateChanged(TtsState? prev, TtsState next) {
    final article = state.article;
    if (article == null) return;

    // Keep highlighted paragraph in sync with TTS position.
    if (next.isActive && next.currentIndex != state.highlightedIndex) {
      state = state.copyWith(
        highlightedIndex: next.currentIndex,
        savedWordOffset: 0,
      );
    }

    if (prev == null) return;

    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final isBackground =
        lifecycle != null && lifecycle != AppLifecycleState.resumed;

    if (isBackground &&
        next.isActive &&
        next.total > 0 &&
        next.currentIndex == next.total - 1 &&
        prev.currentIndex != next.currentIndex) {
      // Screen is off — load immediately so audio continues.
      _navigateToUrlAutoNext(url: article.nextUrl);
    } else if (!isBackground &&
        prev.status != TtsStatus.idle &&
        next.status == TtsStatus.idle) {
      _triggerAutoNext();
    }
  }

  void _triggerAutoNext() {
    final article = state.article;
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null || !settings.autoNext) return;
    if (article?.nextUrl == null) return;
    _navigateToUrlAutoNext(url: article!.nextUrl);
  }

  void _cancelAutoNextInternal() {
    // No countdown to cancel; retained for compatibility.
  }

  Future<void> _navigateToUrlAutoNext({String? url}) async {
    final article = state.article;
    final targetUrl = url ?? article?.nextUrl;
    if (targetUrl == null) return;

    state = state.copyWith(isLoading: true);
    try {
      final repo = ref.read(articleRepositoryProvider);
      if (article != null) await repo.markArticleCompleted(article.id);
      final newArticle = await repo.fetchArticle(targetUrl);
      await ref.read(settingsRepositoryProvider).setLastArticleUrl(targetUrl);
      ref.read(recentArticlesProvider.notifier).load();
      await _switchToArticle(
        newArticle,
        resetProgress: true,
        showAutoNextSnackbar: true,
        forcePlay: true,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
      final msg = e.toString();
      final isNetworkError =
          msg.contains('SocketException') ||
          msg.contains('Failed host lookup') ||
          msg.contains('NetworkException') ||
          msg.contains('ClientException');
      if (isNetworkError) {
        _pendingAutoNextUrl = targetUrl;
        _backgroundRetryTimer?.cancel();
        _backgroundRetryTimer = Timer.periodic(
          const Duration(seconds: 15),
          (_) => _retryAutoNextInBackground(),
        );
      }
    }
  }

  Future<void> _retryAutoNextInBackground() async {
    if (_pendingAutoNextUrl == null) {
      _backgroundRetryTimer?.cancel();
      _backgroundRetryTimer = null;
      return;
    }
    final targetUrl = _pendingAutoNextUrl!;
    try {
      final repo = ref.read(articleRepositoryProvider);
      final newArticle = await repo.fetchArticle(targetUrl);
      _backgroundRetryTimer?.cancel();
      _backgroundRetryTimer = null;
      _pendingAutoNextUrl = null;
      await ref.read(settingsRepositoryProvider).setLastArticleUrl(targetUrl);
      ref.read(recentArticlesProvider.notifier).load();
      await _switchToArticle(
        newArticle,
        resetProgress: true,
        showAutoNextSnackbar: true,
        forcePlay: true,
      );
    } catch (_) {
      // Still offline — timer will fire again in 15 s.
    }
  }

  /// Replace the currently displayed article without pushing a new route.
  /// The widget detects the article ID change and resets its scroll / keys.
  Future<void> _switchToArticle(
    Article article, {
    bool resetProgress = false,
    bool showAutoNextSnackbar = false,
    bool forcePlay = false,
  }) async {
    _cancelAutoNextInternal();
    _autoPlayScheduled = false;

    // TTS hand-off for auto-next path.
    if (showAutoNextSnackbar) {
      ref
          .read(ttsProvider.notifier)
          .transitionToContent(
            article.paragraphs,
            language: article.language,
            articleTitle: article.title,
          );
    }

    state = ArticleReaderState(
      article: article,
      isBookmarked: article.isBookmarked,
      showTts: state.showTts,
      showAutoNextSnackbar: showAutoNextSnackbar,
      // Signal widget to scroll to top; will be overwritten if position
      // restore finds a saved position.
      savedScrollPosition: 0.0,
    );

    await ref.read(articleRepositoryProvider).markArticleRead(article.id);
    ref.read(recentArticlesProvider.notifier).load();

    final cacheService = ref.read(articleCacheServiceProvider);
    cacheService.resetDelaySchedule();
    _maybeStartCache(article);

    if (resetProgress) {
      _maybeAutoPlay(forcePlay: forcePlay);
    } else {
      await _restorePosition(article);
    }
  }

  Future<void> _restorePosition(Article article) async {
    final repo = ref.read(articleRepositoryProvider);
    final isResumable = await repo.isLastUncompletedRead(article.id);
    if (!isResumable) {
      _maybeAutoPlay();
      return;
    }
    final readingStateRepo = ref.read(readingStateRepositoryProvider);
    final saved = await readingStateRepo.getReadingState(article.id);
    if (saved != null) {
      state = state.copyWith(
        highlightedIndex: saved.lastReadIndex,
        savedWordOffset: saved.lastWordOffset,
        savedScrollPosition: saved.scrollPosition,
      );
      _maybeAutoPlay(startIndex: saved.lastReadIndex);
    } else {
      _maybeAutoPlay();
    }
  }

  void _maybeAutoPlay({int startIndex = 0, bool forcePlay = false}) {
    if (_autoPlayScheduled) return;
    final autoRead = ref.read(settingsProvider).valueOrNull?.autoRead ?? true;
    if (!autoRead && !forcePlay) return;
    _autoPlayScheduled = true;

    if (ref.read(ttsProvider).isActive) return;

    final article = state.article;
    if (article == null) return;

    ref
        .read(ttsProvider.notifier)
        .play(
          article.paragraphs,
          startIndex: startIndex,
          wordOffset: state.savedWordOffset,
          language: article.language,
          articleTitle: article.title,
        );
  }

  Future<void> _maybeStartCache(Article article) async {
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null || !settings.cachingEnabled) return;
    await ref.read(articleCacheServiceProvider).startFromArticle(article);
  }

  void _onDispose() {
    _saveTimer?.cancel();
    _backgroundRetryTimer?.cancel();
    // Best-effort save — ref is still valid inside onDispose.
    saveState(scrollFraction: 0);
  }
}
