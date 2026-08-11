import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiReflectionService {
  GeminiReflectionService({required this.apiKey, http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final String apiKey;
  final http.Client _httpClient;

  // gemini-flash-latest is a stable alias Google maintains to always point
  // at their current recommended flash model, rather than a pinned version
  // (e.g. gemini-2.5-flash) that eventually gets deprecated for new API
  // keys/callers and starts returning 404s.
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent';

  Future<String> reflect(String entryText) async {
    final uri = Uri.parse(_endpoint);
    final prompt =
        'You are a gentle journaling companion. In one short sentence, '
        'ask a single reflective follow-up question about this journal entry:\n\n$entryText';

    final response = await _httpClient.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        // Google's newer "auth key" API keys (the default for keys created
        // via Google AI Studio since 2026) are rejected with API_KEY_INVALID
        // when passed as the legacy `?key=` query parameter -- the header is
        // both the currently-documented approach and the only one these
        // newer keys actually accept. Classic keys accept the header too, so
        // this isn't a platform/key-type branch, just always use the header.
        'x-goog-api-key': apiKey,
      },
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
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini returned no candidates (the response may have been safety-blocked)');
    }
    final content = (candidates.first as Map?)?['content'] as Map?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) {
      throw Exception('Gemini response missing content');
    }
    final text = (parts.first as Map?)?['text'];
    if (text is! String) {
      throw Exception('Gemini response missing content');
    }
    return text;
  }
}
