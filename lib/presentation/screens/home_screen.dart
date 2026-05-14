import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webreader/core/theme/app_theme.dart';
import 'package:webreader/domain/entities/article.dart';
import 'package:webreader/domain/entities/settings.dart';
import 'package:webreader/domain/entities/title_group.dart';
import 'package:webreader/presentation/providers/providers.dart';
import 'package:webreader/presentation/screens/reader_screen.dart';
import 'package:webreader/presentation/screens/settings_screen.dart';

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

  // The titleId of the currently-expanded accordion row (null = all collapsed).
  String? _expandedRecentTitleId;
  String? _expandedBookmarkTitleId;

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

    // ScaffoldMessenger.of(context).showSnackBar(
    //   const SnackBar(
    //     content: Text('Continue where you left off'),
    //     duration: Duration(seconds: 2),
    //   ),
    // );
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderScreen(article: cached)));
    _refreshAll();
  }

  void _refreshAll() {
    ref.read(recentGroupedProvider.notifier).load();
    ref.read(bookmarksGroupedProvider.notifier).load();
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

      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ReaderScreen(article: article)));
      _refreshAll();
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

  Future<void> _openArticle(Article article) async {
    await ref.read(settingsRepositoryProvider).setLastArticleUrl(article.url);
    if (!mounted) return;

    // final readingStateRepo = ref.read(readingStateRepositoryProvider);
    // final readingState = await readingStateRepo.getReadingState(article.id);

    // if (readingState != null && mounted) {
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     const SnackBar(
    //       content: Text('Continue where you left off'),
    //       duration: Duration(seconds: 2),
    //     ),
    //   );
    // }

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderScreen(article: article)));
    _refreshAll();
  }

  Future<void> _showRenameTitleDialog(
    TitleGroup group, {
    required bool isBookmarks,
  }) async {
    final ctrl = TextEditingController(text: group.titleName);
    final newName = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text(
              'Rename title',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppColors.primaryColor,
              ),
            ),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Title name'),
              onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
    );
    // Defer dispose until after the dialog close animation finishes (~300 ms).
    // addPostFrameCallback only waits one frame, which is not enough for the
    // pop transition; using a fixed delay avoids "used after dispose" errors.
    Future.delayed(const Duration(milliseconds: 400), ctrl.dispose);
    if (newName == null || newName.isEmpty) return;
    if (isBookmarks) {
      await ref
          .read(bookmarksGroupedProvider.notifier)
          .renameTitle(group.titleId, newName);
    } else {
      await ref
          .read(recentGroupedProvider.notifier)
          .renameTitle(group.titleId, newName);
    }
  }

  Future<void> _confirmDeleteTitle(
    TitleGroup group, {
    required bool isBookmarks,
  }) async {
    final label = isBookmarks ? 'bookmarks' : 'reading history';
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Remove title?'),
            content: Text('Remove "${group.titleName}" from $label?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Remove'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    if (isBookmarks) {
      await ref
          .read(bookmarksGroupedProvider.notifier)
          .removeTitle(group.titleId);
    } else {
      await ref.read(recentGroupedProvider.notifier).removeTitle(group.titleId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recentAsync = ref.watch(recentGroupedProvider);
    final bookmarksAsync = ref.watch(bookmarksGroupedProvider);

    // Show the Get Started page until the user has opened at least one article.
    if (recentAsync.hasValue && (recentAsync.value?.isEmpty ?? true)) {
      return _GetStartedPage(
        controller: _urlController,
        isLoading: _isLoading,
        error: _error,
        onSubmit: _openUrl,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/appicon3.png', width: 24, height: 24),
            const SizedBox(width: 8),
            const Text(
              'WebReader',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppColors.titleColor,
              ),
            ),
          ],
        ),
        actions: [
          _ThemeToggleButton(),
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
                      (groups) =>
                          groups.isEmpty
                              ? const _EmptyState()
                              : _GroupedList(
                                groups: groups,
                                expandedTitleId: _expandedRecentTitleId,
                                onToggle:
                                    (id) => setState(
                                      () =>
                                          _expandedRecentTitleId =
                                              _expandedRecentTitleId == id
                                                  ? null
                                                  : id,
                                    ),
                                onArticleTap: _openArticle,
                                onRenameTitle:
                                    (g) => _showRenameTitleDialog(
                                      g,
                                      isBookmarks: false,
                                    ),
                                onDeleteTitle:
                                    (g) => _confirmDeleteTitle(
                                      g,
                                      isBookmarks: false,
                                    ),
                              ),
                ),
                // Bookmarks tab
                bookmarksAsync.when(
                  skipLoadingOnReload: true,
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                  data:
                      (groups) =>
                          groups.isEmpty
                              ? const Center(child: Text('No bookmarks yet'))
                              : _GroupedList(
                                groups: groups,
                                expandedTitleId: _expandedBookmarkTitleId,
                                onToggle:
                                    (id) => setState(
                                      () =>
                                          _expandedBookmarkTitleId =
                                              _expandedBookmarkTitleId == id
                                                  ? null
                                                  : id,
                                    ),
                                onArticleTap: _openArticle,
                                onRenameTitle:
                                    (g) => _showRenameTitleDialog(
                                      g,
                                      isBookmarks: true,
                                    ),
                                onDeleteTitle:
                                    (g) => _confirmDeleteTitle(
                                      g,
                                      isBookmarks: true,
                                    ),
                                onDeleteArticle:
                                    (a) => ref
                                        .read(bookmarksGroupedProvider.notifier)
                                        .removeArticle(a.id),
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

// ─── URL input bar ──────────────────────────────────────────────────────────

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
          Stack(
            alignment: Alignment.center,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'Paste new URL to read…',
                  prefixIcon: const Icon(Icons.link),
                  // Reserve space so text doesn't slide under the button.
                  suffixIcon: const SizedBox(width: 88),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(30)),
                  ),
                  isDense: true,
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: isLoading ? null : onSubmit,
              ),
              Positioned(
                right: 6,
                child: FilledButton(
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

// ─── Grouped accordion list ──────────────────────────────────────────────────

class _GroupedList extends StatelessWidget {
  final List<TitleGroup> groups;
  final String? expandedTitleId;
  final void Function(String titleId) onToggle;
  final void Function(Article) onArticleTap;
  final void Function(TitleGroup) onRenameTitle;
  final void Function(TitleGroup) onDeleteTitle;
  final void Function(Article)? onDeleteArticle;

  const _GroupedList({
    required this.groups,
    required this.expandedTitleId,
    required this.onToggle,
    required this.onArticleTap,
    required this.onRenameTitle,
    required this.onDeleteTitle,
    this.onDeleteArticle,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final group = groups[i];
        return _TitleAccordion(
          group: group,
          isExpanded: expandedTitleId == group.titleId,
          onToggle: () => onToggle(group.titleId),
          onArticleTap: onArticleTap,
          onRename: () => onRenameTitle(group),
          onDelete: () => onDeleteTitle(group),
          onDeleteArticle: onDeleteArticle,
        );
      },
    );
  }
}

class _TitleAccordion extends StatelessWidget {
  final TitleGroup group;
  final bool isExpanded;
  final VoidCallback onToggle;
  final void Function(Article) onArticleTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final void Function(Article)? onDeleteArticle;

  const _TitleAccordion({
    required this.group,
    required this.isExpanded,
    required this.onToggle,
    required this.onArticleTap,
    required this.onRename,
    required this.onDelete,
    this.onDeleteArticle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimColor = theme.textTheme.bodySmall?.color?.withAlpha(153);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title header
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 4, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.chevron_right, size: 20),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.titleName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        group.websiteDomain,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: dimColor,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Rename',
                  visualDensity: VisualDensity.compact,
                  onPressed: onRename,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
        // Article list (animated)
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState:
              isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Column(
            children:
                group.articles
                    .map(
                      (a) => _ArticleTile(
                        article: a,
                        onTap: onArticleTap,
                        onDelete: onDeleteArticle,
                      ),
                    )
                    .toList(),
          ),
          secondChild: const SizedBox.shrink(),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _ArticleTile extends StatelessWidget {
  final Article article;
  final void Function(Article) onTap;
  final void Function(Article)? onDelete;

  const _ArticleTile({
    required this.article,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onTap(article),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(44, 6, 4, 6),
        child: Row(
          children: [
            Icon(
              article.isBookmarked ? Icons.bookmark : Icons.article_outlined,
              size: 16,
              color:
                  article.isBookmarked
                      ? Colors.amber
                      : theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                article.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.primary.withAlpha(120),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.bookmark_remove_outlined, size: 18),
                tooltip: 'Remove bookmark',
                visualDensity: VisualDensity.compact,
                onPressed: () => onDelete!(article),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

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

// ─── Get Started page ────────────────────────────────────────────────────────

class _GetStartedPage extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final String? error;
  final void Function(String) onSubmit;

  const _GetStartedPage({
    required this.controller,
    required this.isLoading,
    required this.error,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    const titleColor = Color(0xFFF1CAD7);
    const bodyColor = Color(0xFFFCF1E9);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            // CSS 223deg ≈ begin at top-right, end at bottom-left
            begin: Alignment(0.68, -0.73),
            end: Alignment(-0.68, 0.73),
            colors: [Color(0xFF5577FF), Color(0xFF7755FF), Color(0xFF5555FF)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'WebReader',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const Text(
                  'Listen to web articles on the go',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: bodyColor,
                    fontSize: 16,
                    height: 1.55,
                  ),
                ),

                const SizedBox(height: 14),

                Image.asset(
                  'assets/hero-image.png',
                  height: 220,
                  fit: BoxFit.contain,
                ),

                const SizedBox(height: 20),

                const _GsFeatureRow(
                  icon: Icons.text_fields_rounded,
                  text: 'Clean, readable text from any webpage',
                  color: bodyColor,
                ),
                const _GsFeatureRow(
                  icon: Icons.record_voice_over_rounded,
                  text: 'Listen with built-in text-to-speech',
                  color: bodyColor,
                ),
                const _GsFeatureRow(
                  icon: Icons.bookmark_rounded,
                  text: 'Continue saved articles where you left off',
                  color: bodyColor,
                ),

                // Push everything below to bottom
                const Spacer(),

                const Text(
                  'Paste a URL below to get started.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: bodyColor,
                    fontSize: 16,
                    height: 1.55,
                  ),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Paste a URL to read…',
                    hintStyle: TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.link, color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: const BorderSide(
                        color: Colors.white,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white24,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: isLoading ? null : onSubmit,
                ),

                if (error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    error!,
                    style: TextStyle(color: Colors.red.shade200, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed:
                        isLoading ? null : () => onSubmit(controller.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: titleColor,
                      foregroundColor: const Color(0xFF3A1A60),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    child:
                        isLoading
                            ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Color(0xFF3A1A60),
                              ),
                            )
                            : const Text(
                              'Open',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                  ),
                ),
                const SizedBox(height: 64),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GsFeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _GsFeatureRow({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color.withAlpha(200), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

// ─── Theme Toggle ─────────────────────────────────────────────────────────────

class _ThemeToggleButton extends ConsumerWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final pref =
        settingsAsync.valueOrNull?.themePreference ?? ThemePreference.system;

    final (icon, tooltip) = switch (pref) {
      ThemePreference.system => (Icons.brightness_auto, 'System theme'),
      ThemePreference.light => (Icons.light_mode_outlined, 'Light theme'),
      ThemePreference.dark => (Icons.dark_mode_outlined, 'Dark theme'),
    };

    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed:
          settingsAsync.valueOrNull == null
              ? null
              : () {
                final next = switch (pref) {
                  ThemePreference.system => ThemePreference.light,
                  ThemePreference.light => ThemePreference.dark,
                  ThemePreference.dark => ThemePreference.system,
                };
                final updated = settingsAsync.requireValue.copyWith(
                  themePreference: next,
                );
                ref.read(settingsProvider.notifier).update(updated);
              },
    );
  }
}
