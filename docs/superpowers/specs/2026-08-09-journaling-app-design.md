# Journaling app — design spec

## Motivation

A personal learning project: build a journaling app to understand how modern journaling apps (Day One, Journey, Rosebud) are built, and implement a lower-budget (ideally free) version of the same ideas. Journey is the closest existing analog — it already stores entries in the user's own Google Drive or OneDrive rather than a vendor's cloud. This project follows that same pattern, and adds a light AI-reflection feature inspired by Rosebud's guided-journaling approach, using Google's free-tier Gemini API instead of a paid AI subscription.

## Goals & scope

**In scope for v1:**
- Create/edit/delete journal entries: text, optional photos, mood (5-point emoji scale), freeform tags
- Browse entries (reverse-chronological list) and view a single entry
- Offline-first: entries save locally instantly, sync to Google Drive when online
- Google Sign-In, using Drive's private `appDataFolder` (invisible in the user's normal Drive UI, scoped to this app only)
- AI reflection (light touch): after saving an entry, an on-demand "Reflect" button requests one Gemini-generated follow-up question based on the entry text
- Flutter app compiled to both Android and Web from a single codebase

**Explicitly out of scope for v1** (candidates for later phases):
- Multi-turn AI conversation / guided reflection flow (Rosebud-style)
- AI weekly summaries or pattern recognition across entries
- Client-side encryption of entries
- iOS app
- Sharing/collaboration features
- Rich text formatting (plain text for v1)
- Cross-entry search
- Multi-user / multiple journals per account

## Architecture

**Stack:** Flutter (Dart), single codebase compiled to Android + Web.

**Layers:**

- **UI** — Flutter widgets, one shared widget tree for both platforms (responsive layout adjusts for web vs. mobile screen sizes).
- **Local storage** — Hive, an embedded NoSQL object store that works on both Android and Flutter Web (via IndexedDB). Chosen over a SQL option (e.g. Drift) because v1 only needs a chronological list, not complex queries — cross-entry search is out of scope. This is what the UI reads from directly; it's always fast and always available offline.
- **Sync layer** — a background service that:
  - Watches for local changes (new/edited/deleted entries) and pushes them to Drive's private `appDataFolder`, one JSON file per entry (`entries/entry_<id>.json`), photos as separate binary files (`photos/<photoId>.jpg`) referenced by Drive file ID
  - Periodically (and on app foreground / connectivity-restored) pulls the Drive file list, compares `updatedAt` timestamps against the local copy, and pulls down anything newer
  - Conflict rule: last-write-wins by `updatedAt`, applied per-entry. Because each entry is a separate file, editing entry A on one device and entry B on another never conflicts — only concurrent edits to the *same* entry need resolving, and last-write-wins handles that.
- **Auth** — `google_sign_in` package, requesting the narrow `drive.appdata` OAuth scope (not full Drive access). Since this is a personal app used only by the owner, the Google OAuth consent screen stays in "Testing" mode with the owner's account as the only test user — no Google verification review needed.
- **AI reflection** — direct client call to the Gemini API (Flash model, free tier: roughly 250–1,500 requests/day depending on model variant, far more than a personal journaling app needs) after an entry is saved and the user taps "Reflect". Sends the entry text, receives one follow-up question back.
  - **API key handling:** the key is embedded in the client (both Flutter Web and Android ship all client code, so a key is technically extractable either way), but restricted in Google Cloud Console: HTTP-referrer restriction for the web build, package name + SHA-1 fingerprint restriction for Android. This avoids needing a backend proxy. Worst case if the key leaks: it can't be used from any other origin/app, so abuse risk is low for a personal, non-published app.

**Why this shape:** every piece stays on Google's free tiers (Drive API, Gemini API, Google Sign-In all free at personal scale), there's no server to deploy or pay for, and the local-first design means the app is fully usable offline — sync is an eventually-consistent background concern, not something the UI blocks on.

## Data model

**JournalEntry**

| Field | Type | Notes |
|---|---|---|
| `id` | String (UUID) | generated locally on creation |
| `createdAt` | DateTime | set once |
| `updatedAt` | DateTime | bumped on every edit; drives sync conflict resolution |
| `text` | String | plain text |
| `mood` | int? (1–5) | nullable; maps to a fixed emoji scale (😞😕😐🙂😄) — stored as an int so trend charts are easy to add later |
| `tags` | List\<String\> | freeform, user-typed |
| `photoIds` | List\<String\> | references into PhotoAsset |
| `aiReflectionQuestion` | String? | cached Gemini follow-up question for this entry, if requested |
| `deleted` | bool | soft-delete tombstone flag (see Deletion below) |

**PhotoAsset**

| Field | Type | Notes |
|---|---|---|
| `id` | String (UUID) | |
| `entryId` | String | |
| `localPath` | String? | cached local file; null if not yet downloaded to this device |
| `driveFileId` | String? | null until first upload completes |
| `createdAt` | DateTime | |

**Storage layout in Drive's `appDataFolder`:**
- `entries/entry_<id>.json` — one file per entry, mirrors the JournalEntry fields (photos referenced by ID, not embedded)
- `photos/<photoId>.jpg` — binary photo files, uploaded/downloaded on demand

**Local (Hive):** two boxes, `entries` and `photos`, mirroring the same shapes. Drive is purely the sync/backup layer underneath; the UI never reads from Drive directly.

**Deletion:** soft-delete tombstones. Deleting an entry sets `deleted = true` and bumps `updatedAt` instead of removing the file. The sync layer treats this like any other change and propagates it normally; the UI just filters out deleted entries. Tombstone files stay in Drive indefinitely — at personal journaling scale (hundreds to low thousands of entries) this is negligible storage and avoids needing a second synced data structure (a deletion log) to track removals.

## Screens & UX flow

- **Entry list** (home screen) — reverse-chronological list of entries, each row showing date, mood emoji, a text snippet, and tags. Tapping a row opens it. A floating action button starts a new entry.
- **Entry editor** — used for both creating and editing (same screen, one mode): text field, mood picker (5-emoji scale), tag input (freeform, add/remove chips), photo attach (pick from gallery/camera on Android, file picker on web). Save writes to Hive immediately (instant, offline-safe) and queues it for the sync layer.
- **Entry detail view** — after saving, the entry is shown read-only with a **Reflect** button. Tapping it calls Gemini, shows a loading state, then displays the follow-up question inline. The question is cached (`aiReflectionQuestion`) so re-opening the entry doesn't re-trigger the API call.
- **Sign-in screen** — shown once, before any entries can sync; Google Sign-In requesting the `drive.appdata` scope. Local-only use (no sign-in) still works for writing entries — sync just stays paused until signed in.
- **Sync status** — a small, unobtrusive indicator (e.g. icon in the app bar) showing synced / syncing / offline state. No dedicated screen needed for v1.

## Testing

- **Unit tests** — sync conflict resolution logic (per-entry last-write-wins by `updatedAt`), and local↔Drive JSON serialization for entries/photos, since these are the parts most likely to have subtle bugs.
- **Widget tests** — entry editor (save produces correct local record) and entry list (renders entries correctly, hides soft-deleted ones).
- **Manual testing** — the actual Drive sync round-trip (two devices/browsers, verify a change on one appears on the other) and the Gemini reflection call, since both depend on live external services that are awkward to mock meaningfully for a personal project.
