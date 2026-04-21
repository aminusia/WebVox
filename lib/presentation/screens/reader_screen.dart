import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_reader/domain/entities/article.dart';
import 'package:web_reader/domain/entities/reading_state.dart';
import 'package:web_reader/domain/repositories/reading_state_repository.dart';
import 'package:web_reader/presentation/providers/providers.dart';
import 'package:web_reader/presentation/providers/tts_notifier.dart';
import 'package:web_reader/presentation/widgets/article_content_widget.dart';
import 'package:web_reader/presentation/widgets/tts_control_bar.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  final Article article;

  const ReaderScreen({super.key, required this.article});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  late final ScrollController _scroll;
  Timer? _saveTimer;
  Timer? _countdownTimer;

  int _highlightedIndex = 0;
  int _savedWordOffset = 0; // restored from DB; used as TTS start offset
  bool _showTts = true;
  bool _isLoading = false;
  bool _showScrollToTop = false;
  bool _autoPlayScheduled = false;
  int? _autoNextCountdown; // null = not counting, 5..1 = counting down
  bool _ttsWasActive = false; // tracks if TTS has been active this session
  String?
  _pendingAutoNextUrl; // URL to fetch; retried in background until success
  Timer?
  _backgroundRetryTimer; // periodically retries the auto-next fetch in background
  Article?
  _prefetchedArticle; // article fetched in background, waiting for foreground to navigate
  late bool _isBookmarked;

  // Cached values used when saving state during dispose (ref is invalid then).
  late ReadingStateRepository _readingStateRepo;
  TtsState? _lastTtsState;
  bool _disposing = false; // true once dispose() has been entered
  /// GlobalKeys for precise scrolling to paragraphs.
  late final List<GlobalKey> _paragraphKeys;
  Article get article => widget.article;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll = ScrollController();
    _readingStateRepo = ref.read(readingStateRepositoryProvider);
    _isBookmarked = article.isBookmarked;
    // Initialize GlobalKeys for each paragraph
    _paragraphKeys = List.generate(
      article.paragraphs.length,
      (_) => GlobalKey(),
    );
    _restorePosition();
  }

  Future<void> _restorePosition() async {
    final readingStateRepo = _readingStateRepo;
    final saved = await readingStateRepo.getReadingState(article.id);
    if (!mounted) return;
    if (saved != null) {
      setState(() {
        _highlightedIndex = saved.lastReadIndex;
        _savedWordOffset = saved.lastWordOffset;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && saved.scrollPosition > 0) {
          final max = _scroll.position.maxScrollExtent;
          _scroll.jumpTo(saved.scrollPosition * max);
        }
        _maybeAutoPlay(startIndex: saved.lastReadIndex);
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoPlay());
    }
  }

  void _maybeAutoPlay({int startIndex = 0}) {
    if (!mounted || _autoPlayScheduled) return;
    final autoRead = ref.read(settingsProvider).valueOrNull?.autoRead ?? true;
    if (autoRead) {
      _autoPlayScheduled = true;
      ref
          .read(ttsProvider.notifier)
          .play(
            article.paragraphs,
            startIndex: startIndex,
            language: article.language,
            articleTitle: article.title,
          );
    }
  }

  void _onScroll() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _saveState);

    // Check if we should show scroll-to-top FAB
    // Show when scrolled 1.5x screen height
    if (_scroll.hasClients) {
      final screenHeight = MediaQuery.of(context).size.height;
      final showThreshold = screenHeight * 1.5;
      final shouldShow = _scroll.offset > showThreshold;

      if (shouldShow != _showScrollToTop) {
        setState(() => _showScrollToTop = shouldShow);
      }
    }
  }

  void _scrollToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _navigateToUrl(String? url) async {
    if (url == null || url.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(articleRepositoryProvider);
      final newArticle = await repo.fetchArticle(url);
      if (!mounted) return;

      ref.read(ttsProvider.notifier).stop();
      await _saveState();
      await ref.read(settingsRepositoryProvider).setLastArticleUrl(url);
      ref.read(recentArticlesProvider.notifier).load();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ReaderScreen(article: newArticle)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
    }
  }

  Future<void> _refreshPage() async {
    setState(() => _isLoading = true);

    try {
      final repo = ref.read(articleRepositoryProvider);
      final newArticle = await repo.fetchArticle(article.url);
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ReaderScreen(article: newArticle)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to refresh: $e')));
    }
  }

  Future<void> _saveState() async {
    // Never call ref.read() once dispose() has started — the element may have
    // been deactivated already even though mounted is still true.
    final useRef = mounted && !_disposing;
    final ttsState = useRef ? ref.read(ttsProvider) : _lastTtsState;
    final repo =
        useRef ? ref.read(readingStateRepositoryProvider) : _readingStateRepo;
    double scrollFraction = 0;
    if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
      scrollFraction = _scroll.offset / _scroll.position.maxScrollExtent;
    }
    final rs = ReadingState(
      articleId: article.id,
      scrollPosition: scrollFraction,
      lastReadIndex:
          (ttsState?.isActive ?? false)
              ? ttsState!.currentIndex
              : _highlightedIndex,
      lastWordOffset:
          (ttsState?.isActive ?? false)
              ? ttsState!.wordStart.clamp(0, 9999)
              : _savedWordOffset,
    );
    await repo.saveReadingState(rs);
  }

  void _onParagraphChanged(int index) {
    setState(() {
      _highlightedIndex = index;
      _savedWordOffset = 0;
    });
    _scrollToParagraph(index);
  }

  void _scrollToParagraph(int index) {
    if (!_scroll.hasClients) return;
    final paragraphs = article.paragraphs;
    if (paragraphs.isEmpty || index < 0 || index >= paragraphs.length) return;

    final key = _paragraphKeys[index];
    if (key.currentContext == null) return;

    Scrollable.ensureVisible(
      key.currentContext!,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      alignment:
          0.3, // Position paragraph at 30% from top for better visibility
    );
  }

  /// Called when user taps a word.  Immediately highlights the paragraph,
  /// then starts TTS from that word after 2 seconds.
  void _onWordTapped(int paragraphIndex, int charOffset) {
    final notifier = ref.read(ttsProvider.notifier);

    // Cancel any pending scheduled play
    notifier.cancelScheduledPlay();

    // Stop current TTS if active
    if (ref.read(ttsProvider).isActive) {
      notifier.stop();
    }

    // Immediate visual feedback
    setState(() {
      _highlightedIndex = paragraphIndex;
      _savedWordOffset = charOffset;
    });
    _scrollToParagraph(paragraphIndex);

    // Schedule TTS start after 2s
    notifier.schedulePlayFromWord(
      paragraphs: article.paragraphs,
      paragraphIndex: paragraphIndex,
      charOffset: charOffset,
      language: article.language,
      articleTitle: article.title,
    );
  }

  /// Shows a dialog that lets the user edit the current URL and navigate there.
  Future<void> _showUrlEditor() async {
    final controller = TextEditingController(text: article.url);
    final newUrl = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Row(
              children: [
                const Expanded(child: Text('Open URL')),
                if (controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy URL',
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: controller.text.trim()),
                      );
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('URL copied')),
                      );
                    },
                  ),
                if (controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.share),
                    tooltip: 'Share URL',
                    onPressed: () {
                      final url = controller.text.trim();
                      Share.share(url);
                      Navigator.of(ctx).pop();
                    },
                  ),
              ],
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              decoration: const InputDecoration(
                hintText: 'https://…',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                child: const Text('Go'),
              ),
            ],
          ),
    );
    // Defer dispose until after the dialog close animation completes.
    // Disposing immediately causes "TextEditingController used after dispose"
    // because the animation system still references the controller.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());

    if (newUrl == null || newUrl.isEmpty || newUrl == article.url) return;
    if (!mounted) return;

    // Normalise URL
    var url = newUrl;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid URL')));
      return;
    }

    // Stop TTS and navigate away — home screen (or caller) will handle loading
    ref.read(ttsProvider.notifier).stop();
    await _saveState();

    if (!mounted) return;
    final repo = ref.read(articleRepositoryProvider);
    final loadingSnack = ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Loading…'),
        duration: Duration(seconds: 60),
      ),
    );
    try {
      final newArticle = await repo.fetchArticle(url);
      if (!mounted) return;
      await ref.read(settingsRepositoryProvider).setLastArticleUrl(url);
      ref.read(recentArticlesProvider.notifier).load();
      loadingSnack.close();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ReaderScreen(article: newArticle)),
      );
    } catch (e) {
      if (!mounted) return;
      loadingSnack.close();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
    }
  }

  void _startAutoNextCountdown() {
    if (!mounted) return;
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null || !settings.autoNext) return;
    if (article.nextUrl == null) return;

    setState(() {
      _autoNextCountdown = 5;
      _showScrollToTop = false;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final next = (_autoNextCountdown ?? 0) - 1;
      if (next <= 0) {
        t.cancel();
        setState(() => _autoNextCountdown = null);
        _navigateToUrlAutoNext();
      } else {
        setState(() => _autoNextCountdown = next);
      }
    });
  }

  void _cancelAutoNext() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (mounted) setState(() => _autoNextCountdown = null);
  }

  Future<void> _navigateToUrlAutoNext({String? url}) async {
    final targetUrl = url ?? article.nextUrl;
    if (targetUrl == null) return;
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(articleRepositoryProvider);
      final newArticle = await repo.fetchArticle(targetUrl);
      if (!mounted) return;

      // If app is still in the background, cache the article and wait for
      // the foreground — navigation requires an active UI context.
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final inForeground =
          lifecycle == null ||
          lifecycle == AppLifecycleState.resumed ||
          lifecycle == AppLifecycleState.inactive;
      if (!inForeground) {
        _prefetchedArticle = newArticle;
        _backgroundRetryTimer?.cancel();
        _backgroundRetryTimer = null;
        setState(() => _isLoading = false);
        return;
      }

      _navigateWithArticle(newArticle);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      // If the fetch failed, check whether it looks like a transient network
      // error (e.g. DNS unavailable right after screen turns off).
      final msg = e.toString();
      final isNetworkError =
          msg.contains('SocketException') ||
          msg.contains('Failed host lookup') ||
          msg.contains('NetworkException') ||
          msg.contains('ClientException');
      if (isNetworkError) {
        // Keep retrying in background every 15 s while the process is alive
        // (kept alive by the audio_service foreground service).
        _pendingAutoNextUrl = targetUrl;
        _backgroundRetryTimer?.cancel();
        _backgroundRetryTimer = Timer.periodic(
          const Duration(seconds: 15),
          (_) => _retryAutoNextInBackground(),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
      }
    }
  }

  Future<void> _retryAutoNextInBackground() async {
    if (_pendingAutoNextUrl == null || !mounted) {
      _backgroundRetryTimer?.cancel();
      _backgroundRetryTimer = null;
      return;
    }
    final targetUrl = _pendingAutoNextUrl!;
    try {
      final repo = ref.read(articleRepositoryProvider);
      final newArticle = await repo.fetchArticle(targetUrl);
      if (!mounted) return;
      // Success — cancel the retry timer.
      _backgroundRetryTimer?.cancel();
      _backgroundRetryTimer = null;
      _pendingAutoNextUrl = null;

      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final inForeground =
          lifecycle == null ||
          lifecycle == AppLifecycleState.resumed ||
          lifecycle == AppLifecycleState.inactive;
      if (inForeground) {
        _navigateWithArticle(newArticle);
      } else {
        // Keep the fetched article ready; navigate when app is foregrounded.
        _prefetchedArticle = newArticle;
      }
    } catch (_) {
      // Still failing — keep waiting, timer will fire again.
    }
  }

  void _navigateWithArticle(Article newArticle) {
    if (!mounted) return;
    ref.read(ttsProvider.notifier).stop();
    _saveState();
    ref.read(settingsRepositoryProvider).setLastArticleUrl(newArticle.url);
    ref.read(recentArticlesProvider.notifier).load();

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ReaderScreen(article: newArticle)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Automatically continued to next page'),
          duration: Duration(seconds: 3),
        ),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Cancel background retry — we're back in the foreground.
      _backgroundRetryTimer?.cancel();
      _backgroundRetryTimer = null;

      if (_prefetchedArticle != null) {
        // Article was fetched while in background; navigate now.
        final fetched = _prefetchedArticle!;
        _pendingAutoNextUrl = null;
        _prefetchedArticle = null;
        _navigateWithArticle(fetched);
      } else if (_pendingAutoNextUrl != null) {
        // Retry never succeeded; try immediately now that we're foreground.
        final url = _pendingAutoNextUrl!;
        _pendingAutoNextUrl = null;
        _navigateToUrlAutoNext(url: url);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposing = true;
    _saveTimer?.cancel();
    _countdownTimer?.cancel();
    _backgroundRetryTimer?.cancel();
    // Fire-and-forget save on dispose — uses cached values because ref is
    // no longer safe to use after the element was deactivated.
    _saveState();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ttsState = ref.watch(ttsProvider);
    _lastTtsState = ttsState; // keep cached for use in dispose
    final settingsAsync = ref.watch(settingsProvider);
    final fontSize = settingsAsync.valueOrNull?.fontSize ?? 18.0;
    final paragraphs = article.paragraphs;

    // Keep _highlightedIndex in sync with TTS paragraph changes
    ref.listen(ttsProvider, (prev, next) {
      if (next.isActive && next.currentIndex != _highlightedIndex) {
        _onParagraphChanged(next.currentIndex);
      }
      // Track if TTS has ever been active
      if (next.isActive) _ttsWasActive = true;
      // Detect natural completion (playing → idle = all paragraphs finished)
      if (_ttsWasActive &&
          prev != null &&
          prev.status != TtsStatus.idle &&
          next.status == TtsStatus.idle) {
        _ttsWasActive = false;
        _startAutoNextCountdown();
      }
    });

    return PopScope(
      onPopInvokedWithResult: (didPop, __) {
        if (didPop) {
          _cancelAutoNext();
          ref.read(ttsProvider.notifier).stop();
        }
        _saveState();
      },
      child: Scaffold(
        appBar: AppBar(
          // Tapping the title opens URL editor
          title: GestureDetector(
            onTap: _showUrlEditor,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    article.title,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          actions: [
            Consumer(
              builder:
                  (_, ref, __) => IconButton(
                    icon: Icon(
                      _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                      color: _isBookmarked ? Colors.amber : null,
                    ),
                    tooltip: _isBookmarked ? 'Remove bookmark' : 'Bookmark',
                    onPressed: () async {
                      setState(() => _isBookmarked = !_isBookmarked);
                      await ref
                          .read(articleRepositoryProvider)
                          .toggleBookmark(article.id);
                      ref.read(bookmarksProvider.notifier).load();
                    },
                  ),
            ),
            IconButton(
              icon: Icon(
                _showTts
                    ? Icons.record_voice_over
                    : Icons.record_voice_over_outlined,
              ),
              tooltip: 'Toggle TTS bar',
              onPressed: () => setState(() => _showTts = !_showTts),
            ),
          ],
          bottom:
              _isLoading
                  ? PreferredSize(
                    preferredSize: const Size.fromHeight(3),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  )
                  : null,
        ),
        body: Column(
          children: [
            // Navigation buttons (top) — removed from fixed position;
            // rendered inside the scroll view below.
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshPage,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollUpdateNotification) _onScroll();
                    return false;
                  },
                  child: Scrollbar(
                    controller: _scroll,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Navigation buttons (top) — scrolls with content
                          if (article.prevUrl != null ||
                              article.nextUrl != null ||
                              article.homeUrl != null) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: SizedBox(
                                width: double.infinity,
                                child: Wrap(
                                  spacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    if (article.prevUrl != null)
                                      ElevatedButton.icon(
                                        onPressed:
                                            _isLoading
                                                ? null
                                                : () => _navigateToUrl(
                                                  article.prevUrl,
                                                ),
                                        icon: const Icon(Icons.chevron_left),
                                        label: const Text('Previous'),
                                      ),
                                    if (article.homeUrl != null)
                                      ElevatedButton.icon(
                                        onPressed:
                                            _isLoading
                                                ? null
                                                : () => _navigateToUrl(
                                                  article.homeUrl,
                                                ),
                                        icon: const Icon(Icons.home),
                                        label: const Text('Home'),
                                      ),
                                    if (article.nextUrl != null)
                                      ElevatedButton.icon(
                                        onPressed:
                                            _isLoading
                                                ? null
                                                : () => _navigateToUrl(
                                                  article.nextUrl,
                                                ),
                                        icon: const Icon(Icons.chevron_right),
                                        label: const Text('Next'),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 32),
                          Text(
                            article.title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (article.author != null ||
                              article.estimatedReadTime > 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              [
                                if (article.author != null) article.author!,
                                '${article.estimatedReadTime} min read',
                              ].join(' · '),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 32),
                          ArticleContentWidget(
                            paragraphs: paragraphs,
                            fontSize: fontSize,
                            highlightedIndex:
                                ttsState.isActive
                                    ? ttsState.currentIndex
                                    : _highlightedIndex,
                            wordStart:
                                ttsState.isPlaying ? ttsState.wordStart : -1,
                            wordEnd: ttsState.isPlaying ? ttsState.wordEnd : -1,
                            onWordTap: _onWordTapped,
                            paragraphKeys: _paragraphKeys,
                          ),
                          const SizedBox(height: 32),
                          // Navigation buttons (bottom)
                          if (article.prevUrl != null ||
                              article.nextUrl != null ||
                              article.homeUrl != null)
                            Center(
                              child: Wrap(
                                spacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  if (article.prevUrl != null &&
                                      _autoNextCountdown == null)
                                    ElevatedButton.icon(
                                      onPressed:
                                          _isLoading
                                              ? null
                                              : () => _navigateToUrl(
                                                article.prevUrl,
                                              ),
                                      icon: const Icon(Icons.chevron_left),
                                      label: const Text('Previous'),
                                    ),
                                  if (article.homeUrl != null &&
                                      _autoNextCountdown == null)
                                    ElevatedButton.icon(
                                      onPressed:
                                          _isLoading
                                              ? null
                                              : () => _navigateToUrl(
                                                article.homeUrl,
                                              ),
                                      icon: const Icon(Icons.home),
                                      label: const Text('Home'),
                                    ),
                                  if (article.nextUrl != null)
                                    if (_autoNextCountdown != null)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          FilledButton.icon(
                                            onPressed:
                                                _isLoading
                                                    ? null
                                                    : () => _navigateToUrl(
                                                      article.nextUrl,
                                                    ),
                                            icon: const Icon(
                                              Icons.chevron_right,
                                            ),
                                            label: Text(
                                              'Next ($_autoNextCountdown)',
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          FilledButton.icon(
                                            onPressed:
                                                _isLoading
                                                    ? null
                                                    : () => _cancelAutoNext(),
                                            icon: const Icon(Icons.close),
                                            label: Text('Stop'),
                                          ),
                                        ],
                                      )
                                    else
                                      ElevatedButton.icon(
                                        onPressed:
                                            _isLoading
                                                ? null
                                                : () => _navigateToUrl(
                                                  article.nextUrl,
                                                ),
                                        icon: const Icon(Icons.chevron_right),
                                        label: const Text('Next'),
                                      ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_showTts)
              TtsControlBar(
                paragraphs: paragraphs,
                articleLanguage: article.language,
                articleTitle: article.title,
                startIndex: _highlightedIndex,
                startWordOffset: _savedWordOffset,
                onParagraphChanged: _onParagraphChanged,
              ),
          ],
        ),
        floatingActionButton:
            _showScrollToTop
                ? Padding(
                  padding: EdgeInsets.only(bottom: _showTts ? 50 : 0),
                  child: Opacity(
                    opacity: 0.6,
                    child: FloatingActionButton(
                      onPressed: _scrollToTop,
                      tooltip: 'Scroll to top',
                      child: const Icon(Icons.arrow_upward),
                    ),
                  ),
                )
                : null,
      ),
    );
  }
}
