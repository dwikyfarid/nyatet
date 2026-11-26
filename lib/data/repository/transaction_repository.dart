import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/mappers.dart';
import '../sync/sync_transport.dart';

/// Satu-satunya jalan masuk untuk mutasi transaksi, supaya tiap perubahan
/// pasti masuk `sync_queue` dan tercatat di `audit_log` dalam transaksi atomik.
class TransactionRepository {
  TransactionRepository(this._db);

  final AppDatabase _db;

  Future<String> create({
    required DateTime date,
    required String type,
    required double amount,
    required String memberEmail,
    required String source,
    String? categoryId,
    String account = '',
    String? merchant,
    String? note,
    String? receiptUrl,
    String? rawText,
    String? goalId,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();

    await _db.transaction(() async {
      await _db.into(_db.transactions).insert(
            TransactionsCompanion.insert(
              id: id,
              date: date,
              type: type,
              amount: amount,
              memberEmail: memberEmail,
              source: source,
              categoryId: Value(categoryId),
              account: Value(account),
              merchant: Value(merchant),
              note: Value(note),
              receiptUrl: Value(receiptUrl),
              rawText: Value(rawText),
              goalId: Value(goalId),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final created = await _db.transactionById(id);
      await _db.enqueueSync(
        tableName: 'transactions',
        rowId: id,
        action: SyncOp.create,
        payload: transactionToMap(created!),
      );
    });
    return id;
  }

  /// Update penuh: nilai yang diteruskan menggantikan nilai lama.
  Future<void> update({
    required String id,
    required String actorEmail,
    required DateTime date,
    required String type,
    required double amount,
    required String source,
    String? categoryId,
    String account = '',
    String? merchant,
    String? note,
    String? receiptUrl,
    String? rawText,
    String? goalId,
  }) async {
    await _db.transaction(() async {
      final existing = await _db.transactionById(id);
      if (existing == null) throw StateError('Transaksi tidak ditemukan: $id');
      final before = jsonEncode(transactionToMap(existing));
      final now = DateTime.now().toUtc();

      await (_db.update(_db.transactions)..where((t) => t.id.equals(id)))
          .write(
        TransactionsCompanion(
          date: Value(date),
          type: Value(type),
          amount: Value(amount),
          source: Value(source),
          categoryId: Value(categoryId),
          account: Value(account),
          merchant: Value(merchant),
          note: Value(note),
          receiptUrl: Value(receiptUrl),
          rawText: Value(rawText),
          goalId: Value(goalId),
          updatedAt: Value(now),
        ),
      );

      final after = await _db.transactionById(id);
      final afterMap = transactionToMap(after!);
      await _db.enqueueSync(
        tableName: 'transactions',
        rowId: id,
        action: SyncOp.update,
        payload: afterMap,
      );
      await _db.writeAuditLog(
        memberEmail: actorEmail,
        action: 'update',
        txnId: id,
        beforeJson: before,
        afterJson: jsonEncode(afterMap),
      );
    });
  }

  /// Penghapusan selalu soft delete: `is_deleted = true`, baris tidak pernah
  /// dihapus permanen. Idempoten terhadap baris yang sudah terhapus.
  Future<void> softDelete(String id, String actorEmail) async {
    await _db.transaction(() async {
      final existing = await _db.transactionById(id);
      if (existing == null || existing.isDeleted) return;
      final before = jsonEncode(transactionToMap(existing));
      final now = DateTime.now().toUtc();

      await (_db.update(_db.transactions)..where((t) => t.id.equals(id)))
          .write(
        TransactionsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(now),
        ),
      );

      final after = await _db.transactionById(id);
      final afterMap = transactionToMap(after!);
      await _db.enqueueSync(
        tableName: 'transactions',
        rowId: id,
        action: SyncOp.delete,
        // Server hanya butuh id untuk hapus; is_deleted diabaikan pada push.
        payload: {'id': id},
      );
      await _db.writeAuditLog(
        memberEmail: actorEmail,
        action: 'delete',
        txnId: id,
        beforeJson: before,
        afterJson: jsonEncode(afterMap),
      );
    });
  }

  Future<List<Transaction>> listActive() =>
      (_db.select(_db.transactions)
            ..where((t) => t.isDeleted.equals(false))
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .get();
}
