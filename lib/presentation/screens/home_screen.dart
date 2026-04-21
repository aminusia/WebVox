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
                                      .deleteArticle(id);
                                  ref
                                      .read(recentArticlesProvider.notifier)
                                      .load();
                                },
                              ),
                ),
                // Bookmarks tab
                bookmarksAsync.when(
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
                                      .deleteArticle(id);
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

class _ArticleListWithShowMore extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final displayedArticles = articles.take(showCount).toList();
    final hasMore = articles.length > showCount;

    return ListView.builder(
      itemCount: displayedArticles.length + (hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        // Show more button at the end
        if (i == displayedArticles.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: ElevatedButton(
                onPressed: onShowMore,
                child: const Text('Show More'),
              ),
            ),
          );
        }

        final a = displayedArticles[i];
        return ListTile(
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
            onPressed: () => onDelete(a.id),
          ),
          onTap: () => onTap(a),
        );
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
