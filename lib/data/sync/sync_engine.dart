import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/mappers.dart';
import 'sync_transport.dart';

/// Mesin sinkronisasi: push antrean (master data dulu, transaksi kemudian),
/// lalu tarik delta dari Sheet. Kursor selalu `serverTime` server; bentrok
/// diselesaikan last-write-wins dan versi yang kalah dicatat di `audit_log`.
class SyncEngine {
  SyncEngine(this._db, {SyncTransport? transport})
      : _transport = transport ?? const NoopSyncTransport();

  final AppDatabase _db;
  final SyncTransport _transport;

  /// Entity master dikirim lewat endpoint khusus, bukan `sync.push`.
  static const String transactionsEntity = 'transactions';

  static Future<SyncEngine> openDefault() async =>
      SyncEngine(AppDatabase.open());

  Future<void> run() async {
    await push();
    await pull();
  }

  Future<int> push() async {
    final batch = await _db.pendingSyncBatch();
    if (batch.isEmpty) return 0;

    // Urutan kirim: master data dulu supaya transaksi bisa merujuk
    // kategori/tujuan yang baru dibuat (D-22).
    final master = batch.where((r) => r.targetTable != transactionsEntity);
    final txns = batch.where((r) => r.targetTable == transactionsEntity);

    var synced = 0;
    for (final row in master) {
      synced += await _pushMaster(row);
    }
    synced += await _pushTransactions(txns.toList());
    return synced;
  }

  Future<int> _pushMaster(SyncQueueData row) async {
    final mutation = _toMutation(row);
    try {
      final result = await _transport.pushMaster(mutation);
      if (result.ok) {
        await _db.markSynced(row.id);
        return 1;
      }
      await _handleFailure(row, result);
    } catch (_) {
      await _db.markSyncFailed(row.id);
    }
    return 0;
  }

  Future<int> _pushTransactions(List<SyncQueueData> rows) async {
    if (rows.isEmpty) return 0;
    final mutations = rows.map(_toMutation).toList();
    try {
      final results = await _transport.push(mutations);
      var synced = 0;
      for (var i = 0; i < rows.length; i++) {
        final result = i < results.length
            ? results[i]
            : const MutationResult(ok: false, code: 'INTERNAL');
        if (result.ok) {
          await _db.markSynced(rows[i].id);
          synced++;
          continue;
        }
        if (result.isStale && result.row != null) {
          // Server menang: timpa lokal dengan baris server, lalu selesai.
          await _apply(transactionsEntity, result.row!);
          await _db.markSynced(rows[i].id);
          synced++;
          continue;
        }
        await _handleFailure(rows[i], result);
      }
      return synced;
    } catch (_) {
      for (final row in rows) {
        await _db.markSyncFailed(row.id);
      }
      rethrow;
    }
  }

  /// Kegagalan permanen dikeluarkan dari antrean (tidak dicoba selamanya)
  /// dan dicatat supaya bisa ditampilkan ke user.
  Future<void> _handleFailure(
    SyncQueueData row,
    MutationResult result,
  ) async {
    if (result.isPermanentFailure) {
      await _db.writeAuditLog(
        memberEmail: 'sync',
        action: 'sync_rejected',
        txnId: row.rowId,
        afterJson: jsonEncode({
          'entity': row.targetTable,
          'code': result.code,
          'message': result.message,
        }),
      );
      await _db.removeSyncRow(row.id);
      return;
    }
    await _db.markSyncFailed(row.id);
  }

  SyncMutation _toMutation(SyncQueueData row) => SyncMutation(
        entity: row.targetTable,
        op: row.action,
        data: Map<String, Object?>.from(jsonDecode(row.payload) as Map),
        updatedAt: row.createdAt,
      );

  /// Tarik delta. Bila server memotong hasil (`truncated`), ulangi dengan
  /// `nextSince` per entity, bukan menggeser kursor global.
  Future<void> pull() async {
    final start = await _db.lastPullAt();
    var since = start;
    DateTime? cursor = start;
    Set<String>? only;
    for (var page = 0; page < 5; page++) {
      final result = await _transport.pull(since: since, entities: only);
      for (final entry in result.entities.entries) {
        for (final row in entry.value.rows) {
          await _apply(entry.key, row);
        }
      }
      // Kursor = jam server, supaya jam HP yang maju tidak melewatkan baris.
      cursor = result.serverTime;
      final truncated = result.entities.entries
          .where((e) => e.value.truncated && e.value.nextSince != null)
          .toList();
      if (truncated.isEmpty) break;
      only = truncated.map((e) => e.key).toSet();
      since = truncated
          .map((e) => e.value.nextSince!)
          .reduce((a, b) => a.isBefore(b) ? a : b);
    }
    await _db.setLastPullAt(cursor ?? DateTime.now().toUtc());
  }

  Future<void> _apply(String entity, Map<String, Object?> row) async {
    switch (entity) {
      case transactionsEntity:
        await _applyTransaction(row);
      case 'members':
        await _applyMember(row);
      case 'categories':
        await _applyCategory(row);
      case 'budgets':
        await _applyBudget(row);
      case 'goals':
        await _applyGoal(row);
      case 'config_parser':
        await _applyConfigParser(row);
      default:
        // Entity yang belum dikenal diabaikan tanpa merusak antrean.
        break;
    }
  }

  Future<void> _applyTransaction(Map<String, Object?> row) async {
    final remoteId = row['id']! as String;
    final remoteUpdatedAt =
        DateTime.parse(row['updated_at']! as String).toUtc();
    final local = await _db.transactionById(remoteId);

    if (local == null) {
      await _db.upsertTransaction(transactionFromMap(row));
      return;
    }

    final localUpdatedAt = local.updatedAt.toUtc();
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
        tableName: transactionsEntity,
        rowId: remoteId,
        action: SyncOp.update,
        payload: transactionToMap(local),
      );
    }
    // updated_at sama: dianggap sama, tanpa aksi.
  }

  Future<void> _applyMember(Map<String, Object?> row) async {
    final email = row['email']! as String;
    final local = await (_db.select(_db.members)
          ..where((m) => m.email.equals(email)))
        .getSingleOrNull();
    if (local == null) {
      await _db.into(_db.members).insert(memberFromMap(row));
      return;
    }
    final remoteAt = _updatedAt(row);
    if (remoteAt != null && !remoteAt.isAfter(local.updatedAt.toUtc())) return;
    await (_db.update(_db.members)..where((m) => m.email.equals(email)))
        .write(memberFromMap(row));
  }

  Future<void> _applyCategory(Map<String, Object?> row) async {
    final id = row['id']! as String;
    final local = await (_db.select(_db.categories)
          ..where((c) => c.id.equals(id)))
        .getSingleOrNull();
    if (local == null) {
      await _db.into(_db.categories).insert(categoryFromMap(row));
      return;
    }
    final remoteAt = _updatedAt(row);
    if (remoteAt != null && !remoteAt.isAfter(local.updatedAt.toUtc())) return;
    await (_db.update(_db.categories)..where((c) => c.id.equals(id)))
        .write(categoryFromMap(row));
  }

  Future<void> _applyBudget(Map<String, Object?> row) async {
    final id = row['id']! as String;
    var local = await (_db.select(_db.budgets)..where((b) => b.id.equals(id)))
        .getSingleOrNull();
    local ??= await (_db.select(_db.budgets)
          ..where(
            (b) =>
                b.month.equals(row['month']! as String) &
                b.categoryId.equals(row['category_id']! as String) &
                b.type.equals((row['type'] as String?) ?? BudgetType.limit),
          ))
        .getSingleOrNull();
    if (local == null) {
      await _db.into(_db.budgets).insert(budgetFromMap(row));
      return;
    }
    final remoteAt = _updatedAt(row);
    if (remoteAt != null && !remoteAt.isAfter(local.updatedAt.toUtc())) return;
    await (_db.update(_db.budgets)..where((b) => b.id.equals(local!.id)))
        .write(budgetFromMap(row));
  }

  Future<void> _applyGoal(Map<String, Object?> row) async {
    final id = row['id']! as String;
    final local = await (_db.select(_db.goals)..where((g) => g.id.equals(id)))
        .getSingleOrNull();
    if (local == null) {
      await _db.into(_db.goals).insert(goalFromMap(row));
      return;
    }
    final remoteAt = _updatedAt(row);
    if (remoteAt != null && !remoteAt.isAfter(local.updatedAt.toUtc())) return;
    await (_db.update(_db.goals)..where((g) => g.id.equals(id)))
        .write(goalFromMap(row));
  }

  Future<void> _applyConfigParser(Map<String, Object?> row) async {
    // Parser tanpa pola (belum ada contoh notifikasi) tidak disimpan sebagai
    // baris aktif — mencegah parsing dengan konfigurasi setengah jadi.
    final pattern = (row['pattern'] as String?) ?? '';
    if (pattern.isEmpty) return;
    final id = row['id']! as String;
    final local = await (_db.select(_db.configParsers)
          ..where((c) => c.id.equals(id)))
        .getSingleOrNull();
    if (local == null) {
      await _db.into(_db.configParsers).insert(configParserFromMap(row));
      return;
    }
    final remoteAt = _updatedAt(row);
    if (remoteAt != null && !remoteAt.isAfter(local.updatedAt.toUtc())) return;
    await (_db.update(_db.configParsers)..where((c) => c.id.equals(id)))
        .write(configParserFromMap(row));
  }

  DateTime? _updatedAt(Map<String, Object?> row) {
    final raw = row['updated_at'] as String?;
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }
}
