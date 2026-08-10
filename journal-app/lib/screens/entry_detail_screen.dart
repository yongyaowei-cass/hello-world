import 'package:flutter/material.dart';
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
  late JournalEntry _entry;
  bool _loadingReflection = false;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
  }

  Future<void> _delete() async {
    await widget.repository.softDelete(_entry.id);
    widget.onDeleted();
  }

  Future<void> _reflect() async {
    final service = widget.reflectionService;
    if (service == null) return;
    setState(() => _loadingReflection = true);
    final question = await service.reflect(_entry.text);
    final updated = _entry.copyWith(
      aiReflectionQuestion: question,
      updatedAt: DateTime.now(),
    );
    await widget.repository.save(updated);
    setState(() {
      _entry = updated;
      _loadingReflection = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: () => widget.onEdit(_entry)),
          IconButton(icon: const Icon(Icons.delete), onPressed: _delete),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_entry.mood != null)
              Text(_moodEmoji[_entry.mood]!, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 8),
            Text(_entry.text),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [for (final tag in _entry.tags) Chip(label: Text(tag))],
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final id in _entry.photoIds)
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
            if (widget.reflectionService != null && _entry.aiReflectionQuestion == null)
              OutlinedButton(
                onPressed: _loadingReflection ? null : _reflect,
                child: Text(_loadingReflection ? 'Reflecting...' : 'Reflect'),
              ),
            if (_entry.aiReflectionQuestion != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_entry.aiReflectionQuestion!),
              ),
          ],
        ),
      ),
    );
  }
}
