import 'package:uuid/uuid.dart';
import 'package:webvox/core/constants/app_constants.dart';
import 'package:webvox/data/sources/local/local_article_source.dart';
import 'package:webvox/data/sources/remote/remote_article_source.dart';
import 'package:webvox/domain/entities/article.dart';
import 'package:webvox/domain/entities/title_group.dart';
import 'package:webvox/domain/repositories/article_repository.dart';

class ArticleRepositoryImpl implements ArticleRepository {
  final LocalArticleSource _local;
  final RemoteArticleSource _remote;
  final Uuid _uuid;

  ArticleRepositoryImpl({
    LocalArticleSource? local,
    RemoteArticleSource? remote,
  }) : _local = local ?? LocalArticleSource(),
       _remote = remote ?? RemoteArticleSource(),
       _uuid = const Uuid();

  @override
  Future<Article> fetchArticle(String url) async {
    final cached = await _local.findByUrl(url);
    if (cached != null) {
      // Update createdAt so re-accessed articles bubble up in the recent list.
      final refreshed = Article(
        id: cached.id,
        url: cached.url,
        title: cached.title,
        content: cached.content,
        author: cached.author,
        language: cached.language,
        estimatedReadTime: cached.estimatedReadTime,
        isBookmarked: cached.isBookmarked,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        prevUrl: cached.prevUrl,
        nextUrl: cached.nextUrl,
        homeUrl: cached.homeUrl,
        isCached: true,
      );
      await _local.insertOrUpdate(refreshed);
      return refreshed;
    }

    final parsed = await _remote.fetch(url);

    final article = Article(
      id: _uuid.v4(),
      url: url,
      title: parsed.title,
      content: parsed.content,
      author: parsed.author,
      language: parsed.language,
      estimatedReadTime: parsed.estimatedReadTime,
      isBookmarked: false,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      prevUrl: parsed.prevUrl,
      nextUrl: parsed.nextUrl,
      homeUrl: parsed.homeUrl,
    );

    await _local.insertOrUpdate(article);
    await pruneOldArticles();
    return article;
  }

  @override
  Future<List<Article>> getRecentArticles() => _local.getRecent();

  @override
  Future<List<Article>> getBookmarks() => _local.getBookmarks();

  @override
  Future<Article?> getCachedArticle(String url) => _local.findByUrl(url);

  @override
  Future<void> toggleBookmark(String articleId) async {
    final article = await _local.findById(articleId);
    if (article == null) return;
    await _local.updateBookmark(articleId, isBookmarked: !article.isBookmarked);
  }

  @override
  Future<void> deleteArticle(String articleId) => _local.delete(articleId);

  @override
  Future<void> pruneOldArticles() async {
    final count = await _local.count();
    if (count > AppConstants.maxCachedArticles) {
      await _local.pruneOldest(AppConstants.maxCachedArticles);
    }
  }

  @override
  Future<int> clearCachedArticles() => _local.deleteNonBookmarked();

  @override
  Future<List<Article>> getAllCached() => _local.getAll();

  @override
  Future<void> markArticleRead(String id) => _local.markUserRead(id);

  @override
  Future<void> markArticleCompleted(String id) => _local.markCompleted(id);

  @override
  Future<bool> isLastUncompletedRead(String id) =>
      _local.isLastUncompletedRead(id);

  @override
  Future<void> removeFromHistory(String id) => _local.removeFromHistory(id);

  @override
  Future<List<TitleGroup>> getRecentGrouped() => _local.getRecentGrouped();

  @override
  Future<List<TitleGroup>> getBookmarksGrouped() =>
      _local.getBookmarksGrouped();

  @override
  Future<void> updateTitleName(String titleId, String name) =>
      _local.updateTitleName(titleId, name);

  @override
  Future<void> removeHistoryForTitle(String titleId) =>
      _local.removeHistoryForTitle(titleId);

  @override
  Future<void> removeBookmarksForTitle(String titleId) =>
      _local.removeBookmarksForTitle(titleId);
}
