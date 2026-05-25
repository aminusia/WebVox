import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webvox/core/theme/app_theme.dart';
import 'package:webvox/domain/entities/article.dart';
import 'package:webvox/domain/entities/reading_state.dart';
import 'package:webvox/domain/repositories/reading_state_repository.dart';
import 'package:webvox/presentation/providers/article_reader_notifier.dart';
import 'package:webvox/presentation/providers/providers.dart';
import 'package:webvox/presentation/providers/tts_notifier.dart';
import 'package:webvox/presentation/widgets/article_content_widget.dart';
import 'package:webvox/presentation/widgets/tts_control_bar.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  final Article article;

  /// When true the saved reading position is ignored and reading starts
  /// from the very beginning (used when navigating to prev/next pages).
  final bool resetProgress;

  const ReaderScreen({
    super.key,
    required this.article,
    this.resetProgress = false,
  });

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  late final ScrollController _scroll;

  /// Paragraph GlobalKeys — recreated whenever the article changes.
  late List<GlobalKey> _paragraphKeys;

  /// Article ID currently reflected by [_paragraphKeys]; used to detect change.
  String? _keysArticleId;

  /// Last scroll fraction (0–1); updated on every scroll, used for dispose save.
  double _scrollFraction = 0;

  /// Cached references used in [_bestEffortSaveOnDispose] where ref is unsafe.
  late ReadingStateRepository _readingStateRepoCache;
  TtsState? _lastTtsState;
  ArticleReaderState? _lastReaderState;

  /// Key to access [ArticleContentWidgetState.ensureWordVisible].
  final _contentKey = GlobalKey<ArticleContentWidgetState>();

  // ── Paragraph-tap overlay ─────────────────────────────────────────────────
  int? _overlayParagraphIndex;
  OverlayEntry? _playOverlayEntry;
  GlobalKey<_PlayHereOverlayState>? _playOverlayKey;

  // ── Init / Dispose ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll = ScrollController();
    _readingStateRepoCache = ref.read(readingStateRepositoryProvider);

    final article = widget.article;
    _paragraphKeys = List.generate(
      article.paragraphs.length,
      (_) => GlobalKey(),
    );
    _keysArticleId = article.id;

    // Defer to post-frame: modifying provider state during initState (which runs
    // inside the widget-tree build pass) throws a Riverpod assertion error.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(articleReaderProvider.notifier)
          .initWithArticle(article, resetProgress: widget.resetProgress);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bestEffortSaveOnDispose();
    _playOverlayEntry?.remove();
    _playOverlayEntry = null;
    _scroll.dispose();
    super.dispose();
  }

  /// Save reading state using only cached values because ref.read() is unsafe
  /// once the element is being torn down.
  void _bestEffortSaveOnDispose() {
    final readerState = _lastReaderState;
    if (readerState == null) return;
    final article = readerState.article;
    if (article == null) return;
    final ttsState = _lastTtsState;
    _readingStateRepoCache.saveReadingState(
      ReadingState(
        articleId: article.id,
        scrollPosition: _scrollFraction,
        lastReadIndex:
            (ttsState?.isActive ?? false)
                ? ttsState!.currentIndex
                : readerState.highlightedIndex,
        lastWordOffset:
            (ttsState?.isActive ?? false)
                ? ttsState!.wordStart.clamp(0, 9999)
                : readerState.savedWordOffset,
      ),
    );
  }

  // ── App lifecycle (delegated to notifier) ───────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final notifier = ref.read(articleReaderProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      notifier.onAppResumed();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      final cacheInBackground =
          ref.read(settingsProvider).valueOrNull?.cacheInBackground ?? false;
      notifier.onAppPaused(cacheInBackground: cacheInBackground);
    }
  }

  // ── Scroll helpers ──────────────────────────────────────────────────────────

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
      _scrollFraction = _scroll.offset / _scroll.position.maxScrollExtent;
    }
    ref
        .read(articleReaderProvider.notifier)
        .saveState(scrollFraction: _scrollFraction);

    if (_scroll.hasClients) {
      final screenHeight = MediaQuery.of(context).size.height;
      ref
          .read(articleReaderProvider.notifier)
          .setScrollTopVisibility(_scroll.offset > screenHeight * 1.5);
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

  void _scrollToParagraph(int index) {
    if (!_scroll.hasClients || index < 0 || index >= _paragraphKeys.length) {
      return;
    }
    final key = _paragraphKeys[index];
    if (key.currentContext == null) return;
    Scrollable.ensureVisible(
      key.currentContext!,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      alignment: 0.3,
    );
  }

  // ── User interactions ───────────────────────────────────────────────────────

  void _onParagraphTapped(int paragraphIndex) {
    if (_playOverlayEntry != null) {
      if (_overlayParagraphIndex == paragraphIndex) {
        // Same paragraph tapped again — dismiss overlay.
        _dismissPlayOverlay();
        return;
      }
      // Different paragraph — remove current overlay immediately, show new one.
      _playOverlayEntry!.remove();
      _playOverlayEntry = null;
      _overlayParagraphIndex = null;
      _playOverlayKey = null;
    }
    _showPlayOverlay(paragraphIndex);
  }

  void _showPlayOverlay(int paragraphIndex) {
    if (paragraphIndex < 0 || paragraphIndex >= _paragraphKeys.length) return;
    final key = _paragraphKeys[paragraphIndex];
    if (key.currentContext == null) return;
    final renderBox = key.currentContext!.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final width = renderBox.size.width;

    _overlayParagraphIndex = paragraphIndex;
    _playOverlayKey = GlobalKey<_PlayHereOverlayState>();

    _playOverlayEntry = OverlayEntry(
      builder:
          (_) => _PlayHereOverlay(
            key: _playOverlayKey,
            anchorOffset: offset,
            anchorWidth: width,
            onDismissed: () {
              _playOverlayEntry?.remove();
              _playOverlayEntry = null;
              _overlayParagraphIndex = null;
              _playOverlayKey = null;
            },
            onPlay: () => _executePlayFromParagraph(paragraphIndex),
          ),
    );
    Overlay.of(context).insert(_playOverlayEntry!);
  }

  void _dismissPlayOverlay() {
    _playOverlayKey?.currentState?.animateOut();
  }

  void _executePlayFromParagraph(int paragraphIndex) {
    final ttsNotifier = ref.read(ttsProvider.notifier);
    ttsNotifier.cancelScheduledPlay();
    if (ref.read(ttsProvider).isActive) ttsNotifier.stop();

    ref
        .read(articleReaderProvider.notifier)
        .setHighlightedIndex(paragraphIndex);
    _scrollToParagraph(paragraphIndex);

    final article = ref.read(articleReaderProvider).article;
    if (article == null) return;
    ttsNotifier.schedulePlayFromWord(
      paragraphs: article.paragraphs,
      paragraphIndex: paragraphIndex,
      charOffset: 0,
      language: article.language,
      articleTitle: article.title,
    );
  }

  Future<void> _navigateToUrl(
    String? url, {
    bool resetProgress = false,
    bool markCurrentCompleted = false,
  }) async {
    if (url == null || url.isEmpty) return;
    try {
      await ref
          .read(articleReaderProvider.notifier)
          .loadUrl(
            url,
            resetProgress: resetProgress,
            markCurrentCompleted: markCurrentCompleted,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
    }
  }

  Future<void> _refreshPage() async {
    try {
      await ref.read(articleReaderProvider.notifier).refreshCurrentArticle();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to refresh: $e')));
    }
  }

  Future<void> _showUrlEditor(Article article) async {
    final controller = TextEditingController(text: article.url);
    final newUrl = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Open URL',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primaryColor,
                    ),
                  ),
                ),
                if (controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.copy, color: AppColors.onBar),
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
                    icon: const Icon(Icons.share, color: AppColors.onBar),
                    tooltip: 'Share URL',
                    onPressed: () {
                      Share.share(controller.text.trim());
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(30)),
                ),
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
    // Defer dispose until after dialog close animation to avoid
    // "TextEditingController used after dispose" errors.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());

    if (newUrl == null || newUrl.isEmpty || newUrl == article.url) return;
    if (!mounted) return;

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

    final loadingSnack = ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Loading…'),
        duration: Duration(seconds: 60),
      ),
    );
    try {
      await ref.read(articleReaderProvider.notifier).loadUrl(url);
      loadingSnack.close();
    } catch (e) {
      if (!mounted) return;
      loadingSnack.close();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load: $e')));
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final readerState = ref.watch(articleReaderProvider);
    final ttsState = ref.watch(ttsProvider);

    // Cache for dispose-time best-effort save.
    _lastReaderState = readerState;
    _lastTtsState = ttsState;

    // ── React to article changes: regenerate paragraph keys ──────────────────
    ref.listen(articleReaderProvider.select((s) => s.article?.id), (
      prevId,
      nextId,
    ) {
      if (nextId == null || nextId == _keysArticleId) return;
      final article = ref.read(articleReaderProvider).article!;
      setState(() {
        _paragraphKeys = List.generate(
          article.paragraphs.length,
          (_) => GlobalKey(),
        );
        _keysArticleId = nextId;
      });
    });

    // ── Restore scroll position when notifier signals it ─────────────────────
    ref.listen(articleReaderProvider.select((s) => s.savedScrollPosition), (
      _,
      next,
    ) {
      if (next == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          final max = _scroll.position.maxScrollExtent;
          _scroll.jumpTo(next > 0 && max > 0 ? next * max : 0);
        }
        ref.read(articleReaderProvider.notifier).clearSavedScrollPosition();
      });
    });

    // ── Scroll to paragraph when highlighted index changes ───────────────────
    // When TTS is playing, skip paragraph-level scroll — the word-level
    // ensureWordVisible listener fires immediately after and scrolls directly
    // to the highlighted word, avoiding a double-animation (scroll up to
    // paragraph top, then scroll down to word).
    ref.listen(articleReaderProvider.select((s) => s.highlightedIndex), (
      prev,
      next,
    ) {
      if (prev != null && prev != next && !ref.read(ttsProvider).isPlaying) {
        _scrollToParagraph(next);
      }
    });

    // ── Ensure the active TTS word stays inside the viewport ─────────────────
    // Fires only when playing; selects -1 when paused to suppress no-op calls.
    ref.listen(ttsProvider.select((s) => s.isPlaying ? s.wordStart : -1), (
      _,
      next,
    ) {
      if (next >= 0) _contentKey.currentState?.ensureWordVisible();
    });

    // ── Show "auto-continued" snackbar (one-shot) ────────────────────────────
    // ref.listen(articleReaderProvider.select((s) => s.showAutoNextSnackbar), (
    //   _,
    //   show,
    // ) {
    //   if (!show || _isInBackground) return;
    //   ref.read(articleReaderProvider.notifier).clearAutoNextSnackbar();
    //   WidgetsBinding.instance.addPostFrameCallback((_) {
    //     if (!mounted) return;
    //     ScaffoldMessenger.of(context).showSnackBar(
    //       const SnackBar(
    //         content: Text('Automatically continued to next page'),
    //         duration: Duration(seconds: 3),
    //       ),
    //     );
    //   });
    // });

    final article = readerState.article;
    if (article == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final settingsAsync = ref.watch(settingsProvider);
    final settingsVal = settingsAsync.valueOrNull;
    final fontSize = settingsVal?.fontSize ?? 18.0;
    final paragraphHighlightStyle =
        settingsVal != null
            ? HighlightStyle.fromSettings(
              colorValue: settingsVal.paragraphHighlightColor,
              backgroundValue: settingsVal.paragraphHighlightBackground,
              decoration: settingsVal.paragraphHighlightDecoration,
            )
            : HighlightStyle.defaultParagraph;
    final wordHighlightStyle =
        settingsVal != null
            ? HighlightStyle.fromSettings(
              colorValue: settingsVal.wordHighlightColor,
              backgroundValue: settingsVal.wordHighlightBackground,
              decoration: settingsVal.wordHighlightDecoration,
            )
            : HighlightStyle.defaultWord;

    final paragraphs = article.paragraphs;

    // If the paragraph count changed (e.g. article reloaded in place), grow
    // the key list so it always matches paragraphs.length.
    if (_paragraphKeys.length != paragraphs.length) {
      _paragraphKeys = List.generate(paragraphs.length, (_) => GlobalKey());
    }

    final isLoading = readerState.isLoading;
    final isBookmarked = readerState.isBookmarked;
    final showTts = readerState.showTts;
    final showScrollToTop = readerState.showScrollToTop;
    final highlightedIndex = readerState.highlightedIndex;
    final savedWordOffset = readerState.savedWordOffset;

    return PopScope(
      onPopInvokedWithResult: (didPop, __) {
        if (didPop) {
          ref.read(articleReaderProvider.notifier).cancelAutoNext();
        }
        ref
            .read(articleReaderProvider.notifier)
            .saveState(scrollFraction: _scrollFraction);
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: BackButton(color: AppColors.onBar.withAlpha(220)),
          title: GestureDetector(
            onTap: () => _showUrlEditor(article),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    article.title,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color:
                          article.isCached
                              ? AppColors.titleColor
                              : AppColors.bodyColor,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.edit_outlined, size: 20, color: AppColors.onBar),
                const SizedBox(width: 8),
              ],
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(
                isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                color: isBookmarked ? AppColors.titleColor : AppColors.onBar,
              ),
              tooltip: isBookmarked ? 'Remove bookmark' : 'Bookmark',
              onPressed:
                  () =>
                      ref.read(articleReaderProvider.notifier).toggleBookmark(),
            ),
            IconButton(
              icon: Icon(
                showTts
                    ? Icons.record_voice_over
                    : Icons.record_voice_over_outlined,
              ),
              tooltip: 'Toggle TTS bar',
              onPressed:
                  () => ref
                      .read(articleReaderProvider.notifier)
                      .setShowTts(!showTts),
            ),
          ],
          bottom:
              isLoading
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
                          // Navigation buttons (top)
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
                                      ElevatedButton(
                                        onPressed:
                                            isLoading
                                                ? null
                                                : () => _navigateToUrl(
                                                  article.prevUrl,
                                                  resetProgress: true,
                                                ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.chevron_left, size: 18),
                                            SizedBox(width: 8),
                                            Text('Prev'),
                                          ],
                                        ),
                                      ),
                                    if (article.homeUrl != null)
                                      ElevatedButton.icon(
                                        onPressed:
                                            isLoading
                                                ? null
                                                : () => _navigateToUrl(
                                                  article.homeUrl,
                                                ),
                                        icon: const Icon(Icons.home),
                                        label: const Text('Home'),
                                      ),
                                    if (article.nextUrl != null)
                                      ElevatedButton(
                                        onPressed:
                                            isLoading
                                                ? null
                                                : () => _navigateToUrl(
                                                  article.nextUrl,
                                                  resetProgress: true,
                                                  markCurrentCompleted: true,
                                                ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text('Next'),
                                            SizedBox(width: 8),
                                            Icon(Icons.chevron_right, size: 18),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 32),
                          Text(
                            article.title,
                            style: Theme.of(
                              context,
                            ).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              height: 1.3,
                            ),
                          ),
                          if (article.author != null ||
                              article.estimatedReadTime > 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              [
                                if (article.author != null) article.author!,
                                '${article.estimatedReadTime} min read',
                              ].join(' · '),
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                color: AppColors.bodyColor.withAlpha(140),
                              ),
                            ),
                          ],
                          const SizedBox(height: 32),
                          ArticleContentWidget(
                            key: _contentKey,
                            paragraphs: paragraphs,
                            fontSize: fontSize,
                            highlightedIndex:
                                ttsState.isActive
                                    ? ttsState.currentIndex
                                    : highlightedIndex,
                            wordStart:
                                ttsState.isPlaying ? ttsState.wordStart : -1,
                            wordEnd: ttsState.isPlaying ? ttsState.wordEnd : -1,
                            onTap: _onParagraphTapped,
                            paragraphKeys: _paragraphKeys,
                            paragraphHighlightStyle: paragraphHighlightStyle,
                            wordHighlightStyle: wordHighlightStyle,
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
                                  if (article.prevUrl != null)
                                    ElevatedButton(
                                      onPressed:
                                          isLoading
                                              ? null
                                              : () => _navigateToUrl(
                                                article.prevUrl,
                                                resetProgress: true,
                                              ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.chevron_left, size: 18),
                                          SizedBox(width: 8),
                                          Text('Prev'),
                                        ],
                                      ),
                                    ),
                                  if (article.homeUrl != null)
                                    ElevatedButton.icon(
                                      onPressed:
                                          isLoading
                                              ? null
                                              : () => _navigateToUrl(
                                                article.homeUrl,
                                              ),
                                      icon: const Icon(Icons.home),
                                      label: const Text('Home'),
                                    ),
                                  if (article.nextUrl != null)
                                    ElevatedButton(
                                      onPressed:
                                          isLoading
                                              ? null
                                              : () => _navigateToUrl(
                                                article.nextUrl,
                                                resetProgress: true,
                                                markCurrentCompleted: true,
                                              ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('Next'),
                                          SizedBox(width: 8),
                                          Icon(Icons.chevron_right, size: 18),
                                        ],
                                      ),
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
            if (showTts)
              TtsControlBar(
                paragraphs: paragraphs,
                articleLanguage: article.language,
                articleTitle: article.title,
                startIndex: highlightedIndex,
                startWordOffset: savedWordOffset,
                onParagraphChanged:
                    ref
                        .read(articleReaderProvider.notifier)
                        .setHighlightedIndex,
              ),
          ],
        ),
        floatingActionButton:
            showScrollToTop
                ? Padding(
                  padding: EdgeInsets.only(bottom: showTts ? 50 : 0),
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

// ── "Read here" overlay ───────────────────────────────────────────────────────

class _PlayHereOverlay extends StatefulWidget {
  final Offset anchorOffset;
  final double anchorWidth;
  final VoidCallback onDismissed;
  final VoidCallback onPlay;

  const _PlayHereOverlay({
    super.key,
    required this.anchorOffset,
    required this.anchorWidth,
    required this.onDismissed,
    required this.onPlay,
  });

  @override
  State<_PlayHereOverlay> createState() => _PlayHereOverlayState();
}

class _PlayHereOverlayState extends State<_PlayHereOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  static const _buttonHeight = 44.0;
  static const _gap = 8.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      reverseDuration: const Duration(milliseconds: 180),
    );
    // Bouncy scale — elasticOut gives the spring effect on entry.
    _scale = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    // Fade resolves quickly so the button "pops in" then bounces.
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.35, curve: Curves.easeIn),
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void animateOut() {
    if (!mounted) return;
    _controller.reverse().then((_) {
      if (mounted) widget.onDismissed();
    });
  }

  void _handlePlay() {
    widget.onPlay(); // schedule TTS immediately
    animateOut(); // then animate the overlay away
  }

  @override
  Widget build(BuildContext context) {
    // Clamp so the button never appears off the top of the screen.
    final rawTop = widget.anchorOffset.dy - _buttonHeight - _gap;
    final top = rawTop.clamp(
      MediaQuery.of(context).padding.top + 4.0,
      double.infinity,
    );

    return Stack(
      children: [
        // Full-screen invisible barrier — captures taps outside the button.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: animateOut,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        // Animated "Read here" button, anchored above the paragraph.
        Positioned(
          left: widget.anchorOffset.dx,
          top: top,
          width: widget.anchorWidth,
          child: AnimatedBuilder(
            animation: _controller,
            builder:
                (_, child) => Opacity(
                  opacity: _opacity.value,
                  child: ScaleTransition(
                    scale: _scale,
                    alignment: Alignment.bottomCenter,
                    child: child,
                  ),
                ),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: ElevatedButton.icon(
                  onPressed: _handlePlay,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Read here'),
                  style: ElevatedButton.styleFrom(
                    elevation: 8,
                    shadowColor: Colors.black45,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
