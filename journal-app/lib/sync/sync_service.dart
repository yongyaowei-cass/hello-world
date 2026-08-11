import '../data/entry_repository.dart';
import 'drive_entry_store.dart';

class SyncService {
  Future<void> sync(EntryRepository local, DriveEntryStore remote) async {
    final remoteMetas = {for (final m in await remote.listEntryMetas()) m.id: m};
    final localEntries = {for (final e in local.getAllIncludingDeleted()) e.id: e};

    final allIds = {...remoteMetas.keys, ...localEntries.keys};

    for (final id in allIds) {
      final localEntry = localEntries[id];
      final remoteMeta = remoteMetas[id];

      if (localEntry == null && remoteMeta != null) {
        await local.save(await remote.download(id));
      } else if (localEntry != null && remoteMeta == null) {
        await remote.upload(localEntry);
      } else if (localEntry != null && remoteMeta != null) {
        if (remoteMeta.updatedAt.isAfter(localEntry.updatedAt)) {
          await local.save(await remote.download(id));
        } else if (localEntry.updatedAt.isAfter(remoteMeta.updatedAt)) {
          await remote.upload(localEntry);
        }
      }
    }
  }
}
