import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glean/features/ai/data/deepseek_client.dart';
import 'package:http/http.dart' as http;

String _reply(Object content) => jsonEncode({
  'choices': [
    {
      'message': {'content': content is String ? content : jsonEncode(content)},
    },
  ],
});

void main() {
  test('sends the word and sentence, returns the parsed JSON', () async {
    late Map<String, dynamic> sent;
    late Map<String, String> headers;
    final client = DeepSeekClient(
      apiKey: 'k',
      post: (uri, h, body) async {
        headers = h;
        sent = jsonDecode(body) as Map<String, dynamic>;
        return (200, _reply({'meaning_zh': '暂时的', 'explain_zh': '修饰 effect'}));
      },
    );
    final r = await client.explainWord(
      word: 'temporary',
      sentence: 'The effect is usually temporary.',
    );
    expect(r['meaning_zh'], '暂时的');
    expect(headers['Authorization'], 'Bearer k');
    expect(sent['model'], DeepSeekClient.model);
    expect(sent['response_format'], {'type': 'json_object'});
    final user = (sent['messages'] as List).last['content'] as String;
    expect(user, contains('Word: temporary'));
    expect(user, contains('Sentence: The effect is usually temporary.'));
  });

  test('maps failures to readable messages', () async {
    Future<String> fail(Future<(int, String)> Function() post) async {
      final client = DeepSeekClient(apiKey: 'k', post: (_, _, _) => post());
      try {
        await client.explainWord(word: 'w', sentence: 's');
        return 'no error';
      } on AiException catch (e) {
        return e.message;
      }
    }

    expect(await fail(() async => (401, '')), 'AI 密钥无效');
    expect(await fail(() async => (402, '')), 'AI 账户余额不足');
    expect(await fail(() async => (500, '')), 'AI 服务出错（500）');
    expect(await fail(() async => (200, _reply('not json'))), 'AI 返回的内容无法解析');
    expect(await fail(() async => (200, _reply({'other': 1}))), 'AI 返回的内容无法解析');
    expect(
      await fail(() async => throw http.ClientException('down')),
      '网络不可用，联网后再试',
    );
  });
}
