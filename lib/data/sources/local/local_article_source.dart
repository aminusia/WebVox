import 'package:sqflite/sqflite.dart';
import 'package:web_reader/data/database/app_database.dart';
import 'package:web_reader/domain/entities/article.dart';

class LocalArticleSource {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<void> insertOrUpdate(Article article) async {
    final db = await _db;
    await db.insert(
      'articles',
      article.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Article?> findByUrl(String url) async {
    final db = await _db;
    final rows = await db.query(
      'articles',
      where: 'url = ?',
      whereArgs: [url],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Article.fromMap(rows.first);
  }

  Future<Article?> findById(String id) async {
    final db = await _db;
    final rows = await db.query(
      'articles',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Article.fromMap(rows.first);
  }

  Future<List<Article>> getRecent({int limit = 20}) async {
    final db = await _db;
    final rows = await db.query(
      'articles',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(Article.fromMap).toList();
  }

  Future<List<Article>> getBookmarks() async {
    final db = await _db;
    final rows = await db.query(
      'articles',
      where: 'is_bookmarked = 1',
      orderBy: 'created_at DESC',
    );
    return rows.map(Article.fromMap).toList();
  }

  Future<void> updateBookmark(String id, {required bool isBookmarked}) async {
    final db = await _db;
    await db.update(
      'articles',
      {'is_bookmarked': isBookmarked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete('articles', where: 'id = ?', whereArgs: [id]);
    await db.delete('reading_states', where: 'article_id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM articles');
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<void> pruneOldest(int keepCount) async {
    final db = await _db;
    await db.rawDelete(
      '''
      DELETE FROM articles
      WHERE id IN (
        SELECT id FROM articles
        WHERE is_bookmarked = 0
        ORDER BY created_at ASC
        LIMIT MAX(0, (SELECT COUNT(*) FROM articles WHERE is_bookmarked = 0) - ?)
      )
    ''',
      [keepCount],
    );
  }
}
