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

  Future<Map<String, String>> _metaFileIdsByPhotoId() async {
    final files = await _listAllMetaFiles();
    return {for (final f in files) photoMetaIdFromFileName(f.name!): f.id!};
  }

  @override
  Future<List<RemotePhotoMeta>> listMetas() async {
    final files = await _listAllMetaFiles();
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
    final fileIds = await _metaFileIdsByPhotoId();
    final content = utf8.encode(jsonEncode(_toJson(meta)));
    final media = drive.Media(Stream.value(content), content.length);
    final existingId = fileIds[meta.id];

    if (existingId == null) {
      await _api.files.create(
        drive.File()
          ..name = photoMetaFileName(meta.id)
          ..parents = ['appDataFolder'],
        uploadMedia: media,
      );
    } else {
      await _api.files.update(drive.File(), existingId, uploadMedia: media);
    }
  }
}
