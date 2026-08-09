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
      home: EntryEditorScreen(repository: repo, onSaved: (e) => saved = e),
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
}
