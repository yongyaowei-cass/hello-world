import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/data/photo_repository.dart';
import 'package:journal_app/models/photo_asset.dart';
import 'package:journal_app/sync/drive_photo_meta_store.dart';
import 'package:journal_app/sync/photo_meta_sync_service.dart';

class FakeDrivePhotoMetaStore implements DrivePhotoMetaStore {
  final Map<String, RemotePhotoMeta> remote = {};

  @override
  Future<List<RemotePhotoMeta>> listMetas() async => remote.values.toList();

  @override
  Future<void> upload(RemotePhotoMeta meta) async {
    remote[meta.id] = meta;
  }
}

void main() {
  late Directory tempDir;
  late PhotoRepository local;
  late FakeDrivePhotoMetaStore remote;
  late PhotoMetaSyncService sync;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('photo_meta_sync_test');
    Hive.init(tempDir.path);
    local = await PhotoRepository.open();
    remote = FakeDrivePhotoMetaStore();
    sync = PhotoMetaSyncService();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  test('remote-only photo metadata gets pulled to local with localPath null', () async {
    remote.remote['p1'] = RemotePhotoMeta(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
    );

    await sync.sync(local, remote);

    final pulled = local.getById('p1');
    expect(pulled, isNotNull);
    expect(pulled!.entryId, 'e1');
    expect(pulled.localPath, isNull);
  });

  test('local-only photo metadata gets pushed to remote', () async {
    await local.save(PhotoAsset(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      localPath: '/device/a/p1.jpg',
    ));

    await sync.sync(local, remote);

    expect(remote.remote.containsKey('p1'), isTrue);
    expect(remote.remote['p1']!.entryId, 'e1');
  });

  test('pushed metadata never carries localPath (only id/entryId/createdAt/driveFileId are shared)', () async {
    await local.save(PhotoAsset(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      localPath: '/device/a/only/this/device/knows/p1.jpg',
    ));

    await sync.sync(local, remote);

    // RemotePhotoMeta has no localPath field at all, so there's nothing to
    // assert null on other than confirming the type only carries the shared
    // fields; this is enforced by the type signature itself.
    expect(remote.remote['p1']!.id, 'p1');
    expect(remote.remote['p1']!.entryId, 'e1');
    expect(remote.remote['p1']!.createdAt, DateTime.utc(2026, 8, 9));
  });

  test('local photo whose binary just finished uploading pushes its new driveFileId to remote', () async {
    await local.save(PhotoAsset(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      localPath: '/device/a/p1.jpg',
    ));
    remote.remote['p1'] = RemotePhotoMeta(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
    );
    // Simulate the binary sync branch having just discovered a driveFileId.
    await local.save((local.getById('p1'))!.copyWith(driveFileId: 'drive-file-p1'));

    await sync.sync(local, remote);

    expect(remote.remote['p1']!.driveFileId, 'drive-file-p1');
  });

  test('local photo learns a driveFileId the remote already knows about', () async {
    await local.save(PhotoAsset(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
    ));
    remote.remote['p1'] = RemotePhotoMeta(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      driveFileId: 'drive-file-p1',
    );

    await sync.sync(local, remote);

    expect(local.getById('p1')!.driveFileId, 'drive-file-p1');
  });

  test('local entryId correction propagates to remote even when driveFileId already agrees on both sides', () async {
    // Reproduces the entry_editor_screen.dart race: _addPhoto() saves a new
    // PhotoAsset with entryId: '' immediately (the real entry id isn't known
    // yet for a brand-new entry). If a sync fires before _save() rewrites it
    // to the real entry id, and the binary upload also happens to complete
    // in that window, both sides end up agreeing on a non-null driveFileId
    // while remote is still stuck with the stale entryId. Once driveFileId
    // is non-null on both sides, the old logic considered the id "settled"
    // and never looked at entryId again.
    await local.save(PhotoAsset(
      id: 'p1',
      entryId: 'e1', // corrected locally by _save() after the entry was created
      createdAt: DateTime.utc(2026, 8, 9),
      localPath: '/device/a/p1.jpg',
      driveFileId: 'drive-file-p1',
    ));
    remote.remote['p1'] = RemotePhotoMeta(
      id: 'p1',
      entryId: '', // stale value published before _save() ran
      createdAt: DateTime.utc(2026, 8, 9),
      driveFileId: 'drive-file-p1',
    );

    await sync.sync(local, remote);

    expect(remote.remote['p1']!.entryId, 'e1');
  });

  test('a stale local replica with a placeholder entryId does not push it back over a corrected remote value', () async {
    // Reproduces the oscillation the reviewer flagged: device A creates a
    // photo with entryId: '' and syncs; device B pulls that replica down,
    // also with entryId: ''. A later corrects its own entryId to 'e1' and
    // pushes the fix to remote. Now B syncs again -- its local replica is
    // still stale ('' ), while remote already has the correction ('e1').
    // Under the old "local always wins on any diff" rule, B would push its
    // stale '' right back over A's fix. The narrowed rule must NOT push here
    // -- entryId only has a defined pull/push direction for the
    // ''->non-empty transition on the *pushing* side, and B's local side is
    // still ''.
    await local.save(PhotoAsset(
      id: 'p1',
      entryId: '', // B's stale replica -- never corrected locally
      createdAt: DateTime.utc(2026, 8, 9),
      driveFileId: 'drive-file-p1',
    ));
    remote.remote['p1'] = RemotePhotoMeta(
      id: 'p1',
      entryId: 'e1', // A's correction, already pushed to remote
      createdAt: DateTime.utc(2026, 8, 9),
      driveFileId: 'drive-file-p1',
    );

    await sync.sync(local, remote);

    expect(remote.remote['p1']!.entryId, 'e1');
  });

  test('photo metadata already in sync on both sides is left unchanged', () async {
    await local.save(PhotoAsset(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      localPath: '/device/a/p1.jpg',
      driveFileId: 'drive-file-p1',
    ));
    remote.remote['p1'] = RemotePhotoMeta(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      driveFileId: 'drive-file-p1',
    );

    await sync.sync(local, remote);

    expect(local.getById('p1')!.localPath, '/device/a/p1.jpg');
    expect(remote.remote['p1']!.driveFileId, 'drive-file-p1');
  });
}
