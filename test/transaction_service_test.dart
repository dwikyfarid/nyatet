import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/data/repository/transaction_repository.dart';
import 'package:nyatet/domain/access_policy.dart';
import 'package:nyatet/domain/transaction_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late TransactionRepository repo;
  late TransactionService service;

  final admin = AccessPolicy(email: 'bapak@example.com', role: MemberRole.admin);
  final anak = AccessPolicy(email: 'anak@example.com', role: MemberRole.member);

  setUp(() {
    db = AppDatabase.memory();
    repo = TransactionRepository(db);
    service = TransactionService(db, repo);
  });

  tearDown(() => db.close());

  test('create manual menyimpan source=manual dan masuk sync_queue', () async {
    final id = await service.createManual(
      policy: anak,
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.outFlow,
      amount: 45800,
      note: 'Makan siang',
    );

    final txn = await db.transactionById(id);
    expect(txn!.source, TransactionSource.manual);
    expect(txn.memberEmail, 'anak@example.com');
    expect(await db.pendingSyncBatch(), hasLength(1));
  });

  test('create manual menolak nominal nol', () async {
    expect(
      () => service.createManual(
        policy: admin,
        date: DateTime.utc(2026, 11, 25),
        type: TransactionType.outFlow,
        amount: 0,
      ),
      throwsA(isA<AccessDenied>()),
    );
  });

  test('admin mencatat atas nama anggota lain bila diminta', () async {
    final id = await service.createManual(
      policy: admin,
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.inFlow,
      amount: 100000,
      memberEmail: 'ibu@example.com',
    );
    final txn = await db.transactionById(id);
    expect(txn!.memberEmail, 'ibu@example.com');
  });

  test('anggota selalu mencatat atas namanya sendiri, walau mengirim email lain',
      () async {
    final id = await service.createManual(
      policy: anak,
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.outFlow,
      amount: 5000,
      memberEmail: 'bapak@example.com',
    );
    final txn = await db.transactionById(id);
    expect(txn!.memberEmail, 'anak@example.com');
  });

  test('anggota hanya melihat transaksinya sendiri', () async {
    await service.createManual(
      policy: admin,
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.outFlow,
      amount: 1000,
    );
    await service.createManual(
      policy: anak,
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.outFlow,
      amount: 2000,
    );

    final adminList = await service.listVisible(admin);
    final anakList = await service.listVisible(anak);

    expect(adminList, hasLength(2));
    expect(anakList, hasLength(1));
    expect(anakList.single.memberEmail, 'anak@example.com');
  });

  test('pencarian memfilter hasil (UX-03)', () async {
    await service.createManual(
      policy: admin,
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.outFlow,
      amount: 25000,
      note: 'GoFood makan siang',
    );
    await service.createManual(
      policy: admin,
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.outFlow,
      amount: 90000,
      note: 'Bensin',
    );

    final found = await service.listVisible(admin, query: 'gofood');
    expect(found, hasLength(1));
    expect(found.single.note, contains('GoFood'));
  });

  test('anggota tidak bisa menghapus (D-03)', () async {
    final id = await service.createManual(
      policy: anak,
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.outFlow,
      amount: 3000,
    );
    final txn = await db.transactionById(id);

    await expectLater(
      service.delete(policy: anak, txn: txn!),
      throwsA(isA<AccessDenied>()),
    );
    final after = await db.transactionById(id);
    expect(after!.isDeleted, isFalse);
  });

  test('admin menghapus = soft delete + audit_log', () async {
    final id = await service.createManual(
      policy: admin,
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.outFlow,
      amount: 3000,
    );
    final txn = await db.transactionById(id);

    await service.delete(policy: admin, txn: txn!);

    final after = await db.transactionById(id);
    expect(after!.isDeleted, isTrue);
    final audit = await db.select(db.auditLogs).get();
    expect(audit.single.action, 'delete');
    expect(await service.listVisible(admin), isEmpty);
  });

  test('anggota edit transaksi >7 hari ditolak, di dalam 7 hari boleh',
      () async {
    final id = await service.createManual(
      policy: anak,
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.outFlow,
      amount: 3000,
    );
    final txn = await db.transactionById(id);

    // Dalam 7 hari (dibuat sekarang) → boleh.
    await service.updateManual(
      policy: anak,
      txn: txn!,
      date: txn.date,
      type: txn.type,
      amount: 4500,
    );
    expect((await db.transactionById(id))!.amount, 4500);

    // Simulasikan transaksi berumur 10 hari.
    final old = await db.transactionById(id);
    final stale = Transaction(
      id: old!.id,
      date: old.date,
      type: old.type,
      amount: old.amount,
      categoryId: old.categoryId,
      account: old.account,
      merchant: old.merchant,
      note: old.note,
      memberEmail: old.memberEmail,
      source: old.source,
      goalId: old.goalId,
      receiptUrl: old.receiptUrl,
      rawText: old.rawText,
      createdAt: DateTime.now().toUtc().subtract(const Duration(days: 10)),
      updatedAt: old.updatedAt,
      isDeleted: old.isDeleted,
    );

    await expectLater(
      service.updateManual(
        policy: anak,
        txn: stale,
        date: stale.date,
        type: stale.type,
        amount: 9999,
      ),
      throwsA(isA<AccessDenied>()),
    );
  });

  test('D-23: anggota boleh membuat setoran tujuan, tidak boleh mengubah/menghapus',
      () async {
    await db.into(db.goals).insert(
          GoalsCompanion.insert(
            id: 'goal-d23',
            name: 'Dana Sekolah',
            targetAmount: 5000000,
            monthlyAllocation: 500000,
            updatedAt: DateTime.now().toUtc(),
          ),
        );

    // 1) Anggota BOLEH membuat setoran tujuan (D-20).
    final depositId = await repo.create(
      date: DateTime.now(),
      type: TransactionType.goalDeposit,
      amount: 500000,
      memberEmail: anak.email,
      source: TransactionSource.manual,
      goalId: 'goal-d23',
    );
    final deposit = await db.transactionById(depositId);
    expect(deposit!.amount, 500000);

    // 2) Anggota TIDAK boleh mengubahnya (D-23), dengan pesan yang benar.
    await expectLater(
      service.updateManual(
        policy: anak,
        txn: deposit,
        date: deposit.date,
        type: deposit.type,
        amount: 50000,
      ),
      throwsA(
        isA<AccessDenied>().having(
          (e) => e.reason,
          'reason',
          'Setoran tujuan hanya bisa dikoreksi admin.',
        ),
      ),
    );
    expect((await db.transactionById(depositId))!.amount, 500000);

    // 3) Anggota TIDAK boleh menghapusnya, alasannya bukan pesan role generik.
    await expectLater(
      service.delete(policy: anak, txn: deposit),
      throwsA(
        isA<AccessDenied>().having(
          (e) => e.reason,
          'reason',
          'Setoran tujuan hanya bisa dikoreksi admin.',
        ),
      ),
    );

    // 4) Admin BOLEH mengoreksi setoran yang sama.
    await service.updateManual(
      policy: admin,
      txn: deposit,
      date: deposit.date,
      type: deposit.type,
      amount: 450000,
    );
    expect((await db.transactionById(depositId))!.amount, 450000);
  });

  test('D-23: anggota juga tidak bisa mengoreksi penarikan tujuan', () async {
    await db.into(db.goals).insert(
          GoalsCompanion.insert(
            id: 'goal-d23-w',
            name: 'Dana Darurat',
            targetAmount: 5000000,
            monthlyAllocation: 500000,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
    final withdrawalId = await repo.create(
      date: DateTime.now(),
      type: TransactionType.goalWithdrawal,
      amount: 100000,
      memberEmail: admin.email,
      source: TransactionSource.manual,
      goalId: 'goal-d23-w',
    );
    final withdrawal = await db.transactionById(withdrawalId);

    await expectLater(
      service.updateManual(
        policy: anak,
        txn: withdrawal!,
        date: withdrawal.date,
        type: withdrawal.type,
        amount: 1,
      ),
      throwsA(
        isA<AccessDenied>().having(
          (e) => e.reason,
          'reason',
          'Setoran tujuan hanya bisa dikoreksi admin.',
        ),
      ),
    );
  });
}
