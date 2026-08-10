import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/main.dart';

// _trySync() in main.dart had no guard against running twice concurrently.
// Per the design spec, sync runs on app foreground (AppLifecycleState.resumed)
// as well as on connectivity-restored, save, and delete. But `resumed` fires
// whenever ANY external activity is dismissed — not just a genuine app
// reopen — including the photo picker (image_picker) and Google's own
// account-picker activity. So picking a photo mid-edit, or the sign-in flow
// itself, can trigger a concurrent _trySync() call while another one (e.g.
// onSignIn's own explicit `await _trySync()`, or onSaved's `_trySync()`) is
// still in flight, interleaving writes to SyncStatus and the sync services
// over the same repositories.
//
// runGuardedSync() is extracted as a top-level function, parameterized over
// plain get/set callbacks instead of a real instance field, so the guard
// rule itself is directly unit-testable without a real AuthService/Drive
// client — same rationale as runSyncWithStatus and attemptSilentSignIn in
// this file's sibling test files.
void main() {
  test('runGuardedSync skips a concurrent call while one is already running', () async {
    var inFlight = false;
    var runCount = 0;
    final blocker = Completer<void>();

    Future<void> work() async {
      runCount++;
      await blocker.future;
    }

    final first = runGuardedSync(() => inFlight, (v) => inFlight = v, work);
    // Let the first call's synchronous prelude (setting inFlight = true)
    // run before the second call checks the flag.
    await Future<void>.delayed(Duration.zero);
    expect(inFlight, isTrue);

    final second = runGuardedSync(() => inFlight, (v) => inFlight = v, work);

    blocker.complete();
    await Future.wait([first, second]);

    expect(runCount, 1);
  });

  test('runGuardedSync allows a later call once the previous one has finished', () async {
    var inFlight = false;
    var runCount = 0;

    Future<void> work() async {
      runCount++;
    }

    await runGuardedSync(() => inFlight, (v) => inFlight = v, work);
    await runGuardedSync(() => inFlight, (v) => inFlight = v, work);

    expect(runCount, 2);
    expect(inFlight, isFalse);
  });

  test(
    'runGuardedSync resets the in-flight flag after work throws, so it does not '
    'permanently block every later sync attempt',
    () async {
      var inFlight = false;
      var runCount = 0;

      Future<void> throwingWork() async {
        runCount++;
        throw Exception('Drive request failed: 401');
      }

      await expectLater(
        runGuardedSync(() => inFlight, (v) => inFlight = v, throwingWork),
        throwsException,
      );
      expect(inFlight, isFalse);

      await runGuardedSync(() => inFlight, (v) => inFlight = v, () async => runCount++);

      expect(runCount, 2);
    },
  );
}
