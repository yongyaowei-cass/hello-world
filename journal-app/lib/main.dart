import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:hive_flutter/hive_flutter.dart';

import 'ai/gemini_reflection_service.dart';
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

// Replace with a real key restricted in Google Cloud Console (see spec: Architecture).
const _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

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
/// (a failed background check shouldn't crash the app); [trySync] itself is
/// expected to already guard its own failures the way [runSyncWithStatus]
/// does. Extracted as a top-level function, typed against a plain nullable
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
  await trySync();
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
  GeminiReflectionService? _reflectionService;

  // True while the startup silent-sign-in check (see attemptSilentSignIn) is
  // in flight; the app shows a brief loading state instead of SignInScreen
  // while this is true, so a returning user isn't asked to tap "Sign in with
  // Google" on every launch.
  bool _checkingSilentSignIn = true;
  bool _signedInSilently = false;

  @override
  void initState() {
    super.initState();
    if (_geminiApiKey.isNotEmpty) {
      _reflectionService = GeminiReflectionService(apiKey: _geminiApiKey);
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

  Future<void> _trySync() async {
    final account = _authService.currentUser;
    if (account == null) return;
    final authClient = await _authService.authenticatedClient();
    if (authClient == null) return;
    await runSyncWithStatus(_syncStatus, () async {
      final store = GoogleDriveEntryStore(drive.DriveApi(authClient));
      final photoMetaStore = GoogleDrivePhotoMetaStore(drive.DriveApi(authClient));
      final photoStore = GoogleDrivePhotoStore(drive.DriveApi(authClient));
      await _syncService.sync(widget.entryRepository, store);
      // Pull metadata for photos this device doesn't know about yet (so the
      // binary sync below has something to download) and push metadata for
      // photos Drive doesn't know about yet.
      await _photoMetaSyncService.sync(widget.photoRepository, photoMetaStore);
      await _photoSyncService.sync(widget.photoRepository, photoStore);
      // Run metadata sync again so a driveFileId the binary sync just
      // discovered (on upload) gets published to Drive for other devices.
      await _photoMetaSyncService.sync(widget.photoRepository, photoMetaStore);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Journal',
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
