import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../data/entry_repository.dart';
import '../data/photo_repository.dart';
import '../models/journal_entry.dart';
import '../models/photo_asset.dart';
import '../photos/photo_bytes_store.dart';
import '../theme/app_theme.dart';

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
    required this.photoRepository,
    required this.onSaved,
    this.existingEntry,
    this.pickImage,
  });

  final EntryRepository repository;
  final PhotoRepository photoRepository;
  final JournalEntry? existingEntry;
  final void Function(JournalEntry) onSaved;
  final Future<XFile?> Function()? pickImage;

  @override
  State<EntryEditorScreen> createState() => _EntryEditorScreenState();
}

class _EntryEditorScreenState extends State<EntryEditorScreen> {
  late final TextEditingController _textController;
  late final TextEditingController _tagController;
  int? _mood;
  late List<String> _tags;
  late List<String> _photoIds;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.existingEntry?.text ?? '');
    _tagController = TextEditingController();
    _mood = widget.existingEntry?.mood;
    _tags = List.of(widget.existingEntry?.tags ?? const []);
    _photoIds = List.of(widget.existingEntry?.photoIds ?? const []);
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

  Future<void> _addPhoto() async {
    final pick = widget.pickImage ?? () => ImagePicker().pickImage(source: ImageSource.gallery);
    final file = await pick();
    if (file == null) return;
    final asset = PhotoAsset(
      id: const Uuid().v4(),
      entryId: widget.existingEntry?.id ?? '',
      createdAt: DateTime.now(),
      localPath: file.path,
    );
    await widget.photoRepository.save(asset);
    if (!mounted) return;
    setState(() => _photoIds.add(asset.id));
  }

  // Detaches a photo from this entry. This intentionally leaves the
  // PhotoAsset/Hive record (and any already-uploaded Drive data) alone --
  // it just stops the id from being included in _photoIds, so it won't be
  // written to entry.photoIds on save.
  void _removePhoto(String id) {
    setState(() => _photoIds.remove(id));
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
      photoIds: _photoIds,
      aiReflectionQuestion: existing?.aiReflectionQuestion,
    );
    await widget.repository.save(entry);
    for (final id in _photoIds) {
      final asset = widget.photoRepository.getById(id);
      if (asset != null && asset.entryId != entry.id) {
        await widget.photoRepository.save(
          PhotoAsset(id: asset.id, entryId: entry.id, createdAt: asset.createdAt, localPath: asset.localPath, driveFileId: asset.driveFileId),
        );
      }
    }
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
      body: SingleChildScrollView(
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
                        backgroundColor: _mood == value ? AppColors.tagBackground : null,
                      ),
                    ),
                  ),
              ],
            ),
            TextField(
              controller: _textController,
              maxLines: null,
              style: journalTextStyle,
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
            IconButton(
              icon: const Icon(Icons.add_photo_alternate),
              onPressed: _addPhoto,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in _photoIds)
                  if (widget.photoRepository.getById(id)?.localPath != null)
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
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
                        Positioned(
                          top: -8,
                          right: -8,
                          child: GestureDetector(
                            key: Key('removePhoto-$id'),
                            onTap: () => _removePhoto(id),
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
              ],
            ),
            // Zero-size marker kept purely so widget tests can poll for the
            // moment _addPhoto's setState has actually landed (see
            // test/screens/entry_editor_screen_test.dart) -- Hive's Keystore
            // can reflect the underlying save before this widget's own
            // await/setState resumes, so polling repo state directly is
            // unreliable, and the real thumbnail above is keyed by a photo
            // id the test can't predict ahead of the pick completing.
            SizedBox.shrink(key: Key('photoCount-${_photoIds.length}')),
          ],
        ),
      ),
    );
  }
}
