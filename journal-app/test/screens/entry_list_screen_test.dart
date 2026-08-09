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
    await tester.runAsync(() async {
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
    });

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
    await tester.runAsync(() async {
      await repo.save(JournalEntry(
        id: 'e1',
        createdAt: DateTime.utc(2026, 8, 9),
        updatedAt: DateTime.utc(2026, 8, 9),
        text: 'Tap me',
      ));
    });
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
