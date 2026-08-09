import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/journal_entry.dart';

class EntryRepository {
  EntryRepository(this._box);

  final Box<dynamic> _box;

  static Future<EntryRepository> open() async {
    final box = await Hive.openBox<dynamic>('entries');
    return EntryRepository(box);
  }

  List<JournalEntry> getAllIncludingDeleted() {
    return _box.values
        .map((v) => JournalEntry.fromJson(v as Map<dynamic, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<JournalEntry> getAll() {
    return getAllIncludingDeleted().where((e) => !e.deleted).toList();
  }

  JournalEntry? getById(String id) {
    final raw = _box.get(id);
    return raw == null ? null : JournalEntry.fromJson(raw);
  }

  Future<void> save(JournalEntry entry) => _box.put(entry.id, entry.toJson());

  Future<void> softDelete(String id) async {
    final existing = getById(id);
    if (existing == null) return;
    await save(existing.copyWith(deleted: true, updatedAt: DateTime.now()));
  }

  ValueListenable<Box> listenable() => _box as ValueListenable<Box>;
}
