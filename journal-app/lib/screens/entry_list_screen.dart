import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../data/entry_repository.dart';
import '../models/journal_entry.dart';
import '../theme/app_theme.dart';
import '../theme/entry_date_grouping.dart';

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
          final groups = groupEntriesByDate(repository.getAll());
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final group in groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    group.label,
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.8,
                      color: group.label == 'Today'
                          ? AppColors.dateGroupLabelToday
                          : AppColors.dateGroupLabelOlder,
                    ),
                  ),
                ),
                for (final entry in group.entries) _EntryCard(entry: entry, onTap: onOpenEntry),
              ],
            ],
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

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.onTap});

  final JournalEntry entry;
  final void Function(JournalEntry) onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Material(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onTap(entry),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_moodEmoji[entry.mood] ?? '', style: const TextStyle(fontSize: 19)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: journalTextStyle.copyWith(fontSize: 14),
                      ),
                      if (entry.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final tag in entry.tags)
                              Chip(label: Text(tag), visualDensity: VisualDensity.compact),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
