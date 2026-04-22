import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_reader/presentation/providers/providers.dart';

class CacheLogScreen extends ConsumerStatefulWidget {
  const CacheLogScreen({super.key});

  @override
  ConsumerState<CacheLogScreen> createState() => _CacheLogScreenState();
}

class _CacheLogScreenState extends ConsumerState<CacheLogScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // Refresh the cached-articles list whenever this screen is opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cachedArticlesProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(cacheLogProvider);

    // Refresh cached pages list whenever a new log line arrives
    // (means something was just cached)
    ref.listen(cacheLogProvider, (prev, next) {
      if (next.length != (prev?.length ?? 0)) {
        ref.read(cachedArticlesProvider.notifier).load();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cache'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.storage_outlined), text: 'Cached Pages'),
            Tab(icon: Icon(Icons.terminal_outlined), text: 'Log'),
          ],
        ),
        actions: [
          // Show clear-log button only when on the Log tab
          ListenableBuilder(
            listenable: _tabs,
            builder:
                (_, __) =>
                    _tabs.index == 1
                        ? IconButton(
                          icon: const Icon(Icons.delete_sweep_outlined),
                          tooltip: 'Clear log',
                          onPressed:
                              () => ref.read(cacheLogProvider.notifier).clear(),
                        )
                        : const SizedBox.shrink(),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_CachedPagesTab(), _LogTab(lines: lines)],
      ),
    );
  }
}

// ─── Cached Pages tab ────────────────────────────────────────────────────────

class _CachedPagesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articlesAsync = ref.watch(cachedArticlesProvider);

    return articlesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (articles) {
        if (articles.isEmpty) {
          return const Center(
            child: Text(
              'No pages cached yet.\nOpen an article to start caching.',
              textAlign: TextAlign.center,
            ),
          );
        }

        final bookmarked = articles.where((a) => a.isBookmarked).length;
        final regular = articles.length - bookmarked;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Summary bar
            Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  _CountChip(
                    icon: Icons.storage_outlined,
                    label: 'Total',
                    count: articles.length,
                  ),
                  const SizedBox(width: 12),
                  _CountChip(
                    icon: Icons.article_outlined,
                    label: 'Articles',
                    count: regular,
                  ),
                  const SizedBox(width: 12),
                  _CountChip(
                    icon: Icons.bookmark_outlined,
                    label: 'Bookmarks',
                    count: bookmarked,
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh:
                    () => ref.read(cachedArticlesProvider.notifier).load(),
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: articles.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final a = articles[i];
                    return ListTile(
                      leading: Icon(
                        a.isBookmarked
                            ? Icons.bookmark
                            : Icons.article_outlined,
                        color:
                            a.isBookmarked
                                ? Colors.amber
                                : Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                      title: Text(
                        a.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        a.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      dense: true,
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CountChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;

  const _CountChip({
    required this.icon,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4),
        Text(
          '$count $label',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ─── Log tab ─────────────────────────────────────────────────────────────────

class _LogTab extends StatefulWidget {
  final List<String> lines;

  const _LogTab({required this.lines});

  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_LogTab old) {
    super.didUpdateWidget(old);
    if (widget.lines.length != old.lines.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines.isEmpty) {
      return const Center(
        child: Text(
          'No log entries yet.\nOpen an article to start caching.',
          textAlign: TextAlign.center,
        ),
      );
    }

    final mono = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.5);

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: widget.lines.length,
      itemBuilder: (_, i) {
        final line = widget.lines[i];
        final isError = line.contains('FAILED');
        final isOk = line.contains(' OK');
        final color =
            isError
                ? Colors.red
                : isOk
                ? Colors.green
                : null;
        return Text(line, style: mono?.copyWith(color: color));
      },
    );
  }
}
