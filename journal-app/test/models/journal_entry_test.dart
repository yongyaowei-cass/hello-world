import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/journal_entry.dart';

void main() {
  group('JournalEntry', () {
    test('toJson/fromJson round-trips all fields', () {
      final entry = JournalEntry(
        id: 'e1',
        createdAt: DateTime.utc(2026, 8, 9, 9, 40),
        updatedAt: DateTime.utc(2026, 8, 9, 9, 41),
        text: 'Started sketching the journal app today.',
        mood: 4,
        tags: const ['planning', 'work'],
        photoIds: const ['p1'],
        aiReflectionQuestion: 'What excites you most?',
        deleted: false,
      );

      final restored = JournalEntry.fromJson(entry.toJson());

      expect(restored.id, entry.id);
      expect(restored.createdAt, entry.createdAt);
      expect(restored.updatedAt, entry.updatedAt);
      expect(restored.text, entry.text);
      expect(restored.mood, entry.mood);
      expect(restored.tags, entry.tags);
      expect(restored.photoIds, entry.photoIds);
      expect(restored.aiReflectionQuestion, entry.aiReflectionQuestion);
      expect(restored.deleted, entry.deleted);
    });

    test('fromJson defaults missing optional fields', () {
      final restored = JournalEntry.fromJson({
        'id': 'e2',
        'createdAt': '2026-08-09T09:40:00.000Z',
        'updatedAt': '2026-08-09T09:40:00.000Z',
        'text': 'No mood, no tags, no photos yet.',
      });

      expect(restored.mood, isNull);
      expect(restored.tags, isEmpty);
      expect(restored.photoIds, isEmpty);
      expect(restored.aiReflectionQuestion, isNull);
      expect(restored.deleted, isFalse);
    });

    test('toJson serializes DateTimes as UTC even when constructed from local time', () {
      // Not .utc -- a plain local-time DateTime, the same shape DateTime.now()
      // produces. Without .toUtc() before .toIso8601String(), this string
      // would carry no Z/offset suffix and another device in a different
      // timezone would misparse it as its OWN local time, corrupting the
      // last-write-wins comparison in SyncService.
      final localCreatedAt = DateTime(2026, 8, 9, 9, 40);
      final localUpdatedAt = DateTime(2026, 8, 9, 9, 41);
      final entry = JournalEntry(
        id: 'e1',
        createdAt: localCreatedAt,
        updatedAt: localUpdatedAt,
        text: 'local time entry',
      );

      final json = entry.toJson();

      bool isUtcIso8601(String s) => s.endsWith('Z') || s.contains('+00:00');
      expect(isUtcIso8601(json['createdAt'] as String), isTrue,
          reason: 'createdAt "${json['createdAt']}" is missing a UTC indicator');
      expect(isUtcIso8601(json['updatedAt'] as String), isTrue,
          reason: 'updatedAt "${json['updatedAt']}" is missing a UTC indicator');

      // And it round-trips to the same instant regardless of which timezone
      // parses it back.
      final restored = JournalEntry.fromJson(json);
      expect(restored.createdAt.toUtc(), localCreatedAt.toUtc());
      expect(restored.updatedAt.toUtc(), localUpdatedAt.toUtc());
    });

    test('copyWith overrides only the given fields', () {
      final entry = JournalEntry(
        id: 'e1',
        createdAt: DateTime.utc(2026, 8, 9),
        updatedAt: DateTime.utc(2026, 8, 9),
        text: 'original',
      );

      final updated = entry.copyWith(text: 'edited', mood: 5);

      expect(updated.id, entry.id);
      expect(updated.text, 'edited');
      expect(updated.mood, 5);
    });
  });
}
