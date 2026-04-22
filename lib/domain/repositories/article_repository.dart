import 'package:web_reader/domain/entities/article.dart';

abstract class ArticleRepository {
  Future<Article> fetchArticle(String url);
  Future<List<Article>> getRecentArticles();
  Future<List<Article>> getBookmarks();
  Future<Article?> getCachedArticle(String url);
  Future<void> toggleBookmark(String articleId);
  Future<void> deleteArticle(String articleId);
  Future<void> pruneOldArticles();

  /// Delete all non-bookmarked articles from the local cache.
  Future<int> clearCachedArticles();

  /// Returns every article stored locally, newest first.
  Future<List<Article>> getAllCached();

  /// Mark an article as user-read so it appears in the recents list.
  Future<void> markArticleRead(String id);

  /// Mark the article as fully read (user navigated to the next page).
  Future<void> markArticleCompleted(String id);

  /// Returns true when [id] is the most-recently-read article AND incomplete.
  Future<bool> isLastUncompletedRead(String id);

  /// Remove an article from read history without deleting it from cache.
  Future<void> removeFromHistory(String id);
}
