import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/data/photo_repository.dart';
import 'package:journal_app/models/photo_asset.dart';
import 'package:journal_app/sync/drive_photo_store.dart';
import 'package:journal_app/sync/photo_sync_service.dart';

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

void main() {
  late Directory tempDir;
  late PhotoRepository local;
  late FakeDrivePhotoStore remote;
  late PhotoSyncService sync;
  late Directory localFilesDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('photo_sync_test');
    Hive.init(tempDir.path);
    local = await PhotoRepository.open();
    remote = FakeDrivePhotoStore();
    localFilesDir = await Directory('${tempDir.path}/files').create();
    sync = PhotoSyncService(
      saveLocalBytes: (photoId, bytes) async {
        final file = File('${localFilesDir.path}/$photoId.jpg');
        await file.writeAsBytes(bytes);
        return file.path;
      },
    );
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  test('local-only photo with no driveFileId gets uploaded and stamped with the returned id', () async {
    final srcFile = File('${tempDir.path}/pic.jpg');
    await srcFile.writeAsBytes([1, 2, 3]);
    await local.save(PhotoAsset(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      localPath: srcFile.path,
    ));

    await sync.sync(local, remote);

    expect(remote.remote['p1'], [1, 2, 3]);
    expect(local.getById('p1')!.driveFileId, 'drive-file-p1');
  });

  test('remote-only photo with no local file gets downloaded and stamped with a local path', () async {
    remote.remote['p1'] = Uint8List.fromList([4, 5, 6]);
    await local.save(PhotoAsset(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      driveFileId: 'drive-file-p1',
    ));

    await sync.sync(local, remote);

    final updated = local.getById('p1')!;
    expect(updated.localPath, isNotNull);
    expect(await File(updated.localPath!).readAsBytes(), [4, 5, 6]);
  });

  test('photo already present on both sides is left unchanged', () async {
    final srcFile = File('${tempDir.path}/pic.jpg');
    await srcFile.writeAsBytes([1, 2, 3]);
    await local.save(PhotoAsset(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      localPath: srcFile.path,
      driveFileId: 'drive-file-p1',
    ));

    await sync.sync(local, remote);

    expect(remote.remote.containsKey('p1'), isFalse);
  });
}
