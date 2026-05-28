import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:webvox/data/database/voice_dao.dart';

/// Assigns human-readable display names to TTS voices and keeps them in sync
/// with the database.  Called once per app launch from [TtsAudioHandler].
class VoiceSyncService {
  static VoiceSyncService? _instance;
  VoiceSyncService._();
  static VoiceSyncService get instance => _instance ??= VoiceSyncService._();

  final _dao = VoiceDao.instance;

  // ── Name pools ────────────────────────────────────────────────────────────
  // Keyed by ISO-639-1 language code (first segment of lang tag, e.g. 'en').

  static const _femaleNames = <String, List<String>>{
    'en': [
      'Emma',
      'Olivia',
      'Sophia',
      'Ava',
      'Isabella',
      'Charlotte',
      'Amelia',
      'Grace',
      'Lily',
      'Chloe',
    ],
    'de': [
      'Mia',
      'Hannah',
      'Lena',
      'Sophie',
      'Anna',
      'Lea',
      'Clara',
      'Laura',
      'Nina',
      'Sarah',
    ],
    'fr': [
      'Léa',
      'Chloé',
      'Manon',
      'Camille',
      'Inès',
      'Lucie',
      'Jade',
      'Zoé',
      'Lola',
      'Alice',
    ],
    'pt': [
      'Maria',
      'Ana',
      'Beatriz',
      'Camila',
      'Juliana',
      'Gabriela',
      'Fernanda',
      'Larissa',
      'Carla',
      'Paula',
    ],
    'es': [
      'Isabella',
      'Valentina',
      'María',
      'Camila',
      'Lucía',
      'Sofía',
      'Carmen',
      'Elena',
      'Rosa',
      'Mónica',
    ],
    'it': [
      'Sofia',
      'Giulia',
      'Aurora',
      'Chiara',
      'Valentina',
      'Francesca',
      'Sara',
      'Martina',
      'Elisa',
      'Silvia',
    ],
    'ru': [
      'Anastasia',
      'Maria',
      'Natasha',
      'Olga',
      'Tatiana',
      'Elena',
      'Irina',
      'Svetlana',
      'Oksana',
      'Vera',
    ],
  };

  static const _maleNames = <String, List<String>>{
    'en': [
      'James',
      'William',
      'Oliver',
      'Benjamin',
      'Lucas',
      'Henry',
      'Alexander',
      'Mason',
      'Ethan',
      'Noah',
    ],
    'de': [
      'Luca',
      'Noah',
      'Felix',
      'Jonas',
      'Leon',
      'Max',
      'Elias',
      'Paul',
      'Finn',
      'Tim',
    ],
    'fr': [
      'Lucas',
      'Hugo',
      'Nathan',
      'Arthur',
      'Théo',
      'Louis',
      'Tom',
      'Raphaël',
      'Léo',
      'Simon',
    ],
    'pt': [
      'João',
      'Pedro',
      'Gabriel',
      'Lucas',
      'Miguel',
      'Rafael',
      'André',
      'Bruno',
      'Rodrigo',
      'Felipe',
    ],
    'es': [
      'Santiago',
      'Mateo',
      'Sebastián',
      'Nicolás',
      'Pablo',
      'Carlos',
      'Miguel',
      'Alejandro',
      'Diego',
      'Javier',
    ],
    'it': [
      'Francesco',
      'Leonardo',
      'Lorenzo',
      'Matteo',
      'Marco',
      'Giovanni',
      'Roberto',
      'Antonio',
      'Stefano',
      'Davide',
    ],
    'ru': [
      'Alexander',
      'Dmitri',
      'Ivan',
      'Mikhail',
      'Nikolai',
      'Pavel',
      'Sergei',
      'Vladimir',
      'Alexei',
      'Boris',
    ],
  };

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Parses a tab-separated "key=value\tkey=value" features string.
  static Map<String, String> _parseFeatures(String features) {
    final result = <String, String>{};
    for (final part in features.split('\t')) {
      final eq = part.indexOf('=');
      if (eq > 0) {
        result[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
      }
    }
    return result;
  }

  /// Extracts a normalised BCP-47 lang tag from a voice name.
  /// `en-US-SMTf00` → `en-US`, `de-DE-default` → `de-DE`.
  static String extractLangTag(String voiceName) {
    final parts = voiceName.split('-');
    if (parts.length >= 2) {
      return '${parts[0].toLowerCase()}-${parts[1].toUpperCase()}';
    }
    return voiceName;
  }

  /// Picks an unused first name from the language pool for the given gender.
  Future<String> _pickName(
    String langTag,
    String gender,
    Set<String> usedDisplayNames,
  ) async {
    final langCode = langTag.split('-').first.toLowerCase();
    final pool =
        gender == 'male'
            ? (_maleNames[langCode] ?? _maleNames['en']!)
            : (_femaleNames[langCode] ?? _femaleNames['en']!);

    final rng = Random();
    final available =
        pool.where((n) => !usedDisplayNames.contains('$n ($langTag)')).toList();

    if (available.isNotEmpty) {
      return available[rng.nextInt(available.length)];
    }
    // All names taken – append a numeric suffix.
    for (var i = 2; i <= 99; i++) {
      final candidate = '${pool.first} $i';
      if (!usedDisplayNames.contains('$candidate ($langTag)')) return candidate;
    }
    return pool.first;
  }

  /// Builds a display name for a voice with no gender data.
  /// `en-US-default` → `Default (en-US)`, `en-US-SMTf00` → `SMTf00 (en-US)`.
  static String buildDefaultDisplayName(String voiceName, String langTag) {
    final suffix =
        voiceName
            .substring(langTag.length)
            .replaceAll(RegExp(r'^-'), '')
            .toLowerCase();
    if (suffix == 'default' || suffix.isEmpty) return 'Default ($langTag)';
    return '$suffix ($langTag)';
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Syncs device voices with the database:
  /// - Inserts newly discovered voices (assigns display names).
  /// - Removes voices that are no longer present on the device.
  ///
  /// [deviceVoices] maps must contain at least `name`, `locale`, `features`,
  /// and `quality` keys (all values are strings).
  Future<void> sync(List<Map<String, String>> deviceVoices) async {
    try {
      final dbNames = await _dao.getAllNames();
      final deviceNames =
          deviceVoices
              .map((v) => v['name'] ?? '')
              .where((n) => n.isNotEmpty)
              .toSet();

      // ── Remove voices no longer on device ────────────────────────────────
      for (final name in dbNames) {
        if (!deviceNames.contains(name)) {
          await _dao.deleteByName(name);
          debugPrint('[WebVox][VoiceSync] Removed: $name');
        }
      }

      // ── Insert new voices ─────────────────────────────────────────────────
      for (final voice in deviceVoices) {
        final name = voice['name'] ?? '';
        if (name.isEmpty || dbNames.contains(name)) continue;

        final locale = voice['locale'] ?? '';
        final features = voice['features'] ?? '';
        final quality = voice['quality'];
        final langTag = extractLangTag(name);

        String? gender;
        if (features.isNotEmpty) {
          final featureMap = _parseFeatures(features);
          final rawGender = featureMap['gender'];
          if (rawGender == 'male' || rawGender == 'female') gender = rawGender;
        }

        String displayName;
        if (gender != null) {
          final used = await _dao.getUsedDisplayNames(langTag, gender);
          final firstName = await _pickName(langTag, gender, used);
          displayName = '$firstName ($langTag)';
        } else {
          displayName = buildDefaultDisplayName(name, langTag);
        }

        await _dao.upsert(
          VoiceEntry(
            name: name,
            langTag: langTag,
            locale: locale,
            displayName: displayName,
            gender: gender,
            quality: quality,
          ),
        );
        debugPrint('[WebVox][VoiceSync] Added: $name → $displayName');
      }
    } catch (e, st) {
      debugPrint('[WebVox][VoiceSync] sync failed: $e\n$st');
    }
  }

  /// Returns the display name for [voiceName], falling back to the raw name.
  Future<String> getDisplayName(String voiceName) async {
    if (voiceName.isEmpty) return '';
    try {
      final all = await _dao.getAll();
      final match = all.firstWhere(
        (e) => e.name == voiceName,
        orElse:
            () => VoiceEntry(
              name: voiceName,
              langTag: '',
              locale: '',
              displayName: voiceName,
            ),
      );
      return match.displayName;
    } catch (_) {
      return voiceName;
    }
  }
}
