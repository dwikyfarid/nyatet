import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/data/database/mappers.dart';
import 'package:nyatet/data/repository/transaction_repository.dart';
import 'package:nyatet/domain/txn_number.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('F18: format NYT-YYMMDD-NNN dan urutan harian 3 digit', () {
    expect(formatTxnNumber(DateTime(2026, 11, 27), 1), 'NYT-261127-001');
    expect(formatTxnNumber(DateTime(2026, 1, 5), 12), 'NYT-260105-012');
    expect(formatTxnNumber(DateTime(2026, 12, 31), 999), 'NYT-261231-999');
    expect(txnNumberDayKey(DateTime(2026, 11, 27)), '261127');
  });

  late AppDatabase db;
  late TransactionRepository repo;

  setUp(() async {
    db = AppDatabase.memory();
    await db.seedDefaultCategories();
    repo = TransactionRepository(db);
  });

  tearDown(() async => db.close());

  test('F18: nomor dibuat sekali, unik, dan tidak berubah saat diedit',
      () async {
    final a = await repo.create(
      date: DateTime(2026, 11, 27, 9),
      type: TransactionType.outFlow,
      amount: 1000,
      memberEmail: 'bapak@example.com',
      source: TransactionSource.manual,
    );
    final b = await repo.create(
      date: DateTime(2026, 11, 27, 10),
      type: TransactionType.outFlow,
      amount: 2000,
      memberEmail: 'bapak@example.com',
      source: TransactionSource.manual,
    );
    final c = await repo.create(
      date: DateTime(2026, 11, 28, 8),
      type: TransactionType.outFlow,
      amount: 3000,
      memberEmail: 'bapak@example.com',
      source: TransactionSource.manual,
    );

    expect((await db.transactionById(a))!.txnNo, 'NYT-261127-001');
    expect((await db.transactionById(b))!.txnNo, 'NYT-261127-002');
    expect((await db.transactionById(c))!.txnNo, 'NYT-261128-001');

    // Unik lintas semua baris.
    final rows = await db.select(db.transactions).get();
    final numbers = rows.map((t) => t.txnNo).toSet();
    expect(numbers.length, rows.length);

    // Edit tidak mengubah nomor dan tidak pernah menyentuh ref_no.
    final before = (await db.transactionById(a))!;
    await repo.update(
      id: a,
      actorEmail: 'bapak@example.com',
      date: before.date,
      type: before.type,
      amount: 9999,
      source: before.source,
      refNo: 'BANK-REF-1',
    );
    final after = (await db.transactionById(a))!;
    expect(after.txnNo, before.txnNo);
    expect(after.refNo, 'BANK-REF-1');
  });

  test('F18: nomor transaksi dan nomor referensi tidak tertukar di payload',
      () async {
    final id = await repo.create(
      date: DateTime(2026, 11, 27),
      type: TransactionType.outFlow,
      amount: 500,
      memberEmail: 'bapak@example.com',
      source: TransactionSource.manual,
      refNo: 'TRX-BANK-99',
    );
    final row = (await db.transactionById(id))!;
    final payload = jsonDecode(
      (await db.pendingSyncBatch()).last.payload,
    ) as Map<String, dynamic>;
    expect(payload['txn_no'], row.txnNo);
    expect(payload['ref_no'], 'TRX-BANK-99');
    expect(payload['txn_no'], isNot(payload['ref_no']));

    final roundTrip = transactionFromMap(transactionToMap(row));
    expect(roundTrip.txnNo.value, row.txnNo);
    expect(roundTrip.refNo.value, 'TRX-BANK-99');
  });
}
