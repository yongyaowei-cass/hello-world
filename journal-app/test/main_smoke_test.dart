import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:journal_app/data/entry_repository.dart';
import 'package:journal_app/data/photo_repository.dart';
import 'package:journal_app/main.dart';

void main() {
  late Directory tempDir;
  late EntryRepository repo;
  late PhotoRepository photoRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('main_smoke_test');
    Hive.init(tempDir.path);
    repo = await EntryRepository.open();
    photoRepo = await PhotoRepository.open();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  testWidgets('tapping Skip for now navigates from sign-in to the entry list', (tester) async {
    await tester.pumpWidget(JournalApp(entryRepository: repo, photoRepository: photoRepo));
    await tester.pumpAndSettle();

    expect(find.text('Skip for now'), findsOneWidget);

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(find.text('Journal'), findsOneWidget);
  });
}
