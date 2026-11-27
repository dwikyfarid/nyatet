import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Koneksi web (demo F13): drift wasm + IndexedDB.
///
/// Memakai `WasmDatabase.open` yang otomatis jatuh ke jalur non-SharedArrayBuffer
/// bila host statis tidak bisa mengirim header COOP/COEP — jadi build tetap
/// jalan dari hosting statis biasa tanpa server tambahan.
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'nyatet_demo',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    return result.resolvedExecutor;
  });
}

/// Tidak ada database in-memory di web; uji memakai koneksi wasm.
QueryExecutor memoryConnection() =>
    throw UnsupportedError('Database in-memory tidak tersedia di web');
