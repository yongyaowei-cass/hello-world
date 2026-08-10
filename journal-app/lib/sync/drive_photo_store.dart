import 'dart:typed_data';

abstract class DrivePhotoStore {
  Future<Uint8List?> download(String photoId);
  Future<String> upload(String photoId, Uint8List bytes);
}
