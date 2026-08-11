import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/sync/google_drive_entry_store.dart';

void main() {
  test('parseEntryMetaFromContent extracts id from the file name', () {
    final meta = parseEntryMetaFromContent('entry_e1.json', {
      'id': 'e1',
      'updatedAt': '2026-08-09T09:41:00.000Z',
    });

    expect(meta.id, 'e1');
    expect(meta.updatedAt, DateTime.utc(2026, 8, 9, 9, 41));
  });

  test(
      'parseEntryMetaFromContent reads updatedAt from the JSON content, '
      'never from Drive-side metadata (regression for perpetual re-download '
      'and cross-device data loss bug)', () {
    // The whole point: this function's signature only accepts a file name
    // and the entry's own parsed JSON content -- there is no drive.File
    // parameter through which Drive's server-side `modifiedTime` (which is
    // always stamped *after* upload, i.e. always later than the entry's own
    // updatedAt) could leak in and be mistaken for the entry's real
    // updatedAt. Regressing to reading `modifiedTime` again broke
    // last-write-wins in two ways: perpetual re-download (remote always
    // looks "newer") and silent data loss (a stale remote copy overwrites a
    // genuinely newer local edit whenever it falls between the local edit's
    // timestamp and Drive's upload stamp).
    final contentUpdatedAt = DateTime.utc(2026, 8, 9, 9, 41);

    final meta = parseEntryMetaFromContent('entry_e1.json', {
      'id': 'e1',
      'updatedAt': contentUpdatedAt.toIso8601String(),
    });

    expect(meta.updatedAt, contentUpdatedAt);
  });
}
