# Journaling app — dark theme redesign design spec

## Motivation

The app's UI has been purely functional so far — default Flutter Material styling, no custom theme, plain list rows. Now that the core functionality (offline-first entries, Google Drive sync, AI reflection) is built and manually verified end to end, the goal is a visual pass: a more structured, calming, and polished look that fits a personal journaling app, using a dark theme.

## Goals & scope

**In scope:**
- A single, fixed dark theme (warm charcoal + amber), applied app-wide — no light mode, no theme switching.
- A serif typeface for journal entry text specifically (list previews, detail view, editor text field); sans-serif for everything else (app bar, buttons, labels, chrome).
- Entry list: reverse-chronological entries grouped under date headers (Today, Yesterday, then full dates further back), each entry rendered as a distinct rounded card instead of a plain list row.
- Consistent card/chip restyling of tags, mood display, and photo thumbnails across the entry list, editor, and detail screens, following the same palette.
- Sign-in screen restyled to match (dark background, amber-accented primary action).

**Explicitly out of scope:**
- Any behavior, navigation, or data changes — this is a pure visual restyle. Every screen keeps its exact current functionality.
- Light mode / theme switching.
- Changing the mood picker's emoji to icons or colored indicators (kept as emoji, per discussion — only its container styling changes).
- Sign-in session persistence and a logout action (identified during this conversation as a real gap — Android already persists reasonably well via the OS-level Google account, but web does not reliably survive a reload, and there is no logout UI anywhere). This is a behavioral change, not visual, and will be brainstormed and specced separately.

## Color palette

Dark-only theme, warm charcoal base with an amber accent. All values are literal hex (no light-mode counterparts needed, since there is only one theme):

| Role | Color | Usage |
|---|---|---|
| Page background | `#211C18` | Deep warm charcoal |
| Card / surface | `#2A241F` (app bar / outer panel), `#332C25` (entry cards, editor fields) | Two-step elevation: page → panel → card |
| Primary text | `#EFE7DA` | Entry text, headings |
| Secondary / muted text | `#8A8074` | Timestamps, date-group labels, muted UI text |
| Accent (amber) | `#C9915B` | FAB, primary buttons/CTAs, selected states (e.g. selected mood) |
| Tag chip | background `#3D3229`, text `#D9A25C` | Tags throughout all screens |
| Date group label | `#B08A4E` (today's group) / `#8A8074` (older groups) | See "Entry list" below — today's label gets a touch more emphasis |

This palette was validated with a mockup during brainstorming (entry list screen, date-grouped cards) and approved by the user.

## Typography

- **Serif** — [Lora](https://fonts.google.com/specimen/Lora), weights 400/500. Applied specifically to journal entry text: the truncated preview in list cards, the full body text in the detail view, and the multi-line text field in the editor. This is where the "personal, reflective" feel lives — it should not bleed into UI chrome.
- **Sans** — Flutter's default (Roboto/system sans). Applied to everything else: app bar titles, buttons, labels, dates, tags, navigation.
- **Font delivery:** bundle Lora as a local asset (`.ttf` files added to `pubspec.yaml`'s `fonts:` section), not the `google_fonts` package. The app is offline-first by design (Global Constraint from the original design spec); a package that fetches fonts over the network on first use would be a poor fit and could show fallback/system fonts on a first offline launch. A bundled asset has zero runtime network dependency.

## Layout & structure per screen

**Entry list (`EntryListScreen`)**
- Entries grouped under date section headers: "Today", "Yesterday", then full dates (e.g. "Aug 3") for anything older. Headers use the date-group label color above, sentence case, small uppercase-tracked text.
- Each entry renders as a rounded card (not a bare `ListTile` row): mood emoji, truncated serif preview text, timestamp, and tag chips, matching the approved mockup's layout and spacing.
- FAB uses the amber accent color, unchanged position/behavior (still triggers `onCreateEntry`).
- Sync status icon (existing `SyncStatus` indicator) restyled to the muted text color, unchanged logic.

**Entry editor (`EntryEditorScreen`)**
- The multi-line text field is the serif "page" the user writes on — larger line height, primary text color, no visible field border (feels like writing directly on the dark background, not filling out a form).
- Mood picker, tag chips, and photo thumbnail row (with its remove affordance) restyled to the new card/chip treatment. No change to interaction (tap to pick mood, type-and-submit to add a tag, tap "x" to remove a photo).
- Save action (check icon) restyled to the amber accent.

**Entry detail (`EntryDetailScreen`)**
- Same serif treatment for the full entry body text.
- Tags and photo thumbnails restyled to match the list/editor treatment.
- The "Reflect" button restyled to the amber accent (outlined or filled — implementer's call, whichever reads most consistent with the existing `OutlinedButton` usage and the rest of the palette); the returned reflection question renders in the secondary text color beneath it, unchanged logic/caching behavior.

**Sign-in screen (`SignInScreen`)**
- Dark page background, primary text color for the "Sync your journal..." copy.
- "Sign in with Google" button restyled to the amber accent as the primary CTA; "Skip for now" stays a plain text link in the secondary text color, unchanged behavior for both.

## Implementation approach

A single `ThemeData` (dark), defined once in `main.dart`'s `MaterialApp(theme: ...)`, built from a custom `ColorScheme` using the palette above. No theme-switching logic, no `ThemeMode` handling, no light-mode variant to define or maintain.

The serif/sans split is not a global `textTheme` swap — it is applied narrowly, only to the specific `Text`/`TextField` widgets that render journal entry content in each of the three screens above (list preview, detail body, editor input). Everything else continues to use the theme's default (sans) text style. This keeps the serif treatment intentional rather than accidentally leaking into buttons or labels.

## Testing

This is a pure styling change with no new business logic, so it does not need new unit tests for sync/repository/service code. Existing widget tests should continue to pass unchanged, since none of them assert on specific colors or fonts — only content, structure (e.g. `find.byType(SingleChildScrollView)`), and interaction outcomes. Two additions are worth making:
- A widget test confirming the entry list groups entries under the correct date headers (e.g. an entry created "today" appears under a "Today" header, an entry from a prior date under its own date header) — this is new structural behavior, not just styling, and should be covered.
- A manual visual pass on both Android and Web (following the same pattern as the original Task 15 manual verification) to confirm the theme renders correctly on both platforms, since Flutter's font-asset loading and `ColorScheme` rendering can occasionally differ subtly between platforms.
