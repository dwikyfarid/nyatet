import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/data/repository/transaction_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late TransactionRepository repo;

  setUp(() {
    db = AppDatabase.memory();
    repo = TransactionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('create menyimpan transaksi dan mengantrekan ke sync_queue', () async {
    final id = await repo.create(
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.outFlow,
      amount: 50000,
      memberEmail: 'bapak@example.com',
      source: TransactionSource.manual,
      note: 'Beli beras',
    );

    final tx = await db.transactionById(id);
    expect(tx, isNotNull);
    expect(tx!.amount, 50000);
    expect(tx.isDeleted, false);

    final queue = await db.pendingSyncBatch();
    expect(queue, hasLength(1));
    expect(queue.first.targetTable, 'transactions');
    expect(queue.first.rowId, id);
    // D-22: operasi dikirim sebagai create/update/delete, bukan 'upsert'.
    expect(queue.first.action, 'create');

    final payload = jsonDecode(queue.first.payload) as Map<String, dynamic>;
    expect(payload['is_deleted'], false);
    expect(payload['member_email'], 'bapak@example.com');
    // Tanggal Sheet = YYYY-MM-DD lokal.
    expect(payload['date'], matches(r'^\d{4}-\d{2}-\d{2}$'));
  });

  test('setoran tujuan (goal_deposit) menyimpan goal_id dan masuk antrean',
      () async {
    final id = await repo.create(
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.goalDeposit,
      amount: 250000,
      memberEmail: 'anak@example.com',
      source: TransactionSource.manual,
      goalId: 'goal-laptop',
    );

    final tx = await db.transactionById(id);
    expect(tx!.type, 'goal_deposit');
    expect(tx.goalId, 'goal-laptop');

    // D-17: setoran tujuan bukan `out`, jadi tidak masuk keranjang terpakai.
    expect(
      tx.type == TransactionType.outFlow,
      isFalse,
      reason: 'goal_deposit tidak boleh dihitung sebagai pengeluaran',
    );

    final queue = await db.pendingSyncBatch();
    final payload = jsonDecode(queue.first.payload) as Map<String, dynamic>;
    expect(payload['goal_id'], 'goal-laptop');
  });

  test('softDelete hanya menandai is_deleted dan tetap mengantrekan', () async {
    final id = await repo.create(
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.inFlow,
      amount: 250000,
      memberEmail: 'bapak@example.com',
      source: TransactionSource.manual,
    );

    await repo.softDelete(id, 'bapak@example.com');

    final tx = await db.transactionById(id);
    expect(tx!.isDeleted, true);

    // Baris tetap ada (tidak dihapus permanen).
    final all = await db.select(db.transactions).get();
    expect(all, hasLength(1));

    // Create + delete = 2 entri antrean.
    final queue = await db.pendingSyncBatch();
    expect(queue, hasLength(2));

    final audit = await db.select(db.auditLogs).get();
    expect(audit, hasLength(1));
    expect(audit.first.action, 'delete');
    expect(audit.first.txnId, id);
  });

  test('softDelete idempoten: panggil dua kali tidak menambah antrean',
      () async {
    final id = await repo.create(
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.outFlow,
      amount: 10000,
      memberEmail: 'ibu@example.com',
      source: TransactionSource.manual,
    );

    await repo.softDelete(id, 'ibu@example.com');
    await repo.softDelete(id, 'ibu@example.com');

    final queue = await db.pendingSyncBatch();
    expect(queue, hasLength(2)); // create + satu delete
  });
}
