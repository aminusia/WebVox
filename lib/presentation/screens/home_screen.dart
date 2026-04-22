import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_reader/domain/entities/article.dart';
import 'package:web_reader/presentation/providers/providers.dart';
import 'package:web_reader/presentation/screens/reader_screen.dart';
import 'package:web_reader/presentation/screens/settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  final _urlController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  late TabController _tabController;
  int _recentShowCount = 20;
  int _bookmarksShowCount = 20;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // After the first frame, check whether to resume last reading session.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeResumeLastArticle(),
    );
  }

  /// If the user left off in the middle of a page last session, reopen it
  /// without auto-playing TTS and show a 'Continue' snackbar.
  /// If the session was complete (scroll ≥ 95 %) or there is no saved state,
  /// stay on the home screen.
  Future<void> _maybeResumeLastArticle() async {
    if (!mounted) return;
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final lastUrl = await settingsRepo.getLastArticleUrl();
    if (lastUrl == null || lastUrl.isEmpty) return;

    final articleRepo = ref.read(articleRepositoryProvider);
    final cached = await articleRepo.getCachedArticle(lastUrl);
    if (cached == null || !mounted) return;

    final stateRepo = ref.read(readingStateRepositoryProvider);
    final rs = await stateRepo.getReadingState(cached.id);
    if (rs == null || !mounted) return;

    // Consider reading done if user reached the last 5 % of the page.
    if (rs.scrollPosition >= 0.95) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Continue where you left off'),
        duration: Duration(seconds: 2),
      ),
    );
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderScreen(article: cached)));
    ref.read(recentArticlesProvider.notifier).load();
    ref.read(bookmarksProvider.notifier).load();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String rawUrl) async {
    final url = _normaliseUrl(rawUrl.trim());
    if (url == null) {
      setState(() => _error = 'Please enter a valid URL.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repo = ref.read(articleRepositoryProvider);
      final article = await repo.fetchArticle(url);
      await ref.read(settingsRepositoryProvider).setLastArticleUrl(url);
      ref.read(recentArticlesProvider.notifier).load();

      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ReaderScreen(article: article)));
      // Refresh recent list after returning
      ref.read(recentArticlesProvider.notifier).load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load article.\n${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _normaliseUrl(String input) {
    if (input.isEmpty) return null;
    var url = input;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return null;
    return url;
  }

  void _openArticle(Article article) async {
    await ref.read(settingsRepositoryProvider).setLastArticleUrl(article.url);
    if (!mounted) return;

    // Check if article has reading state (i.e., was previously being read)
    final readingStateRepo = ref.read(readingStateRepositoryProvider);
    final readingState = await readingStateRepo.getReadingState(article.id);

    if (readingState != null && mounted) {
      // Show "Continue where you left off" notification
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Continue where you left off'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderScreen(article: article)));
    ref.read(recentArticlesProvider.notifier).load();
    ref.read(bookmarksProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final recentAsync = ref.watch(recentArticlesProvider);
    final bookmarksAsync = ref.watch(bookmarksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebReader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
          ),
        ],
      ),
      body: Column(
        children: [
          _UrlInputBar(
            controller: _urlController,
            isLoading: _isLoading,
            error: _error,
            onSubmit: _openUrl,
          ),
          TabBar(
            controller: _tabController,
            tabs: const [Tab(text: 'Recent'), Tab(text: 'Bookmarks')],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Recent tab
                recentAsync.when(
                  skipLoadingOnReload: true,
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                  data:
                      (articles) =>
                          articles.isEmpty
                              ? const _EmptyState()
                              : _ArticleListWithShowMore(
                                articles: articles,
                                showCount: _recentShowCount,
                                onShowMore:
                                    () =>
                                        setState(() => _recentShowCount += 20),
                                onTap: _openArticle,
                                onDelete: (id) async {
                                  await ref
                                      .read(articleRepositoryProvider)
                                      .removeFromHistory(id);
                                  ref
                                      .read(recentArticlesProvider.notifier)
                                      .load();
                                },
                              ),
                ),
                // Bookmarks tab
                bookmarksAsync.when(
                  skipLoadingOnReload: true,
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                  data:
                      (articles) =>
                          articles.isEmpty
                              ? const Center(child: Text('No bookmarks yet'))
                              : _ArticleListWithShowMore(
                                articles: articles,
                                showCount: _bookmarksShowCount,
                                onShowMore:
                                    () => setState(
                                      () => _bookmarksShowCount += 20,
                                    ),
                                onTap: _openArticle,
                                onDelete: (id) async {
                                  await ref
                                      .read(articleRepositoryProvider)
                                      .toggleBookmark(id);
                                  ref.read(bookmarksProvider.notifier).load();
                                },
                              ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UrlInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final String? error;
  final void Function(String) onSubmit;

  const _UrlInputBar({
    required this.controller,
    required this.isLoading,
    required this.error,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: 'Paste a URL to read…',
                    prefixIcon: Icon(Icons.link),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: isLoading ? null : onSubmit,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: isLoading ? null : () => onSubmit(controller.text),
                child:
                    isLoading
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Text('Open'),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(
              error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArticleListWithShowMore extends StatefulWidget {
  final List<Article> articles;
  final int showCount;
  final VoidCallback onShowMore;
  final void Function(Article) onTap;
  final void Function(String) onDelete;

  const _ArticleListWithShowMore({
    required this.articles,
    required this.showCount,
    required this.onShowMore,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_ArticleListWithShowMore> createState() =>
      _ArticleListWithShowMoreState();
}

class _ArticleListWithShowMoreState extends State<_ArticleListWithShowMore> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late List<Article> _items;
  final Set<String> _removingIds = {};

  @override
  void initState() {
    super.initState();
    _items = widget.articles.take(widget.showCount).toList();
  }

  @override
  void didUpdateWidget(_ArticleListWithShowMore old) {
    super.didUpdateWidget(old);
    // When the provider pushes a new list (after delete/reload), sync _items.
    // We already animated the removed tile out; just refresh the rest.
    final next = widget.articles.take(widget.showCount).toList();
    // Insert any newly added items at the top.
    for (int i = 0; i < next.length; i++) {
      if (i >= _items.length || _items[i].id != next[i].id) {
        // Skip rebuild if the only difference is an item currently animating out.
        if (_removingIds.isNotEmpty) return;
        // Rebuild fully on structural changes other than a single removal
        // (e.g. "show more", refresh) — no animation needed for additions.
        setState(() => _items = next);
        return;
      }
    }
    // Trim any items that are in _items but not in next.
    if (_items.length > next.length && _removingIds.isEmpty) {
      setState(() => _items = next);
    }
  }

  void _removeItem(int index) {
    final removed = _items[index];
    _removingIds.add(removed.id);
    _items.removeAt(index);
    _listKey.currentState?.removeItem(
      index,
      (context, animation) => _buildTile(context, removed, animation),
      duration: const Duration(milliseconds: 300),
    );
    Future.delayed(const Duration(milliseconds: 300), () {
      _removingIds.remove(removed.id);
    });
    widget.onDelete(removed.id);
  }

  Widget _buildTile(
    BuildContext context,
    Article a,
    Animation<double> animation,
  ) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: ListTile(
          leading:
              a.isBookmarked
                  ? const Icon(Icons.bookmark, color: Colors.amber)
                  : const Icon(Icons.article_outlined),
          title: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${a.estimatedReadTime} min read · ${a.language}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              final i = _items.indexOf(a);
              if (i >= 0) _removeItem(i);
            },
          ),
          onTap: () => widget.onTap(a),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMore = widget.articles.length > widget.showCount;

    return AnimatedList(
      key: _listKey,
      initialItemCount: _items.length + (hasMore ? 1 : 0),
      itemBuilder: (context, i, animation) {
        if (i == _items.length) {
          // "Show More" button
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: ElevatedButton(
                onPressed: widget.onShowMore,
                child: const Text('Show More'),
              ),
            ),
          );
        }
        return _buildTile(context, _items[i], animation);
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 12),
            Text(
              'Paste a URL above to start reading',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
