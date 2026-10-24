import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glean/core/db/seed_importer.dart';
import 'package:glean/features/ai/data/ai_repository.dart';

import '../../helpers/test_db.dart';

void main() {
  final seed = SeedBundle.fromJson(
    articlesJson: File('assets/seed/articles.json').readAsStringSync(),
    dictJson: File('assets/seed/dict.json').readAsStringSync(),
    aiJson: File('assets/seed/ai.json').readAsStringSync(),
  );

  test('every bundled article and remote article has valid AI aids', () {
    final remote = RegExp(
      r'"id": "([^"]+)"',
    ).allMatches(File('assets/seed/remote_pool.json').readAsStringSync());
    final ids = {
      for (final a in seed.articles) a['id'] as String,
      for (final m in remote) m.group(1)!,
    };
    expect(seed.ai.keys.toSet(), containsAll(ids));
    for (final entry in seed.ai.values) {
      final ai = entry as Map<String, dynamic>;
      expect(['A1', 'A2', 'B1', 'B2', 'C1', 'C2'], contains(ai['cefr']));
      final questions = ai['questions'] as List;
      expect(questions, hasLength(3));
      for (final q in questions.cast<Map<String, dynamic>>()) {
        expect(q['options'], hasLength(4));
        expect(q['answer'], inInclusiveRange(0, 3));
      }
    }
  });

  test('imported aids, quiz results and cached explanations', () async {
    final db = await openTestDb();
    await SeedImporter.importIfNeeded(db, seed);
    final repo = AiRepository(db, clock: FakeClock().call);

    final ai = (await repo.forArticle('daily-3-a'))!;
    expect(ai.summaryZh, isNotEmpty);
    expect(ai.keyPoints, isNotEmpty);
    expect(ai.questions, hasLength(3));
    expect(ai.model, 'deepseek-flash');
    expect(await repo.forArticle('no-such-article'), isNull);

    // Two right, one wrong; a retry replaces the result.
    final picks = [
      ai.questions[0].answer,
      ai.questions[1].answer,
      (ai.questions[2].answer + 1) % 4,
    ];
    await repo.saveResult('u1', 'daily-3-a', picks, ai.questions);
    expect((await repo.result('u1', 'daily-3-a'))!.correct, 2);
    await repo.saveResult('u1', 'daily-3-a', [
      for (final q in ai.questions) q.answer,
    ], ai.questions);
    final best = (await repo.result('u1', 'daily-3-a'))!;
    expect((best.correct, best.total), (3, 3));
    expect(await repo.result('u2', 'daily-3-a'), isNull);

    const sentence = 'The effect is usually temporary.';
    expect(await repo.cachedExplanation('temporary', sentence), isNull);
    await repo.saveExplanation('temporary', sentence, {
      'meaning_zh': '暂时的',
    }, 'deepseek-flash');
    expect(
      await repo.cachedExplanation('temporary', ' $sentence '),
      {'meaning_zh': '暂时的'},
      reason: 'keyed by the trimmed sentence',
    );
  });
}
