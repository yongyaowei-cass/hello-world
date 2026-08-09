import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:hive_flutter/hive_flutter.dart';

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
import 'sync/sync_service.dart';

// Replace with a real key restricted in Google Cloud Console (see spec: Architecture).
const _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final entryRepository = await EntryRepository.open();
  await PhotoRepository.open();
  runApp(JournalApp(entryRepository: entryRepository));
}

class JournalApp extends StatefulWidget {
  const JournalApp({super.key, required this.entryRepository});

  final EntryRepository entryRepository;

  @override
  State<JournalApp> createState() => _JournalAppState();
}

class _JournalAppState extends State<JournalApp> {
  final _authService = AuthService();
  final _syncService = SyncService();
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
    _syncStatus.value = SyncStatus.synced;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Journal',
      home: SignInScreen(
        onSignIn: () async {
          await _authService.signIn();
          await _trySync();
          if (mounted) _openList(context);
        },
        onSkip: () => _openList(context),
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
