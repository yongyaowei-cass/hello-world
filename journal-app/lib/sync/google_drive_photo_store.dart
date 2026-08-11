import 'dart:typed_data';
import 'package:googleapis/drive/v3.dart' as drive;
import 'drive_photo_store.dart';

class GoogleDrivePhotoStore implements DrivePhotoStore {
  GoogleDrivePhotoStore(this._api);

  final drive.DriveApi _api;

  Future<String?> _findFileId(String photoId) async {
    final list = await _api.files.list(
      spaces: 'appDataFolder',
      $fields: 'files(id, name)',
      q: "name = 'photo_$photoId.jpg'",
    );
    final files = list.files ?? const <drive.File>[];
    return files.isEmpty ? null : files.first.id;
  }

  @override
  Future<Uint8List?> download(String photoId) async {
    final fileId = await _findFileId(photoId);
    if (fileId == null) return null;
    final media = await _api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = await media.stream.expand((chunk) => chunk).toList();
    return Uint8List.fromList(bytes);
  }

  @override
  Future<String> upload(String photoId, Uint8List bytes) async {
    final media = drive.Media(Stream.value(bytes), bytes.length);
    final created = await _api.files.create(
      drive.File()
        ..name = 'photo_$photoId.jpg'
        ..parents = ['appDataFolder'],
      uploadMedia: media,
    );
    return created.id!;
  }
}
