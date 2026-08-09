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

    // Wrap the save action in runAsync to allow real file I/O to complete
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.check));
      // Pump while in real async to let Hive I/O complete
      await Future.delayed(const Duration(milliseconds: 500));
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

    // Wrap the save action in runAsync to allow real file I/O to complete
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.check));
      await Future.delayed(const Duration(milliseconds: 500));
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

    // Wrap the save action in runAsync to allow real file I/O to complete
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.check));
      await Future.delayed(const Duration(milliseconds: 500));
    });

    await tester.pumpAndSettle();

    expect(saved!.tags, contains('gratitude'));
  });
}
