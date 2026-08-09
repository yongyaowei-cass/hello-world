import 'dart:convert';
import 'package:googleapis/drive/v3.dart' as drive;
import '../models/journal_entry.dart';
import 'drive_entry_store.dart';

RemoteEntryMeta parseEntryMeta(drive.File file) {
  final id = file.name!.replaceFirst('entry_', '').replaceFirst('.json', '');
  return RemoteEntryMeta(id: id, updatedAt: file.modifiedTime!.toUtc());
}

class GoogleDriveEntryStore implements DriveEntryStore {
  GoogleDriveEntryStore(this._api);

  final drive.DriveApi _api;

  Future<Map<String, String>> _entryFileIdsByEntryId() async {
    final list = await _api.files.list(
      spaces: 'appDataFolder',
      $fields: 'files(id, name, modifiedTime)',
      q: "name contains 'entry_'",
    );
    return {
      for (final f in list.files ?? const <drive.File>[])
        parseEntryMeta(f).id: f.id!,
    };
  }

  @override
  Future<List<RemoteEntryMeta>> listEntryMetas() async {
    final list = await _api.files.list(
      spaces: 'appDataFolder',
      $fields: 'files(id, name, modifiedTime)',
      q: "name contains 'entry_'",
    );
    return [
      for (final f in list.files ?? const <drive.File>[]) parseEntryMeta(f),
    ];
  }

  @override
  Future<JournalEntry> download(String id) async {
    final fileIds = await _entryFileIdsByEntryId();
    final media = await _api.files.get(
      fileIds[id]!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = await media.stream.expand((chunk) => chunk).toList();
    return JournalEntry.fromJson(jsonDecode(utf8.decode(bytes)) as Map);
  }

  @override
  Future<void> upload(JournalEntry entry) async {
    final fileIds = await _entryFileIdsByEntryId();
    final content = utf8.encode(jsonEncode(entry.toJson()));
    final media = drive.Media(Stream.value(content), content.length);
    final existingId = fileIds[entry.id];

    if (existingId == null) {
      await _api.files.create(
        drive.File()
          ..name = 'entry_${entry.id}.json'
          ..parents = ['appDataFolder'],
        uploadMedia: media,
      );
    } else {
      await _api.files.update(drive.File(), existingId, uploadMedia: media);
    }
  }
}
