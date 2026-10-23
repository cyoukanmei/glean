import 'dart:math';

/// Conflict rules shared by the mock server and the client, so both sides
/// converge to the same row whatever order changes arrive in.
///
/// Reading progress merges field by field (commutative):
/// * `max_progress` and `status` only grow; `finished_at` keeps the first;
/// * the reading position (offset, anchor, font scale, current progress)
///   follows the most recent read (`last_read_at`, ties go to [incoming]).
///
/// Vocabulary is last-write-wins on `updated_at` for the whole record, with
/// deletes kept as tombstones (`deleted_at`), so a delete on one device and
/// an edit on another resolve to whichever happened later.
abstract final class SyncMerge {
  static const positionFields = [
    'scroll_offset',
    'anchor_para',
    'anchor_delta',
    'font_scale',
    'progress',
  ];

  static Map<String, Object?> progress(
    Map<String, Object?> current,
    Map<String, Object?> incoming,
  ) {
    final newer =
        (incoming['last_read_at']! as int) >= (current['last_read_at']! as int);
    final finishedA = current['finished_at'] as int?;
    final finishedB = incoming['finished_at'] as int?;
    return {
      for (final f in positionFields) f: (newer ? incoming : current)[f],
      'max_progress': max(
        (current['max_progress']! as num).toDouble(),
        (incoming['max_progress']! as num).toDouble(),
      ),
      'status': max(current['status']! as int, incoming['status']! as int),
      'finished_at': finishedA == null
          ? finishedB
          : finishedB == null
          ? finishedA
          : min(finishedA, finishedB),
      'last_read_at': max(
        current['last_read_at']! as int,
        incoming['last_read_at']! as int,
      ),
      'updated_at': max(
        current['updated_at']! as int,
        incoming['updated_at']! as int,
      ),
    };
  }

  /// True when [incoming] wins over [current] for a vocabulary record.
  static bool vocabWins(
    Map<String, Object?> current,
    Map<String, Object?> incoming,
  ) => (incoming['updated_at']! as int) >= (current['updated_at']! as int);

  /// Field-wise equality of two payloads (for "did anything change").
  static bool same(Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length && a.keys.every((k) => a[k] == b[k]);
}
