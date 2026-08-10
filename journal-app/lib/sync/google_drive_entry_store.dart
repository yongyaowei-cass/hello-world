import 'dart:convert';
import 'package:googleapis/drive/v3.dart' as drive;
import '../models/journal_entry.dart';
import 'drive_entry_store.dart';

/// Extracts the entry id encoded in an `entry_<id>.json` file name.
String entryIdFromFileName(String fileName) =>
    fileName.replaceFirst('entry_', '').replaceFirst('.json', '');

/// Decodes a [RemoteEntryMeta] from a `entry_<id>.json` file's name plus its
/// own parsed JSON content.
///
/// Deliberately takes the entry's *content* rather than a `drive.File` --
/// there is no `modifiedTime` (or any other Drive-side metadata) anywhere
/// near this function, so there is no code path through which Drive's
/// server-side upload timestamp could be mistaken for the entry's own
/// `updatedAt`. Drive's `modifiedTime` is stamped when an upload lands on
/// the server, which is always slightly *after* the `updatedAt` value baked
/// into the uploaded content -- using it for `SyncService`'s last-write-wins
/// comparison meant every entry looked "newer on remote" than it really
/// was, causing perpetual re-download and, on a slower device, silent
/// overwriting of a genuinely newer local edit with stale remote content.
RemoteEntryMeta parseEntryMetaFromContent(String fileName, Map json) {
  return RemoteEntryMeta(
    id: entryIdFromFileName(fileName),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

class GoogleDriveEntryStore implements DriveEntryStore {
  GoogleDriveEntryStore(this._api);

  final drive.DriveApi _api;

  /// Instance-level cache of entry id -> Drive file id for `entry_<id>.json`
  /// files, populated by [listEntryMetas] and updated after every successful
  /// create in [upload].
  ///
  /// Without this, [download] and [upload] each re-derived this mapping
  /// from a fresh `files.list()` call every time they ran, on top of the
  /// `files.list()` [listEntryMetas] already did at the start of a sync
  /// pass -- see `GoogleDrivePhotoMetaStore` for the same pattern applied to
  /// photo metadata. `SyncService.sync` always calls [listEntryMetas] before
  /// any [download]/[upload] in the same pass, so the cache is warm by the
  /// time either is needed.
  final Map<String, String> _fileIdCache = {};

  Future<List<drive.File>> _listAllEntryFiles() async {
    final files = <drive.File>[];
    String? pageToken;
    do {
      final list = await _api.files.list(
        spaces: 'appDataFolder',
        $fields: 'nextPageToken, files(id, name)',
        q: "name contains 'entry_'",
        pageToken: pageToken,
      );
      files.addAll(list.files ?? const <drive.File>[]);
      pageToken = list.nextPageToken;
    } while (pageToken != null);
    return files;
  }

  Future<Map> _downloadJson(String fileId) async {
    final media = await _api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = await media.stream.expand((chunk) => chunk).toList();
    return jsonDecode(utf8.decode(bytes)) as Map;
  }

  @override
  Future<List<RemoteEntryMeta>> listEntryMetas() async {
    final files = await _listAllEntryFiles();
    final metas = <RemoteEntryMeta>[];
    for (final f in files) {
      _fileIdCache[entryIdFromFileName(f.name!)] = f.id!;
      final json = await _downloadJson(f.id!);
      metas.add(parseEntryMetaFromContent(f.name!, json));
    }
    return metas;
  }

  Future<String> _resolveFileId(String id) async {
    final cached = _fileIdCache[id];
    if (cached != null) return cached;
    // Not seen by a prior listEntryMetas() call on this instance -- fall
    // back to a fresh listing rather than assuming the id doesn't exist.
    await listEntryMetas();
    return _fileIdCache[id]!;
  }

  @override
  Future<JournalEntry> download(String id) async {
    final fileId = await _resolveFileId(id);
    return JournalEntry.fromJson(await _downloadJson(fileId));
  }

  @override
  Future<void> upload(JournalEntry entry) async {
    final content = utf8.encode(jsonEncode(entry.toJson()));
    final media = drive.Media(Stream.value(content), content.length);
    final existingId = _fileIdCache[entry.id];

    if (existingId == null) {
      final created = await _api.files.create(
        drive.File()
          ..name = 'entry_${entry.id}.json'
          ..parents = ['appDataFolder'],
        uploadMedia: media,
      );
      if (created.id != null) {
        _fileIdCache[entry.id] = created.id!;
      }
    } else {
      await _api.files.update(drive.File(), existingId, uploadMedia: media);
    }
  }
}
