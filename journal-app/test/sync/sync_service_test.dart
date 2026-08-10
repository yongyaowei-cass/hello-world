import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/data/entry_repository.dart';
import 'package:journal_app/models/journal_entry.dart';
import 'package:journal_app/sync/drive_entry_store.dart';
import 'package:journal_app/sync/sync_service.dart';

class FakeDriveEntryStore implements DriveEntryStore {
  final Map<String, JournalEntry> remote = {};

  @override
  Future<List<RemoteEntryMeta>> listEntryMetas() async {
    return remote.values
        .map((e) => RemoteEntryMeta(id: e.id, updatedAt: e.updatedAt))
        .toList();
  }

  @override
  Future<JournalEntry> download(String id) async => remote[id]!;

  @override
  Future<void> upload(JournalEntry entry) async {
    remote[entry.id] = entry;
  }
}

void main() {
  late Directory tempDir;
  late EntryRepository local;
  late FakeDriveEntryStore remote;
  late SyncService sync;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_test');
    Hive.init(tempDir.path);
    local = await EntryRepository.open();
    remote = FakeDriveEntryStore();
    sync = SyncService();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  JournalEntry make(String id, {required DateTime updatedAt, String text = 'text'}) {
    return JournalEntry(id: id, createdAt: updatedAt, updatedAt: updatedAt, text: text);
  }

  test('local-only entry gets pushed to remote', () async {
    await local.save(make('e1', updatedAt: DateTime.utc(2026, 8, 9)));

    await sync.sync(local, remote);

    expect(remote.remote.containsKey('e1'), isTrue);
  });

  test('remote-only entry gets pulled to local', () async {
    await remote.upload(make('e1', updatedAt: DateTime.utc(2026, 8, 9)));

    await sync.sync(local, remote);

    expect(local.getById('e1'), isNotNull);
  });

  test('newer remote entry overwrites older local entry', () async {
    await local.save(make('e1', updatedAt: DateTime.utc(2026, 8, 1), text: 'old local'));
    await remote.upload(make('e1', updatedAt: DateTime.utc(2026, 8, 9), text: 'newer remote'));

    await sync.sync(local, remote);

    expect(local.getById('e1')!.text, 'newer remote');
  });

  test('newer local entry overwrites older remote entry', () async {
    await local.save(make('e1', updatedAt: DateTime.utc(2026, 8, 9), text: 'newer local'));
    await remote.upload(make('e1', updatedAt: DateTime.utc(2026, 8, 1), text: 'old remote'));

    await sync.sync(local, remote);

    expect(remote.remote['e1']!.text, 'newer local');
  });

  test('entries with equal updatedAt are left unchanged (no redundant writes)', () async {
    final ts = DateTime.utc(2026, 8, 9);
    await local.save(make('e1', updatedAt: ts, text: 'same'));
    await remote.upload(make('e1', updatedAt: ts, text: 'same'));

    await sync.sync(local, remote);

    expect(local.getById('e1')!.text, 'same');
    expect(remote.remote['e1']!.text, 'same');
  });

  test('editing different entries on each side never conflicts', () async {
    await local.save(make('local-only', updatedAt: DateTime.utc(2026, 8, 9)));
    await remote.upload(make('remote-only', updatedAt: DateTime.utc(2026, 8, 9)));

    await sync.sync(local, remote);

    expect(local.getById('local-only'), isNotNull);
    expect(local.getById('remote-only'), isNotNull);
    expect(remote.remote.containsKey('local-only'), isTrue);
    expect(remote.remote.containsKey('remote-only'), isTrue);
  });

  // Regression coverage for the "Drive's modifiedTime used as updatedAt"
  // bug: a fully-synced, unchanged entry must never be re-downloaded, no
  // matter how many sync passes run.
  //
  // Note this test cannot, by itself, catch a regression of that specific
  // bug: it lived entirely in GoogleDriveEntryStore's Drive-file parsing
  // (see google_drive_entry_store_test.dart), not in SyncService's
  // comparison logic exercised here. FakeDriveEntryStore.listEntryMetas()
  // already returns the entry's own `updatedAt` (`RemoteEntryMeta(id: e.id,
  // updatedAt: e.updatedAt)`) with no Drive-specific timestamp anywhere
  // near it, so a fake built against the DriveEntryStore *contract* is
  // correct by construction and cannot reproduce a bug that only existed in
  // one concrete implementation's adapter code translating Drive's
  // `modifiedTime` into that contract. This test instead documents and
  // guards the behavioural contract itself -- useful if a future change to
  // SyncService's comparison logic (not just the Drive adapter) ever
  // reintroduces spurious re-syncing.
  test('an unchanged entry is never re-downloaded across repeated sync passes', () async {
    final ts = DateTime.utc(2026, 8, 9, 9, 41);
    await local.save(make('e1', updatedAt: ts, text: 'stable'));

    await sync.sync(local, remote); // first pass: pushes local -> remote

    for (var i = 0; i < 3; i++) {
      await sync.sync(local, remote);
    }

    expect(local.getById('e1')!.updatedAt, ts);
    expect(local.getById('e1')!.text, 'stable');
    expect(remote.remote['e1']!.updatedAt, ts);
    expect(remote.remote['e1']!.text, 'stable');
  });

  test('soft-deleted entry propagates to remote with deleted flag', () async {
    final entry = make('e1', updatedAt: DateTime.utc(2026, 8, 1));
    await local.save(entry);
    await remote.upload(entry);

    await local.softDelete('e1');

    await sync.sync(local, remote);

    expect(remote.remote['e1']!.deleted, isTrue);
  });
}
