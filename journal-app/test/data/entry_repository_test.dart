import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/data/entry_repository.dart';
import 'package:journal_app/models/journal_entry.dart';

void main() {
  late Directory tempDir;
  late EntryRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('entry_repo_test');
    Hive.init(tempDir.path);
    repo = await EntryRepository.open();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  JournalEntry makeEntry(String id, {DateTime? createdAt}) {
    final ts = createdAt ?? DateTime.utc(2026, 8, 9);
    return JournalEntry(id: id, createdAt: ts, updatedAt: ts, text: 'entry $id');
  }

  test('save then getById returns the same entry', () async {
    final entry = makeEntry('e1');
    await repo.save(entry);

    final fetched = repo.getById('e1');

    expect(fetched, isNotNull);
    expect(fetched!.text, 'entry e1');
  });

  test('getAll excludes soft-deleted entries', () async {
    await repo.save(makeEntry('e1'));
    await repo.save(makeEntry('e2'));
    await repo.softDelete('e1');

    final all = repo.getAll();

    expect(all.map((e) => e.id), ['e2']);
  });

  test('getAll orders newest createdAt first', () async {
    await repo.save(makeEntry('older', createdAt: DateTime.utc(2026, 8, 1)));
    await repo.save(makeEntry('newer', createdAt: DateTime.utc(2026, 8, 9)));

    final all = repo.getAll();

    expect(all.map((e) => e.id), ['newer', 'older']);
  });

  test('softDelete sets deleted flag and bumps updatedAt', () async {
    final entry = makeEntry('e1', createdAt: DateTime.utc(2026, 8, 1));
    await repo.save(entry);

    await repo.softDelete('e1');

    final fetched = repo.getAllIncludingDeleted().single;
    expect(fetched.deleted, isTrue);
    expect(fetched.updatedAt.isAfter(entry.updatedAt), isTrue);
  });

  test('softDelete on a missing id is a no-op', () async {
    await repo.softDelete('does-not-exist');
    expect(repo.getAllIncludingDeleted(), isEmpty);
  });
}
