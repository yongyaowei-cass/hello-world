import 'dart:convert';
import 'package:googleapis/drive/v3.dart' as drive;
import 'drive_photo_meta_store.dart';

/// Filename convention for a photo's metadata JSON file in the appDataFolder.
///
/// Deliberately distinct from the binary naming (`photo_<id>.jpg`, see
/// `GoogleDrivePhotoStore`) so a `name contains 'photo_'`-style query can
/// never accidentally sweep up a metadata file as if it were image bytes,
/// or vice versa.
String photoMetaFileName(String photoId) => 'photo_meta_$photoId.json';

String photoMetaIdFromFileName(String fileName) =>
    fileName.replaceFirst('photo_meta_', '').replaceFirst('.json', '');

/// Decodes a [RemotePhotoMeta] from the parsed JSON content of a
/// `photo_meta_<id>.json` file. Never reads (or expects) a `localPath` key:
/// that field is device-specific and is never written to these files in the
/// first place.
RemotePhotoMeta parsePhotoMeta(Map json) {
  return RemotePhotoMeta(
    id: json['id'] as String,
    entryId: json['entryId'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    driveFileId: json['driveFileId'] as String?,
  );
}

Map<String, dynamic> _toJson(RemotePhotoMeta meta) => {
      'id': meta.id,
      'entryId': meta.entryId,
      'createdAt': meta.createdAt.toIso8601String(),
      'driveFileId': meta.driveFileId,
    };

class GoogleDrivePhotoMetaStore implements DrivePhotoMetaStore {
  GoogleDrivePhotoMetaStore(this._api);

  final drive.DriveApi _api;

  /// Instance-level cache of photo id -> Drive file id for
  /// `photo_meta_<id>.json` files, populated by [listMetas] and updated
  /// after every successful [upload].
  ///
  /// Without this, [upload] re-derived this mapping from a fresh
  /// `files.list()` call every time it ran. `main.dart`'s `_trySync()` calls
  /// `PhotoMetaSyncService.sync` (and therefore this store's `upload`) twice
  /// per sync pass, reusing one `GoogleDrivePhotoMetaStore` instance for
  /// both calls. Drive's `files.list` is eventually consistent for
  /// just-created files, so the second call's fresh list query could miss a
  /// file the first call just created and issue a second `files.create` for
  /// the same photo id instead of a `files.update`, leaving two divergent
  /// `photo_meta_<id>.json` files with no reconciliation path. Caching
  /// within the instance's lifetime (one sync pass) closes that window
  /// without needing to re-list.
  final Map<String, String> _metaFileIdCache = {};

  Future<List<drive.File>> _listAllMetaFiles() async {
    final files = <drive.File>[];
    String? pageToken;
    do {
      final list = await _api.files.list(
        spaces: 'appDataFolder',
        $fields: 'nextPageToken, files(id, name)',
        q: "name contains 'photo_meta_'",
        pageToken: pageToken,
      );
      files.addAll(list.files ?? const <drive.File>[]);
      pageToken = list.nextPageToken;
    } while (pageToken != null);
    return files;
  }

  @override
  Future<List<RemotePhotoMeta>> listMetas() async {
    final files = await _listAllMetaFiles();
    for (final f in files) {
      _metaFileIdCache[photoMetaIdFromFileName(f.name!)] = f.id!;
    }
    final metas = <RemotePhotoMeta>[];
    for (final f in files) {
      final media = await _api.files.get(
        f.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final bytes = await media.stream.expand((chunk) => chunk).toList();
      metas.add(parsePhotoMeta(jsonDecode(utf8.decode(bytes)) as Map));
    }
    return metas;
  }

  @override
  Future<void> upload(RemotePhotoMeta meta) async {
    final content = utf8.encode(jsonEncode(_toJson(meta)));
    final media = drive.Media(Stream.value(content), content.length);
    final existingId = _metaFileIdCache[meta.id];

    if (existingId == null) {
      final created = await _api.files.create(
        drive.File()
          ..name = photoMetaFileName(meta.id)
          ..parents = ['appDataFolder'],
        uploadMedia: media,
      );
      if (created.id != null) {
        _metaFileIdCache[meta.id] = created.id!;
      }
    } else {
      await _api.files.update(drive.File(), existingId, uploadMedia: media);
    }
  }
}
