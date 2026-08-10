import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/main.dart';

// AuthService.signInSilently() returns a GoogleSignInAccount, a type with no
// public constructor (same constraint documented in main_sync_status_test.dart
// for Drive/auth types). attemptSilentSignIn() is extracted as a top-level
// function taking a signInSilently callback typed to return Future<Object?>
// so the fallback logic (skip SignInScreen on a cached session, fall back to
// it otherwise) is directly testable with plain fakes instead.
void main() {
  test('attemptSilentSignIn syncs and returns true when a cached session is found', () async {
    var syncCalled = false;
    final result = await attemptSilentSignIn(
      () async => Object(),
      () async {
        syncCalled = true;
      },
    );

    expect(result, isTrue);
    expect(syncCalled, isTrue);
  });

  test('attemptSilentSignIn returns false without syncing when there is no cached session', () async {
    var syncCalled = false;
    final result = await attemptSilentSignIn(
      () async => null,
      () async {
        syncCalled = true;
      },
    );

    expect(result, isFalse);
    expect(syncCalled, isFalse);
  });

  test('attemptSilentSignIn returns false without rethrowing when silent sign-in throws', () async {
    var syncCalled = false;
    final result = await attemptSilentSignIn(
      () async => throw Exception('no cached session'),
      () async {
        syncCalled = true;
      },
    );

    expect(result, isFalse);
    expect(syncCalled, isFalse);
  });

  // Regression test for the reviewed bug: a cached session was found (so
  // signInSilently succeeds), but the subsequent trySync — concretely,
  // _trySync()'s _authService.authenticatedClient() call, e.g. on a cold
  // offline launch — throws. Previously attemptSilentSignIn awaited trySync
  // directly, so this throw propagated out of attemptSilentSignIn itself,
  // aborting _initSilentSignIn's `await attemptSilentSignIn(...)` before it
  // ever reached the `setState` that turns off `_checkingSilentSignIn` —
  // freezing the app on the loading spinner forever, with no timeout and no
  // way out. attemptSilentSignIn must both (a) not hang waiting on trySync
  // and (b) not let a trySync failure prevent it from resolving `true`.
  test(
    'attemptSilentSignIn resolves promptly to true, without hanging or rethrowing, '
    'when a cached session is found but the subsequent sync throws',
    () async {
      final result = await attemptSilentSignIn(
        () async => Object(),
        () async => throw Exception('authenticatedClient failed: offline'),
      );

      expect(result, isTrue);
    },
  );

  test(
    'attemptSilentSignIn does not block on how long the sync takes to finish',
    () async {
      final neverCompletes = Completer<void>();
      final result = await attemptSilentSignIn(
        () async => Object(),
        () => neverCompletes.future,
      );

      // If attemptSilentSignIn awaited trySync's completion, this await
      // would hang forever (neverCompletes is never completed) and the test
      // itself would time out instead of finishing.
      expect(result, isTrue);
    },
  );
}
