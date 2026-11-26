import 'dart:convert';

import '../database/app_database.dart';
import '../database/mappers.dart';
import 'sync_transport.dart';

/// Mesin sinkronisasi: push batch dari `sync_queue`, lalu tarik delta dari
/// Sheet dengan resolusi bentrok last-write-wins (updated_at terbaru menang,
/// versi kalah dicatat di `audit_log`).
class SyncEngine {
  SyncEngine(this._db, {SyncTransport? transport})
      : _transport = transport ?? const NoopSyncTransport();

  final AppDatabase _db;
  final SyncTransport _transport;

  static Future<SyncEngine> openDefault() async =>
      SyncEngine(AppDatabase.open());

  Future<void> run() async {
    await push();
    await pull();
  }

  Future<int> push() async {
    final batch = await _db.pendingSyncBatch();
    if (batch.isEmpty) return 0;

    final records = batch
        .map(
          (r) => SyncRecord(
            tableName: r.targetTable,
            rowId: r.rowId,
            action: r.action,
            payload: Map<String, Object?>.from(jsonDecode(r.payload) as Map),
          ),
        )
        .toList();

    try {
      await _transport.push(records);
      for (final r in batch) {
        await _db.markSynced(r.id);
      }
      return batch.length;
    } catch (_) {
      for (final r in batch) {
        await _db.markSyncFailed(r.id);
      }
      rethrow;
    }
  }

  Future<void> pull() async {
    final since = await _db.lastPullAt();
    final remote = await _transport.pull(since: since);
    for (final entry in remote.entries) {
      for (final row in entry.value) {
        await _apply(entry.key, row);
      }
    }
    await _db.setLastPullAt(DateTime.now().toUtc());
  }

  Future<void> _apply(String table, Map<String, Object?> row) async {
    switch (table) {
      case 'transactions':
        await _applyTransaction(row);
      // Tabel lain (members/categories/budgets/config_parser) diurus FS-02/F1.
      default:
        break;
    }
  }

  Future<void> _applyTransaction(Map<String, Object?> row) async {
    final remoteId = row['id']! as String;
    final remoteUpdatedAt = DateTime.parse(row['updated_at']! as String);
    final local = await _db.transactionById(remoteId);

    if (local == null) {
      await _db.upsertTransaction(transactionFromMap(row));
      return;
    }

    final localUpdatedAt = local.updatedAt;
    if (remoteUpdatedAt.isAfter(localUpdatedAt)) {
      // Server lebih baru: timpa lokal, catat versi lokal yang kalah.
      await _db.upsertTransaction(transactionFromMap(row));
      await _db.writeAuditLog(
        memberEmail: (row['member_email'] as String?) ?? local.memberEmail,
        action: 'conflict_server_won',
        txnId: remoteId,
        beforeJson: jsonEncode(transactionToMap(local)),
        afterJson: jsonEncode(row),
      );
    } else if (localUpdatedAt.isAfter(remoteUpdatedAt)) {
      // Lokal lebih baru: pertahankan dan pastikan ter-antre untuk di-push.
      await _db.enqueueSync(
        tableName: 'transactions',
        rowId: remoteId,
        action: 'upsert',
        payload: transactionToMap(local),
      );
    }
    // updated_at sama: dianggap sama, tanpa aksi.
  }
}
