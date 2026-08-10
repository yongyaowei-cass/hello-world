import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../ai/gemini_reflection_service.dart';
import '../data/entry_repository.dart';
import '../data/photo_repository.dart';
import '../models/journal_entry.dart';
import '../photos/photo_bytes_store.dart';

const _moodEmoji = {1: '😞', 2: '😕', 3: '😐', 4: '🙂', 5: '😄'};

class EntryDetailScreen extends StatefulWidget {
  const EntryDetailScreen({
    super.key,
    required this.repository,
    required this.photoRepository,
    required this.entry,
    required this.onEdit,
    required this.onDeleted,
    this.reflectionService,
  });

  final EntryRepository repository;
  final PhotoRepository photoRepository;
  final JournalEntry entry;
  final void Function(JournalEntry) onEdit;
  final VoidCallback onDeleted;
  final GeminiReflectionService? reflectionService;

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  bool _loadingReflection = false;

  // Re-reads the entry from the repository on every rebuild (this State is
  // rebuilt via the ValueListenableBuilder below whenever the box changes,
  // e.g. after the editor screen pops back here having saved an edit) so the
  // screen never shows stale, pre-edit content. Falls back to widget.entry
  // if the id somehow isn't present (e.g. mid-transition).
  JournalEntry _currentEntry() => widget.repository.getById(widget.entry.id) ?? widget.entry;

  Future<void> _delete() async {
    await widget.repository.softDelete(widget.entry.id);
    widget.onDeleted();
  }

  Future<void> _reflect(JournalEntry entry) async {
    final service = widget.reflectionService;
    if (service == null) return;
    setState(() => _loadingReflection = true);
    try {
      final question = await service.reflect(entry.text);
      final updated = entry.copyWith(
        aiReflectionQuestion: question,
        updatedAt: DateTime.now(),
      );
      await widget.repository.save(updated);
      if (!mounted) return;
      setState(() => _loadingReflection = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingReflection = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get a reflection right now. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: widget.repository.listenable(),
      builder: (context, box, _) {
        final entry = _currentEntry();
        return Scaffold(
          appBar: AppBar(
            leading: const BackButton(),
            actions: [
              IconButton(icon: const Icon(Icons.edit), onPressed: () => widget.onEdit(entry)),
              IconButton(icon: const Icon(Icons.delete), onPressed: _delete),
            ],
          ),
          body: SingleChildScrollView(
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
                Wrap(
                  spacing: 8,
                  children: [
                    for (final id in entry.photoIds)
                      if (widget.photoRepository.getById(id)?.localPath != null)
                        SizedBox(
                          key: Key('photo-$id'),
                          width: 64,
                          height: 64,
                          child: buildLocalPhotoThumbnail(
                            widget.photoRepository.getById(id)!.localPath!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const ColoredBox(color: Colors.black12),
                          ),
                        ),
                  ],
                ),
                const SizedBox(height: 16),
                if (widget.reflectionService != null && entry.aiReflectionQuestion == null)
                  OutlinedButton(
                    onPressed: _loadingReflection ? null : () => _reflect(entry),
                    child: Text(_loadingReflection ? 'Reflecting...' : 'Reflect'),
                  ),
                if (entry.aiReflectionQuestion != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(entry.aiReflectionQuestion!),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
