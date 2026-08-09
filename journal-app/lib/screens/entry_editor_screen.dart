import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/entry_repository.dart';
import '../models/journal_entry.dart';

const _moodOptions = [
  (1, '😞'),
  (2, '😕'),
  (3, '😐'),
  (4, '🙂'),
  (5, '😄'),
];

class EntryEditorScreen extends StatefulWidget {
  const EntryEditorScreen({
    super.key,
    required this.repository,
    required this.onSaved,
    this.existingEntry,
  });

  final EntryRepository repository;
  final JournalEntry? existingEntry;
  final void Function(JournalEntry) onSaved;

  @override
  State<EntryEditorScreen> createState() => _EntryEditorScreenState();
}

class _EntryEditorScreenState extends State<EntryEditorScreen> {
  late final TextEditingController _textController;
  late final TextEditingController _tagController;
  int? _mood;
  late List<String> _tags;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.existingEntry?.text ?? '');
    _tagController = TextEditingController();
    _mood = widget.existingEntry?.mood;
    _tags = List.of(widget.existingEntry?.tags ?? const []);
  }

  @override
  void dispose() {
    _textController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _addTag(String value) {
    final tag = value.trim();
    if (tag.isEmpty) return;
    setState(() {
      _tags.add(tag);
      _tagController.clear();
    });
  }

  Future<void> _save() async {
    final now = DateTime.now();
    final existing = widget.existingEntry;
    final entry = JournalEntry(
      id: existing?.id ?? const Uuid().v4(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      text: _textController.text,
      mood: _mood,
      tags: _tags,
      photoIds: existing?.photoIds ?? const [],
      aiReflectionQuestion: existing?.aiReflectionQuestion,
    );
    await widget.repository.save(entry);
    widget.onSaved(entry);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(widget.existingEntry == null ? 'New entry' : 'Edit entry'),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final (value, emoji) in _moodOptions)
                  IconButton(
                    onPressed: () => setState(() => _mood = value),
                    icon: Text(
                      emoji,
                      style: TextStyle(
                        fontSize: 22,
                        backgroundColor: _mood == value
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            TextField(
              controller: _textController,
              maxLines: null,
              decoration: const InputDecoration(hintText: "What's on your mind today?"),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final tag in _tags) Chip(label: Text(tag)),
                SizedBox(
                  width: 120,
                  child: TextField(
                    key: const Key('tagInput'),
                    controller: _tagController,
                    decoration: const InputDecoration(hintText: 'add tag'),
                    onSubmitted: _addTag,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
