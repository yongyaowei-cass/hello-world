import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Fallback implementation selected when neither `dart:io` nor
/// `dart:html` is available (i.e. neither the IO nor the web
/// implementation applies). Not expected to be reachable on this app's
/// supported targets (Android + Web) — exists so the conditional export in
/// `photo_bytes_store.dart` always has a default to fall back to.
Future<String> saveLocalPhotoBytes(String photoId, Uint8List bytes) {
  throw UnsupportedError(
    'No local photo byte storage implementation is available for this platform.',
  );
}

Future<Uint8List> readLocalPhotoBytes(String localPath) {
  throw UnsupportedError(
    'No local photo byte storage implementation is available for this platform.',
  );
}

Widget buildLocalPhotoThumbnail(
  String localPath, {
  required BoxFit fit,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  throw UnsupportedError(
    'No local photo byte storage implementation is available for this platform.',
  );
}
