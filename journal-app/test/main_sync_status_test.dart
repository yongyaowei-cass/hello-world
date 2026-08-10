import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/main.dart';
import 'package:journal_app/screens/entry_list_screen.dart';

// _trySync() in main.dart resolves the signed-in account and Drive auth
// client, then delegates the actual sync work (and the syncing/synced/
// offline status transitions around it) to this extracted, directly
// testable helper. Testing this in isolation avoids needing to fake
// GoogleSignIn's account/auth-client types, which aren't constructible
// outside the plugin.
void main() {
  test('runSyncWithStatus sets syncing then synced when the sync work succeeds', () async {
    final status = ValueNotifier(SyncStatus.offline);
    final seen = <SyncStatus>[];
    status.addListener(() => seen.add(status.value));

    await runSyncWithStatus(status, () async {});

    expect(seen, [SyncStatus.syncing, SyncStatus.synced]);
  });

  test('runSyncWithStatus recovers to offline instead of staying stuck on syncing when the sync work throws', () async {
    final status = ValueNotifier(SyncStatus.offline);
    final seen = <SyncStatus>[];
    status.addListener(() => seen.add(status.value));

    await runSyncWithStatus(status, () async {
      throw Exception('Drive request failed: 401');
    });

    expect(seen, [SyncStatus.syncing, SyncStatus.offline]);
  });

  test('runSyncWithStatus does not rethrow on failure (a failed background sync should not crash the app)', () async {
    final status = ValueNotifier(SyncStatus.offline);

    await expectLater(
      runSyncWithStatus(status, () async => throw Exception('boom')),
      completes,
    );
  });
}
