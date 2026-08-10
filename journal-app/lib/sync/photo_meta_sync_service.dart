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

        // Pull side: adopt any correction remote already has that this
        // local replica is still missing. Both pulls are gathered into a
        // single save so a record needing both corrections catches up in
        // one pass instead of two.
        final needsDriveFileIdPull =
            localAsset.driveFileId == null && remoteMeta.driveFileId != null;
        final needsEntryIdPull =
            localAsset.entryId.isEmpty && remoteMeta.entryId.isNotEmpty;
        if (needsDriveFileIdPull || needsEntryIdPull) {
          // Remote already knows a value (driveFileId and/or entryId) that
          // this local record doesn't yet -- pull it/them in, without
          // touching localPath, so the binary sync's download branch (for
          // driveFileId) still works off an untouched localPath.
          await local.save(localAsset.copyWith(
            driveFileId: needsDriveFileIdPull ? remoteMeta.driveFileId : null,
            entryId: needsEntryIdPull ? remoteMeta.entryId : null,
          ));
        } else if ((localAsset.driveFileId != null && remoteMeta.driveFileId == null) ||
            (localAsset.entryId.isNotEmpty && remoteMeta.entryId.isEmpty)) {
          // Push local's metadata, but only for the two specific one-way
          // transitions this device can ever be the origin of -- never for
          // an arbitrary diff:
          //
          //  - driveFileId: null -> non-null. This device's own binary
          //    upload just discovered the driveFileId (the reverse, pull,
          //    direction is handled above); once set, a driveFileId never
          //    reverts to null, so this can't flip back.
          //  - entryId: '' -> non-empty. entry_editor_screen.dart's
          //    _addPhoto() initially saves a brand-new photo with
          //    entryId: '' and only corrects it once _save() runs. If a
          //    sync fires in between (and the binary upload also completes
          //    in that window), driveFileId can end up settled while
          //    entryId is still '' on remote.
          //
          // Both are one-way: the "before" state (null / '') never comes
          // back once corrected. That's what makes this safe without a
          // version/timestamp field on PhotoAsset -- a device whose local
          // replica still holds the "before" value (e.g. it merely pulled a
          // placeholder from another device, rather than being the device
          // that produced the correction) never satisfies the "after" side
          // of either check, so it can never push a stale value back over a
          // correction another device already made. The old rule pushed on
          // *any* diff, which had no such guarantee and could oscillate
          // forever between two devices trading a stale value back and
          // forth.
          await remote.upload(localMeta);
        }
        // Otherwise both sides already fully agree -- nothing to do. This
        // relies on the same one-way-transition invariant as the push branch
        // above: driveFileId only ever goes null -> a single stable value,
        // and entryId only ever goes '' -> a single stable value, each set
        // by exactly one origin device. So if neither side is missing a
        // value the other has (the pull branch), and neither side has a
        // value the other is still missing (the push branch), there's no
        // remaining state in which the two non-null/non-empty values could
        // differ -- both must already hold the same final value.
      }
    }
  }

  RemotePhotoMeta _toRemoteMeta(PhotoAsset asset) => RemotePhotoMeta(
        id: asset.id,
        entryId: asset.entryId,
        createdAt: asset.createdAt,
        driveFileId: asset.driveFileId,
      );
}
