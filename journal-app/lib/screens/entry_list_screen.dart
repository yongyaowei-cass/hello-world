import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../data/entry_repository.dart';
import '../models/journal_entry.dart';

const _moodEmoji = {1: '😞', 2: '😕', 3: '😐', 4: '🙂', 5: '😄'};

enum SyncStatus { synced, syncing, offline }

const _syncIcons = {
  SyncStatus.synced: Icons.cloud_done,
  SyncStatus.syncing: Icons.cloud_sync,
  SyncStatus.offline: Icons.cloud_off,
};

class EntryListScreen extends StatelessWidget {
  const EntryListScreen({
    super.key,
    required this.repository,
    required this.onCreateEntry,
    required this.onOpenEntry,
    this.syncStatus,
  });

  final EntryRepository repository;
  final VoidCallback onCreateEntry;
  final void Function(JournalEntry) onOpenEntry;
  final ValueListenable<SyncStatus>? syncStatus;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal'),
        actions: [
          if (syncStatus != null)
            ValueListenableBuilder<SyncStatus>(
              valueListenable: syncStatus!,
              builder: (context, status, _) =>
                  Icon(_syncIcons[status], key: const Key('syncStatusIcon')),
            ),
        ],
      ),
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
