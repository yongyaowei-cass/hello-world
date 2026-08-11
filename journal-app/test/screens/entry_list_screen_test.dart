import 'dart:io';
import 'package:flutter/foundation.dart' show ValueNotifier;
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

  testWidgets('groups entries under date headers', (tester) async {
    // Real Hive I/O (repo.save) directly inside a testWidgets body must run
    // inside runAsync, per this project's established async-widget-test
    // pattern (testWidgets runs in a fake-async zone that never drives real
    // dart:io/Hive completions on its own — see the neighboring tests in
    // this file and entry_editor_screen_test.dart for the same pattern).
    final today = DateTime.now();
    final oldDate = today.subtract(const Duration(days: 10));
    await tester.runAsync(() async {
      await repo.save(JournalEntry(
        id: 'e1',
        createdAt: today,
        updatedAt: today,
        text: 'Todays entry',
      ));
      await repo.save(JournalEntry(
        id: 'e2',
        createdAt: oldDate,
        updatedAt: oldDate,
        text: 'Older entry',
      ));
    });

    await tester.pumpWidget(MaterialApp(
      home: EntryListScreen(repository: repo, onCreateEntry: () {}, onOpenEntry: (_) {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Todays entry'), findsOneWidget);
    expect(find.text('Older entry'), findsOneWidget);
  });
}
