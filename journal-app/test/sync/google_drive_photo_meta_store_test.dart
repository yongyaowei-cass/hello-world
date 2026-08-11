import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/sync/google_drive_photo_meta_store.dart';

void main() {
  test('parsePhotoMeta decodes id/entryId/createdAt/driveFileId from JSON content', () {
    final json = {
      'id': 'p1',
      'entryId': 'e1',
      'createdAt': '2026-08-09T09:41:00.000Z',
      'driveFileId': 'drive-file-p1',
    };

    final meta = parsePhotoMeta(json);

    expect(meta.id, 'p1');
    expect(meta.entryId, 'e1');
    expect(meta.createdAt, DateTime.utc(2026, 8, 9, 9, 41));
    expect(meta.driveFileId, 'drive-file-p1');
  });

  test('parsePhotoMeta tolerates a null driveFileId (binary not yet uploaded)', () {
    final json = {
      'id': 'p1',
      'entryId': 'e1',
      'createdAt': '2026-08-09T09:41:00.000Z',
      'driveFileId': null,
    };

    final meta = parsePhotoMeta(json);

    expect(meta.driveFileId, isNull);
  });

  test('photoMetaFileName / photoMetaIdFromFileName round-trip and stay distinct from photo_<id>.jpg binaries', () {
    final name = photoMetaFileName('p1');

    expect(name, 'photo_meta_p1.json');
    expect(photoMetaIdFromFileName(name), 'p1');
  });
}
