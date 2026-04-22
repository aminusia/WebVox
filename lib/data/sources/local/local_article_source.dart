import 'package:sqflite/sqflite.dart';
import 'package:web_reader/data/database/app_database.dart';
import 'package:web_reader/domain/entities/article.dart';

class LocalArticleSource {
  Future<Database> get _db => AppDatabase.instance.database;

  // Columns shared by all queries that need bookmark status via LEFT JOIN.
  static const _cols = '''
    a.id, a.url, a.title, a.content, a.author, a.language,
    a.estimated_read_time, a.created_at,
    a.prev_url, a.next_url, a.home_url,
    CASE WHEN b.article_id IS NOT NULL THEN 1 ELSE 0 END AS is_bookmarked
  ''';

  Future<void> insertOrUpdate(Article article) async {
    final db = await _db;
    final map = article.toMap(); // no is_bookmarked column anymore
    await db.insert(
      'articles',
      map,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.update(
      'articles',
      map,
      where: 'url = ?',
      whereArgs: [article.url],
    );
  }

  Future<Article?> findByUrl(String url) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT $_cols
      FROM articles a
      LEFT JOIN bookmarks b ON b.article_id = a.id
      WHERE a.url = ?
      LIMIT 1
      ''',
      [url],
    );
    if (rows.isEmpty) return null;
    return Article.fromMap(rows.first);
  }

  Future<Article?> findById(String id) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT $_cols
      FROM articles a
      LEFT JOIN bookmarks b ON b.article_id = a.id
      WHERE a.id = ?
      LIMIT 1
      ''',
      [id],
    );
    if (rows.isEmpty) return null;
    return Article.fromMap(rows.first);
  }

  Future<List<Article>> getRecent() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT $_cols
      FROM read_history rh
      JOIN articles a ON a.id = rh.article_id
      LEFT JOIN bookmarks b ON b.article_id = a.id
      ORDER BY rh.read_at DESC
      ''');
    return rows.map(Article.fromMap).toList();
  }

  Future<List<Article>> getBookmarks() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT a.*, 1 AS is_bookmarked
      FROM bookmarks bk
      JOIN articles a ON a.id = bk.article_id
      ORDER BY bk.bookmarked_at DESC
      ''');
    return rows.map(Article.fromMap).toList();
  }

  Future<void> updateBookmark(String id, {required bool isBookmarked}) async {
    final db = await _db;
    if (isBookmarked) {
      await db.insert('bookmarks', {
        'article_id': id,
        'bookmarked_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.delete('bookmarks', where: 'article_id = ?', whereArgs: [id]);
    }
  }

  Future<void> markUserRead(String id) async {
    final db = await _db;
    await db.insert(
      'read_history',
      {
        'article_id': id,
        'read_at': DateTime.now().millisecondsSinceEpoch,
        'is_completed': 0,
      },
      conflictAlgorithm:
          ConflictAlgorithm
              .ignore, // don't reset completion if already recorded
    );
    // Always bump read_at so it bubbles to top in history.
    await db.rawUpdate(
      'UPDATE read_history SET read_at = ? WHERE article_id = ?',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  Future<void> markCompleted(String id) async {
    final db = await _db;
    await db.rawUpdate(
      'UPDATE read_history SET is_completed = 1 WHERE article_id = ?',
      [id],
    );
  }

  /// Returns true when [id] is the most-recently-read article AND it has
  /// not been marked as completed (i.e. the user didn't reach the next page).
  Future<bool> isLastUncompletedRead(String id) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT article_id, is_completed FROM read_history ORDER BY read_at DESC LIMIT 1',
    );
    if (rows.isEmpty) return false;
    final lastId = rows.first['article_id'] as String;
    final isCompleted = (rows.first['is_completed'] as int? ?? 0) == 1;
    return lastId == id && !isCompleted;
  }

  Future<void> removeFromHistory(String id) async {
    final db = await _db;
    await db.delete('read_history', where: 'article_id = ?', whereArgs: [id]);
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete('articles', where: 'id = ?', whereArgs: [id]);
    await db.delete('reading_states', where: 'article_id = ?', whereArgs: [id]);
    await db.delete('bookmarks', where: 'article_id = ?', whereArgs: [id]);
    await db.delete('read_history', where: 'article_id = ?', whereArgs: [id]);
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
        WHERE id NOT IN (SELECT article_id FROM bookmarks)
        ORDER BY created_at ASC
        LIMIT MAX(0,
          (SELECT COUNT(*) FROM articles WHERE id NOT IN (SELECT article_id FROM bookmarks)) - ?
        )
      )
      ''',
      [keepCount],
    );
    // Clean up orphaned rows in related tables.
    await db.rawDelete(
      'DELETE FROM read_history WHERE article_id NOT IN (SELECT id FROM articles)',
    );
    await db.rawDelete(
      'DELETE FROM reading_states WHERE article_id NOT IN (SELECT id FROM articles)',
    );
  }

  /// Delete all non-bookmarked articles. Returns the number of rows deleted.
  Future<int> deleteNonBookmarked() async {
    final db = await _db;
    final count = await db.rawDelete(
      'DELETE FROM articles WHERE id NOT IN (SELECT article_id FROM bookmarks)',
    );
    await db.rawDelete(
      'DELETE FROM read_history WHERE article_id NOT IN (SELECT id FROM articles)',
    );
    await db.rawDelete(
      'DELETE FROM reading_states WHERE article_id NOT IN (SELECT id FROM articles)',
    );
    return count;
  }

  /// Returns all articles ordered by creation date descending (no limit).
  Future<List<Article>> getAll() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT $_cols
      FROM articles a
      LEFT JOIN bookmarks b ON b.article_id = a.id
      ORDER BY a.created_at DESC
      ''');
    return rows.map(Article.fromMap).toList();
  }
}
