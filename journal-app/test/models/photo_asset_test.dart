import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/photo_asset.dart';

void main() {
  test('PhotoAsset toJson/fromJson round-trips all fields', () {
    final asset = PhotoAsset(
      id: 'p1',
      entryId: 'e1',
      localPath: '/cache/p1.jpg',
      driveFileId: 'drive-123',
      createdAt: DateTime.utc(2026, 8, 9),
    );

    final restored = PhotoAsset.fromJson(asset.toJson());

    expect(restored.id, asset.id);
    expect(restored.entryId, asset.entryId);
    expect(restored.localPath, asset.localPath);
    expect(restored.driveFileId, asset.driveFileId);
    expect(restored.createdAt, asset.createdAt);
  });

  test('PhotoAsset toJson serializes createdAt as UTC even when constructed from local time', () {
    final localCreatedAt = DateTime(2026, 8, 9, 9, 40);
    final asset = PhotoAsset(id: 'p1', entryId: 'e1', createdAt: localCreatedAt);

    final json = asset.toJson();
    final createdAtStr = json['createdAt'] as String;

    expect(createdAtStr.endsWith('Z') || createdAtStr.contains('+00:00'), isTrue,
        reason: 'createdAt "$createdAtStr" is missing a UTC indicator');
    expect(PhotoAsset.fromJson(json).createdAt.toUtc(), localCreatedAt.toUtc());
  });

  test('PhotoAsset fromJson allows null localPath and driveFileId', () {
    final restored = PhotoAsset.fromJson({
      'id': 'p2',
      'entryId': 'e1',
      'createdAt': '2026-08-09T00:00:00.000Z',
    });

    expect(restored.localPath, isNull);
    expect(restored.driveFileId, isNull);
  });
}
