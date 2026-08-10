import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:journal_app/data/entry_repository.dart';
import 'package:journal_app/data/photo_repository.dart';
import 'package:journal_app/models/journal_entry.dart';
import 'package:journal_app/screens/entry_editor_screen.dart';

void main() {
  late Directory tempDir;
  late EntryRepository repo;
  late PhotoRepository photoRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('entry_editor_test');
    Hive.init(tempDir.path);
    repo = await EntryRepository.open();
    photoRepo = await PhotoRepository.open();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  testWidgets('saving a new entry writes text and mood to the repository', (tester) async {
    JournalEntry? saved;

    await tester.pumpWidget(MaterialApp(
      home: EntryEditorScreen(
        repository: repo,
        photoRepository: photoRepo,
        onSaved: (e) => saved = e,
      ),
    ));

    await tester.enterText(find.byType(TextField).first, 'My first entry');
    await tester.tap(find.text('🙂'));

    // The check button's onPressed is async and awaits real Hive I/O, so the
    // tap (which synchronously invokes onPressed) must stay inside runAsync:
    // that's what makes the awaited save's continuation run in the real zone
    // instead of being stranded as an unflushable FakeAsync microtask. Poll
    // on `saved` (set only once the awaited save() call truly resolves and
    // onSaved fires) rather than repo state: Hive's Keystore updates its
    // in-memory store synchronously before the real disk write completes, so
    // repo.getAll()/getById() would report the write as done prematurely.
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.check));
      var attempts = 0;
      while (saved == null && attempts < 100) {
        await Future.delayed(const Duration(milliseconds: 10));
        attempts++;
      }
    });

    // Back in fake-async zone, pump to process any pending callbacks
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
    await tester.runAsync(() async {
      await repo.save(existing);
    });
    JournalEntry? saved;

    await tester.pumpWidget(MaterialApp(
      home: EntryEditorScreen(
        repository: repo,
        photoRepository: photoRepo,
        existingEntry: existing,
        onSaved: (e) => saved = e,
      ),
    ));

    expect(find.text('Original text'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Updated text');

    // See the comment in the first test: tap must stay inside runAsync so
    // the awaited save()'s continuation runs in the real zone, and we poll
    // on `saved` rather than repo state since Hive updates its in-memory
    // store synchronously ahead of the real disk write completing.
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.check));
      var attempts = 0;
      while (saved == null && attempts < 100) {
        await Future.delayed(const Duration(milliseconds: 10));
        attempts++;
      }
    });

    await tester.pumpAndSettle();

    expect(saved!.id, 'e1');
    expect(saved!.text, 'Updated text');
    expect(repo.getById('e1')?.text, 'Updated text');
  });

  testWidgets('adding a tag chip includes it in the saved entry', (tester) async {
    JournalEntry? saved;

    await tester.pumpWidget(MaterialApp(
      home: EntryEditorScreen(
        repository: repo,
        photoRepository: photoRepo,
        onSaved: (e) => saved = e,
      ),
    ));

    await tester.enterText(find.byType(TextField).first, 'Entry with a tag');
    await tester.enterText(find.byKey(const Key('tagInput')), 'gratitude');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // See the comment in the first test: tap must stay inside runAsync so
    // the awaited save()'s continuation runs in the real zone, and we poll
    // on `saved` rather than repo state since Hive updates its in-memory
    // store synchronously ahead of the real disk write completing.
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.check));
      var attempts = 0;
      while (saved == null && attempts < 100) {
        await Future.delayed(const Duration(milliseconds: 10));
        attempts++;
      }
    });

    await tester.pumpAndSettle();

    expect(saved!.tags, contains('gratitude'));
  });

  testWidgets('picking a photo attaches it to the saved entry', (tester) async {
    // Real dart:io calls (Directory.createTemp, File.writeAsBytes) must run
    // inside runAsync: testWidgets bodies execute in a FakeAsync zone by
    // default, and real I/O there can hang indefinitely rather than just
    // race, since nothing ever drives the fake clock forward for it.
    late File tempImage;
    await tester.runAsync(() async {
      tempImage = File('${(await Directory.systemTemp.createTemp('photo_test')).path}/pic.jpg');
      await tempImage.writeAsBytes([0, 1, 2, 3]);
    });
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

    // _addPhoto awaits real Hive I/O (photoRepository.save) before its
    // setState adds the id to _photoIds, so the tap must stay inside
    // runAsync (same reasoning as the check-button taps above). We poll on
    // a rendered widget keyed with the current photo count rather than repo
    // state: Hive's Keystore can reflect a write before the calling
    // widget's own await/setState has actually resumed and run, so polling
    // repo state is an unreliable completion signal. The keyed widget can
    // only appear once _photoIds genuinely has 1 element AND a frame has
    // been pumped reflecting it.
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.add_photo_alternate));
      var attempts = 0;
      while (find.byKey(const Key('photoCount-1')).evaluate().isEmpty && attempts < 100) {
        await Future.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        attempts++;
      }
    });
    await tester.pumpAndSettle();

    // See the comment in the first test: tap must stay inside runAsync so
    // the awaited save()'s continuation runs in the real zone, and we poll
    // on `saved` rather than repo state since Hive updates its in-memory
    // store synchronously ahead of the real disk write completing.
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.check));
      var attempts = 0;
      while (saved == null && attempts < 100) {
        await Future.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        attempts++;
      }
    });
    await tester.pumpAndSettle();

    expect(saved!.photoIds, hasLength(1));
    final asset = photoRepo.getById(saved!.photoIds.first);
    expect(asset, isNotNull);
    expect(asset!.localPath, tempImage.path);
    expect(photoRepo.getById(saved!.photoIds.first)!.entryId, saved!.id);
  });
}
