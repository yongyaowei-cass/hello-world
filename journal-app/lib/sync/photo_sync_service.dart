import 'dart:io';
import 'dart:typed_data';
import '../data/photo_repository.dart';
import 'drive_photo_store.dart';

class PhotoSyncService {
  PhotoSyncService({required this.saveLocalBytes});

  final Future<String> Function(String photoId, Uint8List bytes) saveLocalBytes;

  Future<void> sync(PhotoRepository local, DrivePhotoStore remote) async {
    for (final asset in local.getAll()) {
      if (asset.driveFileId == null && asset.localPath != null) {
        final bytes = await File(asset.localPath!).readAsBytes();
        final fileId = await remote.upload(asset.id, bytes);
        await local.save(asset.copyWith(driveFileId: fileId));
      } else if (asset.localPath == null && asset.driveFileId != null) {
        final bytes = await remote.download(asset.id);
        if (bytes == null) continue;
        final path = await saveLocalBytes(asset.id, bytes);
        await local.save(asset.copyWith(localPath: path));
      }
    }
  }
}
