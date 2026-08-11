import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:journal_app/ai/groq_reflection_service.dart';

void main() {
  test('reflect sends entry text and returns the generated question', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request as http.Request;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': 'What part of the plan excites you most?',
              }
            }
          ]
        }),
        200,
      );
    });

    final service = GroqReflectionService(apiKey: 'test-key', httpClient: client);
    final question = await service.reflect('Started sketching the journal app today.');

    expect(question, 'What part of the plan excites you most?');
    expect(captured.headers['Authorization'], 'Bearer test-key');
    final body = jsonDecode(captured.body) as Map;
    expect(body['model'], isNotEmpty);
    final promptText = body['messages'][0]['content'] as String;
    expect(promptText, contains('Started sketching the journal app today.'));
  });

  test('reflect throws on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('error', 500));
    final service = GroqReflectionService(apiKey: 'test-key', httpClient: client);

    expect(() => service.reflect('anything'), throwsException);
  });

  test('reflect throws a clear error when Groq returns an empty choices list', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'choices': <Object?>[]}), 200);
    });
    final service = GroqReflectionService(apiKey: 'test-key', httpClient: client);

    expect(
      () => service.reflect('anything'),
      throwsA(isA<Exception>().having(
        (e) => e.toString(),
        'message',
        contains('no choices'),
      )),
    );
  });

  test('reflect throws a clear error when a choice has no message content', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'choices': [
            {'message': <String, Object?>{}}
          ]
        }),
        200,
      );
    });
    final service = GroqReflectionService(apiKey: 'test-key', httpClient: client);

    expect(
      () => service.reflect('anything'),
      throwsA(isA<Exception>().having(
        (e) => e.toString(),
        'message',
        contains('missing content'),
      )),
    );
  });
}
