import 'package:hive_flutter/hive_flutter.dart';
import '../models/photo_asset.dart';

class PhotoRepository {
  PhotoRepository(this._box);

  final Box<Map> _box;

  static Future<PhotoRepository> open() async {
    final box = await Hive.openBox<Map>('photos');
    return PhotoRepository(box);
  }

  List<PhotoAsset> getForEntry(String entryId) {
    return _box.values
        .map(PhotoAsset.fromJson)
        .where((p) => p.entryId == entryId)
        .toList();
  }

  PhotoAsset? getById(String id) {
    final raw = _box.get(id);
    return raw == null ? null : PhotoAsset.fromJson(raw);
  }

  Future<void> save(PhotoAsset asset) => _box.put(asset.id, asset.toJson());

  Future<void> delete(String id) => _box.delete(id);
}
