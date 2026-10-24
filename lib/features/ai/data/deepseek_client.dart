import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Why a live AI request did not produce an answer.
class AiException implements Exception {
  const AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sends a JSON body to [uri] and returns (status code, response body).
typedef JsonPost =
    Future<(int, String)> Function(
      Uri uri,
      Map<String, String> headers,
      String body,
    );

/// Live calls to DeepSeek's chat API (OpenAI-compatible), used for the
/// word panel's AI 解释. Everything else AI in the app is generated ahead
/// of time (tool/ai_enrich.py) and works offline.
///
/// The key comes from the build (`--dart-define=DEEPSEEK_API_KEY=...`), so
/// it is never in the repository. A key shipped inside an app can be
/// extracted; a production app would call its own backend, which holds the
/// key and rate-limits per user (see README).
class DeepSeekClient {
  DeepSeekClient({required this.apiKey, JsonPost? post})
    : _post = post ?? _httpPost;

  final String apiKey;
  final JsonPost _post;

  static const keyFromBuild = String.fromEnvironment('DEEPSEEK_API_KEY');
  static const model = 'deepseek-flash';
  static final endpoint = Uri.parse(
    'https://api.deepseek.com/chat/completions',
  );
  static const timeout = Duration(seconds: 25);

  static const _explainSystem = '''
You explain one English word to a Chinese learner, in the sentence where
they met it. Reply with one JSON object and nothing else:
{
  "meaning_zh": "这个词在本句中的意思（简短，10 字以内）",
  "explain_zh": "1-2 句中文说明：为什么在这里是这个意思，它在句中的作用",
  "collocations": ["常见搭配 —— 中文", "最多三条"],
  "example_en": "one new, simple example sentence using the word the same way",
  "example_zh": "例句译文"
}''';

  /// Explains [word] as used in [sentence]. Throws [AiException].
  Future<Map<String, dynamic>> explainWord({
    required String word,
    required String sentence,
    String? articleTitle,
  }) async {
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': _explainSystem},
        {
          'role': 'user',
          'content': [
            'Word: $word',
            'Sentence: $sentence',
            if (articleTitle != null) 'Article: $articleTitle',
          ].join('\n'),
        },
      ],
      'response_format': {'type': 'json_object'},
      'max_tokens': 800,
    });
    final (int, String) response;
    try {
      response = await _post(endpoint, {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      }, body).timeout(timeout);
    } on TimeoutException {
      throw const AiException('AI 响应超时，稍后再试');
    } on SocketException {
      throw const AiException('网络不可用，联网后再试');
    } on HttpException {
      throw const AiException('网络请求失败，稍后再试');
    }
    final (status, text) = response;
    if (status == 401) throw const AiException('AI 密钥无效');
    if (status == 402) throw const AiException('AI 账户余额不足');
    if (status == 429) throw const AiException('请求太频繁，稍后再试');
    if (status != 200) throw AiException('AI 服务出错（$status）');
    try {
      final data = jsonDecode(text) as Map<String, dynamic>;
      final content =
          ((data['choices'] as List).first as Map)['message']['content']
              as String;
      final result = jsonDecode(content) as Map<String, dynamic>;
      if (result['meaning_zh'] is! String) throw const FormatException();
      return result;
    } on Object {
      throw const AiException('AI 返回的内容无法解析');
    }
  }

  static Future<(int, String)> _httpPost(
    Uri uri,
    Map<String, String> headers,
    String body,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.postUrl(uri);
      headers.forEach(req.headers.set);
      req.add(utf8.encode(body));
      final res = await req.close();
      return (res.statusCode, await res.transform(utf8.decoder).join());
    } finally {
      client.close();
    }
  }
}
