/// A lightweight, cross-device-safe snapshot of a [PhotoAsset].
///
/// Deliberately does NOT carry `localPath`: that field is a real file path
/// on Android/desktop or an in-memory data: URL on web (see
/// `lib/photos/photo_bytes_store.dart`), meaningful only on the device that
/// created it. Only `id`, `entryId`, `createdAt`, and `driveFileId` describe
/// facts that are true regardless of which device is looking at them, so
/// only those are ever written to or read from Drive.
class RemotePhotoMeta {
  RemotePhotoMeta({
    required this.id,
    required this.entryId,
    required this.createdAt,
    this.driveFileId,
  });

  final String id;
  final String entryId;
  final DateTime createdAt;
  final String? driveFileId;
}

abstract class DrivePhotoMetaStore {
  Future<List<RemotePhotoMeta>> listMetas();
  Future<void> upload(RemotePhotoMeta meta);
}
