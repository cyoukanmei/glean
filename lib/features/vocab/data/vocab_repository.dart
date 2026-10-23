import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/clock.dart';

/// Where in an article a word was collected, so the word list can jump back.
class WordSource {
  const WordSource({
    required this.articleId,
    required this.paraIndex,
    required this.charStart,
    required this.charEnd,
    this.sentence,
  });

  final String articleId;
  final int paraIndex;
  final int charStart;
  final int charEnd;
  final String? sentence;
}

class VocabItem {
  const VocabItem({
    required this.id,
    required this.word,
    required this.lemma,
    required this.definition,
    required this.source,
    required this.status,
    required this.createdAt,
    this.articleTitle,
  });

  factory VocabItem.fromRow(Map<String, Object?> row) => VocabItem(
    articleTitle: row['article_title'] as String?,
    id: row['id']! as String,
    word: row['word']! as String,
    lemma: row['lemma']! as String,
    definition: row['definition']! as String,
    source: WordSource(
      articleId: row['article_id']! as String,
      paraIndex: row['para_index']! as int,
      charStart: row['char_start']! as int,
      charEnd: row['char_end']! as int,
      sentence: row['sentence'] as String?,
    ),
    status: row['status']! as int,
    createdAt: row['created_at']! as int,
  );

  final String id;
  final String word;
  final String lemma;
  final String definition;
  final WordSource source;
  final int status;
  final int createdAt;

  /// Title of the source article, when listed with [VocabRepository.list].
  final String? articleTitle;
}

class VocabRepository {
  VocabRepository(this._db, {this._clock = systemClock, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final DatabaseExecutor _db;
  final Clock _clock;
  final Uuid _uuid;

  /// Adds a word to the user's list, keyed by (user, lemma).
  ///
  /// Collecting a word that is already in the list changes nothing (the first
  /// source is kept). Collecting a deleted word revives the same row with the
  /// new source, so ids stay stable across delete / re-collect.
  Future<void> collect({
    required String userId,
    required String word,
    required String lemma,
    required String definition,
    required WordSource source,
  }) {
    final now = _clock();
    return _db.rawInsert(
      '''
      INSERT INTO vocab (id, user_id, word, lemma, definition, article_id,
        para_index, char_start, char_end, sentence, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(user_id, lemma) DO UPDATE SET
        word = excluded.word, definition = excluded.definition,
        article_id = excluded.article_id, para_index = excluded.para_index,
        char_start = excluded.char_start, char_end = excluded.char_end,
        sentence = excluded.sentence, created_at = excluded.created_at,
        deleted_at = NULL, dirty = 1, updated_at = excluded.updated_at
      WHERE vocab.deleted_at IS NOT NULL''',
      [
        _uuid.v4(),
        userId,
        word,
        lemma,
        definition,
        source.articleId,
        source.paraIndex,
        source.charStart,
        source.charEnd,
        source.sentence,
        now,
        now,
      ],
    );
  }

  /// Soft delete: keeps a tombstone so a later sync can propagate it.
  Future<void> delete(String id) {
    final now = _clock();
    return _db.rawUpdate(
      'UPDATE vocab SET deleted_at = ?, dirty = 1, updated_at = ? '
      'WHERE id = ? AND deleted_at IS NULL',
      [now, now, id],
    );
  }

  /// Undo for [delete], keeping the original source and timestamps.
  Future<void> restore(String id) {
    return _db.rawUpdate(
      'UPDATE vocab SET deleted_at = NULL, dirty = 1, updated_at = ? '
      'WHERE id = ? AND deleted_at IS NOT NULL',
      [_clock(), id],
    );
  }

  Future<bool> isCollected(String userId, String lemma) async {
    final rows = await _db.query(
      'vocab',
      columns: ['id'],
      where: 'user_id = ? AND lemma = ? AND deleted_at IS NULL',
      whereArgs: [userId, lemma],
    );
    return rows.isNotEmpty;
  }

  /// The active entry for [lemma], if collected.
  Future<VocabItem?> find(String userId, String lemma) async {
    final rows = await _db.query(
      'vocab',
      where: 'user_id = ? AND lemma = ? AND deleted_at IS NULL',
      whereArgs: [userId, lemma],
    );
    return rows.isEmpty ? null : VocabItem.fromRow(rows.single);
  }

  /// Newest first, with the source article's title for display.
  Future<List<VocabItem>> list(String userId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT v.*, a.title AS article_title
      FROM vocab v LEFT JOIN articles a ON a.id = v.article_id
      WHERE v.user_id = ? AND v.deleted_at IS NULL
      ORDER BY v.created_at DESC''',
      [userId],
    );
    return rows.map(VocabItem.fromRow).toList();
  }

  /// Lower-cased surface forms and headwords of every collected word, so the
  /// reader can mark them in any article ("you saved this one").
  Future<Set<String>> collectedForms(String userId) async {
    final rows = await _db.query(
      'vocab',
      columns: ['word', 'lemma'],
      where: 'user_id = ? AND deleted_at IS NULL',
      whereArgs: [userId],
    );
    return {
      for (final r in rows) ...[
        (r['word']! as String).toLowerCase(),
        (r['lemma']! as String).toLowerCase(),
      ],
    };
  }
}
