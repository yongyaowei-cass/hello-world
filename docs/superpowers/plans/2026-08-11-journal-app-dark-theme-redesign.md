# Dark theme redesign implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the journaling app with a single fixed dark theme (warm charcoal + amber), a serif typeface for journal entry text, and a date-grouped card-based entry list — a pure visual change with no behavior differences.

**Architecture:** A centralized `ThemeData` (dark) and a narrowly-scoped serif `TextStyle` constant, both defined once in a new `lib/theme/app_theme.dart` and consumed by `main.dart` and the four screen widgets. A small pure function (`groupEntriesByDate`) computes date-section groupings for the entry list, kept in its own file so it's unit-testable independent of any widget.

**Tech Stack:** Flutter/Dart (existing app), a bundled Lora variable font asset (no new package — explicitly not using `google_fonts`, per the design spec's offline-first reasoning), `intl` (already a dependency) for date-group label formatting.

## Global Constraints

- Dark-only theme, no light mode, no `ThemeMode` switching (spec: Goals & scope).
- Color palette is fixed: page `#211C18`, panel `#2A241F`, card `#332C25`, primary text `#EFE7DA`, secondary text `#8A8074`, accent `#C9915B`, tag background `#3D3229` / tag text `#D9A25C`, date-group label `#B08A4E` (today) / `#8A8074` (older) (spec: Color palette).
- Serif (Lora) applies ONLY to journal entry text — list preview, detail body, editor input. Everywhere else (app bar, buttons, labels, chips, dates) stays sans-serif (spec: Typography).
- Font is a bundled local asset, not the `google_fonts` package — zero runtime network dependency, consistent with the app's offline-first design (spec: Typography).
- This is a pure visual restyle: no behavior, navigation, or data changes anywhere (spec: Goals & scope, explicitly out of scope).
- Mood stays emoji-based; only its container styling changes (spec: Goals & scope).
- Entry list groups entries under date headers: "Today", "Yesterday", then formatted dates for anything older (spec: Layout & structure, Entry list).

---

## Task 1: Bundle the Lora font and define the app theme

**Files:**
- Create: `journal-app/assets/fonts/Lora-Variable.ttf`
- Modify: `journal-app/pubspec.yaml`
- Create: `journal-app/lib/theme/app_theme.dart`
- Modify: `journal-app/lib/main.dart`
- Test: `journal-app/test/theme/app_theme_test.dart`

**Interfaces:**
- Produces: `AppColors` (a class of `static const Color` constants: `pageBackground`, `panelBackground`, `cardBackground`, `textPrimary`, `textSecondary`, `accent`, `tagBackground`, `tagText`, `dateGroupLabelToday`, `dateGroupLabelOlder`), `appTheme` (a `ThemeData`), `journalTextStyle` (a `TextStyle`) — all in `lib/theme/app_theme.dart`, imported by later tasks.

- [ ] **Step 1: Download the font asset**

Lora is distributed by Google Fonts as a single variable font (covers all weights 400-700 in one file — no separate files needed per weight). Run from the repo root:

```bash
mkdir -p journal-app/assets/fonts
curl -L -o journal-app/assets/fonts/Lora-Variable.ttf "https://github.com/google/fonts/raw/main/ofl/lora/Lora%5Bwght%5D.ttf"
```

Expected: creates a ~207KB file at `journal-app/assets/fonts/Lora-Variable.ttf`. Verify with:

```bash
ls -la journal-app/assets/fonts/Lora-Variable.ttf
```

Expected: file exists, size roughly 200-220KB (not a tiny HTML error page — if the file is only a few KB, the download failed; check the URL resolved correctly).

- [ ] **Step 2: Register the font in pubspec.yaml**

Open `journal-app/pubspec.yaml`. Find the `flutter:` section (it currently ends with `uses-material-design: true` and has no `fonts:` key). Add a `fonts:` list as a sibling of `uses-material-design`:

```yaml
  uses-material-design: true

  fonts:
    - family: Lora
      fonts:
        - asset: assets/fonts/Lora-Variable.ttf
```

- [ ] **Step 3: Write the failing test for the theme**

```dart
// journal-app/test/theme/app_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/theme/app_theme.dart';

void main() {
  test('appTheme is a dark theme using the warm charcoal page background', () {
    expect(appTheme.brightness, Brightness.dark);
    expect(appTheme.scaffoldBackgroundColor, AppColors.pageBackground);
  });

  test('appTheme uses the amber accent for primary/FAB styling', () {
    expect(appTheme.colorScheme.primary, AppColors.accent);
    expect(appTheme.floatingActionButtonTheme.backgroundColor, AppColors.accent);
  });

  test('journalTextStyle uses the Lora font family and primary text color', () {
    expect(journalTextStyle.fontFamily, 'Lora');
    expect(journalTextStyle.color, AppColors.textPrimary);
  });
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `cd journal-app && flutter test test/theme/app_theme_test.dart`
Expected: FAIL — `package:journal_app/theme/app_theme.dart` not found.

- [ ] **Step 5: Implement the theme**

```dart
// journal-app/lib/theme/app_theme.dart
import 'package:flutter/material.dart';

class AppColors {
  static const pageBackground = Color(0xFF211C18);
  static const panelBackground = Color(0xFF2A241F);
  static const cardBackground = Color(0xFF332C25);
  static const textPrimary = Color(0xFFEFE7DA);
  static const textSecondary = Color(0xFF8A8074);
  static const accent = Color(0xFFC9915B);
  static const tagBackground = Color(0xFF3D3229);
  static const tagText = Color(0xFFD9A25C);
  static const dateGroupLabelToday = Color(0xFFB08A4E);
  static const dateGroupLabelOlder = Color(0xFF8A8074);
}

final ThemeData appTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.pageBackground,
  colorScheme: const ColorScheme.dark(
    surface: AppColors.pageBackground,
    primary: AppColors.accent,
    onPrimary: AppColors.pageBackground,
    secondary: AppColors.accent,
    onSurface: AppColors.textPrimary,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.panelBackground,
    foregroundColor: AppColors.textPrimary,
    elevation: 0,
  ),
  cardColor: AppColors.cardBackground,
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: AppColors.textPrimary),
    bodySmall: TextStyle(color: AppColors.textSecondary),
    titleLarge: TextStyle(color: AppColors.textPrimary),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: AppColors.accent,
    foregroundColor: AppColors.pageBackground,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.pageBackground,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.accent,
      side: const BorderSide(color: AppColors.accent),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
  ),
  chipTheme: const ChipThemeData(
    backgroundColor: AppColors.tagBackground,
    labelStyle: TextStyle(color: AppColors.tagText, fontSize: 12),
    side: BorderSide.none,
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    hintStyle: TextStyle(color: AppColors.textSecondary),
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
  ),
  iconTheme: const IconThemeData(color: AppColors.textPrimary),
);

const journalTextStyle = TextStyle(
  fontFamily: 'Lora',
  color: AppColors.textPrimary,
  fontSize: 15,
  height: 1.5,
);
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/theme/app_theme_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 7: Wire the theme into MaterialApp**

In `journal-app/lib/main.dart`, add the import near the other local imports:

```dart
import 'theme/app_theme.dart';
```

Find `MaterialApp(` inside `_JournalAppState.build` (currently starts with `title: 'Journal',`). Add a `theme:` argument:

```dart
    return MaterialApp(
      title: 'Journal',
      theme: appTheme,
      home: Builder(
```

- [ ] **Step 8: Run the full test suite**

Run: `flutter test`
Expected: PASS (all existing tests still pass — this task only adds a theme definition and wires it in; no existing widget's structure changed yet, so no existing test should be affected by a plain color/font change since none of them assert on color or font).

- [ ] **Step 9: Verify `flutter build web` still succeeds**

Run: `flutter build web`
Expected: succeeds (confirms the font asset registration didn't break the web build).

- [ ] **Step 10: Commit**

```bash
git add journal-app/assets/fonts/Lora-Variable.ttf journal-app/pubspec.yaml journal-app/lib/theme/app_theme.dart journal-app/lib/main.dart journal-app/test/theme/app_theme_test.dart
git commit -m "feat: add dark theme (warm charcoal + amber) and bundled Lora serif font"
```

---

## Task 2: Date-grouped, card-based entry list

**Files:**
- Create: `journal-app/lib/theme/entry_date_grouping.dart`
- Test: `journal-app/test/theme/entry_date_grouping_test.dart`
- Modify: `journal-app/lib/screens/entry_list_screen.dart`
- Modify: `journal-app/test/screens/entry_list_screen_test.dart`

**Interfaces:**
- Consumes: `AppColors`, `journalTextStyle` (Task 1), `JournalEntry` (existing model), `EntryRepository.getAll()` (existing).
- Produces: `EntryGroup` (class with `label: String`, `entries: List<JournalEntry>`), `groupEntriesByDate(List<JournalEntry> entries, {DateTime? now}) -> List<EntryGroup>`.

- [ ] **Step 1: Write the failing test for date grouping**

```dart
// journal-app/test/theme/entry_date_grouping_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/models/journal_entry.dart';
import 'package:journal_app/theme/entry_date_grouping.dart';

JournalEntry _entry(String id, DateTime createdAt) => JournalEntry(
      id: id,
      createdAt: createdAt,
      updatedAt: createdAt,
      text: 'entry $id',
    );

void main() {
  test('groups entries into Today, Yesterday, and formatted-date buckets', () {
    final now = DateTime(2026, 8, 11, 15, 0);
    final entries = [
      _entry('e1', DateTime(2026, 8, 11, 9, 0)),
      _entry('e2', DateTime(2026, 8, 10, 20, 0)),
      _entry('e3', DateTime(2026, 8, 3, 10, 0)),
    ];

    final groups = groupEntriesByDate(entries, now: now);

    expect(groups.map((g) => g.label), ['Today', 'Yesterday', 'Aug 3']);
    expect(groups[0].entries.map((e) => e.id), ['e1']);
    expect(groups[1].entries.map((e) => e.id), ['e2']);
    expect(groups[2].entries.map((e) => e.id), ['e3']);
  });

  test('groups multiple same-day entries under one label, preserving order', () {
    final now = DateTime(2026, 8, 11, 15, 0);
    final entries = [
      _entry('e1', DateTime(2026, 8, 11, 9, 0)),
      _entry('e2', DateTime(2026, 8, 11, 8, 0)),
    ];

    final groups = groupEntriesByDate(entries, now: now);

    expect(groups.length, 1);
    expect(groups[0].label, 'Today');
    expect(groups[0].entries.map((e) => e.id), ['e1', 'e2']);
  });

  test('returns an empty list for no entries', () {
    expect(groupEntriesByDate([], now: DateTime(2026, 8, 11)), isEmpty);
  });
}
```

Note: these tests deliberately use local (non-UTC) `DateTime(...)` construction for both `now` and entry timestamps, not `DateTime.utc(...)`. `groupEntriesByDate` converts timestamps via `.toLocal()` internally (so "Today" reflects the device's local date, not UTC), and `.toLocal()` on an already-local `DateTime` is a no-op — using local construction throughout keeps the test deterministic regardless of which timezone the machine running it is in.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/theme/entry_date_grouping_test.dart`
Expected: FAIL — `package:journal_app/theme/entry_date_grouping.dart` not found.

- [ ] **Step 3: Implement date grouping**

```dart
// journal-app/lib/theme/entry_date_grouping.dart
import 'package:intl/intl.dart';
import '../models/journal_entry.dart';

class EntryGroup {
  const EntryGroup({required this.label, required this.entries});

  final String label;
  final List<JournalEntry> entries;
}

List<EntryGroup> groupEntriesByDate(List<JournalEntry> entries, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  final yesterday = today.subtract(const Duration(days: 1));

  final byLabel = <String, List<JournalEntry>>{};
  final labelOrder = <String>[];

  for (final entry in entries) {
    final entryDate = _dateOnly(entry.createdAt.toLocal());
    final String label;
    if (entryDate == today) {
      label = 'Today';
    } else if (entryDate == yesterday) {
      label = 'Yesterday';
    } else {
      label = DateFormat('MMM d').format(entryDate);
    }

    if (!byLabel.containsKey(label)) {
      byLabel[label] = [];
      labelOrder.add(label);
    }
    byLabel[label]!.add(entry);
  }

  return [for (final label in labelOrder) EntryGroup(label: label, entries: byLabel[label]!)];
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/theme/entry_date_grouping_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Write the failing test for the restyled list screen**

Add this new test to `journal-app/test/screens/entry_list_screen_test.dart` (add `import 'package:journal_app/theme/entry_date_grouping.dart';` if referencing `EntryGroup` directly is useful — it isn't needed here, this test only checks rendered text):

```dart
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
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/screens/entry_list_screen_test.dart`
Expected: FAIL — no "Today" text found (current screen renders a flat list with no date headers).

- [ ] **Step 7: Restyle the entry list screen**

Replace the full contents of `journal-app/lib/screens/entry_list_screen.dart`:

```dart
// journal-app/lib/screens/entry_list_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../data/entry_repository.dart';
import '../models/journal_entry.dart';
import '../theme/app_theme.dart';
import '../theme/entry_date_grouping.dart';

const _moodEmoji = {1: '😞', 2: '😕', 3: '😐', 4: '🙂', 5: '😄'};

enum SyncStatus { synced, syncing, offline }

const _syncIcons = {
  SyncStatus.synced: Icons.cloud_done,
  SyncStatus.syncing: Icons.cloud_sync,
  SyncStatus.offline: Icons.cloud_off,
};

class EntryListScreen extends StatelessWidget {
  const EntryListScreen({
    super.key,
    required this.repository,
    required this.onCreateEntry,
    required this.onOpenEntry,
    this.syncStatus,
  });

  final EntryRepository repository;
  final VoidCallback onCreateEntry;
  final void Function(JournalEntry) onOpenEntry;
  final ValueListenable<SyncStatus>? syncStatus;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      body: ValueListenableBuilder<Box>(
        valueListenable: repository.listenable(),
        builder: (context, box, _) {
          final groups = groupEntriesByDate(repository.getAll());
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final group in groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    group.label,
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.8,
                      color: group.label == 'Today'
                          ? AppColors.dateGroupLabelToday
                          : AppColors.dateGroupLabelOlder,
                    ),
                  ),
                ),
                for (final entry in group.entries) _EntryCard(entry: entry, onTap: onOpenEntry),
              ],
            ],
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

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.onTap});

  final JournalEntry entry;
  final void Function(JournalEntry) onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Material(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onTap(entry),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_moodEmoji[entry.mood] ?? '', style: const TextStyle(fontSize: 19)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: journalTextStyle.copyWith(fontSize: 14),
                      ),
                      if (entry.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final tag in entry.tags)
                              Chip(label: Text(tag), visualDensity: VisualDensity.compact),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `flutter test test/screens/entry_list_screen_test.dart`
Expected: PASS (all tests in this file, including the new grouping test).

- [ ] **Step 9: Run the full test suite**

Run: `flutter test`
Expected: PASS (all tests).

- [ ] **Step 10: Commit**

```bash
git add journal-app/lib/theme/entry_date_grouping.dart journal-app/test/theme/entry_date_grouping_test.dart journal-app/lib/screens/entry_list_screen.dart journal-app/test/screens/entry_list_screen_test.dart
git commit -m "feat: date-grouped, card-based entry list with dark theme styling"
```

---

## Task 3: Restyle the entry editor screen

**Files:**
- Modify: `journal-app/lib/screens/entry_editor_screen.dart`
- Modify: `journal-app/test/screens/entry_editor_screen_test.dart`

**Interfaces:**
- Consumes: `AppColors`, `journalTextStyle` (Task 1). No change to `EntryEditorScreen`'s constructor, public interface, or save/photo logic — styling only.

- [ ] **Step 1: Write the failing test confirming the serif style is applied**

Add this test to `journal-app/test/screens/entry_editor_screen_test.dart`:

```dart
  testWidgets('entry text field uses the journal serif style', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EntryEditorScreen(repository: repo, photoRepository: photoRepo, onSaved: (_) {}),
    ));

    final textField = tester.widget<TextField>(find.byType(TextField).first);

    expect(textField.style?.fontFamily, 'Lora');
  });
```

(This file already has `photoRepo` set up in its `setUp` per the existing tests — reuse it, don't redeclare.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/entry_editor_screen_test.dart`
Expected: FAIL — `textField.style` is null (no explicit style set today).

- [ ] **Step 3: Restyle the editor screen**

In `journal-app/lib/screens/entry_editor_screen.dart`, add the import:

```dart
import '../theme/app_theme.dart';
```

Replace the mood-picker `Row` (the one using `_moodOptions` and `Theme.of(context).colorScheme.primaryContainer`):

```dart
            Row(
              children: [
                for (final (value, emoji) in _moodOptions)
                  IconButton(
                    onPressed: () => setState(() => _mood = value),
                    icon: Text(
                      emoji,
                      style: TextStyle(
                        fontSize: 22,
                        backgroundColor: _mood == value ? AppColors.tagBackground : null,
                      ),
                    ),
                  ),
              ],
            ),
```

Replace the main `TextField` (the entry text input, currently `controller: _textController, maxLines: null, decoration: const InputDecoration(hintText: "What's on your mind today?")`):

```dart
            TextField(
              controller: _textController,
              maxLines: null,
              style: journalTextStyle,
              decoration: const InputDecoration(hintText: "What's on your mind today?"),
            ),
```

Leave everything else in the file (tag input, photo picking/removal, save logic) exactly as-is — only these two widgets change.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/entry_editor_screen_test.dart`
Expected: PASS (all tests in this file, including the new style test).

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: PASS (all tests).

- [ ] **Step 6: Commit**

```bash
git add journal-app/lib/screens/entry_editor_screen.dart journal-app/test/screens/entry_editor_screen_test.dart
git commit -m "feat: apply dark theme and serif entry text style to the editor screen"
```

---

## Task 4: Restyle the entry detail screen

**Files:**
- Modify: `journal-app/lib/screens/entry_detail_screen.dart`
- Modify: `journal-app/test/screens/entry_detail_screen_test.dart`

**Interfaces:**
- Consumes: `AppColors`, `journalTextStyle` (Task 1). No change to `EntryDetailScreen`'s constructor, public interface, or edit/delete/reflect logic — styling only.

- [ ] **Step 1: Write the failing test confirming the serif style is applied**

Add this test to `journal-app/test/screens/entry_detail_screen_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/entry_detail_screen_test.dart`
Expected: FAIL — `bodyText.style` is null (no explicit style set today).

- [ ] **Step 3: Restyle the detail screen**

In `journal-app/lib/screens/entry_detail_screen.dart`, add the import:

```dart
import '../theme/app_theme.dart';
```

Replace the body text line (currently `Text(entry.text),`):

```dart
                Text(entry.text, style: journalTextStyle),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/entry_detail_screen_test.dart`
Expected: PASS (all tests in this file, including the new style test).

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: PASS (all tests).

- [ ] **Step 6: Commit**

```bash
git add journal-app/lib/screens/entry_detail_screen.dart journal-app/test/screens/entry_detail_screen_test.dart
git commit -m "feat: apply dark theme and serif entry text style to the detail screen"
```

---

## Task 5: Restyle the sign-in screen

**Files:**
- Modify: `journal-app/lib/screens/sign_in_screen.dart`
- Modify: `journal-app/test/screens/sign_in_screen_test.dart`

**Interfaces:**
- Consumes: `AppColors` (Task 1). No change to `SignInScreen`'s constructor or `onSignIn`/`onSkip` behavior — styling only.

- [ ] **Step 1: Write the failing test confirming the accent-styled button**

Add this test to `journal-app/test/screens/sign_in_screen_test.dart`:

```dart
  testWidgets('sign-in button uses the amber accent background', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: appTheme,
      home: SignInScreen(onSignIn: () async {}, onSkip: () {}),
    ));

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    final resolvedColor = button.style?.backgroundColor?.resolve({});

    expect(resolvedColor, AppColors.accent);
  });
```

Add the import at the top of the file:

```dart
import 'package:journal_app/theme/app_theme.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/sign_in_screen_test.dart`
Expected: FAIL — the button's `style` is null (no explicit style set today; without `theme: appTheme` passed in the test, there's also no themed default yet at this point in the task).

- [ ] **Step 3: Restyle the sign-in screen**

Replace the full contents of `journal-app/lib/screens/sign_in_screen.dart`:

```dart
// journal-app/lib/screens/sign_in_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key, required this.onSignIn, required this.onSkip});

  final Future<void> Function() onSignIn;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Sync your journal across devices with Google Drive.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: onSignIn, child: const Text('Sign in with Google')),
              const SizedBox(height: 8),
              TextButton(onPressed: onSkip, child: const Text('Skip for now')),
            ],
          ),
        ),
      ),
    );
  }
}
```

Note: this relies on `ElevatedButton`'s themed default styling (accent background, set in Task 1's `elevatedButtonTheme`), which is why the test in Step 1 wraps the widget in `MaterialApp(theme: appTheme, ...)` — without an ancestor `Theme` supplying it, `ElevatedButton`'s background falls back to Flutter's own default, not the accent color.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/sign_in_screen_test.dart`
Expected: PASS (all tests in this file, including the new style test).

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: PASS (all tests).

- [ ] **Step 6: Verify `flutter build web` still succeeds**

Run: `flutter build web`
Expected: succeeds.

- [ ] **Step 7: Commit**

```bash
git add journal-app/lib/screens/sign_in_screen.dart journal-app/test/screens/sign_in_screen_test.dart
git commit -m "feat: apply dark theme styling to the sign-in screen"
```

---

## Task 6: Manual visual verification

This is a visual/subjective check that needs human eyes on a real device and a real browser — not something the automated test suite can meaningfully assert on beyond the structural checks already covered in Tasks 1-5. Hand this checklist to the user.

- [ ] **Step 1: Run on Android via Android Studio**

Open `journal-app/` in Android Studio, run on an emulator or device. Confirm:
- The app launches directly into the dark charcoal theme (no flash of a light/default theme)
- Entry list shows date-group headers and card-styled rows
- Journal entry text (list preview, detail view, editor input) renders in the serif font; buttons/labels/tags stay sans-serif
- The FAB, "Sign in with Google" button, and "Reflect" button all show the amber accent color
- Nothing looks visually broken (overlapping text, invisible text on same-color background, misaligned cards)

- [ ] **Step 2: Run on Web**

Run: `cd journal-app && flutter run -d edge` (or `-d chrome`, whichever is available)
Confirm the same checks as Step 1 render correctly in the browser, and specifically confirm the Lora font actually loads (compare entry text against button text — they should visibly differ in typeface, not silently fall back to the same sans-serif everywhere).

- [ ] **Step 3: Report back**

Tell me the outcomes of Steps 1-2 (pass/fail, anything that looks visually off) so any follow-up polish can be scoped as new tasks.
