import '../models/journal_entry.dart';

class RemoteEntryMeta {
  RemoteEntryMeta({required this.id, required this.updatedAt});

  final String id;
  final DateTime updatedAt;
}

abstract class DriveEntryStore {
  Future<List<RemoteEntryMeta>> listEntryMetas();
  Future<JournalEntry> download(String id);
  Future<void> upload(JournalEntry entry);
}
