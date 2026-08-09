import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiReflectionService {
  GeminiReflectionService({required this.apiKey, http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final String apiKey;
  final http.Client _httpClient;

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  Future<String> reflect(String entryText) async {
    final uri = Uri.parse(_endpoint).replace(queryParameters: {'key': apiKey});
    final prompt =
        'You are a gentle journaling companion. In one short sentence, '
        'ask a single reflective follow-up question about this journal entry:\n\n$entryText';

    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ]
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Gemini request failed: ${response.statusCode} ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map;
    return decoded['candidates'][0]['content']['parts'][0]['text'] as String;
  }
}
