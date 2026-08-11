import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/photos/photo_bytes_store_web.dart';

// This file imports the web implementation directly (bypassing the
// dart.library.io / dart.library.html conditional export in
// photo_bytes_store.dart) so its platform-agnostic data: URL round-trip
// logic can be exercised under `flutter test`, which runs on the Dart VM
// and would otherwise always select the IO implementation.
void main() {
  test('saveLocalPhotoBytes encodes bytes as a base64 data: URL', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

    final localPath = await saveLocalPhotoBytes('p1', bytes);

    expect(localPath, startsWith('data:image/jpeg;base64,'));
  });

  test('readLocalPhotoBytes decodes the data: URL back to the original bytes', () async {
    final bytes = Uint8List.fromList([10, 20, 30, 255, 0]);
    final localPath = await saveLocalPhotoBytes('p2', bytes);

    final roundTripped = await readLocalPhotoBytes(localPath);

    expect(roundTripped, bytes);
  });

  test('round-trips empty bytes', () async {
    final bytes = Uint8List(0);
    final localPath = await saveLocalPhotoBytes('p3', bytes);

    final roundTripped = await readLocalPhotoBytes(localPath);

    expect(roundTripped, isEmpty);
  });
}
