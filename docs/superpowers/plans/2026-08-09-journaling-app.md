# Journaling app implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter journaling app (Android + Web) with offline-first local storage, Google Drive-backed multi-device sync, and an on-demand Gemini AI reflection feature.

**Architecture:** Flutter app with a Hive-backed local repository as the source of truth for the UI, a background sync service that reconciles per-entry JSON files against Google Drive's private `appDataFolder` using last-write-wins conflict resolution, and a direct client call to the Gemini API for on-demand reflection questions. See [docs/superpowers/specs/2026-08-09-journaling-app-design.md](../specs/2026-08-09-journaling-app-design.md) for full rationale.

**Tech Stack:** Flutter/Dart, Hive (local storage), `google_sign_in` + `googleapis` (Drive API), Gemini REST API via `http`, `image_picker` (photos), `connectivity_plus` (sync triggers).

## Global Constraints

- Single Flutter codebase targeting Android and Web (spec: Architecture).
- Local storage is Hive; entries/photos stored as `Map<String, dynamic>` (the same shape as `toJson()`), no code-generated Hive adapters — keeps the local shape identical to the Drive JSON shape (spec: Data model).
- Drive OAuth scope is `drive.appdata` only, never full Drive access (spec: Architecture).
- Sync conflict rule is last-write-wins by `updatedAt`, applied per-entry (spec: Architecture, Data model).
- Deletion is soft-delete: set `deleted = true` and bump `updatedAt`, never remove the Drive file (spec: Data model).
- AI reflection is on-demand only (user taps "Reflect"), never automatic on save (spec: Screens & UX flow).
- Mood is stored as `int? (1-5)`, not a string or emoji (spec: Data model).
- No client-side encryption, no rich text, no cross-entry search in this plan (spec: Goals & scope, out of scope).
- **Build environment constraint:** this environment cannot run Gradle (Android builds hit a sandboxed-JVM loopback-connection block). `flutter test` (Dart VM, no Gradle) and `flutter build web` work fine here. Anything requiring `flutter build apk` / `flutter run -d android` / an Android emulator must be run by the user in Android Studio — those steps are called out explicitly as manual checkpoints, not automated steps.

---

## Task 1: Flutter project scaffold

**Files:**
- Create: `journal-app/` (via `flutter create`)
- Modify: `journal-app/pubspec.yaml`

**Interfaces:**
- Produces: a Flutter project at `journal-app/` with dependencies installed, ready for `flutter test` to run in later tasks.

- [ ] **Step 1: Verify Flutter SDK is available**

Run: `flutter --version`
Expected: prints a Flutter/Dart version (e.g. `Flutter 3.x.x`). If this fails, stop and tell the user the Flutter SDK needs to be installed before continuing — do not attempt to install it yourself.

- [ ] **Step 2: Scaffold the project**

Run (from the `claude.code` repo root):
```bash
flutter create --platforms=android,web --org com.yaowei --project-name journal_app journal-app
```
Expected: creates `journal-app/` containing `lib/main.dart`, `android/`, `web/`, `test/widget_test.dart`, `pubspec.yaml`.

- [ ] **Step 3: Confirm the default scaffold test passes**

Run: `cd journal-app && flutter test`
Expected: PASS (the default counter-app widget test that ships with `flutter create`).

- [ ] **Step 4: Add project dependencies**

Edit `journal-app/pubspec.yaml`, adding under `dependencies:` (keep the existing `flutter:` and `cupertino_icons:` entries):

```yaml
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  path_provider: ^2.1.3
  uuid: ^4.4.0
  google_sign_in: ^6.2.1
  extension_google_sign_in_as_googleapis_auth: ^2.0.1
  googleapis: ^13.2.0
  http: ^1.2.1
  image_picker: ^1.1.2
  connectivity_plus: ^6.0.5
  intl: ^0.19.0
```

- [ ] **Step 5: Install dependencies**

Run: `flutter pub get`
Expected: resolves and downloads all packages with no version conflicts.

- [ ] **Step 6: Commit**

```bash
git add journal-app/
git commit -m "chore: scaffold journal-app Flutter project"
```

---

## Task 2: Models — JournalEntry and PhotoAsset

**Files:**
- Create: `journal-app/lib/models/journal_entry.dart`
- Create: `journal-app/lib/models/photo_asset.dart`
- Test: `journal-app/test/models/journal_entry_test.dart`
- Test: `journal-app/test/models/photo_asset_test.dart`

**Interfaces:**
- Produces: `JournalEntry` (fields: `id, createdAt, updatedAt, text, mood, tags, photoIds, aiReflectionQuestion, deleted`; methods: `toJson()`, `JournalEntry.fromJson(Map)`, `copyWith(...)`), `PhotoAsset` (fields: `id, entryId, localPath, driveFileId, createdAt`; methods: `toJson()`, `PhotoAsset.fromJson(Map)`, `copyWith(...)`).

- [ ] **Step 1: Write the failing test for JournalEntry round-trip serialization**

```dart
// journal-app/test/models/journal_entry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/journal_entry.dart';

void main() {
  group('JournalEntry', () {
    test('toJson/fromJson round-trips all fields', () {
      final entry = JournalEntry(
        id: 'e1',
        createdAt: DateTime.utc(2026, 8, 9, 9, 40),
        updatedAt: DateTime.utc(2026, 8, 9, 9, 41),
        text: 'Started sketching the journal app today.',
        mood: 4,
        tags: const ['planning', 'work'],
        photoIds: const ['p1'],
        aiReflectionQuestion: 'What excites you most?',
        deleted: false,
      );

      final restored = JournalEntry.fromJson(entry.toJson());

      expect(restored.id, entry.id);
      expect(restored.createdAt, entry.createdAt);
      expect(restored.updatedAt, entry.updatedAt);
      expect(restored.text, entry.text);
      expect(restored.mood, entry.mood);
      expect(restored.tags, entry.tags);
      expect(restored.photoIds, entry.photoIds);
      expect(restored.aiReflectionQuestion, entry.aiReflectionQuestion);
      expect(restored.deleted, entry.deleted);
    });

    test('fromJson defaults missing optional fields', () {
      final restored = JournalEntry.fromJson({
        'id': 'e2',
        'createdAt': '2026-08-09T09:40:00.000Z',
        'updatedAt': '2026-08-09T09:40:00.000Z',
        'text': 'No mood, no tags, no photos yet.',
      });

      expect(restored.mood, isNull);
      expect(restored.tags, isEmpty);
      expect(restored.photoIds, isEmpty);
      expect(restored.aiReflectionQuestion, isNull);
      expect(restored.deleted, isFalse);
    });

    test('copyWith overrides only the given fields', () {
      final entry = JournalEntry(
        id: 'e1',
        createdAt: DateTime.utc(2026, 8, 9),
        updatedAt: DateTime.utc(2026, 8, 9),
        text: 'original',
      );

      final updated = entry.copyWith(text: 'edited', mood: 5);

      expect(updated.id, entry.id);
      expect(updated.text, 'edited');
      expect(updated.mood, 5);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/journal_entry_test.dart`
Expected: FAIL — `package:journal_app/models/journal_entry.dart` not found.

- [ ] **Step 3: Implement JournalEntry**

```dart
// journal-app/lib/models/journal_entry.dart
class JournalEntry {
  JournalEntry({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.text,
    this.mood,
    this.tags = const [],
    this.photoIds = const [],
    this.aiReflectionQuestion,
    this.deleted = false,
  });

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String text;
  final int? mood;
  final List<String> tags;
  final List<String> photoIds;
  final String? aiReflectionQuestion;
  final bool deleted;

  JournalEntry copyWith({
    String? text,
    int? mood,
    List<String>? tags,
    List<String>? photoIds,
    String? aiReflectionQuestion,
    bool? deleted,
    DateTime? updatedAt,
  }) {
    return JournalEntry(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      text: text ?? this.text,
      mood: mood ?? this.mood,
      tags: tags ?? this.tags,
      photoIds: photoIds ?? this.photoIds,
      aiReflectionQuestion: aiReflectionQuestion ?? this.aiReflectionQuestion,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'text': text,
        'mood': mood,
        'tags': tags,
        'photoIds': photoIds,
        'aiReflectionQuestion': aiReflectionQuestion,
        'deleted': deleted,
      };

  factory JournalEntry.fromJson(Map<dynamic, dynamic> json) {
    return JournalEntry(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      text: json['text'] as String,
      mood: json['mood'] as int?,
      tags: List<String>.from(json['tags'] as List? ?? const []),
      photoIds: List<String>.from(json['photoIds'] as List? ?? const []),
      aiReflectionQuestion: json['aiReflectionQuestion'] as String?,
      deleted: json['deleted'] as bool? ?? false,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/journal_entry_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Write the failing test for PhotoAsset**

```dart
// journal-app/test/models/photo_asset_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/photo_asset.dart';

void main() {
  test('PhotoAsset toJson/fromJson round-trips all fields', () {
    final asset = PhotoAsset(
      id: 'p1',
      entryId: 'e1',
      localPath: '/cache/p1.jpg',
      driveFileId: 'drive-123',
      createdAt: DateTime.utc(2026, 8, 9),
    );

    final restored = PhotoAsset.fromJson(asset.toJson());

    expect(restored.id, asset.id);
    expect(restored.entryId, asset.entryId);
    expect(restored.localPath, asset.localPath);
    expect(restored.driveFileId, asset.driveFileId);
    expect(restored.createdAt, asset.createdAt);
  });

  test('PhotoAsset fromJson allows null localPath and driveFileId', () {
    final restored = PhotoAsset.fromJson({
      'id': 'p2',
      'entryId': 'e1',
      'createdAt': '2026-08-09T00:00:00.000Z',
    });

    expect(restored.localPath, isNull);
    expect(restored.driveFileId, isNull);
  });
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/models/photo_asset_test.dart`
Expected: FAIL — `package:journal_app/models/photo_asset.dart` not found.

- [ ] **Step 7: Implement PhotoAsset**

```dart
// journal-app/lib/models/photo_asset.dart
class PhotoAsset {
  PhotoAsset({
    required this.id,
    required this.entryId,
    required this.createdAt,
    this.localPath,
    this.driveFileId,
  });

  final String id;
  final String entryId;
  final DateTime createdAt;
  final String? localPath;
  final String? driveFileId;

  PhotoAsset copyWith({String? localPath, String? driveFileId}) {
    return PhotoAsset(
      id: id,
      entryId: entryId,
      createdAt: createdAt,
      localPath: localPath ?? this.localPath,
      driveFileId: driveFileId ?? this.driveFileId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'entryId': entryId,
        'createdAt': createdAt.toIso8601String(),
        'localPath': localPath,
        'driveFileId': driveFileId,
      };

  factory PhotoAsset.fromJson(Map<dynamic, dynamic> json) {
    return PhotoAsset(
      id: json['id'] as String,
      entryId: json['entryId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      localPath: json['localPath'] as String?,
      driveFileId: json['driveFileId'] as String?,
    );
  }
}
```

- [ ] **Step 8: Run both model tests to verify they pass**

Run: `flutter test test/models/`
Expected: PASS (5 tests total).

- [ ] **Step 9: Commit**

```bash
git add lib/models/ test/models/
git commit -m "feat: add JournalEntry and PhotoAsset models"
```

---

## Task 3: EntryRepository (Hive CRUD + soft delete)

**Files:**
- Create: `journal-app/lib/data/entry_repository.dart`
- Test: `journal-app/test/data/entry_repository_test.dart`

**Interfaces:**
- Consumes: `JournalEntry` (Task 2).
- Produces: `EntryRepository` with `static Future<EntryRepository> open({String? path})`, `List<JournalEntry> getAll()` (excludes soft-deleted, newest first), `List<JournalEntry> getAllIncludingDeleted()`, `JournalEntry? getById(String id)`, `Future<void> save(JournalEntry entry)`, `Future<void> softDelete(String id)`, `ValueListenable<Box> listenable()`.

- [ ] **Step 1: Write the failing test**

```dart
// journal-app/test/data/entry_repository_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/data/entry_repository.dart';
import 'package:journal_app/models/journal_entry.dart';

void main() {
  late Directory tempDir;
  late EntryRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('entry_repo_test');
    Hive.init(tempDir.path);
    repo = await EntryRepository.open();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  JournalEntry makeEntry(String id, {DateTime? createdAt}) {
    final ts = createdAt ?? DateTime.utc(2026, 8, 9);
    return JournalEntry(id: id, createdAt: ts, updatedAt: ts, text: 'entry $id');
  }

  test('save then getById returns the same entry', () async {
    final entry = makeEntry('e1');
    await repo.save(entry);

    final fetched = repo.getById('e1');

    expect(fetched, isNotNull);
    expect(fetched!.text, 'entry e1');
  });

  test('getAll excludes soft-deleted entries', () async {
    await repo.save(makeEntry('e1'));
    await repo.save(makeEntry('e2'));
    await repo.softDelete('e1');

    final all = repo.getAll();

    expect(all.map((e) => e.id), ['e2']);
  });

  test('getAll orders newest createdAt first', () async {
    await repo.save(makeEntry('older', createdAt: DateTime.utc(2026, 8, 1)));
    await repo.save(makeEntry('newer', createdAt: DateTime.utc(2026, 8, 9)));

    final all = repo.getAll();

    expect(all.map((e) => e.id), ['newer', 'older']);
  });

  test('softDelete sets deleted flag and bumps updatedAt', () async {
    final entry = makeEntry('e1', createdAt: DateTime.utc(2026, 8, 1));
    await repo.save(entry);

    await repo.softDelete('e1');

    final fetched = repo.getAllIncludingDeleted().single;
    expect(fetched.deleted, isTrue);
    expect(fetched.updatedAt.isAfter(entry.updatedAt), isTrue);
  });

  test('softDelete on a missing id is a no-op', () async {
    await repo.softDelete('does-not-exist');
    expect(repo.getAllIncludingDeleted(), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/entry_repository_test.dart`
Expected: FAIL — `package:journal_app/data/entry_repository.dart` not found.

- [ ] **Step 3: Add the `hive_test`-free test dependency check**

No new dependency needed — the test above uses `Hive.init(tempDir.path)` directly with the real `hive` package, which works without Flutter bindings. Skip this step's setup; proceed to implementation.

- [ ] **Step 4: Implement EntryRepository**

```dart
// journal-app/lib/data/entry_repository.dart
import 'package:hive/hive.dart';
import '../models/journal_entry.dart';

class EntryRepository {
  EntryRepository(this._box);

  final Box<Map> _box;

  static Future<EntryRepository> open() async {
    final box = await Hive.openBox<Map>('entries');
    return EntryRepository(box);
  }

  List<JournalEntry> getAllIncludingDeleted() {
    return _box.values.map(JournalEntry.fromJson).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<JournalEntry> getAll() {
    return getAllIncludingDeleted().where((e) => !e.deleted).toList();
  }

  JournalEntry? getById(String id) {
    final raw = _box.get(id);
    return raw == null ? null : JournalEntry.fromJson(raw);
  }

  Future<void> save(JournalEntry entry) => _box.put(entry.id, entry.toJson());

  Future<void> softDelete(String id) async {
    final existing = getById(id);
    if (existing == null) return;
    await save(existing.copyWith(deleted: true, updatedAt: DateTime.now()));
  }

  ValueListenable<Box<Map>> listenable() => _box.listenable();
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/data/entry_repository_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/data/entry_repository.dart test/data/entry_repository_test.dart
git commit -m "feat: add EntryRepository with Hive-backed CRUD and soft delete"
```

---

## Task 4: PhotoRepository

**Files:**
- Create: `journal-app/lib/data/photo_repository.dart`
- Test: `journal-app/test/data/photo_repository_test.dart`

**Interfaces:**
- Consumes: `PhotoAsset` (Task 2).
- Produces: `PhotoRepository` with `static Future<PhotoRepository> open()`, `List<PhotoAsset> getForEntry(String entryId)`, `PhotoAsset? getById(String id)`, `Future<void> save(PhotoAsset asset)`, `Future<void> delete(String id)`.

- [ ] **Step 1: Write the failing test**

```dart
// journal-app/test/data/photo_repository_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/data/photo_repository.dart';
import 'package:journal_app/models/photo_asset.dart';

void main() {
  late Directory tempDir;
  late PhotoRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('photo_repo_test');
    Hive.init(tempDir.path);
    repo = await PhotoRepository.open();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  test('save then getById returns the same asset', () async {
    final asset = PhotoAsset(id: 'p1', entryId: 'e1', createdAt: DateTime.utc(2026, 8, 9));
    await repo.save(asset);

    expect(repo.getById('p1')?.entryId, 'e1');
  });

  test('getForEntry returns only photos for that entry', () async {
    await repo.save(PhotoAsset(id: 'p1', entryId: 'e1', createdAt: DateTime.utc(2026, 8, 9)));
    await repo.save(PhotoAsset(id: 'p2', entryId: 'e2', createdAt: DateTime.utc(2026, 8, 9)));

    final forE1 = repo.getForEntry('e1');

    expect(forE1.map((p) => p.id), ['p1']);
  });

  test('delete removes the asset', () async {
    await repo.save(PhotoAsset(id: 'p1', entryId: 'e1', createdAt: DateTime.utc(2026, 8, 9)));

    await repo.delete('p1');

    expect(repo.getById('p1'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/photo_repository_test.dart`
Expected: FAIL — `package:journal_app/data/photo_repository.dart` not found.

- [ ] **Step 3: Implement PhotoRepository**

```dart
// journal-app/lib/data/photo_repository.dart
import 'package:hive/hive.dart';
import '../models/photo_asset.dart';

class PhotoRepository {
  PhotoRepository(this._box);

  final Box<Map> _box;

  static Future<PhotoRepository> open() async {
    final box = await Hive.openBox<Map>('photos');
    return PhotoRepository(box);
  }

  List<PhotoAsset> getForEntry(String entryId) {
    return _box.values
        .map(PhotoAsset.fromJson)
        .where((p) => p.entryId == entryId)
        .toList();
  }

  PhotoAsset? getById(String id) {
    final raw = _box.get(id);
    return raw == null ? null : PhotoAsset.fromJson(raw);
  }

  Future<void> save(PhotoAsset asset) => _box.put(asset.id, asset.toJson());

  Future<void> delete(String id) => _box.delete(id);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/photo_repository_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/data/photo_repository.dart test/data/photo_repository_test.dart
git commit -m "feat: add PhotoRepository with Hive-backed CRUD"
```

---

## Task 5: Sync core — DriveEntryStore interface, conflict resolution, SyncService

This is the heart of the sync design and is fully unit-testable without any real network or Drive account, using a fake in-memory store.

**Files:**
- Create: `journal-app/lib/sync/drive_entry_store.dart`
- Create: `journal-app/lib/sync/sync_service.dart`
- Test: `journal-app/test/sync/sync_service_test.dart`

**Interfaces:**
- Consumes: `JournalEntry` (Task 2), `EntryRepository` (Task 3).
- Produces: `RemoteEntryMeta {id, updatedAt}`, abstract `DriveEntryStore` with `Future<List<RemoteEntryMeta>> listEntryMetas()`, `Future<JournalEntry> download(String id)`, `Future<void> upload(JournalEntry entry)`; `SyncService` with `Future<void> sync(EntryRepository local, DriveEntryStore remote)`.

- [ ] **Step 1: Write the failing test using a fake DriveEntryStore**

```dart
// journal-app/test/sync/sync_service_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/data/entry_repository.dart';
import 'package:journal_app/models/journal_entry.dart';
import 'package:journal_app/sync/drive_entry_store.dart';
import 'package:journal_app/sync/sync_service.dart';

class FakeDriveEntryStore implements DriveEntryStore {
  final Map<String, JournalEntry> remote = {};

  @override
  Future<List<RemoteEntryMeta>> listEntryMetas() async {
    return remote.values
        .map((e) => RemoteEntryMeta(id: e.id, updatedAt: e.updatedAt))
        .toList();
  }

  @override
  Future<JournalEntry> download(String id) async => remote[id]!;

  @override
  Future<void> upload(JournalEntry entry) async {
    remote[entry.id] = entry;
  }
}

void main() {
  late Directory tempDir;
  late EntryRepository local;
  late FakeDriveEntryStore remote;
  late SyncService sync;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_test');
    Hive.init(tempDir.path);
    local = await EntryRepository.open();
    remote = FakeDriveEntryStore();
    sync = SyncService();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  JournalEntry make(String id, {required DateTime updatedAt, String text = 'text'}) {
    return JournalEntry(id: id, createdAt: updatedAt, updatedAt: updatedAt, text: text);
  }

  test('local-only entry gets pushed to remote', () async {
    await local.save(make('e1', updatedAt: DateTime.utc(2026, 8, 9)));

    await sync.sync(local, remote);

    expect(remote.remote.containsKey('e1'), isTrue);
  });

  test('remote-only entry gets pulled to local', () async {
    await remote.upload(make('e1', updatedAt: DateTime.utc(2026, 8, 9)));

    await sync.sync(local, remote);

    expect(local.getById('e1'), isNotNull);
  });

  test('newer remote entry overwrites older local entry', () async {
    await local.save(make('e1', updatedAt: DateTime.utc(2026, 8, 1), text: 'old local'));
    await remote.upload(make('e1', updatedAt: DateTime.utc(2026, 8, 9), text: 'newer remote'));

    await sync.sync(local, remote);

    expect(local.getById('e1')!.text, 'newer remote');
  });

  test('newer local entry overwrites older remote entry', () async {
    await local.save(make('e1', updatedAt: DateTime.utc(2026, 8, 9), text: 'newer local'));
    await remote.upload(make('e1', updatedAt: DateTime.utc(2026, 8, 1), text: 'old remote'));

    await sync.sync(local, remote);

    expect(remote.remote['e1']!.text, 'newer local');
  });

  test('entries with equal updatedAt are left unchanged (no redundant writes)', () async {
    final ts = DateTime.utc(2026, 8, 9);
    await local.save(make('e1', updatedAt: ts, text: 'same'));
    await remote.upload(make('e1', updatedAt: ts, text: 'same'));

    await sync.sync(local, remote);

    expect(local.getById('e1')!.text, 'same');
    expect(remote.remote['e1']!.text, 'same');
  });

  test('editing different entries on each side never conflicts', () async {
    await local.save(make('local-only', updatedAt: DateTime.utc(2026, 8, 9)));
    await remote.upload(make('remote-only', updatedAt: DateTime.utc(2026, 8, 9)));

    await sync.sync(local, remote);

    expect(local.getById('local-only'), isNotNull);
    expect(local.getById('remote-only'), isNotNull);
    expect(remote.remote.containsKey('local-only'), isTrue);
    expect(remote.remote.containsKey('remote-only'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/sync/sync_service_test.dart`
Expected: FAIL — `package:journal_app/sync/drive_entry_store.dart` not found.

- [ ] **Step 3: Implement DriveEntryStore interface**

```dart
// journal-app/lib/sync/drive_entry_store.dart
import '../models/journal_entry.dart';

class RemoteEntryMeta {
  RemoteEntryMeta({required this.id, required this.updatedAt});

  final String id;
  final DateTime updatedAt;
}

abstract class DriveEntryStore {
  Future<List<RemoteEntryMeta>> listEntryMetas();
  Future<JournalEntry> download(String id);
  Future<void> upload(JournalEntry entry);
}
```

- [ ] **Step 4: Implement SyncService**

```dart
// journal-app/lib/sync/sync_service.dart
import '../data/entry_repository.dart';
import 'drive_entry_store.dart';

class SyncService {
  Future<void> sync(EntryRepository local, DriveEntryStore remote) async {
    final remoteMetas = {for (final m in await remote.listEntryMetas()) m.id: m};
    final localEntries = {for (final e in local.getAllIncludingDeleted()) e.id: e};

    final allIds = {...remoteMetas.keys, ...localEntries.keys};

    for (final id in allIds) {
      final localEntry = localEntries[id];
      final remoteMeta = remoteMetas[id];

      if (localEntry == null && remoteMeta != null) {
        await local.save(await remote.download(id));
      } else if (localEntry != null && remoteMeta == null) {
        await remote.upload(localEntry);
      } else if (localEntry != null && remoteMeta != null) {
        if (remoteMeta.updatedAt.isAfter(localEntry.updatedAt)) {
          await local.save(await remote.download(id));
        } else if (localEntry.updatedAt.isAfter(remoteMeta.updatedAt)) {
          await remote.upload(localEntry);
        }
      }
    }
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/sync/sync_service_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/sync/drive_entry_store.dart lib/sync/sync_service.dart test/sync/sync_service_test.dart
git commit -m "feat: add DriveEntryStore interface and per-entry last-write-wins SyncService"
```

---

## Task 6: Google Sign-In and GoogleDriveEntryStore

This wires the real Drive `appDataFolder` implementation behind the `DriveEntryStore` interface from Task 5. The upload/download/list logic against a live Google account cannot be meaningfully unit-tested in this environment — it's covered by the manual verification in Task 13. This task's own unit test covers the one piece of pure logic here: turning `googleapis` file-list results into `RemoteEntryMeta`.

**Files:**
- Create: `journal-app/lib/sync/auth_service.dart`
- Create: `journal-app/lib/sync/google_drive_entry_store.dart`
- Test: `journal-app/test/sync/google_drive_entry_store_test.dart`

**Interfaces:**
- Consumes: `DriveEntryStore`, `RemoteEntryMeta` (Task 5), `JournalEntry` (Task 2).
- Produces: `AuthService` with `Future<GoogleSignInAccount?> signIn()`, `Future<void> signOut()`, `GoogleSignInAccount? get currentUser`; `GoogleDriveEntryStore implements DriveEntryStore` constructed from a `drive.DriveApi`.

- [ ] **Step 1: Write the failing test for metadata parsing**

```dart
// journal-app/test/sync/google_drive_entry_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:journal_app/sync/google_drive_entry_store.dart';

void main() {
  test('parseEntryMeta extracts id and updatedAt from a Drive File', () {
    final file = drive.File()
      ..name = 'entry_e1.json'
      ..modifiedTime = DateTime.utc(2026, 8, 9, 9, 41);

    final meta = parseEntryMeta(file);

    expect(meta.id, 'e1');
    expect(meta.updatedAt, DateTime.utc(2026, 8, 9, 9, 41));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/sync/google_drive_entry_store_test.dart`
Expected: FAIL — `package:journal_app/sync/google_drive_entry_store.dart` not found.

- [ ] **Step 3: Implement AuthService**

```dart
// journal-app/lib/sync/auth_service.dart
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService()
      : _googleSignIn = GoogleSignIn(
          scopes: ['https://www.googleapis.com/auth/drive.appdata'],
        );

  final GoogleSignIn _googleSignIn;

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Future<GoogleSignInAccount?> signIn() => _googleSignIn.signIn();

  Future<void> signOut() => _googleSignIn.signOut();
}
```

- [ ] **Step 4: Implement GoogleDriveEntryStore**

```dart
// journal-app/lib/sync/google_drive_entry_store.dart
import 'dart:convert';
import 'package:googleapis/drive/v3.dart' as drive;
import '../models/journal_entry.dart';
import 'drive_entry_store.dart';

RemoteEntryMeta parseEntryMeta(drive.File file) {
  final id = file.name!.replaceFirst('entry_', '').replaceFirst('.json', '');
  return RemoteEntryMeta(id: id, updatedAt: file.modifiedTime!.toUtc());
}

class GoogleDriveEntryStore implements DriveEntryStore {
  GoogleDriveEntryStore(this._api);

  final drive.DriveApi _api;

  Future<Map<String, String>> _entryFileIdsByEntryId() async {
    final list = await _api.files.list(
      spaces: 'appDataFolder',
      $fields: 'files(id, name, modifiedTime)',
      q: "name contains 'entry_'",
    );
    return {
      for (final f in list.files ?? const <drive.File>[])
        parseEntryMeta(f).id: f.id!,
    };
  }

  @override
  Future<List<RemoteEntryMeta>> listEntryMetas() async {
    final list = await _api.files.list(
      spaces: 'appDataFolder',
      $fields: 'files(id, name, modifiedTime)',
      q: "name contains 'entry_'",
    );
    return [
      for (final f in list.files ?? const <drive.File>[]) parseEntryMeta(f),
    ];
  }

  @override
  Future<JournalEntry> download(String id) async {
    final fileIds = await _entryFileIdsByEntryId();
    final media = await _api.files.get(
      fileIds[id]!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = await media.stream.expand((chunk) => chunk).toList();
    return JournalEntry.fromJson(jsonDecode(utf8.decode(bytes)) as Map);
  }

  @override
  Future<void> upload(JournalEntry entry) async {
    final fileIds = await _entryFileIdsByEntryId();
    final content = utf8.encode(jsonEncode(entry.toJson()));
    final media = drive.Media(Stream.value(content), content.length);
    final existingId = fileIds[entry.id];

    if (existingId == null) {
      await _api.files.create(
        drive.File()
          ..name = 'entry_${entry.id}.json'
          ..parents = ['appDataFolder'],
        uploadMedia: media,
      );
    } else {
      await _api.files.update(drive.File(), existingId, uploadMedia: media);
    }
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/sync/google_drive_entry_store_test.dart`
Expected: PASS (1 test).

- [ ] **Step 6: Commit**

```bash
git add lib/sync/auth_service.dart lib/sync/google_drive_entry_store.dart test/sync/google_drive_entry_store_test.dart
git commit -m "feat: add Google Sign-In auth service and Drive appDataFolder entry store"
```

---

## Task 7: Entry list screen

**Files:**
- Create: `journal-app/lib/screens/entry_list_screen.dart`
- Test: `journal-app/test/screens/entry_list_screen_test.dart`

**Interfaces:**
- Consumes: `EntryRepository` (Task 3, via `getAll()` and `listenable()`), `JournalEntry` (Task 2).
- Produces: `EntryListScreen extends StatelessWidget` with constructor `EntryListScreen({required EntryRepository repository, required void Function() onCreateEntry, required void Function(JournalEntry) onOpenEntry})`.

- [ ] **Step 1: Write the failing widget test**

```dart
// journal-app/test/screens/entry_list_screen_test.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/data/entry_repository.dart';
import 'package:journal_app/models/journal_entry.dart';
import 'package:journal_app/screens/entry_list_screen.dart';

void main() {
  late Directory tempDir;
  late EntryRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('entry_list_test');
    Hive.init(tempDir.path);
    repo = await EntryRepository.open();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  testWidgets('shows entry text snippet and hides deleted entries', (tester) async {
    await repo.save(JournalEntry(
      id: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      updatedAt: DateTime.utc(2026, 8, 9),
      text: 'Visible entry',
    ));
    await repo.save(JournalEntry(
      id: 'e2',
      createdAt: DateTime.utc(2026, 8, 8),
      updatedAt: DateTime.utc(2026, 8, 8),
      text: 'Hidden entry',
      deleted: true,
    ));

    await tester.pumpWidget(MaterialApp(
      home: EntryListScreen(repository: repo, onCreateEntry: () {}, onOpenEntry: (_) {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Visible entry'), findsOneWidget);
    expect(find.text('Hidden entry'), findsNothing);
  });

  testWidgets('tapping the add button calls onCreateEntry', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: EntryListScreen(
        repository: repo,
        onCreateEntry: () => tapped = true,
        onOpenEntry: (_) {},
      ),
    ));

    await tester.tap(find.byIcon(Icons.add));

    expect(tapped, isTrue);
  });

  testWidgets('tapping an entry row calls onOpenEntry with that entry', (tester) async {
    await repo.save(JournalEntry(
      id: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      updatedAt: DateTime.utc(2026, 8, 9),
      text: 'Tap me',
    ));
    JournalEntry? opened;

    await tester.pumpWidget(MaterialApp(
      home: EntryListScreen(
        repository: repo,
        onCreateEntry: () {},
        onOpenEntry: (e) => opened = e,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap me'));

    expect(opened?.id, 'e1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/entry_list_screen_test.dart`
Expected: FAIL — `package:journal_app/screens/entry_list_screen.dart` not found.

- [ ] **Step 3: Implement EntryListScreen**

```dart
// journal-app/lib/screens/entry_list_screen.dart
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../data/entry_repository.dart';
import '../models/journal_entry.dart';

const _moodEmoji = {1: '😞', 2: '😕', 3: '😐', 4: '🙂', 5: '😄'};

class EntryListScreen extends StatelessWidget {
  const EntryListScreen({
    super.key,
    required this.repository,
    required this.onCreateEntry,
    required this.onOpenEntry,
  });

  final EntryRepository repository;
  final VoidCallback onCreateEntry;
  final void Function(JournalEntry) onOpenEntry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Journal')),
      body: ValueListenableBuilder<Box>(
        valueListenable: repository.listenable(),
        builder: (context, box, _) {
          final entries = repository.getAll();
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                leading: Text(
                  _moodEmoji[entry.mood] ?? '',
                  style: const TextStyle(fontSize: 20),
                ),
                title: Text(
                  entry.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: entry.tags.isEmpty ? null : Text(entry.tags.join(', ')),
                onTap: () => onOpenEntry(entry),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: onCreateEntry,
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/entry_list_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/screens/entry_list_screen.dart test/screens/entry_list_screen_test.dart
git commit -m "feat: add entry list screen"
```

---

## Task 8: Entry editor screen

**Files:**
- Create: `journal-app/lib/screens/entry_editor_screen.dart`
- Test: `journal-app/test/screens/entry_editor_screen_test.dart`

**Interfaces:**
- Consumes: `EntryRepository` (Task 3), `JournalEntry` (Task 2).
- Produces: `EntryEditorScreen extends StatefulWidget` with constructor `EntryEditorScreen({required EntryRepository repository, JournalEntry? existingEntry, required void Function(JournalEntry) onSaved})` covering text/mood/tags. Photo attach is added on top of this screen in Task 13, once `PhotoRepository` wiring is in place — kept separate here because `image_picker` needs a fakeable seam to stay unit-testable, which is easier to introduce cleanly as its own reviewable change.

- [ ] **Step 1: Write the failing widget test**

```dart
// journal-app/test/screens/entry_editor_screen_test.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/data/entry_repository.dart';
import 'package:journal_app/models/journal_entry.dart';
import 'package:journal_app/screens/entry_editor_screen.dart';

void main() {
  late Directory tempDir;
  late EntryRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('entry_editor_test');
    Hive.init(tempDir.path);
    repo = await EntryRepository.open();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  testWidgets('saving a new entry writes text and mood to the repository', (tester) async {
    JournalEntry? saved;

    await tester.pumpWidget(MaterialApp(
      home: EntryEditorScreen(repository: repo, onSaved: (e) => saved = e),
    ));

    await tester.enterText(find.byType(TextField), 'My first entry');
    await tester.tap(find.text('🙂'));
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.text, 'My first entry');
    expect(saved!.mood, 4);
    expect(repo.getById(saved!.id)?.text, 'My first entry');
  });

  testWidgets('editing an existing entry pre-fills text and updates on save', (tester) async {
    final existing = JournalEntry(
      id: 'e1',
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
      text: 'Original text',
      mood: 3,
    );
    await repo.save(existing);
    JournalEntry? saved;

    await tester.pumpWidget(MaterialApp(
      home: EntryEditorScreen(
        repository: repo,
        existingEntry: existing,
        onSaved: (e) => saved = e,
      ),
    ));

    expect(find.text('Original text'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Updated text');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(saved!.id, 'e1');
    expect(saved!.text, 'Updated text');
    expect(repo.getById('e1')?.text, 'Updated text');
  });

  testWidgets('adding a tag chip includes it in the saved entry', (tester) async {
    JournalEntry? saved;

    await tester.pumpWidget(MaterialApp(
      home: EntryEditorScreen(repository: repo, onSaved: (e) => saved = e),
    ));

    await tester.enterText(find.byType(TextField).first, 'Entry with a tag');
    await tester.enterText(find.byKey(const Key('tagInput')), 'gratitude');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(saved!.tags, contains('gratitude'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/entry_editor_screen_test.dart`
Expected: FAIL — `package:journal_app/screens/entry_editor_screen.dart` not found.

- [ ] **Step 3: Implement EntryEditorScreen**

```dart
// journal-app/lib/screens/entry_editor_screen.dart
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/entry_repository.dart';
import '../models/journal_entry.dart';

const _moodOptions = [
  (1, '😞'),
  (2, '😕'),
  (3, '😐'),
  (4, '🙂'),
  (5, '😄'),
];

class EntryEditorScreen extends StatefulWidget {
  const EntryEditorScreen({
    super.key,
    required this.repository,
    required this.onSaved,
    this.existingEntry,
  });

  final EntryRepository repository;
  final JournalEntry? existingEntry;
  final void Function(JournalEntry) onSaved;

  @override
  State<EntryEditorScreen> createState() => _EntryEditorScreenState();
}

class _EntryEditorScreenState extends State<EntryEditorScreen> {
  late final TextEditingController _textController;
  late final TextEditingController _tagController;
  int? _mood;
  late List<String> _tags;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.existingEntry?.text ?? '');
    _tagController = TextEditingController();
    _mood = widget.existingEntry?.mood;
    _tags = List.of(widget.existingEntry?.tags ?? const []);
  }

  @override
  void dispose() {
    _textController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _addTag(String value) {
    final tag = value.trim();
    if (tag.isEmpty) return;
    setState(() {
      _tags.add(tag);
      _tagController.clear();
    });
  }

  Future<void> _save() async {
    final now = DateTime.now();
    final existing = widget.existingEntry;
    final entry = JournalEntry(
      id: existing?.id ?? const Uuid().v4(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      text: _textController.text,
      mood: _mood,
      tags: _tags,
      photoIds: existing?.photoIds ?? const [],
      aiReflectionQuestion: existing?.aiReflectionQuestion,
    );
    await widget.repository.save(entry);
    widget.onSaved(entry);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(widget.existingEntry == null ? 'New entry' : 'Edit entry'),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final (value, emoji) in _moodOptions)
                  IconButton(
                    onPressed: () => setState(() => _mood = value),
                    icon: Text(
                      emoji,
                      style: TextStyle(
                        fontSize: 22,
                        backgroundColor: _mood == value
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            TextField(
              controller: _textController,
              maxLines: null,
              decoration: const InputDecoration(hintText: "What's on your mind today?"),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final tag in _tags) Chip(label: Text(tag)),
                SizedBox(
                  width: 120,
                  child: TextField(
                    key: const Key('tagInput'),
                    controller: _tagController,
                    decoration: const InputDecoration(hintText: 'add tag'),
                    onSubmitted: _addTag,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/entry_editor_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/screens/entry_editor_screen.dart test/screens/entry_editor_screen_test.dart
git commit -m "feat: add entry editor screen with mood and tag input"
```

---

## Task 9: Entry detail screen

**Files:**
- Create: `journal-app/lib/screens/entry_detail_screen.dart`
- Test: `journal-app/test/screens/entry_detail_screen_test.dart`

**Interfaces:**
- Consumes: `EntryRepository` (Task 3), `JournalEntry` (Task 2).
- Produces: `EntryDetailScreen extends StatelessWidget` with constructor `EntryDetailScreen({required EntryRepository repository, required JournalEntry entry, required void Function(JournalEntry) onEdit, required void Function() onDeleted})`. No AI wiring here — the `Reflect` button and its callback land in Task 11.

- [ ] **Step 1: Write the failing widget test**

```dart
// journal-app/test/screens/entry_detail_screen_test.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/data/entry_repository.dart';
import 'package:journal_app/models/journal_entry.dart';
import 'package:journal_app/screens/entry_detail_screen.dart';

void main() {
  late Directory tempDir;
  late EntryRepository repo;
  late JournalEntry entry;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('entry_detail_test');
    Hive.init(tempDir.path);
    repo = await EntryRepository.open();
    entry = JournalEntry(
      id: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      updatedAt: DateTime.utc(2026, 8, 9),
      text: 'Detail view entry',
      mood: 4,
      tags: const ['planning'],
    );
    await repo.save(entry);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  testWidgets('shows entry text, mood emoji, and tags', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EntryDetailScreen(
        repository: repo,
        entry: entry,
        onEdit: (_) {},
        onDeleted: () {},
      ),
    ));

    expect(find.text('Detail view entry'), findsOneWidget);
    expect(find.text('🙂'), findsOneWidget);
    expect(find.text('planning'), findsOneWidget);
  });

  testWidgets('tapping edit calls onEdit with the entry', (tester) async {
    JournalEntry? editTarget;

    await tester.pumpWidget(MaterialApp(
      home: EntryDetailScreen(
        repository: repo,
        entry: entry,
        onEdit: (e) => editTarget = e,
        onDeleted: () {},
      ),
    ));
    await tester.tap(find.byIcon(Icons.edit));

    expect(editTarget?.id, 'e1');
  });

  testWidgets('tapping delete soft-deletes and calls onDeleted', (tester) async {
    var deleted = false;

    await tester.pumpWidget(MaterialApp(
      home: EntryDetailScreen(
        repository: repo,
        entry: entry,
        onEdit: (_) {},
        onDeleted: () => deleted = true,
      ),
    ));
    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(repo.getById('e1')!.deleted, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/entry_detail_screen_test.dart`
Expected: FAIL — `package:journal_app/screens/entry_detail_screen.dart` not found.

- [ ] **Step 3: Implement EntryDetailScreen**

```dart
// journal-app/lib/screens/entry_detail_screen.dart
import 'package:flutter/material.dart';
import '../data/entry_repository.dart';
import '../models/journal_entry.dart';

const _moodEmoji = {1: '😞', 2: '😕', 3: '😐', 4: '🙂', 5: '😄'};

class EntryDetailScreen extends StatelessWidget {
  const EntryDetailScreen({
    super.key,
    required this.repository,
    required this.entry,
    required this.onEdit,
    required this.onDeleted,
  });

  final EntryRepository repository;
  final JournalEntry entry;
  final void Function(JournalEntry) onEdit;
  final VoidCallback onDeleted;

  Future<void> _delete() async {
    await repository.softDelete(entry.id);
    onDeleted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: () => onEdit(entry)),
          IconButton(icon: const Icon(Icons.delete), onPressed: _delete),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.mood != null)
              Text(_moodEmoji[entry.mood]!, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 8),
            Text(entry.text),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [for (final tag in entry.tags) Chip(label: Text(tag))],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/entry_detail_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/screens/entry_detail_screen.dart test/screens/entry_detail_screen_test.dart
git commit -m "feat: add entry detail screen with edit and delete"
```

---

## Task 10: GeminiReflectionService

**Files:**
- Create: `journal-app/lib/ai/gemini_reflection_service.dart`
- Test: `journal-app/test/ai/gemini_reflection_service_test.dart`

**Interfaces:**
- Produces: `GeminiReflectionService` with constructor `GeminiReflectionService({required String apiKey, http.Client? httpClient})` and `Future<String> reflect(String entryText)`.

- [ ] **Step 1: Write the failing test using http's MockClient**

```dart
// journal-app/test/ai/gemini_reflection_service_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:journal_app/ai/gemini_reflection_service.dart';

void main() {
  test('reflect sends entry text and returns the generated question', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request as http.Request;
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'What part of the plan excites you most?'}
                ]
              }
            }
          ]
        }),
        200,
      );
    });

    final service = GeminiReflectionService(apiKey: 'test-key', httpClient: client);
    final question = await service.reflect('Started sketching the journal app today.');

    expect(question, 'What part of the plan excites you most?');
    expect(captured.url.queryParameters['key'], 'test-key');
    final body = jsonDecode(captured.body) as Map;
    final promptText =
        body['contents'][0]['parts'][0]['text'] as String;
    expect(promptText, contains('Started sketching the journal app today.'));
  });

  test('reflect throws on a non-200 response', () async {
    final client = MockClient((request) async => http.Response('error', 500));
    final service = GeminiReflectionService(apiKey: 'test-key', httpClient: client);

    expect(() => service.reflect('anything'), throwsException);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ai/gemini_reflection_service_test.dart`
Expected: FAIL — `package:journal_app/ai/gemini_reflection_service.dart` not found.

- [ ] **Step 3: Implement GeminiReflectionService**

```dart
// journal-app/lib/ai/gemini_reflection_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiReflectionService {
  GeminiReflectionService({required this.apiKey, http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final String apiKey;
  final http.Client _httpClient;

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  Future<String> reflect(String entryText) async {
    final uri = Uri.parse(_endpoint).replace(queryParameters: {'key': apiKey});
    final prompt =
        'You are a gentle journaling companion. In one short sentence, '
        'ask a single reflective follow-up question about this journal entry:\n\n$entryText';

    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ]
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Gemini request failed: ${response.statusCode} ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map;
    return decoded['candidates'][0]['content']['parts'][0]['text'] as String;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ai/gemini_reflection_service_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ai/gemini_reflection_service.dart test/ai/gemini_reflection_service_test.dart
git commit -m "feat: add GeminiReflectionService for on-demand AI follow-up questions"
```

---

## Task 11: Wire the Reflect button into the entry detail screen

**Files:**
- Modify: `journal-app/lib/screens/entry_detail_screen.dart`
- Modify: `journal-app/test/screens/entry_detail_screen_test.dart`

**Interfaces:**
- Consumes: `GeminiReflectionService` (Task 10).
- Produces: `EntryDetailScreen` constructor grows an optional `GeminiReflectionService? reflectionService` parameter; when null, the Reflect button is hidden (used by earlier tests that don't pass one).

- [ ] **Step 1: Write the failing test for the Reflect flow**

Add to `journal-app/test/screens/entry_detail_screen_test.dart` (new imports: `package:journal_app/ai/gemini_reflection_service.dart`, `package:http/testing.dart`, `package:http/http.dart` as `http`, `dart:convert`):

```dart
  testWidgets('tapping Reflect calls Gemini and displays the question', (tester) async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'What made today feel worth writing about?'}
                ]
              }
            }
          ]
        }),
        200,
      );
    });
    final reflectionService = GeminiReflectionService(apiKey: 'test-key', httpClient: client);

    await tester.pumpWidget(MaterialApp(
      home: EntryDetailScreen(
        repository: repo,
        entry: entry,
        onEdit: (_) {},
        onDeleted: () {},
        reflectionService: reflectionService,
      ),
    ));

    await tester.tap(find.text('Reflect'));
    await tester.pumpAndSettle();

    expect(find.text('What made today feel worth writing about?'), findsOneWidget);
    expect(repo.getById('e1')!.aiReflectionQuestion, 'What made today feel worth writing about?');
  });

  testWidgets('Reflect button is hidden when no reflectionService is provided', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EntryDetailScreen(
        repository: repo,
        entry: entry,
        onEdit: (_) {},
        onDeleted: () {},
      ),
    ));

    expect(find.text('Reflect'), findsNothing);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/entry_detail_screen_test.dart`
Expected: FAIL — no `reflectionService` parameter on `EntryDetailScreen`.

- [ ] **Step 3: Convert EntryDetailScreen to a StatefulWidget and add the Reflect flow**

Replace the full contents of `journal-app/lib/screens/entry_detail_screen.dart`:

```dart
// journal-app/lib/screens/entry_detail_screen.dart
import 'package:flutter/material.dart';
import '../ai/gemini_reflection_service.dart';
import '../data/entry_repository.dart';
import '../models/journal_entry.dart';

const _moodEmoji = {1: '😞', 2: '😕', 3: '😐', 4: '🙂', 5: '😄'};

class EntryDetailScreen extends StatefulWidget {
  const EntryDetailScreen({
    super.key,
    required this.repository,
    required this.entry,
    required this.onEdit,
    required this.onDeleted,
    this.reflectionService,
  });

  final EntryRepository repository;
  final JournalEntry entry;
  final void Function(JournalEntry) onEdit;
  final VoidCallback onDeleted;
  final GeminiReflectionService? reflectionService;

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  late JournalEntry _entry;
  bool _loadingReflection = false;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
  }

  Future<void> _delete() async {
    await widget.repository.softDelete(_entry.id);
    widget.onDeleted();
  }

  Future<void> _reflect() async {
    final service = widget.reflectionService;
    if (service == null) return;
    setState(() => _loadingReflection = true);
    final question = await service.reflect(_entry.text);
    final updated = _entry.copyWith(
      aiReflectionQuestion: question,
      updatedAt: DateTime.now(),
    );
    await widget.repository.save(updated);
    setState(() {
      _entry = updated;
      _loadingReflection = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: () => widget.onEdit(_entry)),
          IconButton(icon: const Icon(Icons.delete), onPressed: _delete),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_entry.mood != null)
              Text(_moodEmoji[_entry.mood]!, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 8),
            Text(_entry.text),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [for (final tag in _entry.tags) Chip(label: Text(tag))],
            ),
            const SizedBox(height: 16),
            if (widget.reflectionService != null && _entry.aiReflectionQuestion == null)
              OutlinedButton(
                onPressed: _loadingReflection ? null : _reflect,
                child: Text(_loadingReflection ? 'Reflecting...' : 'Reflect'),
              ),
            if (_entry.aiReflectionQuestion != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_entry.aiReflectionQuestion!),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/entry_detail_screen_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/screens/entry_detail_screen.dart test/screens/entry_detail_screen_test.dart
git commit -m "feat: wire on-demand Reflect button into entry detail screen"
```

---

## Task 12: App root — sign-in, sync wiring, and main.dart

**Files:**
- Create: `journal-app/lib/screens/sign_in_screen.dart`
- Modify: `journal-app/lib/main.dart`
- Test: `journal-app/test/screens/sign_in_screen_test.dart`

**Interfaces:**
- Consumes: `AuthService` (Task 6), `EntryRepository` (Task 3), `PhotoRepository` (Task 4), `SyncService` + `GoogleDriveEntryStore` (Tasks 5-6), `EntryListScreen`, `EntryEditorScreen`, `EntryDetailScreen` (Tasks 7-9, 11), `GeminiReflectionService` (Task 10).
- Produces: `SignInScreen extends StatelessWidget` with `SignInScreen({required Future<void> Function() onSignIn, required VoidCallback onSkip})`; `main.dart` assembling the app with a simple in-memory `Navigator`-based flow: sign-in (skippable) → entry list → editor/detail, plus a `connectivity_plus` listener that triggers `SyncService.sync` on reconnect.

- [ ] **Step 1: Write the failing test for SignInScreen**

```dart
// journal-app/test/screens/sign_in_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/screens/sign_in_screen.dart';

void main() {
  testWidgets('tapping Sign in with Google calls onSignIn', (tester) async {
    var signInCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: SignInScreen(onSignIn: () async => signInCalled = true, onSkip: () {}),
    ));
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();

    expect(signInCalled, isTrue);
  });

  testWidgets('tapping Skip calls onSkip', (tester) async {
    var skipCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: SignInScreen(onSignIn: () async {}, onSkip: () => skipCalled = true),
    ));
    await tester.tap(find.text('Skip for now'));

    expect(skipCalled, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/sign_in_screen_test.dart`
Expected: FAIL — `package:journal_app/screens/sign_in_screen.dart` not found.

- [ ] **Step 3: Implement SignInScreen**

```dart
// journal-app/lib/screens/sign_in_screen.dart
import 'package:flutter/material.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key, required this.onSignIn, required this.onSkip});

  final Future<void> Function() onSignIn;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sync your journal across devices with Google Drive.'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onSignIn, child: const Text('Sign in with Google')),
            TextButton(onPressed: onSkip, child: const Text('Skip for now')),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/sign_in_screen_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Assemble main.dart**

Replace the full contents of `journal-app/lib/main.dart`:

```dart
// journal-app/lib/main.dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
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
    final authClient = await account.authenticatedClient();
    if (authClient == null) return;
    final store = GoogleDriveEntryStore(drive.DriveApi(authClient));
    await _syncService.sync(widget.entryRepository, store);
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
```

- [ ] **Step 6: Write the failing test for the sync status indicator**

Add to `journal-app/test/screens/entry_list_screen_test.dart` (new import: `package:flutter/foundation.dart show ValueNotifier`; the existing tests that don't pass `syncStatus` continue to work since it's optional):

```dart
  testWidgets('shows a synced icon when syncStatus is synced', (tester) async {
    final status = ValueNotifier(SyncStatus.synced);

    await tester.pumpWidget(MaterialApp(
      home: EntryListScreen(
        repository: repo,
        onCreateEntry: () {},
        onOpenEntry: (_) {},
        syncStatus: status,
      ),
    ));

    expect(find.byIcon(Icons.cloud_done), findsOneWidget);
  });

  testWidgets('shows an offline icon when syncStatus is offline', (tester) async {
    final status = ValueNotifier(SyncStatus.offline);

    await tester.pumpWidget(MaterialApp(
      home: EntryListScreen(
        repository: repo,
        onCreateEntry: () {},
        onOpenEntry: (_) {},
        syncStatus: status,
      ),
    ));

    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });
```

- [ ] **Step 7: Run test to verify it fails**

Run: `flutter test test/screens/entry_list_screen_test.dart`
Expected: FAIL — `SyncStatus` and `syncStatus` parameter don't exist yet.

- [ ] **Step 8: Add the sync status indicator to EntryListScreen**

In `journal-app/lib/screens/entry_list_screen.dart`, add:

```dart
enum SyncStatus { synced, syncing, offline }

const _syncIcons = {
  SyncStatus.synced: Icons.cloud_done,
  SyncStatus.syncing: Icons.cloud_sync,
  SyncStatus.offline: Icons.cloud_off,
};
```

Add to the constructor: `this.syncStatus,` and field `final ValueListenable<SyncStatus>? syncStatus;`.

Change the `AppBar` to include an action:

```dart
      appBar: AppBar(
        title: const Text('Journal'),
        actions: [
          if (syncStatus != null)
            ValueListenableBuilder<SyncStatus>(
              valueListenable: syncStatus!,
              builder: (context, status, _) =>
                  Icon(_syncIcons[status], key: const Key('syncStatusIcon')),
            ),
        ],
      ),
```

- [ ] **Step 9: Run test to verify it passes**

Run: `flutter test test/screens/entry_list_screen_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 10: Wire syncStatus into main.dart**

In `journal-app/lib/main.dart`, add a field to `_JournalAppState`:

```dart
  final _syncStatus = ValueNotifier(SyncStatus.offline);
```

(`SyncStatus` comes from `import 'screens/entry_list_screen.dart';`, already imported.) In `_trySync`, set `_syncStatus.value = SyncStatus.syncing;` before syncing and `_syncStatus.value = SyncStatus.synced;` after both syncs succeed — wrap the existing body:

```dart
  Future<void> _trySync() async {
    final account = _authService.currentUser;
    if (account == null) return;
    final authClient = await account.authenticatedClient();
    if (authClient == null) return;
    _syncStatus.value = SyncStatus.syncing;
    final store = GoogleDriveEntryStore(drive.DriveApi(authClient));
    await _syncService.sync(widget.entryRepository, store);
    _syncStatus.value = SyncStatus.synced;
  }
```

(Task 14 will insert a photo-sync call between the entry sync and the `synced` status update — leave the anchor line `await _syncService.sync(widget.entryRepository, store);` exactly as above so that later insertion has something to match against.)

In `_openList`, pass `syncStatus: _syncStatus` into `EntryListScreen(...)`.

- [ ] **Step 11: Run the full test suite**

Run: `flutter test`
Expected: PASS (all tests across models, data, sync, ai, and screens).

- [ ] **Step 12: Commit**

```bash
git add lib/main.dart lib/screens/sign_in_screen.dart lib/screens/entry_list_screen.dart test/screens/sign_in_screen_test.dart test/screens/entry_list_screen_test.dart
git commit -m "feat: assemble app root with sign-in, navigation, and sync status indicator"
```

---

## Task 13: Photo attach in editor and display in detail screen

**Files:**
- Modify: `journal-app/lib/screens/entry_editor_screen.dart`
- Modify: `journal-app/lib/screens/entry_detail_screen.dart`
- Modify: `journal-app/lib/main.dart`
- Modify: `journal-app/test/screens/entry_editor_screen_test.dart`
- Modify: `journal-app/test/screens/entry_detail_screen_test.dart`

**Interfaces:**
- Consumes: `PhotoRepository` (Task 4), `PhotoAsset` (Task 2).
- Produces: `EntryEditorScreen` grows required `PhotoRepository photoRepository` and optional `Future<XFile?> Function()? pickImage` (defaults to a real `ImagePicker().pickImage(source: ImageSource.gallery)` call, overridable in tests); `EntryDetailScreen` grows required `PhotoRepository photoRepository` and renders a thumbnail row.

- [ ] **Step 1: Write the failing test for picking and saving a photo**

Add to `journal-app/test/screens/entry_editor_screen_test.dart` (new imports: `package:image_picker/image_picker.dart`, `package:journal_app/data/photo_repository.dart`; add `late PhotoRepository photoRepo;` and `photoRepo = await PhotoRepository.open();` in `setUp`):

```dart
  testWidgets('picking a photo attaches it to the saved entry', (tester) async {
    final tempImage = File('${(await Directory.systemTemp.createTemp('photo_test')).path}/pic.jpg');
    await tempImage.writeAsBytes([0, 1, 2, 3]);
    JournalEntry? saved;

    await tester.pumpWidget(MaterialApp(
      home: EntryEditorScreen(
        repository: repo,
        photoRepository: photoRepo,
        pickImage: () async => XFile(tempImage.path),
        onSaved: (e) => saved = e,
      ),
    ));

    await tester.enterText(find.byType(TextField).first, 'Entry with a photo');
    await tester.tap(find.byIcon(Icons.add_photo_alternate));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(saved!.photoIds, hasLength(1));
    final asset = photoRepo.getById(saved!.photoIds.first);
    expect(asset, isNotNull);
    expect(asset!.localPath, tempImage.path);
  });
```

Every other test in this file must also pass `photoRepository: photoRepo` to its `EntryEditorScreen(...)` construction — update them now so the file still compiles.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/entry_editor_screen_test.dart`
Expected: FAIL — no `photoRepository`/`pickImage` parameters on `EntryEditorScreen`.

- [ ] **Step 3: Add photo picking to EntryEditorScreen**

In `journal-app/lib/screens/entry_editor_screen.dart`, add imports:

```dart
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart' show Uuid;
import '../data/photo_repository.dart';
import '../models/photo_asset.dart';
```

Add to the constructor and state:

```dart
  const EntryEditorScreen({
    super.key,
    required this.repository,
    required this.photoRepository,
    required this.onSaved,
    this.existingEntry,
    this.pickImage,
  });

  final PhotoRepository photoRepository;
  final Future<XFile?> Function()? pickImage;
```

Add to `_EntryEditorScreenState`:

```dart
  late List<String> _photoIds;

  Future<void> _addPhoto() async {
    final pick = widget.pickImage ?? () => ImagePicker().pickImage(source: ImageSource.gallery);
    final file = await pick();
    if (file == null) return;
    final asset = PhotoAsset(
      id: const Uuid().v4(),
      entryId: widget.existingEntry?.id ?? '',
      createdAt: DateTime.now(),
      localPath: file.path,
    );
    await widget.photoRepository.save(asset);
    setState(() => _photoIds.add(asset.id));
  }
```

In `initState`, add: `_photoIds = List.of(widget.existingEntry?.photoIds ?? const []);`

In `_save`, change the `photoIds:` field from `existing?.photoIds ?? const []` to `_photoIds`, and after computing `entry`, backfill any newly-added photo assets' `entryId` (they were created before the entry existed on first save):

```dart
    for (final id in _photoIds) {
      final asset = widget.photoRepository.getById(id);
      if (asset != null && asset.entryId != entry.id) {
        await widget.photoRepository.save(
          PhotoAsset(id: asset.id, entryId: entry.id, createdAt: asset.createdAt, localPath: asset.localPath, driveFileId: asset.driveFileId),
        );
      }
    }
```

Add a photo-add button to the `Column` in `build`, after the tag `Wrap`:

```dart
            IconButton(
              icon: const Icon(Icons.add_photo_alternate),
              onPressed: _addPhoto,
            ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/entry_editor_screen_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Write the failing test for displaying photos in the detail screen**

Add to `journal-app/test/screens/entry_detail_screen_test.dart` (new import: `package:journal_app/data/photo_repository.dart`; add `late PhotoRepository photoRepo;` and `photoRepo = await PhotoRepository.open();` in `setUp`). Update every existing `EntryDetailScreen(...)` construction in the file to also pass `photoRepository: photoRepo`, then add:

```dart
  testWidgets('shows a thumbnail for each attached photo', (tester) async {
    await photoRepo.save(PhotoAsset(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      localPath: '/tmp/does-not-need-to-exist.jpg',
    ));
    final entryWithPhoto = entry.copyWith(photoIds: ['p1']);
    await repo.save(entryWithPhoto);

    await tester.pumpWidget(MaterialApp(
      home: EntryDetailScreen(
        repository: repo,
        photoRepository: photoRepo,
        entry: entryWithPhoto,
        onEdit: (_) {},
        onDeleted: () {},
      ),
    ));

    expect(find.byKey(const Key('photo-p1')), findsOneWidget);
  });
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/screens/entry_detail_screen_test.dart`
Expected: FAIL — no `photoRepository` parameter on `EntryDetailScreen`.

- [ ] **Step 7: Add photo thumbnails to EntryDetailScreen**

In `journal-app/lib/screens/entry_detail_screen.dart`, add imports:

```dart
import 'dart:io';
import '../data/photo_repository.dart';
```

Add to the constructor: `required this.photoRepository,` and field `final PhotoRepository photoRepository;`.

Add to `build`, after the tags `Wrap`:

```dart
            Wrap(
              spacing: 8,
              children: [
                for (final id in _entry.photoIds)
                  if (widget.photoRepository.getById(id) != null)
                    SizedBox(
                      key: Key('photo-$id'),
                      width: 64,
                      height: 64,
                      child: Image.file(
                        File(widget.photoRepository.getById(id)!.localPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const ColoredBox(color: Colors.black12),
                      ),
                    ),
              ],
            ),
```

- [ ] **Step 8: Run test to verify it passes**

Run: `flutter test test/screens/entry_detail_screen_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 9: Wire PhotoRepository through main.dart**

In `journal-app/lib/main.dart`: add `import 'data/photo_repository.dart';`, change `await PhotoRepository.open();` in `main()` to `final photoRepository = await PhotoRepository.open();`, pass it into `JournalApp(entryRepository: entryRepository, photoRepository: photoRepository)`, add a matching `final PhotoRepository photoRepository;` field to `JournalApp`, and pass `photoRepository: widget.photoRepository` into both the `EntryEditorScreen(...)` and `EntryDetailScreen(...)` constructions in `_openEditor` and `_openDetail`.

- [ ] **Step 10: Run the full test suite**

Run: `flutter test`
Expected: PASS (all tests).

- [ ] **Step 11: Commit**

```bash
git add lib/screens/entry_editor_screen.dart lib/screens/entry_detail_screen.dart lib/main.dart test/screens/entry_editor_screen_test.dart test/screens/entry_detail_screen_test.dart
git commit -m "feat: add photo attach in editor and thumbnail display in detail screen"
```

---

## Task 14: Photo sync to Drive

Entry JSON syncs via Task 5-6, but the design spec also requires photo binaries to sync (`photos/<photoId>.jpg` in `appDataFolder`, referenced by `PhotoAsset.driveFileId`). This task adds that, following the same fakeable-interface pattern as Task 5.

**Files:**
- Modify: `journal-app/lib/data/photo_repository.dart`
- Create: `journal-app/lib/sync/drive_photo_store.dart`
- Create: `journal-app/lib/sync/photo_sync_service.dart`
- Create: `journal-app/lib/sync/google_drive_photo_store.dart`
- Modify: `journal-app/lib/main.dart`
- Test: `journal-app/test/data/photo_repository_test.dart`
- Test: `journal-app/test/sync/photo_sync_service_test.dart`

**Interfaces:**
- Consumes: `PhotoAsset` (Task 2), `PhotoRepository` (Task 4).
- Produces: `PhotoRepository.getAll()`; abstract `DrivePhotoStore` with `Future<Uint8List?> download(String photoId)`, `Future<String> upload(String photoId, Uint8List bytes)`; `PhotoSyncService` with constructor `PhotoSyncService({required Future<String> Function(String photoId, Uint8List bytes) saveLocalBytes})` and `Future<void> sync(PhotoRepository local, DrivePhotoStore remote)`; `GoogleDrivePhotoStore implements DrivePhotoStore`.

- [ ] **Step 1: Write the failing test for PhotoRepository.getAll()**

Add to `journal-app/test/data/photo_repository_test.dart`:

```dart
  test('getAll returns every stored photo asset', () async {
    await repo.save(PhotoAsset(id: 'p1', entryId: 'e1', createdAt: DateTime.utc(2026, 8, 9)));
    await repo.save(PhotoAsset(id: 'p2', entryId: 'e2', createdAt: DateTime.utc(2026, 8, 9)));

    expect(repo.getAll().map((p) => p.id), containsAll(['p1', 'p2']));
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/photo_repository_test.dart`
Expected: FAIL — `getAll` is not a method on `PhotoRepository`.

- [ ] **Step 3: Add getAll() to PhotoRepository**

In `journal-app/lib/data/photo_repository.dart`, add:

```dart
  List<PhotoAsset> getAll() => _box.values.map(PhotoAsset.fromJson).toList();
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/photo_repository_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Write the failing test for PhotoSyncService using fakes**

```dart
// journal-app/test/sync/photo_sync_service_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/data/photo_repository.dart';
import 'package:journal_app/models/photo_asset.dart';
import 'package:journal_app/sync/drive_photo_store.dart';
import 'package:journal_app/sync/photo_sync_service.dart';

class FakeDrivePhotoStore implements DrivePhotoStore {
  final Map<String, Uint8List> remote = {};

  @override
  Future<Uint8List?> download(String photoId) async => remote[photoId];

  @override
  Future<String> upload(String photoId, Uint8List bytes) async {
    remote[photoId] = bytes;
    return 'drive-file-$photoId';
  }
}

void main() {
  late Directory tempDir;
  late PhotoRepository local;
  late FakeDrivePhotoStore remote;
  late PhotoSyncService sync;
  late Directory localFilesDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('photo_sync_test');
    Hive.init(tempDir.path);
    local = await PhotoRepository.open();
    remote = FakeDrivePhotoStore();
    localFilesDir = await Directory('${tempDir.path}/files').create();
    sync = PhotoSyncService(
      saveLocalBytes: (photoId, bytes) async {
        final file = File('${localFilesDir.path}/$photoId.jpg');
        await file.writeAsBytes(bytes);
        return file.path;
      },
    );
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  test('local-only photo with no driveFileId gets uploaded and stamped with the returned id', () async {
    final srcFile = File('${tempDir.path}/pic.jpg');
    await srcFile.writeAsBytes([1, 2, 3]);
    await local.save(PhotoAsset(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      localPath: srcFile.path,
    ));

    await sync.sync(local, remote);

    expect(remote.remote['p1'], [1, 2, 3]);
    expect(local.getById('p1')!.driveFileId, 'drive-file-p1');
  });

  test('remote-only photo with no local file gets downloaded and stamped with a local path', () async {
    remote.remote['p1'] = Uint8List.fromList([4, 5, 6]);
    await local.save(PhotoAsset(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      driveFileId: 'drive-file-p1',
    ));

    await sync.sync(local, remote);

    final updated = local.getById('p1')!;
    expect(updated.localPath, isNotNull);
    expect(await File(updated.localPath!).readAsBytes(), [4, 5, 6]);
  });

  test('photo already present on both sides is left unchanged', () async {
    final srcFile = File('${tempDir.path}/pic.jpg');
    await srcFile.writeAsBytes([1, 2, 3]);
    await local.save(PhotoAsset(
      id: 'p1',
      entryId: 'e1',
      createdAt: DateTime.utc(2026, 8, 9),
      localPath: srcFile.path,
      driveFileId: 'drive-file-p1',
    ));

    await sync.sync(local, remote);

    expect(remote.remote.containsKey('p1'), isFalse);
  });
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/sync/photo_sync_service_test.dart`
Expected: FAIL — `package:journal_app/sync/drive_photo_store.dart` not found.

- [ ] **Step 7: Implement DrivePhotoStore and PhotoSyncService**

```dart
// journal-app/lib/sync/drive_photo_store.dart
import 'dart:typed_data';

abstract class DrivePhotoStore {
  Future<Uint8List?> download(String photoId);
  Future<String> upload(String photoId, Uint8List bytes);
}
```

```dart
// journal-app/lib/sync/photo_sync_service.dart
import 'dart:io';
import 'dart:typed_data';
import '../data/photo_repository.dart';
import 'drive_photo_store.dart';

class PhotoSyncService {
  PhotoSyncService({required this.saveLocalBytes});

  final Future<String> Function(String photoId, Uint8List bytes) saveLocalBytes;

  Future<void> sync(PhotoRepository local, DrivePhotoStore remote) async {
    for (final asset in local.getAll()) {
      if (asset.driveFileId == null && asset.localPath != null) {
        final bytes = await File(asset.localPath!).readAsBytes();
        final fileId = await remote.upload(asset.id, bytes);
        await local.save(asset.copyWith(driveFileId: fileId));
      } else if (asset.localPath == null && asset.driveFileId != null) {
        final bytes = await remote.download(asset.id);
        if (bytes == null) continue;
        final path = await saveLocalBytes(asset.id, bytes);
        await local.save(asset.copyWith(localPath: path));
      }
    }
  }
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `flutter test test/sync/photo_sync_service_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 9: Implement GoogleDrivePhotoStore**

```dart
// journal-app/lib/sync/google_drive_photo_store.dart
import 'dart:typed_data';
import 'package:googleapis/drive/v3.dart' as drive;
import 'drive_photo_store.dart';

class GoogleDrivePhotoStore implements DrivePhotoStore {
  GoogleDrivePhotoStore(this._api);

  final drive.DriveApi _api;

  Future<String?> _findFileId(String photoId) async {
    final list = await _api.files.list(
      spaces: 'appDataFolder',
      $fields: 'files(id, name)',
      q: "name = 'photo_$photoId.jpg'",
    );
    final files = list.files ?? const <drive.File>[];
    return files.isEmpty ? null : files.first.id;
  }

  @override
  Future<Uint8List?> download(String photoId) async {
    final fileId = await _findFileId(photoId);
    if (fileId == null) return null;
    final media = await _api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = await media.stream.expand((chunk) => chunk).toList();
    return Uint8List.fromList(bytes);
  }

  @override
  Future<String> upload(String photoId, Uint8List bytes) async {
    final media = drive.Media(Stream.value(bytes), bytes.length);
    final created = await _api.files.create(
      drive.File()
        ..name = 'photo_$photoId.jpg'
        ..parents = ['appDataFolder'],
      uploadMedia: media,
    );
    return created.id!;
  }
}
```

- [ ] **Step 10: Wire photo sync into main.dart's `_trySync`**

In `journal-app/lib/main.dart`, add imports:

```dart
import 'package:path_provider/path_provider.dart';
import 'sync/google_drive_photo_store.dart';
import 'sync/photo_sync_service.dart';
```

Add a field to `_JournalAppState`:

```dart
  final _photoSyncService = PhotoSyncService(
    saveLocalBytes: (photoId, bytes) async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$photoId.jpg');
      await file.writeAsBytes(bytes);
      return file.path;
    },
  );
```

(Add `import 'dart:io';` alongside the other imports for `File`.)

In `_trySync`, after `await _syncService.sync(widget.entryRepository, store);`, add:

```dart
    await _photoSyncService.sync(widget.photoRepository, GoogleDrivePhotoStore(drive.DriveApi(authClient)));
```

- [ ] **Step 11: Run the full test suite**

Run: `flutter test`
Expected: PASS (all tests).

- [ ] **Step 12: Commit**

```bash
git add lib/data/photo_repository.dart lib/sync/drive_photo_store.dart lib/sync/photo_sync_service.dart lib/sync/google_drive_photo_store.dart lib/main.dart test/data/photo_repository_test.dart test/sync/photo_sync_service_test.dart
git commit -m "feat: sync photo binaries to Drive appDataFolder"
```

---

## Task 15: Manual verification checklist

These steps require Android Studio, a real Google account, and a real Gemini API key — none of which can run through this environment's automated tools (see Global Constraints). Hand this checklist to the user.

- [ ] **Step 1: Set up Google Cloud project**

In [Google Cloud Console](https://console.cloud.google.com/): create a project, enable the Google Drive API and the Generative Language API (Gemini), create an OAuth 2.0 Client ID (Android + Web) for `google_sign_in`, and create a Gemini API key. Leave the OAuth consent screen in "Testing" mode with your own Google account as the sole test user.

- [ ] **Step 2: Restrict the Gemini API key**

In Google Cloud Console, edit the Gemini API key's application restrictions: add the Android build's package name + SHA-1 signing fingerprint, and add the web build's deployed origin as an HTTP referrer restriction, per the design spec's Architecture section.

- [ ] **Step 3: Run the app on Android via Android Studio**

Open `journal-app/` in Android Studio, run on an emulator or device, and confirm: sign-in works, creating/editing/deleting entries works offline, and the app doesn't crash on launch.

- [ ] **Step 4: Run the app on Web**

Run: `cd journal-app && flutter build web`
Then serve the `build/web` output (e.g. `flutter run -d chrome` during development) and confirm the same flows work in a browser.

- [ ] **Step 5: Verify Drive sync round-trip**

Sign in on two different devices/browsers with the same Google account. Create an entry (with an attached photo) on one, trigger sync (reconnect or reopen the app), and confirm both the entry and its photo appear on the other. Edit an entry on one side and confirm the edit propagates. Delete an entry and confirm it disappears on the other side too.

- [ ] **Step 6: Verify the Reflect button against the real Gemini API**

With `--dart-define=GEMINI_API_KEY=<your key>` passed to `flutter run`/`flutter build`, open an entry and tap Reflect. Confirm a real follow-up question appears and is still there when you reopen the entry (cached, no repeat API call).

- [ ] **Step 7: Report back**

Tell me the outcomes of steps 3-6 (pass/fail, any errors seen) so any follow-up fixes can be scoped as new tasks.
