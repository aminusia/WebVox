import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_reader/domain/entities/article.dart';
import 'package:web_reader/presentation/providers/providers.dart';
import 'package:web_reader/presentation/screens/reader_screen.dart';

class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarksAsync = ref.watch(bookmarksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: bookmarksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data:
            (articles) =>
                articles.isEmpty
                    ? const _EmptyState()
                    : ListView.builder(
                      itemCount: articles.length,
                      itemBuilder:
                          (_, i) => _BookmarkTile(
                            article: articles[i],
                            onTap: () async {
                              await ref
                                  .read(settingsRepositoryProvider)
                                  .setLastArticleUrl(articles[i].url);
                              if (!context.mounted) return;
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder:
                                      (_) => ReaderScreen(article: articles[i]),
                                ),
                              );
                              ref.read(bookmarksProvider.notifier).load();
                            },
                            onRemoveBookmark: () async {
                              await ref
                                  .read(articleRepositoryProvider)
                                  .toggleBookmark(articles[i].id);
                              ref.read(bookmarksProvider.notifier).load();
                            },
                          ),
                    ),
      ),
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  final Article article;
  final VoidCallback onTap;
  final VoidCallback onRemoveBookmark;

  const _BookmarkTile({
    required this.article,
    required this.onTap,
    required this.onRemoveBookmark,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.bookmark, color: Colors.amber),
      title: Text(article.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${article.estimatedReadTime} min · ${article.language}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.bookmark_remove_outlined),
        tooltip: 'Remove bookmark',
        onPressed: onRemoveBookmark,
      ),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bookmarks_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(height: 16),
          const Text('No bookmarks yet'),
        ],
      ),
    );
  }
}
