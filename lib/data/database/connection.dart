/// Pemilih koneksi database per platform, lewat conditional import.
///
/// Android/iOS: `NativeDatabase` (SQLite file, sama seperti sebelumnya).
/// Web: `WasmDatabase` (IndexedDB) untuk demo F13 — tanpa server tambahan.
library;

export 'connection_io.dart'
    if (dart.library.js_interop) 'connection_web.dart';
