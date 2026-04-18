import 'package:web_reader/domain/entities/article.dart';

abstract class ArticleRepository {
  Future<Article> fetchArticle(String url);
  Future<List<Article>> getRecentArticles();
  Future<List<Article>> getBookmarks();
  Future<Article?> getCachedArticle(String url);
  Future<void> toggleBookmark(String articleId);
  Future<void> deleteArticle(String articleId);
  Future<void> pruneOldArticles();
}
