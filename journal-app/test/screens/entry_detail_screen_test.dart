import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:journal_app/ai/gemini_reflection_service.dart';
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
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.delete));
      var attempts = 0;
      while (!deleted && attempts < 100) {
        await Future.delayed(const Duration(milliseconds: 10));
        attempts++;
      }
    });
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(repo.getById('e1')!.deleted, isTrue);
  });

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

    await tester.runAsync(() async {
      await tester.tap(find.text('Reflect'));
      var attempts = 0;
      while (repo.getById('e1')!.aiReflectionQuestion == null && attempts < 100) {
        await Future.delayed(const Duration(milliseconds: 10));
        attempts++;
      }
    });
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
}
