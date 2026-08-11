/// Platform-conditional storage for local photo bytes.
///
/// `dart:io` (real files, used to persist synced photos locally) does not
/// exist on Flutter Web, so this file conditionally exports one of two
/// implementations with an identical API, chosen at compile time:
///
/// - `photo_bytes_store_io.dart` (Android/iOS/desktop, and Dart VM tests):
///   writes bytes to a real file via `path_provider` and returns the file
///   path.
/// - `photo_bytes_store_web.dart` (web): there is no meaningful local
///   filesystem, so bytes are instead encoded as an in-memory base64
///   `data:` URL string, which round-trips through `PhotoAsset.localPath`
///   just like a file path would.
///
/// Callers (main.dart, PhotoSyncService, EntryDetailScreen) should only ever
/// import this file, never `dart:io` or the platform-specific files
/// directly, so the whole app stays buildable for both targets.
library;

export 'photo_bytes_store_stub.dart'
    if (dart.library.io) 'photo_bytes_store_io.dart'
    if (dart.library.html) 'photo_bytes_store_web.dart';
