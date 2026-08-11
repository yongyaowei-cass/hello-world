import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;
import 'package:hive_flutter/hive_flutter.dart';

import 'ai/groq_reflection_service.dart';
import 'data/entry_repository.dart';
import 'data/photo_repository.dart';
import 'models/journal_entry.dart';
import 'photos/photo_bytes_store.dart';
import 'screens/entry_detail_screen.dart';
import 'screens/entry_editor_screen.dart';
import 'screens/entry_list_screen.dart';
import 'screens/sign_in_screen.dart';
import 'sync/auth_service.dart';
import 'sync/google_drive_entry_store.dart';
import 'sync/google_drive_photo_meta_store.dart';
import 'sync/google_drive_photo_store.dart';
import 'sync/photo_meta_sync_service.dart';
import 'sync/photo_sync_service.dart';
import 'sync/sync_service.dart';
import 'theme/app_theme.dart';

// Free tier, no credit card required: https://console.groq.com
const _groqApiKey = String.fromEnvironment('GROQ_API_KEY');

/// Runs [doSync], driving [status] through syncing -> synced on success or
/// syncing -> offline on failure. Never rethrows: a failed background sync
/// shouldn't crash the app, and leaving [status] stuck on `syncing` forever
/// (the pre-fix behavior when a Drive call threw) hides that a retry is
/// even needed. Extracted as a top-level function so it's directly
/// unit-testable without needing a real/fake GoogleSignIn account or Drive
/// client (see test/main_sync_status_test.dart).
@visibleForTesting
Future<void> runSyncWithStatus(
  ValueNotifier<SyncStatus> status,
  Future<void> Function() doSync,
) async {
  status.value = SyncStatus.syncing;
  try {
    await doSync();
    status.value = SyncStatus.synced;
  } catch (_) {
    status.value = SyncStatus.offline;
  }
}

/// Attempts a silent (no user interaction) sign-in via [signInSilently] and,
/// if it finds a cached session, kicks off [trySync] and reports success.
/// Returns false (without syncing) if there's no cached session or
/// [signInSilently] throws — callers should fall back to showing an explicit
/// sign-in screen in that case. A [signInSilently] failure never propagates
/// (a failed background check shouldn't crash the app).
///
/// [trySync] is fired and forgotten — started, but never awaited — so this
/// function's returned Future resolves as soon as [signInSilently] answers,
/// regardless of how long the sync takes or whether it ultimately succeeds
/// or fails. This matters concretely: a caller (see `_initSilentSignIn`)
/// typically gates a loading spinner on this function's result. Previously
/// [trySync] was awaited directly here, so on a cold, offline launch with a
/// cached Google session, a throw from the sync (e.g.
/// `AuthService.authenticatedClient()` failing before it ever reaches
/// [runSyncWithStatus]'s own guard) propagated out of this function, which
/// aborted the caller's `await` before it could turn off the spinner —
/// freezing the app forever on a bare loading indicator. Any error from
/// [trySync] is now swallowed here too (on top of [runSyncWithStatus]'s own
/// guard), so it can never surface as an unhandled Future error either.
/// Extracted as a top-level function, typed against a plain nullable
/// [Object] rather than [GoogleSignInAccount] (which has no public
/// constructor), so it's directly unit-testable without a real GoogleSignIn
/// account (see test/main_silent_sign_in_test.dart).
@visibleForTesting
Future<bool> attemptSilentSignIn(
  Future<Object?> Function() signInSilently,
  Future<void> Function() trySync,
) async {
  Object? account;
  try {
    account = await signInSilently();
  } catch (_) {
    return false;
  }
  if (account == null) return false;
  unawaited(trySync().catchError((_) {}));
  return true;
}

/// Per the design spec, sync should run "periodically (and on app
/// foreground / connectivity-restored)". This implements the foreground
/// half: only the transition to [AppLifecycleState.resumed] (the app
/// coming back to the front) triggers [trySync]; other lifecycle states
/// (inactive, paused, detached, hidden) are no-ops. Extracted as a
/// top-level function so the state-filtering rule is directly
/// unit-testable without a real WidgetsBinding lifecycle event or a
/// signed-in AuthService/Drive client (see test/main_lifecycle_sync_test.dart).
@visibleForTesting
void handleAppLifecycleStateForSync(AppLifecycleState state, VoidCallback trySync) {
  if (state == AppLifecycleState.resumed) {
    trySync();
  }
}

/// Runs [work] unless a previous call through this same guard is still
/// running. [isInFlight]/[setInFlight] track that state for the caller
/// (typically backed by a single instance field) so the guard rule itself
/// has no dependency on any particular state container and is directly
/// unit-testable (see test/main_sync_guard_test.dart). The in-flight flag
/// is always reset via `finally`, even when [work] throws, so a single
/// failure can't permanently wedge every later call into a no-op.
///
/// Addresses the fact that [AppLifecycleState.resumed] fires whenever any
/// external activity is dismissed — not just when the user genuinely
/// reopens the app — including the photo picker and Google's own
/// account-picker activity. Without this guard, picking a photo mid-edit or
/// the sign-in flow itself could trigger a concurrent `_trySync()` call
/// while another one (from `onSignIn`, `onSaved`, or the startup silent
/// sign-in check) is still in flight, interleaving writes to `SyncStatus`
/// and the sync services over the same repositories.
///
/// A call that arrives while another is in flight is NOT simply dropped: it
/// would otherwise silently discard a legitimate trigger. Concretely,
/// `onSaved`/`onDeleted` call `_trySync()` because new local state needs
/// pushing; if that call landed while a lifecycle-triggered sync (e.g. the
/// photo picker closing) was already in flight and got dropped, the
/// in-flight sync — which read the repository BEFORE the save/delete —
/// would still finish and set status to `synced`, even though the new
/// entry was never pushed. Instead, [isPending]/[setPending] record that a
/// re-run is needed, and once the in-flight [work] finishes, this runs
/// [work] exactly once more, reflecting state at (or after) the skip. Any
/// number of calls skipped while one run is in flight collapse into a
/// single trailing re-run, not one re-run per skipped call.
@visibleForTesting
Future<void> runGuardedSync(
  bool Function() isInFlight,
  void Function(bool) setInFlight,
  bool Function() isPending,
  void Function(bool) setPending,
  Future<void> Function() work,
) async {
  if (isInFlight()) {
    setPending(true);
    return;
  }
  setInFlight(true);
  try {
    await work();
  } finally {
    setInFlight(false);
  }
  if (isPending()) {
    setPending(false);
    await runGuardedSync(isInFlight, setInFlight, isPending, setPending, work);
  }
}

/// Runs the actual sync work behind `_trySync()`: checks for a signed-in
/// account, obtains a Drive-authenticated client, and delegates to
/// [runSyncWithStatus] for the syncing/synced/offline status transitions.
///
/// [currentUser] is checked BEFORE calling [runSyncWithStatus] at all: "not
/// signed in" is a normal no-op, not a sync failure, so it must not touch
/// [status]. [authenticatedClient] is deliberately called INSIDE
/// [runSyncWithStatus]'s guarded closure (not before it, as this used to be
/// structured) so that a throw from it — e.g. offline, an expired or
/// revoked token — is caught by the same try/catch and correctly flips
/// [status] to `SyncStatus.offline`. Previously `authenticatedClient()` sat
/// outside that guard, so a throw there propagated straight out of
/// `_trySync()` — an unhandled Future rejection at the
/// `didChangeAppLifecycleState` call site, which invokes `_trySync` as a
/// bare `VoidCallback` — and left [status] at whatever it was before: wrong
/// after a prior successful sync, where the UI would keep showing "synced"
/// even though the latest attempt failed.
///
/// Extracted as a top-level function, parameterized over plain fakes, for
/// the same testability reasons as [runSyncWithStatus] and
/// [attemptSilentSignIn] (see test/main_try_sync_test.dart).
@visibleForTesting
Future<void> performSync(
  Object? currentUser,
  ValueNotifier<SyncStatus> status,
  Future<Object?> Function() authenticatedClient,
  Future<void> Function(Object authClient) doSync,
) async {
  if (currentUser == null) return;
  await runSyncWithStatus(status, () async {
    final authClient = await authenticatedClient();
    if (authClient == null) {
      throw StateError('No authenticated Drive client available');
    }
    await doSync(authClient);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final entryRepository = await EntryRepository.open();
  final photoRepository = await PhotoRepository.open();
  runApp(JournalApp(entryRepository: entryRepository, photoRepository: photoRepository));
}

class JournalApp extends StatefulWidget {
  const JournalApp({super.key, required this.entryRepository, required this.photoRepository});

  final EntryRepository entryRepository;
  final PhotoRepository photoRepository;

  @override
  State<JournalApp> createState() => _JournalAppState();
}

class _JournalAppState extends State<JournalApp> with WidgetsBindingObserver {
  final _authService = AuthService();
  final _syncService = SyncService();
  final _photoSyncService = PhotoSyncService(saveLocalBytes: saveLocalPhotoBytes);
  final _photoMetaSyncService = PhotoMetaSyncService();
  final _syncStatus = ValueNotifier(SyncStatus.offline);
  GroqReflectionService? _reflectionService;

  // True while the startup silent-sign-in check (see attemptSilentSignIn) is
  // in flight; the app shows a brief loading state instead of SignInScreen
  // while this is true, so a returning user isn't asked to tap "Sign in with
  // Google" on every launch.
  bool _checkingSilentSignIn = true;
  bool _signedInSilently = false;

  // Guards _trySync() against running concurrently with itself (see
  // runGuardedSync's docstring for why AppLifecycleState.resumed alone makes
  // this reachable). Always reset in runGuardedSync's `finally`.
  bool _syncInFlight = false;

  // Set when a _trySync() call arrives while _syncInFlight is already true,
  // so that call's work runs once more (a single trailing re-run) instead
  // of being silently dropped — see runGuardedSync's docstring.
  bool _syncPending = false;

  @override
  void initState() {
    super.initState();
    if (_groqApiKey.isNotEmpty) {
      _reflectionService = GroqReflectionService(apiKey: _groqApiKey);
    }
    WidgetsBinding.instance.addObserver(this);
    Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) {
        _trySync();
      }
    });
    _initSilentSignIn();
  }

  Future<void> _initSilentSignIn() async {
    final signedIn = await attemptSilentSignIn(_authService.signInSilently, _trySync);
    if (mounted) {
      setState(() {
        _checkingSilentSignIn = false;
        _signedInSilently = signedIn;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Design spec: sync "periodically (and on app foreground /
    // connectivity-restored)". This covers the foreground half; connectivity
    // is covered by the onConnectivityChanged listener above.
    handleAppLifecycleStateForSync(state, _trySync);
  }

  Future<void> _trySync() {
    return runGuardedSync(
      () => _syncInFlight,
      (value) => _syncInFlight = value,
      () => _syncPending,
      (value) => _syncPending = value,
      () => performSync(
        _authService.currentUser,
        _syncStatus,
        _authService.authenticatedClient,
        (authClient) async {
          final client = authClient as gapis.AuthClient;
          final store = GoogleDriveEntryStore(drive.DriveApi(client));
          final photoMetaStore = GoogleDrivePhotoMetaStore(drive.DriveApi(client));
          final photoStore = GoogleDrivePhotoStore(drive.DriveApi(client));
          await _syncService.sync(widget.entryRepository, store);
          // Pull metadata for photos this device doesn't know about yet (so
          // the binary sync below has something to download) and push
          // metadata for photos Drive doesn't know about yet.
          await _photoMetaSyncService.sync(widget.photoRepository, photoMetaStore);
          await _photoSyncService.sync(widget.photoRepository, photoStore);
          // Run metadata sync again so a driveFileId the binary sync just
          // discovered (on upload) gets published to Drive for other
          // devices.
          await _photoMetaSyncService.sync(widget.photoRepository, photoMetaStore);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Journal',
      theme: appTheme,
      home: Builder(
        builder: (context) {
          if (_checkingSilentSignIn) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(key: Key('silentSignInLoading')),
              ),
            );
          }
          if (_signedInSilently) {
            // A cached session was restored without user interaction: go
            // straight to the entry list instead of SignInScreen.
            return _buildEntryList(context);
          }
          return SignInScreen(
            onSignIn: () async {
              await _authService.signIn();
              await _trySync();
              if (context.mounted) _openList(context);
            },
            onSkip: () => _openList(context),
          );
        },
      ),
    );
  }

  Widget _buildEntryList(BuildContext context) {
    return EntryListScreen(
      repository: widget.entryRepository,
      onCreateEntry: () => _openEditor(context, null),
      onOpenEntry: (entry) => _openDetail(context, entry),
      syncStatus: _syncStatus,
    );
  }

  void _openList(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: _buildEntryList));
  }

  void _openEditor(BuildContext context, JournalEntry? existing) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => EntryEditorScreen(
        repository: widget.entryRepository,
        photoRepository: widget.photoRepository,
        existingEntry: existing,
        onSaved: (entry) {
          _trySync();
          Navigator.of(context).pop();
        },
      ),
    ));
  }

  void _openDetail(BuildContext context, JournalEntry entry) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => EntryDetailScreen(
        repository: widget.entryRepository,
        photoRepository: widget.photoRepository,
        entry: entry,
        reflectionService: _reflectionService,
        onEdit: (e) => _openEditor(context, e),
        onDeleted: () {
          _trySync();
          Navigator.of(context).pop();
        },
      ),
    ));
  }
}
