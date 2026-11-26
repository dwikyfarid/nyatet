/// Abstraksi transport sinkronisasi. Implementasi Apps Script masuk di
/// FS-02/F1; untuk fondasi FS-01 dipakai [NoopSyncTransport].
library;

class SyncRecord {
  SyncRecord({
    required this.tableName,
    required this.rowId,
    required this.action,
    required this.payload,
  });

  final String tableName;
  final String rowId;
  final String action;
  final Map<String, Object?> payload;
}

abstract class SyncTransport {
  /// Kirim batch antrean ke Sheet (Apps Script). Lempar exception saat gagal
  /// supaya baris antrean ditandai gagal dan dicoba lagi.
  Future<void> push(List<SyncRecord> batch);

  /// Tarik delta sejak [since]; peta: nama tabel -> daftar baris (JSON).
  Future<Map<String, List<Map<String, Object?>>>> pull({
    required DateTime? since,
  });
}

class NoopSyncTransport implements SyncTransport {
  const NoopSyncTransport();

  @override
  Future<void> push(List<SyncRecord> batch) async {}

  @override
  Future<Map<String, List<Map<String, Object?>>>> pull({
    required DateTime? since,
  }) async {
    return const {};
  }
}
