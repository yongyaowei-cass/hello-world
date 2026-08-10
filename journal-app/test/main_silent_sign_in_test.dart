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
}
