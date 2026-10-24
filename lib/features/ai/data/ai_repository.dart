import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/clock.dart';

/// One multiple-choice comprehension question.
class QuizQuestion {
  const QuizQuestion({
    required this.type,
    required this.question,
    required this.options,
    required this.answer,
    required this.explainZh,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> j) => QuizQuestion(
    type: j['type'] as String? ?? '',
    question: j['q'] as String,
    options: (j['options'] as List).cast<String>(),
    answer: j['answer'] as int,
    explainZh: j['explain_zh'] as String? ?? '',
  );

  /// main_idea / detail / inference.
  final String type;
  final String question;
  final List<String> options;

  /// Index of the correct option.
  final int answer;
  final String explainZh;

  String get typeLabel => switch (type) {
    'main_idea' => '主旨',
    'detail' => '细节',
    'inference' => '推断',
    _ => '理解',
  };
}

/// The bundled AI reading aids of one article.
class ArticleAi {
  const ArticleAi({
    required this.summaryZh,
    required this.keyPoints,
    required this.cefr,
    required this.cefrReason,
    required this.questions,
    this.model,
  });

  final String summaryZh;
  final List<String> keyPoints;

  /// CEFR level, A1-C2.
  final String cefr;
  final String cefrReason;
  final List<QuizQuestion> questions;

  /// Model that generated it, for attribution ("由 deepseek-flash 生成").
  final String? model;
}

/// The user's answers to one article's quiz.
class QuizResult {
  const QuizResult({
    required this.correct,
    required this.total,
    required this.answers,
    required this.finishedAt,
  });

  final int correct;
  final int total;
  final List<int> answers;
  final int finishedAt;
}

/// AI aids (read-only, from the seed), quiz results (per user) and cached
/// live word explanations.
class AiRepository {
  AiRepository(this._db, {this._clock = systemClock});

  final DatabaseExecutor _db;
  final Clock _clock;

  Future<ArticleAi?> forArticle(String articleId) async {
    final rows = await _db.query(
      'article_ai',
      where: 'article_id = ?',
      whereArgs: [articleId],
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return ArticleAi(
      summaryZh: r['summary_zh']! as String,
      keyPoints: (jsonDecode(r['key_points']! as String) as List)
          .cast<String>(),
      cefr: r['cefr']! as String,
      cefrReason: r['cefr_reason'] as String? ?? '',
      questions: [
        for (final q in jsonDecode(r['questions']! as String) as List)
          QuizQuestion.fromJson(q as Map<String, dynamic>),
      ],
      model: r['model'] as String?,
    );
  }

  Future<QuizResult?> result(String userId, String articleId) async {
    final rows = await _db.query(
      'quiz_results',
      where: 'user_id = ? AND article_id = ?',
      whereArgs: [userId, articleId],
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return QuizResult(
      correct: r['correct']! as int,
      total: r['total']! as int,
      answers: (jsonDecode(r['answers']! as String) as List).cast<int>(),
      finishedAt: r['finished_at']! as int,
    );
  }

  /// Keeps the latest attempt (idempotent per user and article).
  Future<void> saveResult(
    String userId,
    String articleId,
    List<int> answers,
    List<QuizQuestion> questions,
  ) {
    var correct = 0;
    for (final (i, q) in questions.indexed) {
      if (i < answers.length && answers[i] == q.answer) correct++;
    }
    return _db.rawInsert(
      '''
      INSERT OR REPLACE INTO quiz_results (user_id, article_id, correct,
        total, answers, finished_at)
      VALUES (?, ?, ?, ?, ?, ?)''',
      [
        userId,
        articleId,
        correct,
        questions.length,
        jsonEncode(answers),
        _clock(),
      ],
    );
  }

  static String sentenceHash(String sentence) =>
      sha1.convert(utf8.encode(sentence.trim())).toString().substring(0, 16);

  Future<Map<String, dynamic>?> cachedExplanation(
    String lemma,
    String sentence,
  ) async {
    final rows = await _db.query(
      'ai_explanations',
      columns: ['body'],
      where: 'lemma = ? AND sentence_hash = ?',
      whereArgs: [lemma, sentenceHash(sentence)],
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.single['body']! as String) as Map<String, dynamic>;
  }

  Future<void> saveExplanation(
    String lemma,
    String sentence,
    Map<String, dynamic> body,
    String model,
  ) => _db.rawInsert(
    '''
    INSERT OR REPLACE INTO ai_explanations (lemma, sentence_hash, body,
      model, created_at)
    VALUES (?, ?, ?, ?, ?)''',
    [lemma, sentenceHash(sentence), jsonEncode(body), model, _clock()],
  );
}
