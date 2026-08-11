import 'dart:convert';
import 'package:http/http.dart' as http;

class GroqReflectionService {
  GroqReflectionService({required this.apiKey, http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final String apiKey;
  final http.Client _httpClient;

  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';

  // openai/gpt-oss-20b is Groq's recommended lightweight general-purpose
  // model -- more than enough for a single one-sentence reflective question,
  // and part of Groq's free tier.
  static const _model = 'openai/gpt-oss-20b';

  Future<String> reflect(String entryText) async {
    final uri = Uri.parse(_endpoint);
    final prompt =
        'You are a gentle journaling companion. In one short sentence, '
        'ask a single reflective follow-up question about this journal entry:\n\n$entryText';

    final response = await _httpClient.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Groq request failed: ${response.statusCode} ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map;
    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('Groq returned no choices');
    }
    final message = (choices.first as Map?)?['message'] as Map?;
    final content = message?['content'];
    if (content is! String) {
      throw Exception('Groq response missing content');
    }
    return content;
  }
}
