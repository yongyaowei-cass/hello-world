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

  Future<List<drive.File>> _listAllEntryFiles() async {
    final files = <drive.File>[];
    String? pageToken;
    do {
      final list = await _api.files.list(
        spaces: 'appDataFolder',
        $fields: 'nextPageToken, files(id, name, modifiedTime)',
        q: "name contains 'entry_'",
        pageToken: pageToken,
      );
      files.addAll(list.files ?? const <drive.File>[]);
      pageToken = list.nextPageToken;
    } while (pageToken != null);
    return files;
  }

  Future<Map<String, String>> _entryFileIdsByEntryId() async {
    final files = await _listAllEntryFiles();
    return {for (final f in files) parseEntryMeta(f).id: f.id!};
  }

  @override
  Future<List<RemoteEntryMeta>> listEntryMetas() async {
    final files = await _listAllEntryFiles();
    return [for (final f in files) parseEntryMeta(f)];
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
