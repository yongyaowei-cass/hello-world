import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/data/entry_repository.dart';
import 'package:journal_app/data/photo_repository.dart';
import 'package:journal_app/main.dart';

// JournalApp now calls AuthService.signInSilently() on startup (Bug 1). Its
// underlying google_sign_in plugin call goes through this method channel;
// with no mock handler registered, the "no implementation found" reply
// comes back via the real engine/platform round trip rather than a
// zone-local microtask, so it never resolves inside testWidgets' FakeAsync
// zone and pumpAndSettle hangs forever (confirmed by direct reproduction).
// Mocking the channel is the standard fix (see google_sign_in_platform_
// interface's own MethodChannelGoogleSignIn tests for the same pattern) and
// also makes "no cached session" deterministic instead of relying on
// whatever a real, unmocked plugin call happens to do.
const _googleSignInChannel = MethodChannel('plugins.flutter.io/google_sign_in');

void main() {
  late Directory tempDir;
  late EntryRepository repo;
  late PhotoRepository photoRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('main_smoke_test');
    Hive.init(tempDir.path);
    repo = await EntryRepository.open();
    photoRepo = await PhotoRepository.open();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_googleSignInChannel, (call) async => null);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_googleSignInChannel, null);
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  testWidgets('tapping Skip for now navigates from sign-in to the entry list', (tester) async {
    await tester.pumpWidget(JournalApp(entryRepository: repo, photoRepository: photoRepo));
    await tester.pumpAndSettle();

    expect(find.text('Skip for now'), findsOneWidget);

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(find.text('Journal'), findsOneWidget);
  });

  testWidgets('shows a loading indicator while checking for a cached Google session', (tester) async {
    await tester.pumpWidget(JournalApp(entryRepository: repo, photoRepository: photoRepo));

    // Before the silent sign-in check resolves (the mocked channel above
    // reports "no cached session"), the app should show a brief loading
    // state instead of jumping straight to the sign-in screen.
    expect(find.byKey(const Key('silentSignInLoading')), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('silentSignInLoading')), findsNothing);
    expect(find.text('Skip for now'), findsOneWidget);
  });

  testWidgets('app-resumed lifecycle event does not crash when there is no signed-in account', (tester) async {
    await tester.pumpWidget(JournalApp(entryRepository: repo, photoRepository: photoRepo));
    await tester.pumpAndSettle();

    // Regression guard for the foreground-sync wiring (WidgetsBindingObserver
    // registration/dispose and didChangeAppLifecycleState calling _trySync).
    // _trySync's Drive orchestration itself isn't exercised here (no signed-in
    // account is constructible in tests, see main_silent_sign_in_test.dart);
    // the pure resumed-triggers-sync rule is covered by
    // main_lifecycle_sync_test.dart. This just proves the observer is wired
    // without throwing.
    WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
