import 'package:sqflite/sqflite.dart';

class DictEntry {
  const DictEntry({
    required this.word,
    required this.lemma,
    required this.phonetic,
    required this.definition,
  });

  /// The word as it was looked up, lower-cased.
  final String word;

  /// Dictionary headword; differs from [word] for inflections ("bought").
  final String lemma;
  final String? phonetic;
  final String definition;
}

class DictionaryRepository {
  DictionaryRepository(this._db);

  final DatabaseExecutor _db;

  /// Looks up [raw] by its base form first ("running" -> "run"), then as-is.
  Future<DictEntry?> lookup(String raw) async {
    final word = raw.trim().toLowerCase();
    if (word.isEmpty) return null;

    final forms = await _db.query(
      'word_forms',
      columns: ['lemma'],
      where: 'form = ?',
      whereArgs: [word],
    );
    final candidates = [
      if (forms.isNotEmpty) forms.first['lemma']! as String,
      word,
    ];
    for (final lemma in candidates) {
      final rows = await _db.query(
        'dict',
        where: 'word = ?',
        whereArgs: [lemma],
      );
      if (rows.isNotEmpty) {
        final r = rows.first;
        return DictEntry(
          word: word,
          lemma: lemma,
          phonetic: r['phonetic'] as String?,
          definition: r['definition']! as String,
        );
      }
    }
    return null;
  }
}
