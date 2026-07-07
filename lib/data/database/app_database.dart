import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:webvox/core/constants/app_constants.dart';
import 'package:webvox/core/utils/title_extractor.dart';

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
    if (oldVersion < 4) {
      // DEFAULT 1 so all pre-existing articles remain visible in recents.
      await db.execute(
        'ALTER TABLE articles ADD COLUMN is_user_read INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (oldVersion < 5) {
      // Create dedicated bookmarks and read_history tables.
      await db.execute('''
        CREATE TABLE bookmarks (
          article_id TEXT PRIMARY KEY,
          bookmarked_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE read_history (
          article_id TEXT PRIMARY KEY,
          read_at INTEGER NOT NULL
        )
      ''');
      // Migrate existing flags into the new tables.
      await db.rawInsert('''
        INSERT OR IGNORE INTO bookmarks (article_id, bookmarked_at)
        SELECT id, created_at FROM articles WHERE is_bookmarked = 1
      ''');
      await db.rawInsert('''
        INSERT OR IGNORE INTO read_history (article_id, read_at)
        SELECT id, created_at FROM articles WHERE is_user_read = 1
      ''');
      // Rebuild articles table without the now-redundant flag columns.
      await db.execute('''
        CREATE TABLE articles_new (
          id TEXT PRIMARY KEY,
          url TEXT NOT NULL UNIQUE,
          title TEXT NOT NULL,
          content TEXT NOT NULL,
          author TEXT,
          language TEXT NOT NULL DEFAULT 'en-US',
          estimated_read_time INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          prev_url TEXT,
          next_url TEXT,
          home_url TEXT
        )
      ''');
      await db.rawInsert('''
        INSERT INTO articles_new
          (id, url, title, content, author, language,
           estimated_read_time, created_at, prev_url, next_url, home_url)
        SELECT
          id, url, title, content, author, language,
          estimated_read_time, created_at, prev_url, next_url, home_url
        FROM articles
      ''');
      await db.execute('DROP TABLE articles');
      await db.execute('ALTER TABLE articles_new RENAME TO articles');
    }
    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE read_history ADD COLUMN is_completed INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 7) {
      // Create websites table.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS websites (
          id TEXT PRIMARY KEY,
          domain TEXT NOT NULL UNIQUE,
          custom_title TEXT
        )
      ''');
      // Create series table (formerly volumes/titles).
      await db.execute('''
        CREATE TABLE IF NOT EXISTS series (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          website_id TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      // Add series_id column to articles.
      await db.execute('ALTER TABLE articles ADD COLUMN series_id TEXT');

      // Migrate existing articles → derive website + series records.
      const uuid = Uuid();
      final articles = await db.query('articles');
      final Map<String, String> domainToWebsiteId = {};
      // key = "websiteId\x00seriesName" → seriesId
      final Map<String, String> seriesKeyToId = {};

      for (final row in articles) {
        final url = row['url'] as String? ?? '';
        final articleTitle = row['title'] as String? ?? '';
        final articleId = row['id'] as String;
        final createdAt = row['created_at'] as int? ?? 0;

        final domain = TitleExtractor.extractDomain(url);
        final bookTitle = TitleExtractor.extractBookTitle(articleTitle);

        // Find or create website.
        String websiteId;
        if (domainToWebsiteId.containsKey(domain)) {
          websiteId = domainToWebsiteId[domain]!;
        } else {
          websiteId = uuid.v4();
          await db.insert('websites', {
            'id': websiteId,
            'domain': domain,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          domainToWebsiteId[domain] = websiteId;
        }

        // Find or create series.
        final seriesKey = '$websiteId\x00$bookTitle';
        String seriesId;
        if (seriesKeyToId.containsKey(seriesKey)) {
          seriesId = seriesKeyToId[seriesKey]!;
        } else {
          seriesId = uuid.v4();
          await db.insert('series', {
            'id': seriesId,
            'name': bookTitle,
            'website_id': websiteId,
            'created_at': createdAt,
          });
          seriesKeyToId[seriesKey] = seriesId;
        }

        // Link article to series.
        await db.update(
          'articles',
          {'series_id': seriesId},
          where: 'id = ?',
          whereArgs: [articleId],
        );
      }
    }
    if (oldVersion < 8) {
      // Add display_name to series: user-editable label separate from the
      // original name (which is used for matching new articles to groups).
      await db.execute('ALTER TABLE series ADD COLUMN display_name TEXT');
    }
    if (oldVersion < 11) {
      // Make bookmarks and read_history independent from articles table
      // Add new columns to bookmarks
      await db.execute('ALTER TABLE bookmarks ADD COLUMN id TEXT');
      await db.execute('ALTER TABLE bookmarks ADD COLUMN series_id TEXT');
      await db.execute('ALTER TABLE bookmarks ADD COLUMN title TEXT');
      await db.execute('ALTER TABLE bookmarks ADD COLUMN url TEXT');
      
      // Migrate existing bookmarks: populate id, title, url from articles
      // Use COALESCE to provide fallback values for deleted articles
      await db.rawUpdate('''
        UPDATE bookmarks SET 
          id = article_id,
          title = COALESCE((SELECT title FROM articles WHERE id = bookmarks.article_id), 'Unknown Title'),
          url = COALESCE((SELECT url FROM articles WHERE id = bookmarks.article_id), ''),
          series_id = (SELECT series_id FROM articles WHERE id = bookmarks.article_id)
      ''');
      
      // Make article_id nullable (we can't change PK directly in SQLite, so rebuild)
      await db.execute('''
        CREATE TABLE bookmarks_new (
          id TEXT PRIMARY KEY,
          article_id TEXT,
          series_id TEXT,
          title TEXT NOT NULL,
          url TEXT NOT NULL,
          bookmarked_at INTEGER NOT NULL
        )
      ''');
      await db.rawInsert('''
        INSERT INTO bookmarks_new (id, article_id, series_id, title, url, bookmarked_at)
        SELECT id, article_id, series_id, title, url, bookmarked_at FROM bookmarks
      ''');
      await db.execute('DROP TABLE bookmarks');
      await db.execute('ALTER TABLE bookmarks_new RENAME TO bookmarks');
      
      // Add new columns to read_history
      await db.execute('ALTER TABLE read_history ADD COLUMN id TEXT');
      await db.execute('ALTER TABLE read_history ADD COLUMN series_id TEXT');
      await db.execute('ALTER TABLE read_history ADD COLUMN title TEXT');
      await db.execute('ALTER TABLE read_history ADD COLUMN url TEXT');
      
      // Migrate existing read_history: populate id, title, url from articles
      await db.rawUpdate('''
        UPDATE read_history SET 
          id = article_id,
          title = COALESCE((SELECT title FROM articles WHERE id = read_history.article_id), 'Unknown Title'),
          url = COALESCE((SELECT url FROM articles WHERE id = read_history.article_id), ''),
          series_id = (SELECT series_id FROM articles WHERE id = read_history.article_id)
      ''');
      
      // Rebuild read_history table with nullable article_id
      await db.execute('''
        CREATE TABLE read_history_new (
          id TEXT PRIMARY KEY,
          article_id TEXT,
          series_id TEXT,
          title TEXT NOT NULL,
          url TEXT NOT NULL,
          read_at INTEGER NOT NULL,
          is_completed INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.rawInsert('''
        INSERT INTO read_history_new (id, article_id, series_id, title, url, read_at, is_completed)
        SELECT id, article_id, series_id, title, url, read_at, is_completed FROM read_history
      ''');
      await db.execute('DROP TABLE read_history');
      await db.execute('ALTER TABLE read_history_new RENAME TO read_history');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE websites (
        id TEXT PRIMARY KEY,
        domain TEXT NOT NULL UNIQUE,
        custom_title TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE series (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        display_name TEXT,
        website_id TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE articles (
        id TEXT PRIMARY KEY,
        url TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        author TEXT,
        language TEXT NOT NULL DEFAULT 'en-US',
        estimated_read_time INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        prev_url TEXT,
        next_url TEXT,
        home_url TEXT,
        series_id TEXT
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

    await db.execute('''
      CREATE TABLE tts_voices (
        name TEXT PRIMARY KEY,
        lang_tag TEXT NOT NULL,
        locale TEXT NOT NULL,
        display_name TEXT NOT NULL,
        gender TEXT,
        quality TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE bookmarks (
        id TEXT PRIMARY KEY,
        article_id TEXT,
        series_id TEXT,
        title TEXT NOT NULL,
        url TEXT NOT NULL,
        bookmarked_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE read_history (
        id TEXT PRIMARY KEY,
        article_id TEXT,
        series_id TEXT,
        title TEXT NOT NULL,
        url TEXT NOT NULL,
        read_at INTEGER NOT NULL,
        is_completed INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }
}
