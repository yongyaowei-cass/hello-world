import '../data/photo_repository.dart';
import '../models/photo_asset.dart';
import 'drive_photo_meta_store.dart';

/// Reconciles [PhotoAsset] *metadata* (not binaries) between local Hive
/// storage and Drive, mirroring [SyncService]'s id-diffing approach for
/// journal entries.
///
/// This is what lets a device that only knows about a photo via an entry's
/// `photoIds` (pulled through the ordinary entry sync) learn the rest of the
/// record -- `entryId`, `createdAt`, and eventually `driveFileId` -- so the
/// existing [PhotoSyncService] binary-download branch (which only looks at
/// [PhotoRepository.getAll]) has something to act on.
///
/// Callers should run this both before and after [PhotoSyncService.sync] in
/// a single sync pass: once before, so newly-learned remote photos exist
/// locally (with `localPath: null`) in time for the binary sync to download
/// them; once after, so a `driveFileId` that binary sync just discovered
/// during upload gets published to Drive for other devices to find. Running
/// it twice is safe -- each branch below is idempotent once both sides
/// agree.
class PhotoMetaSyncService {
  Future<void> sync(PhotoRepository local, DrivePhotoMetaStore remote) async {
    final remoteMetas = {for (final m in await remote.listMetas()) m.id: m};
    final localAssets = {for (final a in local.getAll()) a.id: a};
    final allIds = {...remoteMetas.keys, ...localAssets.keys};

    for (final id in allIds) {
      final localAsset = localAssets[id];
      final remoteMeta = remoteMetas[id];

      if (localAsset == null && remoteMeta != null) {
        // Remote knows about a photo this device has never heard of --
        // create a local record with localPath: null so the binary sync
        // knows there's something to download.
        await local.save(PhotoAsset(
          id: remoteMeta.id,
          entryId: remoteMeta.entryId,
          createdAt: remoteMeta.createdAt,
          driveFileId: remoteMeta.driveFileId,
        ));
      } else if (localAsset != null && remoteMeta == null) {
        // This device knows about a photo Drive has never heard of --
        // publish its existence immediately, even before the binary
        // finishes uploading.
        await remote.upload(_toRemoteMeta(localAsset));
      } else if (localAsset != null && remoteMeta != null) {
        final localMeta = _toRemoteMeta(localAsset);
        if (localAsset.driveFileId == null && remoteMeta.driveFileId != null) {
          // Remote already knows the driveFileId (another device uploaded
          // it) but this local record doesn't yet -- pull it in, without
          // touching localPath, so the binary sync's download branch picks
          // it up.
          await local.save(localAsset.copyWith(driveFileId: remoteMeta.driveFileId));
        } else if (!_metaEquals(localMeta, remoteMeta)) {
          // Local and remote disagree on some field other than the
          // null/non-null driveFileId case handled above -- most notably
          // entryId, which entry_editor_screen.dart's _addPhoto() initially
          // saves as '' for a brand-new entry and only corrects once _save()
          // runs. If a sync fires in between (and the binary upload also
          // completes in that window), driveFileId can end up settled
          // (non-null on both sides) while entryId is still stale on
          // remote. There's no updatedAt/version field on PhotoAsset to do
          // real last-write-wins, so treat local as authoritative and push
          // it: the creating device is the only one that ever changes these
          // fields post-creation, and only during this brief window.
          await remote.upload(localMeta);
        }
        // Otherwise both sides already fully agree -- nothing to do.
      }
    }
  }

  RemotePhotoMeta _toRemoteMeta(PhotoAsset asset) => RemotePhotoMeta(
        id: asset.id,
        entryId: asset.entryId,
        createdAt: asset.createdAt,
        driveFileId: asset.driveFileId,
      );

  bool _metaEquals(RemotePhotoMeta a, RemotePhotoMeta b) =>
      a.id == b.id &&
      a.entryId == b.entryId &&
      a.createdAt == b.createdAt &&
      a.driveFileId == b.driveFileId;
}
