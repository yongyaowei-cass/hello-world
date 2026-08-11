import 'package:intl/intl.dart';
import '../models/journal_entry.dart';

class EntryGroup {
  const EntryGroup({required this.label, required this.entries});

  final String label;
  final List<JournalEntry> entries;
}

List<EntryGroup> groupEntriesByDate(List<JournalEntry> entries, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  final yesterday = today.subtract(const Duration(days: 1));

  final byLabel = <String, List<JournalEntry>>{};
  final labelOrder = <String>[];

  for (final entry in entries) {
    final entryDate = _dateOnly(entry.createdAt.toLocal());
    final String label;
    if (entryDate == today) {
      label = 'Today';
    } else if (entryDate == yesterday) {
      label = 'Yesterday';
    } else {
      label = DateFormat('MMM d').format(entryDate);
    }

    if (!byLabel.containsKey(label)) {
      byLabel[label] = [];
      labelOrder.add(label);
    }
    byLabel[label]!.add(entry);
  }

  return [for (final label in labelOrder) EntryGroup(label: label, entries: byLabel[label]!)];
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
