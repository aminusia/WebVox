import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_reader/domain/entities/article.dart';
import 'package:web_reader/domain/repositories/article_repository.dart';

/// Background service that proactively caches upcoming (next) articles
/// while the user is reading.
///
/// Caching strategy:
/// - Only caches "next" articles (prev links are not cached).
/// - Each fetch is delayed by a random 1–5 minutes (polite crawling).
/// - The queue is persisted in SharedPreferences so it survives app restarts.
/// - Incrementally extends the chain: when a fetched article has its own
///   next URL it is enqueued automatically.
class ArticleCacheService {
  static const _prefNextQueue = 'cache_next_queue';

  final ArticleRepository _repo;
  final Random _rng = Random();

  final List<String> _nextQueue = [];

  Timer? _timer;
  bool _paused = false;
  bool _started = false;

  /// How many fetches have been completed since the last page was opened.
  /// Used to implement the staged delay schedule:
  ///   0 → 5 s, 1 → 30 s, 2+ → random 1–5 min.
  int _fetchesSincePageOpen = 0;

  // ─── Logging ──────────────────────────────────────────────────────────────
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  /// Stream of human-readable log messages emitted during caching.
  Stream<String> get logStream => _logController.stream;

  void _log(String message) {
    final ts = DateTime.now().toLocal();
    final hms =
        '${ts.hour.toString().padLeft(2, '0')}:'
        '${ts.minute.toString().padLeft(2, '0')}:'
        '${ts.second.toString().padLeft(2, '0')}';
    _logController.add('[$hms] $message');
  }

  ArticleCacheService(this._repo);

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Seed the queue from a newly opened article and start processing.
  /// Also ensures the current article itself is persisted in the local cache.
  Future<void> startFromArticle(Article article) async {
    // Save the currently-read article if it hasn't been cached yet.
    if (!article.isCached) {
      try {
        await _repo.fetchArticle(article.url);
        _log('Saved current page to cache: "${article.title}"');
      } catch (e) {
        _log('Failed to save current page to cache: $e');
      }
    }

    await _loadQueue();
    await _seedFromArticle(article);
    await _saveQueue();
    _started = true;
    _paused = false;
    _log('Cache started. Next queue: ${_nextQueue.length}');
    _scheduleNext();
  }

  /// Resets the staged delay schedule back to the fast initial cadence
  /// (5 s → 30 s → 1–5 min). Call this when the reader navigates to a new page.
  void resetDelaySchedule() {
    _fetchesSincePageOpen = 0;
  }

  /// Pause processing (e.g. screen turned off). Queue is preserved.
  void pause() {
    _paused = true;
    _timer?.cancel();
    _timer = null;
    _log('Cache paused (screen off / app backgrounded).');
  }

  /// Resume processing (e.g. screen turned back on).
  void resume() {
    if (!_started || !_paused) return;
    _paused = false;
    _log('Cache resumed.');
    _scheduleNext();
  }

  /// Clear persisted queues and reset state.
  Future<void> clearQueue() async {
    _timer?.cancel();
    _timer = null;
    _nextQueue.clear();
    await _saveQueue();
    _log('Cache queue cleared.');
  }

  /// Stop and clear the service (e.g. app is shutting down).
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    _logController.close();
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  Future<void> _seedFromArticle(Article article) async {
    if (article.nextUrl != null && !await _isCachedOrQueued(article.nextUrl!)) {
      _nextQueue.add(article.nextUrl!);
    }
  }

  bool _isQueued(String url) => _nextQueue.contains(url);

  Future<bool> _isCachedOrQueued(String url) async {
    if (_isQueued(url)) return true;
    return await _repo.getCachedArticle(url) != null;
  }

  void _scheduleNext() {
    if (_paused) return;
    if (_nextQueue.isEmpty) return;

    // Staged delay schedule (resets each time a new page is opened):
    //   fetch #1 → 5 s
    //   fetch #2 → 30 s
    //   fetch #3+ → random 60–300 s (1–5 min)
    final int delaySeconds;
    final String delayLabel;
    if (_fetchesSincePageOpen == 0) {
      delaySeconds = 5;
      delayLabel = '5s';
    } else if (_fetchesSincePageOpen == 1) {
      delaySeconds = 30;
      delayLabel = '30s';
    } else {
      delaySeconds = 60 + _rng.nextInt(4 * 60); // 60..300 s
      delayLabel = '${(delaySeconds / 60).toStringAsFixed(1)}m';
    }

    _timer?.cancel();
    _timer = Timer(Duration(seconds: delaySeconds), _fetchNext);
    _log(
      'Next cache fetch scheduled in $delayLabel '
      '(${_nextQueue.length} queued).',
    );
  }

  Future<void> _fetchNext() async {
    if (_paused) return;

    // Loop: drain already-cached URLs immediately (no network, no delay)
    // until we find one that needs a real network fetch.
    while (true) {
      if (_paused) return;

      if (_nextQueue.isEmpty) return;

      final url = _nextQueue.removeAt(0);
      await _saveQueue();

      // If already in cache, extend the chain and immediately continue.
      final alreadyCached = await _repo.getCachedArticle(url);
      if (alreadyCached != null) {
        _log(
          'Already cached (next): "${alreadyCached.title}" — skipping fetch.',
        );
        if (alreadyCached.nextUrl != null &&
            !await _isCachedOrQueued(alreadyCached.nextUrl!)) {
          _nextQueue.add(alreadyCached.nextUrl!);
          _log('Enqueued next: ${alreadyCached.nextUrl}');
        }
        await _saveQueue();
        continue; // pick the next URL without waiting
      }

      // Not cached — fetch from network, then break to apply the delay.
      _log('Caching next: $url …');
      try {
        final article = await _repo.fetchArticle(url);
        _log('Cached next OK: "${article.title}"');
        // Incrementally extend the chain
        if (article.nextUrl != null &&
            !await _isCachedOrQueued(article.nextUrl!)) {
          _nextQueue.add(article.nextUrl!);
          _log('Enqueued next: ${article.nextUrl}');
        }
        _fetchesSincePageOpen++;
        await _saveQueue();
      } catch (e) {
        _log('Cache next FAILED ($url): $e — will retry.');
        // Re-enqueue at the front so it is retried next round.
        // Do NOT increment the counter so the retry keeps the same delay slot.
        _nextQueue.insert(0, url);
        await _saveQueue();
      }
      break; // after one network fetch, apply the normal polite delay
    }

    // Schedule the next fetch if the queue is still non-empty
    if (!_paused && _nextQueue.isNotEmpty) {
      _scheduleNext();
    }
  }

  // ─── Persistence ──────────────────────────────────────────────────────────

  Future<void> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final nextRaw = prefs.getString(_prefNextQueue);
    if (nextRaw != null) {
      final list = (jsonDecode(nextRaw) as List).cast<String>();
      for (final u in list) {
        if (!_nextQueue.contains(u)) _nextQueue.add(u);
      }
    }
  }

  Future<void> _saveQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefNextQueue, jsonEncode(_nextQueue));
  }
}
