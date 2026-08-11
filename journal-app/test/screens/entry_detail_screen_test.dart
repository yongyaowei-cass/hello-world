import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:journal_app/ai/groq_reflection_service.dart';
import 'package:journal_app/data/entry_repository.dart';
import 'package:journal_app/data/photo_repository.dart';
import 'package:journal_app/models/journal_entry.dart';
import 'package:journal_app/models/photo_asset.dart';
import 'package:journal_app/screens/entry_detail_screen.dart';

void main() {
  late Directory tempDir;
  late EntryRepository repo;
  late PhotoRepository photoRepo;
  late JournalEntry entry;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('entry_detail_test');
    Hive.init(tempDir.path);
    repo = await EntryRepository.open();
    photoRepo = await PhotoRepository.open();
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
        photoRepository: photoRepo,
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
        photoRepository: photoRepo,
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
        photoRepository: photoRepo,
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

  testWidgets('tapping Reflect calls Groq and displays the question', (tester) async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': 'What made today feel worth writing about?',
              }
            }
          ]
        }),
        200,
      );
    });
    final reflectionService = GroqReflectionService(apiKey: 'test-key', httpClient: client);

    await tester.pumpWidget(MaterialApp(
      home: EntryDetailScreen(
        repository: repo,
        photoRepository: photoRepo,
        entry: entry,
        onEdit: (_) {},
        onDeleted: () {},
        reflectionService: reflectionService,
      ),
    ));

    await tester.runAsync(() async {
      await tester.tap(find.text('Reflect'));
      var attempts = 0;
      while (find.text('What made today feel worth writing about?').evaluate().isEmpty && attempts < 100) {
        await Future.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        attempts++;
      }
    });
    await tester.pumpAndSettle();

    expect(find.text('What made today feel worth writing about?'), findsOneWidget);
    expect(repo.getById('e1')!.aiReflectionQuestion, 'What made today feel worth writing about?');
  });

  testWidgets('a failing Reflect call resets the button and shows a snackbar instead of hanging', (tester) async {
    final client = MockClient((request) async => http.Response('server error', 500));
    final reflectionService = GroqReflectionService(apiKey: 'test-key', httpClient: client);

    await tester.pumpWidget(MaterialApp(
      home: EntryDetailScreen(
        repository: repo,
        photoRepository: photoRepo,
        entry: entry,
        onEdit: (_) {},
        onDeleted: () {},
        reflectionService: reflectionService,
      ),
    ));

    await tester.runAsync(() async {
      await tester.tap(find.text('Reflect'));
      var attempts = 0;
      while (find.byType(SnackBar).evaluate().isEmpty && attempts < 100) {
        await Future.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        attempts++;
      }
    });
    await tester.pump();

    // The button must be re-enabled (back to "Reflect", not stuck on
    // "Reflecting...") and a snackbar should explain something went wrong.
    expect(find.text('Reflect'), findsOneWidget);
    expect(find.text('Reflecting...'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(repo.getById('e1')!.aiReflectionQuestion, isNull);

    // Let the snackbar's auto-dismiss timer finish so no pending timers leak
    // into the next test.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('Reflect button is hidden when no reflectionService is provided', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EntryDetailScreen(
        repository: repo,
        photoRepository: photoRepo,
        entry: entry,
        onEdit: (_) {},
        onDeleted: () {},
      ),
    ));

    expect(find.text('Reflect'), findsNothing);
  });

  testWidgets('shows a thumbnail for each attached photo', (tester) async {
    final entryWithPhoto = entry.copyWith(photoIds: ['p1']);
    // Real Hive I/O in a testWidgets body must run inside runAsync, per the
    // pattern established elsewhere in this file/suite (e.g. the delete and
    // Reflect tests): fake-async zones don't drive real dart:io/Hive
    // completions, so unwrapped awaits here can hang indefinitely.
    await tester.runAsync(() async {
      await photoRepo.save(PhotoAsset(
        id: 'p1',
        entryId: 'e1',
        createdAt: DateTime.utc(2026, 8, 9),
        localPath: '/tmp/does-not-need-to-exist.jpg',
      ));
      await repo.save(entryWithPhoto);
    });

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

  testWidgets('body is scrollable so a long entry does not overflow and controls stay reachable', (tester) async {
    final longEntry = entry.copyWith(text: List.filled(200, 'A long journal entry line.').join('\n'));
    await tester.runAsync(() async {
      await repo.save(longEntry);
    });

    await tester.pumpWidget(MaterialApp(
      home: EntryDetailScreen(
        repository: repo,
        photoRepository: photoRepo,
        entry: longEntry,
        onEdit: (_) {},
        onDeleted: () {},
      ),
    ));

    // A bare Column overflowing a screenful of text throws a RenderFlex
    // overflow error during layout; a SingleChildScrollView instead lets the
    // content grow past the viewport without error.
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('refreshes displayed content when the underlying entry is updated elsewhere (e.g. after an edit)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EntryDetailScreen(
        repository: repo,
        photoRepository: photoRepo,
        entry: entry,
        onEdit: (_) {},
        onDeleted: () {},
      ),
    ));

    expect(find.text('Detail view entry'), findsOneWidget);

    // Simulate what happens when the editor screen (pushed on top of this
    // one) saves an edit and pops back: the repository record changes but
    // this screen was never told about it directly.
    final edited = entry.copyWith(text: 'Edited via the editor screen');
    await tester.runAsync(() async {
      await repo.save(edited);
    });
    await tester.pumpAndSettle();

    expect(find.text('Edited via the editor screen'), findsOneWidget);
    expect(find.text('Detail view entry'), findsNothing);
  });

  testWidgets('does not crash and skips rendering a photo whose metadata was pulled but binary not yet downloaded', (tester) async {
    // Simulates a device that has synced an entry's photoIds and pulled the
    // PhotoAsset metadata record from Drive, but whose binary sync hasn't
    // caught up yet: the record exists locally with localPath: null.
    final entryWithPhoto = entry.copyWith(photoIds: ['p1']);
    await tester.runAsync(() async {
      await photoRepo.save(PhotoAsset(
        id: 'p1',
        entryId: 'e1',
        createdAt: DateTime.utc(2026, 8, 9),
        driveFileId: 'drive-file-p1',
      ));
      await repo.save(entryWithPhoto);
    });

    await tester.pumpWidget(MaterialApp(
      home: EntryDetailScreen(
        repository: repo,
        photoRepository: photoRepo,
        entry: entryWithPhoto,
        onEdit: (_) {},
        onDeleted: () {},
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('photo-p1')), findsNothing);
  });

  testWidgets('entry body text uses the journal serif style', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EntryDetailScreen(
        repository: repo,
        photoRepository: photoRepo,
        entry: entry,
        onEdit: (_) {},
        onDeleted: () {},
      ),
    ));

    final bodyText = tester.widget<Text>(find.text('Detail view entry'));

    expect(bodyText.style?.fontFamily, 'Lora');
  });
}
