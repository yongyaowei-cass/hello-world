import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'ai/gemini_reflection_service.dart';
import 'data/entry_repository.dart';
import 'data/photo_repository.dart';
import 'models/journal_entry.dart';
import 'screens/entry_detail_screen.dart';
import 'screens/entry_editor_screen.dart';
import 'screens/entry_list_screen.dart';
import 'screens/sign_in_screen.dart';
import 'sync/auth_service.dart';
import 'sync/google_drive_entry_store.dart';
import 'sync/google_drive_photo_store.dart';
import 'sync/photo_sync_service.dart';
import 'sync/sync_service.dart';

// Replace with a real key restricted in Google Cloud Console (see spec: Architecture).
const _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

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
  final _photoSyncService = PhotoSyncService(
    saveLocalBytes: (photoId, bytes) async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$photoId.jpg');
      await file.writeAsBytes(bytes);
      return file.path;
    },
  );
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
    _syncStatus.value = SyncStatus.syncing;
    final store = GoogleDriveEntryStore(drive.DriveApi(authClient));
    await _syncService.sync(widget.entryRepository, store);
    await _photoSyncService.sync(widget.photoRepository, GoogleDrivePhotoStore(drive.DriveApi(authClient)));
    _syncStatus.value = SyncStatus.synced;
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
