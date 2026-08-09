import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:journal_app/sync/google_drive_entry_store.dart';

void main() {
  test('parseEntryMeta extracts id and updatedAt from a Drive File', () {
    final file = drive.File()
      ..name = 'entry_e1.json'
      ..modifiedTime = DateTime.utc(2026, 8, 9, 9, 41);

    final meta = parseEntryMeta(file);

    expect(meta.id, 'e1');
    expect(meta.updatedAt, DateTime.utc(2026, 8, 9, 9, 41));
  });
}
