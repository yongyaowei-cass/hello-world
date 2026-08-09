import 'package:flutter/material.dart';
import '../data/entry_repository.dart';
import '../models/journal_entry.dart';

const _moodEmoji = {1: '😞', 2: '😕', 3: '😐', 4: '🙂', 5: '😄'};

class EntryDetailScreen extends StatelessWidget {
  const EntryDetailScreen({
    super.key,
    required this.repository,
    required this.entry,
    required this.onEdit,
    required this.onDeleted,
  });

  final EntryRepository repository;
  final JournalEntry entry;
  final void Function(JournalEntry) onEdit;
  final VoidCallback onDeleted;

  Future<void> _delete() async {
    await repository.softDelete(entry.id);
    onDeleted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: () => onEdit(entry)),
          IconButton(icon: const Icon(Icons.delete), onPressed: _delete),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.mood != null)
              Text(_moodEmoji[entry.mood]!, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 8),
            Text(entry.text),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [for (final tag in entry.tags) Chip(label: Text(tag))],
            ),
          ],
        ),
      ),
    );
  }
}
