import 'package:sqflite/sqflite.dart';
import 'package:webvox/data/database/app_database.dart';

class VoiceEntry {
  final String name;
  final String langTag;
  final String locale;
  final String displayName;
  final String? gender;
  final String? quality;

  const VoiceEntry({
    required this.name,
    required this.langTag,
    required this.locale,
    required this.displayName,
    this.gender,
    this.quality,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'lang_tag': langTag,
    'locale': locale,
    'display_name': displayName,
    'gender': gender,
    'quality': quality,
  };

  factory VoiceEntry.fromMap(Map<String, dynamic> map) => VoiceEntry(
    name: map['name'] as String,
    langTag: map['lang_tag'] as String,
    locale: map['locale'] as String,
    displayName: map['display_name'] as String,
    gender: map['gender'] as String?,
    quality: map['quality'] as String?,
  );
}

class VoiceDao {
  static VoiceDao? _instance;
  VoiceDao._();
  static VoiceDao get instance => _instance ??= VoiceDao._();

  Future<List<VoiceEntry>> getAll() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('tts_voices');
    return rows
        .map((r) => VoiceEntry.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<List<VoiceEntry>> getByLangCode(String langCode) async {
    final db = await AppDatabase.instance.database;
    // lang_tag starts with the lang code, e.g. 'en-US', 'en-GB' for langCode 'en'
    final rows = await db.query(
      'tts_voices',
      where: "lang_tag LIKE ?",
      whereArgs: ['$langCode-%'],
    );
    return rows
        .map((r) => VoiceEntry.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<void> upsert(VoiceEntry entry) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      'tts_voices',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteByName(String name) async {
    final db = await AppDatabase.instance.database;
    await db.delete('tts_voices', where: 'name = ?', whereArgs: [name]);
  }

  Future<Set<String>> getAllNames() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('tts_voices', columns: ['name']);
    return rows.map((r) => r['name'] as String).toSet();
  }

  /// Returns all display_name values for a given lang_tag + gender pair,
  /// used to avoid reusing a name when assigning a new voice.
  Future<Set<String>> getUsedDisplayNames(String langTag, String gender) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'tts_voices',
      columns: ['display_name'],
      where: 'lang_tag = ? AND gender = ?',
      whereArgs: [langTag, gender],
    );
    return rows.map((r) => r['display_name'] as String).toSet();
  }
}
