// journal-app/test/ai/gemini_reflection_service_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:journal_app/ai/gemini_reflection_service.dart';

void main() {
  test('reflect sends entry text and returns the generated question', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request as http.Request;
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'What part of the plan excites you most?'}
                ]
              }
            }
          ]
        }),
        200,
      );
    });

    final service = GeminiReflectionService(apiKey: 'test-key', httpClient: client);
    final question = await service.reflect('Started sketching the journal app today.');

    expect(question, 'What part of the plan excites you most?');
    expect(captured.url.queryParameters['key'], 'test-key');
    final body = jsonDecode(captured.body) as Map;
    final promptText =
        body['contents'][0]['parts'][0]['text'] as String;
    expect(promptText, contains('Started sketching the journal app today.'));
  });

  test('reflect throws on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('error', 500));
    final service = GeminiReflectionService(apiKey: 'test-key', httpClient: client);

    expect(() => service.reflect('anything'), throwsException);
  });
}
