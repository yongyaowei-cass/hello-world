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
//
// A skipped call must not be a silent drop: onSaved/onDeleted calling
// _trySync() while a lifecycle-triggered sync (e.g. from the photo picker
// closing) is already in flight represents genuine new local state that
// needs pushing. runGuardedSync now marks that a re-run is needed
// (isPending/setPending) and, once the in-flight work() finishes, runs it
// exactly once more — collapsing any number of skipped calls into a single
// trailing run instead of dropping them.
void main() {
  test(
    'runGuardedSync skips a concurrent call while one is already running, but marks it pending',
    () async {
      var inFlight = false;
      var pending = false;
      var runCount = 0;
      final blocker = Completer<void>();

      Future<void> work() async {
        runCount++;
        await blocker.future;
      }

      final first = runGuardedSync(
        () => inFlight,
        (v) => inFlight = v,
        () => pending,
        (v) => pending = v,
        work,
      );
      // Let the first call's synchronous prelude (setting inFlight = true)
      // run before the second call checks the flag.
      await Future<void>.delayed(Duration.zero);
      expect(inFlight, isTrue);

      final second = runGuardedSync(
        () => inFlight,
        (v) => inFlight = v,
        () => pending,
        (v) => pending = v,
        work,
      );
      await second;

      // The second call was skipped (work not re-entered concurrently)...
      expect(runCount, 1);
      // ...but recorded as pending so it isn't silently dropped.
      expect(pending, isTrue);

      blocker.complete();
      await first;

      // The pending flag queued a trailing re-run, so work ran again once
      // the first call finished (see the next test for the dedicated
      // trailing-re-run assertion).
      expect(runCount, 2);
      expect(pending, isFalse);
    },
  );

  test(
    'runGuardedSync runs work a second time (a trailing re-run) after a call was '
    'skipped while the first was in flight',
    () async {
      var inFlight = false;
      var pending = false;
      var runCount = 0;
      final firstBlocker = Completer<void>();

      Future<void> work() async {
        runCount++;
        if (runCount == 1) {
          await firstBlocker.future;
        }
      }

      final first = runGuardedSync(
        () => inFlight,
        (v) => inFlight = v,
        () => pending,
        (v) => pending = v,
        work,
      );
      await Future<void>.delayed(Duration.zero);
      expect(inFlight, isTrue);

      // Arrives while the first call is still running: skipped, but queues
      // a trailing re-run instead of being dropped.
      final second = runGuardedSync(
        () => inFlight,
        (v) => inFlight = v,
        () => pending,
        (v) => pending = v,
        work,
      );
      await second;
      expect(runCount, 1);

      firstBlocker.complete();
      await first;

      // The trailing re-run happened: work was called a second time, not
      // just the first (in-flight) call completing.
      expect(runCount, 2);
      expect(pending, isFalse);
      expect(inFlight, isFalse);
    },
  );

  test(
    'runGuardedSync collapses multiple skipped calls into exactly one trailing re-run',
    () async {
      var inFlight = false;
      var pending = false;
      var runCount = 0;
      final firstBlocker = Completer<void>();

      Future<void> work() async {
        runCount++;
        if (runCount == 1) {
          await firstBlocker.future;
        }
      }

      final first = runGuardedSync(
        () => inFlight,
        (v) => inFlight = v,
        () => pending,
        (v) => pending = v,
        work,
      );
      await Future<void>.delayed(Duration.zero);

      // Several calls arrive while the first is still running.
      await runGuardedSync(() => inFlight, (v) => inFlight = v, () => pending, (v) => pending = v, work);
      await runGuardedSync(() => inFlight, (v) => inFlight = v, () => pending, (v) => pending = v, work);
      await runGuardedSync(() => inFlight, (v) => inFlight = v, () => pending, (v) => pending = v, work);

      firstBlocker.complete();
      await first;

      // Collapsed into exactly one trailing run, not one per skipped call.
      expect(runCount, 2);
      expect(pending, isFalse);
    },
  );

  test('runGuardedSync allows a later call once the previous one has finished', () async {
    var inFlight = false;
    var pending = false;
    var runCount = 0;

    Future<void> work() async {
      runCount++;
    }

    await runGuardedSync(() => inFlight, (v) => inFlight = v, () => pending, (v) => pending = v, work);
    await runGuardedSync(() => inFlight, (v) => inFlight = v, () => pending, (v) => pending = v, work);

    expect(runCount, 2);
    expect(inFlight, isFalse);
  });

  test(
    'runGuardedSync resets the in-flight flag after work throws, so it does not '
    'permanently block every later sync attempt',
    () async {
      var inFlight = false;
      var pending = false;
      var runCount = 0;

      Future<void> throwingWork() async {
        runCount++;
        throw Exception('Drive request failed: 401');
      }

      await expectLater(
        runGuardedSync(() => inFlight, (v) => inFlight = v, () => pending, (v) => pending = v, throwingWork),
        throwsException,
      );
      expect(inFlight, isFalse);

      await runGuardedSync(
        () => inFlight,
        (v) => inFlight = v,
        () => pending,
        (v) => pending = v,
        () async => runCount++,
      );

      expect(runCount, 2);
    },
  );
}
