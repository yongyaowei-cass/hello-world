// End-to-end fake-level integration test proving photos actually reach a
// second device.
//
// Before the fix, PhotoAsset *metadata* only ever lived in local Hive
// storage: entry JSON synced, photo binaries synced, but nothing told a
// second device that a photo tied to a synced entry even existed. This test
// simulates two independent devices (A and B), each with its own
// EntryRepository/PhotoRepository, sharing one fake Drive backend (fake
// DriveEntryStore + fake photo binary store + fake photo meta store) and
// asserts that after A creates an entry with a photo and syncs, and B syncs,
// B ends up with both the entry AND a locally-downloaded copy of the photo.
//
// Run this test against pre-fix code (PhotoSyncService.sync alone, with no
// metadata sync) and it fails: B's PhotoRepository never learns about 'p1'
// in the first place, so the binary-download branch (which iterates
// local.getAll()) never even considers it.
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/data/entry_repository.dart';
import 'package:journal_app/data/photo_repository.dart';
import 'package:journal_app/models/journal_entry.dart';
import 'package:journal_app/models/photo_asset.dart';
import 'package:journal_app/sync/drive_entry_store.dart';
import 'package:journal_app/sync/drive_photo_meta_store.dart';
import 'package:journal_app/sync/drive_photo_store.dart';
import 'package:journal_app/sync/photo_meta_sync_service.dart';
import 'package:journal_app/sync/photo_sync_service.dart';
import 'package:journal_app/sync/sync_service.dart';

class FakeDriveEntryStore implements DriveEntryStore {
  final Map<String, JournalEntry> remote = {};

  @override
  Future<List<RemoteEntryMeta>> listEntryMetas() async {
    return remote.values.map((e) => RemoteEntryMeta(id: e.id, updatedAt: e.updatedAt)).toList();
  }

  @override
  Future<JournalEntry> download(String id) async => remote[id]!;

  @override
  Future<void> upload(JournalEntry entry) async {
    remote[entry.id] = entry;
  }
}

class FakeDrivePhotoStore implements DrivePhotoStore {
  final Map<String, Uint8List> remote = {};

  @override
  Future<Uint8List?> download(String photoId) async => remote[photoId];

  @override
  Future<String> upload(String photoId, Uint8List bytes) async {
    remote[photoId] = bytes;
    return 'drive-file-$photoId';
  }
}

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
  late Directory tempDirA;
  late Directory tempDirB;
  late Directory filesDirA;
  late Directory filesDirB;

  late EntryRepository entryRepoA;
  late PhotoRepository photoRepoA;
  late EntryRepository entryRepoB;
  late PhotoRepository photoRepoB;

  late FakeDriveEntryStore driveEntries;
  late FakeDrivePhotoStore drivePhotos;
  late FakeDrivePhotoMetaStore drivePhotoMetas;

  final syncService = SyncService();
  final photoMetaSyncService = PhotoMetaSyncService();

  setUp(() async {
    tempDirA = await Directory.systemTemp.createTemp('device_a');
    tempDirB = await Directory.systemTemp.createTemp('device_b');
    filesDirA = await Directory('${tempDirA.path}/files').create();
    filesDirB = await Directory('${tempDirB.path}/files').create();

    driveEntries = FakeDriveEntryStore();
    drivePhotos = FakeDrivePhotoStore();
    drivePhotoMetas = FakeDrivePhotoMetaStore();
  });

  tearDown(() async {
    await tempDirA.delete(recursive: true);
    await tempDirB.delete(recursive: true);
  });

  /// Runs the full sync pipeline (entries, then photo metadata, then photo
  /// binaries, then photo metadata again so a driveFileId discovered during
  /// binary sync gets published) exactly as main.dart's _trySync wires it.
  Future<void> fullSync(
    EntryRepository entries,
    PhotoRepository photos,
    Directory filesDir,
  ) async {
    await syncService.sync(entries, driveEntries);
    await photoMetaSyncService.sync(photos, drivePhotoMetas);
    final photoSyncService = PhotoSyncService(
      saveLocalBytes: (photoId, bytes) async {
        final file = File('${filesDir.path}/$photoId.jpg');
        await file.writeAsBytes(bytes);
        return file.path;
      },
    );
    await photoSyncService.sync(photos, drivePhotos);
    await photoMetaSyncService.sync(photos, drivePhotoMetas);
  }

  test('a photo attached to an entry on device A reaches device B end-to-end', () async {
    Hive.init(tempDirA.path);
    entryRepoA = await EntryRepository.open();
    photoRepoA = await PhotoRepository.open();

    // Device A creates an entry with a photo and syncs.
    final srcFile = File('${tempDirA.path}/pic.jpg');
    await srcFile.writeAsBytes([1, 2, 3, 4]);
    await photoRepoA.save(PhotoAsset(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      localPath: srcFile.path,
    ));
    await entryRepoA.save(JournalEntry(
      id: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      updatedAt: DateTime.utc(2026, 8, 9),
      text: 'Entry with a photo',
      photoIds: const ['p1'],
    ));

    await fullSync(entryRepoA, photoRepoA, filesDirA);
    await Hive.deleteFromDisk();

    // Device B (separate Hive instance, separate PhotoRepository/EntryRepository)
    // syncs against the same fake Drive backend.
    Hive.init(tempDirB.path);
    entryRepoB = await EntryRepository.open();
    photoRepoB = await PhotoRepository.open();

    await fullSync(entryRepoB, photoRepoB, filesDirB);

    // B now has the entry.
    final pulledEntry = entryRepoB.getById('e1');
    expect(pulledEntry, isNotNull);
    expect(pulledEntry!.photoIds, contains('p1'));

    // B now has a PhotoAsset record for p1 (this is what the bug broke: the
    // metadata never made it to B, so this lookup used to return null).
    final pulledPhoto = photoRepoB.getById('p1');
    expect(pulledPhoto, isNotNull);
    expect(pulledPhoto!.entryId, 'e1');

    // B has actually downloaded the binary locally too.
    expect(pulledPhoto.localPath, isNotNull);
    expect(await File(pulledPhoto.localPath!).readAsBytes(), [1, 2, 3, 4]);

    await Hive.deleteFromDisk();
  });

  test('an entryId correction made after an early sync still reaches device B', () async {
    // Reproduces the entry_editor_screen.dart race that motivated Fix 1 in
    // PhotoMetaSyncService: _addPhoto() saves a brand-new PhotoAsset with
    // entryId: '' immediately (the real entry id isn't known until _save()
    // runs). If a sync fires in that window -- and the binary upload
    // happens to complete during it too -- driveFileId ends up settled
    // (non-null on both sides) while entryId is still stale on Drive.
    Hive.init(tempDirA.path);
    entryRepoA = await EntryRepository.open();
    photoRepoA = await PhotoRepository.open();

    final srcFile = File('${tempDirA.path}/pic.jpg');
    await srcFile.writeAsBytes([1, 2, 3, 4]);

    // _addPhoto(): entryId is '' because the entry doesn't exist yet.
    await photoRepoA.save(PhotoAsset(
      id: 'p1',
      entryId: '',
      createdAt: DateTime.utc(2026, 8, 9),
      localPath: srcFile.path,
    ));

    // A connectivity-triggered sync fires before the user hits save. No
    // entry exists yet, so only the photo (with its stale entryId) syncs;
    // the binary sync in the same pass also completes, so driveFileId ends
    // up settled on both sides with entryId still ''.
    await fullSync(entryRepoA, photoRepoA, filesDirA);
    expect(drivePhotoMetas.remote['p1']!.entryId, '');
    expect(drivePhotoMetas.remote['p1']!.driveFileId, isNotNull);

    // _save(): the entry now exists, so entryId gets corrected locally.
    await entryRepoA.save(JournalEntry(
      id: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      updatedAt: DateTime.utc(2026, 8, 9),
      text: 'Entry with a photo',
      photoIds: const ['p1'],
    ));
    final corrected = photoRepoA.getById('p1')!;
    await photoRepoA.save(PhotoAsset(
      id: corrected.id,
      entryId: 'e1',
      createdAt: corrected.createdAt,
      localPath: corrected.localPath,
      driveFileId: corrected.driveFileId,
    ));

    // A later sync should propagate the correction to Drive even though
    // driveFileId already agrees on both sides.
    await fullSync(entryRepoA, photoRepoA, filesDirA);
    expect(drivePhotoMetas.remote['p1']!.entryId, 'e1');
    await Hive.deleteFromDisk();

    // Device B, syncing fresh, must see the corrected entryId -- not the
    // stale '' that was published before _save() ran.
    Hive.init(tempDirB.path);
    entryRepoB = await EntryRepository.open();
    photoRepoB = await PhotoRepository.open();
    await fullSync(entryRepoB, photoRepoB, filesDirB);

    final pulledPhoto = photoRepoB.getById('p1');
    expect(pulledPhoto, isNotNull);
    expect(pulledPhoto!.entryId, 'e1');

    await Hive.deleteFromDisk();
  });
}
