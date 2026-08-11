import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/data/photo_repository.dart';
import 'package:journal_app/models/photo_asset.dart';

void main() {
  late Directory tempDir;
  late PhotoRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('photo_repo_test');
    Hive.init(tempDir.path);
    repo = await PhotoRepository.open();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  test('save then getById returns the same asset', () async {
    final asset = PhotoAsset(id: 'p1', entryId: 'e1', createdAt: DateTime.utc(2026, 8, 9));
    await repo.save(asset);

    expect(repo.getById('p1')?.entryId, 'e1');
  });

  test('getForEntry returns only photos for that entry', () async {
    await repo.save(PhotoAsset(id: 'p1', entryId: 'e1', createdAt: DateTime.utc(2026, 8, 9)));
    await repo.save(PhotoAsset(id: 'p2', entryId: 'e2', createdAt: DateTime.utc(2026, 8, 9)));

    final forE1 = repo.getForEntry('e1');

    expect(forE1.map((p) => p.id), ['p1']);
  });

  test('delete removes the asset', () async {
    await repo.save(PhotoAsset(id: 'p1', entryId: 'e1', createdAt: DateTime.utc(2026, 8, 9)));

    await repo.delete('p1');

    expect(repo.getById('p1'), isNull);
  });

  test('getAll returns every stored photo asset', () async {
    await repo.save(PhotoAsset(id: 'p1', entryId: 'e1', createdAt: DateTime.utc(2026, 8, 9)));
    await repo.save(PhotoAsset(id: 'p2', entryId: 'e2', createdAt: DateTime.utc(2026, 8, 9)));

    expect(repo.getAll().map((p) => p.id), containsAll(['p1', 'p2']));
  });
}
