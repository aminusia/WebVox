import 'package:sqflite/sqflite.dart';
import 'package:webreader/data/database/app_database.dart';
import 'package:webreader/domain/entities/reading_state.dart';

class LocalReadingStateSource {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<ReadingState?> get(String articleId) async {
    final db = await _db;
    final rows = await db.query(
      'reading_states',
      where: 'article_id = ?',
      whereArgs: [articleId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ReadingState.fromMap(rows.first);
  }

  Future<void> save(ReadingState state) async {
    final db = await _db;
    await db.insert(
      'reading_states',
      state.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String articleId) async {
    final db = await _db;
    await db.delete(
      'reading_states',
      where: 'article_id = ?',
      whereArgs: [articleId],
    );
  }
}
