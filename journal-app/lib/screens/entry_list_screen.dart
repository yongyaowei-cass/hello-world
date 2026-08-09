import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../data/entry_repository.dart';
import '../models/journal_entry.dart';

const _moodEmoji = {1: '😞', 2: '😕', 3: '😐', 4: '🙂', 5: '😄'};

class EntryListScreen extends StatelessWidget {
  const EntryListScreen({
    super.key,
    required this.repository,
    required this.onCreateEntry,
    required this.onOpenEntry,
  });

  final EntryRepository repository;
  final VoidCallback onCreateEntry;
  final void Function(JournalEntry) onOpenEntry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Journal')),
      body: ValueListenableBuilder<Box>(
        valueListenable: repository.listenable(),
        builder: (context, box, _) {
          final entries = repository.getAll();
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                leading: Text(
                  _moodEmoji[entry.mood] ?? '',
                  style: const TextStyle(fontSize: 20),
                ),
                title: Text(
                  entry.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: entry.tags.isEmpty ? null : Text(entry.tags.join(', ')),
                onTap: () => onOpenEntry(entry),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: onCreateEntry,
        child: const Icon(Icons.add),
      ),
    );
  }
}
