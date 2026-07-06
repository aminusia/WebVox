import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:webvox/core/utils/title_extractor.dart';
import 'package:webvox/data/database/app_database.dart';
import 'package:webvox/domain/entities/article.dart';
import 'package:webvox/domain/entities/title_group.dart';

class LocalArticleSource {
  Future<Database> get _db => AppDatabase.instance.database;

  static const _uuid = Uuid();

  // Columns shared by all queries that need bookmark status via LEFT JOIN.
  static const _cols = '''
    a.id, a.url, a.title, a.content, a.author, a.language,
    a.estimated_read_time, a.created_at,
    a.prev_url, a.next_url, a.home_url,
    a.volume_id,
    CASE WHEN b.article_id IS NOT NULL THEN 1 ELSE 0 END AS is_bookmarked
  ''';

  // ─── Volume / website resolution ─────────────────────────────────────────

  /// Returns the volume_id for the given article URL + title, creating the
  /// website and/or volume record if they don't exist yet.
  /// If [volumeName] is provided (e.g., from novelarrow.com API), it's used as the
  /// volume name instead of extracting from article title.
  Future<String> _resolveOrCreateVolumeId(
    Database db,
    String url,
    String articleTitle, {
    String? volumeName,
  }) async {
    final domain = TitleExtractor.extractDomain(url);
    // Use volumeName if provided (e.g., from API), otherwise extract from article title
    final vName = volumeName ?? TitleExtractor.extractBookTitle(articleTitle);

    // Find or create website row.
    final wsRows = await db.query(
      'websites',
      columns: ['id'],
      where: 'domain = ?',
      whereArgs: [domain],
      limit: 1,
    );
    final String websiteId;
    if (wsRows.isNotEmpty) {
      websiteId = wsRows.first['id'] as String;
    } else {
      websiteId = _uuid.v4();
      await db.insert('websites', {
        'id': websiteId,
        'domain': domain,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // Find or create volume row.
    final vRows = await db.query(
      'volumes',
      columns: ['id'],
      where: 'name = ? AND website_id = ?',
      whereArgs: [vName, websiteId],
      limit: 1,
    );
    if (vRows.isNotEmpty) {
      return vRows.first['id'] as String;
    }
    final volumeId = _uuid.v4();
    await db.insert('volumes', {
      'id': volumeId,
      'name': vName,
      'website_id': websiteId,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    return volumeId;
  }

  Future<void> insertOrUpdate(Article article) async {
    final db = await _db;
    final volumeId = await _resolveOrCreateVolumeId(
      db,
      article.url,
      article.title,
      volumeName: article.homeUrl != null
          ? Uri.parse(article.homeUrl!).pathSegments.last
          : null,
    );
    final map = {...article.toMap(), 'volume_id': volumeId};
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
  /// Only deletes from articles table (cache). Does NOT touch read_history or bookmarks.
  Future<int> deleteNonBookmarked() async {
    final db = await _db;
    final count = await db.rawDelete(
      'DELETE FROM articles WHERE id NOT IN (SELECT article_id FROM bookmarks)',
    );
    // Clean up orphaned reading_states for deleted articles
    await db.rawDelete(
      'DELETE FROM reading_states WHERE article_id NOT IN (SELECT id FROM articles)',
    );
    return count;
  }

  /// Clear all cached articles (from articles table only).
  /// Does NOT touch read_history (recent list) or bookmarks.
  /// Returns the number of rows deleted.
  Future<int> clearCachedArticles() async {
    final db = await _db;
    final count = await db.rawDelete('DELETE FROM articles');
    // Clean up orphaned reading_states
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

  // ─── Grouped queries ────────────────────────────────────────────────────

    /// Recent: all volumes that have at least one article, ordered by most-recently
    /// read article first. Volumes with no read history appear at the end (sorted
    /// by volume creation date). Each volume includes ALL its articles, with
    /// read articles first (most recent), then unread ones.
    Future<List<TitleGroup>> getRecentGrouped() async {
      final db = await _db;
      final volumeRows = await db.rawQuery('''
        SELECT v.id AS volume_id, COALESCE(v.display_name, v.name) AS volume_name, w.domain AS website_domain,
               MAX(rh.read_at) AS last_read_at
        FROM volumes v
        JOIN websites w ON w.id = v.website_id
        JOIN articles a ON a.volume_id = v.id
        LEFT JOIN read_history rh ON rh.article_id = a.id
        GROUP BY v.id, v.name, w.domain
        ORDER BY last_read_at DESC, v.created_at DESC
      ''');

      final groups = <TitleGroup>[];
      for (final vr in volumeRows) {
        final volumeId = vr['volume_id'] as String;
        final articleRows = await db.rawQuery(
          '''
          SELECT $_cols
          FROM articles a
          LEFT JOIN read_history rh ON rh.article_id = a.id
          LEFT JOIN bookmarks b ON b.article_id = a.id
          WHERE a.volume_id = ?
          ORDER BY rh.read_at DESC, a.created_at DESC
        ''',
          [volumeId],
        );
        groups.add(
          TitleGroup(
            titleId: volumeId,
            titleName: vr['volume_name'] as String,
            websiteDomain: vr['website_domain'] as String,
            articles: articleRows.map(Article.fromMap).toList(),
          ),
        );
      }
      return groups;
    }

    /// Bookmarked articles grouped by volume, ordered by most-recently-bookmarked first.
    Future<List<TitleGroup>> getBookmarksGrouped() async {
      final db = await _db;
      final volumeRows = await db.rawQuery('''
        SELECT v.id AS volume_id, COALESCE(v.display_name, v.name) AS volume_name, w.domain AS website_domain,
               MAX(bk.bookmarked_at) AS last_bookmarked_at
        FROM volumes v
        JOIN websites w ON w.id = v.website_id
        JOIN articles a ON a.volume_id = v.id
        JOIN bookmarks bk ON bk.article_id = a.id
        GROUP BY v.id, v.name, w.domain
        ORDER BY last_bookmarked_at DESC
      ''');

      final groups = <TitleGroup>[];
      for (final vr in volumeRows) {
        final volumeId = vr['volume_id'] as String;
        final articleRows = await db.rawQuery(
          '''
          SELECT $_cols
          FROM bookmarks bk
          JOIN articles a ON a.id = bk.article_id
          LEFT JOIN bookmarks b ON b.article_id = a.id
          WHERE a.volume_id = ?
          ORDER BY bk.bookmarked_at DESC
        ''',
          [volumeId],
        );
        groups.add(
          TitleGroup(
            titleId: volumeId,
            titleName: vr['volume_name'] as String,
            websiteDomain: vr['website_domain'] as String,
            articles: articleRows.map(Article.fromMap).toList(),
          ),
        );
      }
      return groups;
    }

    // ─── Volume management ───────────────────────────────────────────────────

    Future<void> updateVolumeName(String volumeId, String name) async {
      final db = await _db;
      await db.update(
        'volumes',
        {'display_name': name},
        where: 'id = ?',
        whereArgs: [volumeId],
      );
    }

    /// Remove all read_history rows for articles belonging to [volumeId].
    /// Also removes the articles from cache if they're not bookmarked.
    Future<void> removeHistoryForVolume(String volumeId) async {
      final db = await _db;

      // First, get all article IDs for this volume
      final articleRows = await db.query(
        'articles',
        columns: ['id'],
        where: 'volume_id = ?',
        whereArgs: [volumeId],
      );
      final articleIds = articleRows.map((r) => r['id'] as String).toList();

      // Delete from read_history
      await db.rawDelete(
        '''
        DELETE FROM read_history
        WHERE article_id IN (SELECT id FROM articles WHERE volume_id = ?)
        ''',
        [volumeId],
      );

      // Delete articles from cache if they're not bookmarked
      if (articleIds.isNotEmpty) {
        await db.rawDelete(
          '''
          DELETE FROM articles
          WHERE volume_id = ?
          AND id NOT IN (SELECT article_id FROM bookmarks)
          ''',
          [volumeId],
        );
      }

      // Clean up orphaned reading_states
      if (articleIds.isNotEmpty) {
        await db.rawDelete(
          'DELETE FROM reading_states WHERE article_id IN (SELECT id FROM articles WHERE volume_id = ?)',
          [volumeId],
        );
      }
    }

    /// Remove all bookmark rows for articles belonging to [volumeId].
    /// Also removes the articles from cache if they're not in read history.
    Future<void> removeBookmarksForVolume(String volumeId) async {
      final db = await _db;

      // First, get all article IDs for this volume
      final articleRows = await db.query(
        'articles',
        columns: ['id'],
        where: 'volume_id = ?',
        whereArgs: [volumeId],
      );
      final articleIds = articleRows.map((r) => r['id'] as String).toList();

      // Delete from bookmarks
      await db.rawDelete(
        '''
        DELETE FROM bookmarks
        WHERE article_id IN (SELECT id FROM articles WHERE volume_id = ?)
        ''',
        [volumeId],
      );

      // Delete articles from cache if they're not in read history
      if (articleIds.isNotEmpty) {
        await db.rawDelete(
          '''
          DELETE FROM articles
          WHERE volume_id = ?
          AND id NOT IN (SELECT article_id FROM read_history)
          ''',
          [volumeId],
        );
      }

      // Clean up orphaned reading_states
      if (articleIds.isNotEmpty) {
        await db.rawDelete(
          'DELETE FROM reading_states WHERE article_id IN (SELECT id FROM articles WHERE volume_id = ?)',
          [volumeId],
        );
      }
    }
  }
