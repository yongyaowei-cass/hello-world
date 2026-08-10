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

class _JournalAppState extends State<JournalApp> {
  final _authService = AuthService();
  final _syncService = SyncService();
  final _photoSyncService = PhotoSyncService(saveLocalBytes: saveLocalPhotoBytes);
  final _photoMetaSyncService = PhotoMetaSyncService();
  final _syncStatus = ValueNotifier(SyncStatus.offline);
  GeminiReflectionService? _reflectionService;

  @override
  void initState() {
    super.initState();
    if (_geminiApiKey.isNotEmpty) {
      _reflectionService = GeminiReflectionService(apiKey: _geminiApiKey);
    }
    Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) {
        _trySync();
      }
    });
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
        builder: (context) => SignInScreen(
          onSignIn: () async {
            await _authService.signIn();
            await _trySync();
            if (context.mounted) _openList(context);
          },
          onSkip: () => _openList(context),
        ),
      ),
    );
  }

  void _openList(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => EntryListScreen(
        repository: widget.entryRepository,
        onCreateEntry: () => _openEditor(context, null),
        onOpenEntry: (entry) => _openDetail(context, entry),
        syncStatus: _syncStatus,
      ),
    ));
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
