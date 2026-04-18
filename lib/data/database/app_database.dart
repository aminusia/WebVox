import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:web_reader/core/constants/app_constants.dart';

class AppDatabase {
  static AppDatabase? _instance;
  static Database? _db;

  AppDatabase._();

  static AppDatabase get instance {
    _instance ??= AppDatabase._();
    return _instance!;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _openDatabase();
    return _db!;
  }

  Future<Database> _openDatabase() async {
    final basePath = await getDatabasesPath();
    final path = join(basePath, AppConstants.dbName);
    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE reading_states ADD COLUMN last_word_offset INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE articles ADD COLUMN prev_url TEXT');
      await db.execute('ALTER TABLE articles ADD COLUMN next_url TEXT');
      await db.execute('ALTER TABLE articles ADD COLUMN home_url TEXT');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE articles (
        id TEXT PRIMARY KEY,
        url TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        author TEXT,
        language TEXT NOT NULL DEFAULT 'en-US',
        estimated_read_time INTEGER NOT NULL DEFAULT 0,
        is_bookmarked INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        prev_url TEXT,
        next_url TEXT,
        home_url TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE reading_states (
        article_id TEXT PRIMARY KEY,
        scroll_position REAL NOT NULL DEFAULT 0.0,
        last_read_index INTEGER NOT NULL DEFAULT 0,
        last_word_offset INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }
}
