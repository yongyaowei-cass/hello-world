import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/journal_entry.dart';
import 'package:journal_app/theme/entry_date_grouping.dart';

JournalEntry _entry(String id, DateTime createdAt) => JournalEntry(
      id: id,
      createdAt: createdAt,
      updatedAt: createdAt,
      text: 'entry $id',
    );

void main() {
  test('groups entries into Today, Yesterday, and formatted-date buckets', () {
    final now = DateTime(2026, 8, 11, 15, 0);
    final entries = [
      _entry('e1', DateTime(2026, 8, 11, 9, 0)),
      _entry('e2', DateTime(2026, 8, 10, 20, 0)),
      _entry('e3', DateTime(2026, 8, 3, 10, 0)),
    ];

    final groups = groupEntriesByDate(entries, now: now);

    expect(groups.map((g) => g.label), ['Today', 'Yesterday', 'Aug 3']);
    expect(groups[0].entries.map((e) => e.id), ['e1']);
    expect(groups[1].entries.map((e) => e.id), ['e2']);
    expect(groups[2].entries.map((e) => e.id), ['e3']);
  });

  test('groups multiple same-day entries under one label, preserving order', () {
    final now = DateTime(2026, 8, 11, 15, 0);
    final entries = [
      _entry('e1', DateTime(2026, 8, 11, 9, 0)),
      _entry('e2', DateTime(2026, 8, 11, 8, 0)),
    ];

    final groups = groupEntriesByDate(entries, now: now);

    expect(groups.length, 1);
    expect(groups[0].label, 'Today');
    expect(groups[0].entries.map((e) => e.id), ['e1', 'e2']);
  });

  test('returns an empty list for no entries', () {
    expect(groupEntriesByDate([], now: DateTime(2026, 8, 11)), isEmpty);
  });
}
