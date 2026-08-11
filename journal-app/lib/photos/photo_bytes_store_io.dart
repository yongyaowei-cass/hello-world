import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Writes [bytes] to a real file named after [photoId] in the app's
/// documents directory and returns the file's path.
Future<String> saveLocalPhotoBytes(String photoId, Uint8List bytes) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$photoId.jpg');
  await file.writeAsBytes(bytes);
  return file.path;
}

/// Reads the bytes of the real file at [localPath].
Future<Uint8List> readLocalPhotoBytes(String localPath) {
  return File(localPath).readAsBytes();
}

/// Renders [localPath] (a real file path) as an image thumbnail.
Widget buildLocalPhotoThumbnail(
  String localPath, {
  required BoxFit fit,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  return Image.file(File(localPath), fit: fit, errorBuilder: errorBuilder);
}
