import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/main.dart';
import 'package:journal_app/screens/entry_list_screen.dart';

// _trySync()'s guarded work used to call AuthService.authenticatedClient()
// OUTSIDE runSyncWithStatus's try/catch:
//
//   final account = _authService.currentUser;
//   if (account == null) return;
//   final authClient = await _authService.authenticatedClient();
//   if (authClient == null) return;
//   await runSyncWithStatus(_syncStatus, () async { ... });
//
// authenticatedClient() can throw (e.g. offline, an expired or revoked
// token), and that throw sat outside runSyncWithStatus's guard, so
// _syncStatus was never flipped to SyncStatus.offline on this specific
// failure — it stayed at whatever it was before. That's only accidentally
// correct on a cold start (where it already defaults to offline); after a
// prior successful sync it left the UI stuck showing "synced" even though
// the latest sync attempt failed. It also meant the throw propagated out of
// _trySync() itself, which didChangeAppLifecycleState invokes as a bare
// VoidCallback (handleAppLifecycleStateForSync(state, _trySync)),
// discarding the returned Future with no error handling — an unhandled
// async error on an offline resume-while-signed-in.
//
// performSync() is extracted as a top-level function, parameterized over
// plain fakes (same rationale as runSyncWithStatus and attemptSilentSignIn
// in this file's sibling test files), with authenticatedClient() now called
// INSIDE runSyncWithStatus's guarded closure so both problems are closed by
// the same try/catch.
void main() {
  test('performSync does nothing when there is no signed-in user', () async {
    final status = ValueNotifier(SyncStatus.offline);
    var authClientCalled = false;
    var doSyncCalled = false;

    await performSync(
      null,
      status,
      () async {
        authClientCalled = true;
        return Object();
      },
      (authClient) async {
        doSyncCalled = true;
      },
    );

    expect(authClientCalled, isFalse);
    expect(doSyncCalled, isFalse);
    expect(status.value, SyncStatus.offline);
  });

  test('performSync sets status to syncing then synced when signed in and sync succeeds', () async {
    final status = ValueNotifier(SyncStatus.offline);
    final seen = <SyncStatus>[];
    status.addListener(() => seen.add(status.value));
    var doSyncCalled = false;

    await performSync(
      Object(),
      status,
      () async => Object(),
      (authClient) async {
        doSyncCalled = true;
      },
    );

    expect(seen, [SyncStatus.syncing, SyncStatus.synced]);
    expect(doSyncCalled, isTrue);
  });

  // Regression test for the reviewed bug: when authenticatedClient() returns
  // null (reachable offline, or when a cached token can't be refreshed), the
  // guarded closure used to return normally instead of throwing, so
  // runSyncWithStatus fell through to `synced` even though nothing was
  // synced. Simulating a prior successful sync (status starts at `synced`)
  // makes that false-success bug observable: without the fix this test's
  // status would stay `synced` instead of correctly flipping to `offline`.
  test('performSync does not call doSync when authenticatedClient returns null', () async {
    final status = ValueNotifier(SyncStatus.synced);
    var doSyncCalled = false;

    await performSync(
      Object(),
      status,
      () async => null,
      (authClient) async {
        doSyncCalled = true;
      },
    );

    expect(doSyncCalled, isFalse);
    expect(status.value, SyncStatus.offline);
  });

  // Regression test for the reviewed bug: previously authenticatedClient()
  // was called BEFORE runSyncWithStatus, so a throw from it propagated out
  // of _trySync entirely, leaving _syncStatus untouched. Simulating a prior
  // successful sync (status starts at `synced`) makes the stale-status bug
  // observable: without the fix this test's status would stay `synced`.
  test(
    'performSync sets status to offline (not left stuck on a prior synced value) '
    'when authenticatedClient throws',
    () async {
      final status = ValueNotifier(SyncStatus.synced);
      final seen = <SyncStatus>[];
      status.addListener(() => seen.add(status.value));

      await performSync(
        Object(),
        status,
        () async => throw Exception('authenticatedClient failed: offline'),
        (authClient) async {},
      );

      expect(status.value, SyncStatus.offline);
      expect(seen, [SyncStatus.syncing, SyncStatus.offline]);
    },
  );

  test('performSync does not rethrow when authenticatedClient throws', () async {
    final status = ValueNotifier(SyncStatus.offline);

    await expectLater(
      performSync(
        Object(),
        status,
        () async => throw Exception('boom'),
        (authClient) async {},
      ),
      completes,
    );
  });
}
