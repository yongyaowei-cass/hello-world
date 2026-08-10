import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

/// Web has no meaningful local filesystem, so "saving" bytes locally just
/// means keeping them in memory, encoded as a base64 `data:` URL. That
/// string is what ends up stored in `PhotoAsset.localPath` on web, and both
/// [readLocalPhotoBytes] and [buildLocalPhotoThumbnail] below know how to
/// read it back.
Future<String> saveLocalPhotoBytes(String photoId, Uint8List bytes) async {
  return 'data:image/jpeg;base64,${base64Encode(bytes)}';
}

/// Reads bytes back out of [localPath]. Handles the `data:` URLs produced
/// by [saveLocalPhotoBytes] directly (no network round-trip needed); falls
/// back to an HTTP fetch for anything else, which also covers the `blob:`
/// URLs that image_picker's `XFile.path` produces in a browser.
Future<Uint8List> readLocalPhotoBytes(String localPath) async {
  final uri = Uri.parse(localPath);
  final data = uri.data;
  if (data != null) {
    return data.contentAsBytes();
  }
  final response = await http.get(uri);
  return response.bodyBytes;
}

/// Renders [localPath] as an image thumbnail. Both the `data:` URLs this
/// file produces and the `blob:` URLs image_picker produces on web are
/// valid `Image.network` sources in a browser context.
Widget buildLocalPhotoThumbnail(
  String localPath, {
  required BoxFit fit,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  return Image.network(localPath, fit: fit, errorBuilder: errorBuilder);
}
