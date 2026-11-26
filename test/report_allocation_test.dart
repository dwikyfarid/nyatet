import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/data/repository/transaction_repository.dart';
import 'package:nyatet/data/seed/dev_seeder.dart';
import 'package:nyatet/domain/access_policy.dart';
import 'package:nyatet/domain/allocation_repository.dart';
import 'package:nyatet/domain/report_service.dart';
import 'package:nyatet/domain/transaction_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late TransactionRepository repo;
  late TransactionService service;
  late ReportService reports;
  late AllocationRepository allocations;

  final admin =
      AccessPolicy(email: 'bapak@example.com', role: MemberRole.admin);
  final anak = AccessPolicy(email: 'anak@example.com', role: MemberRole.member);
  final month = DateTime(2026, 11, 15);

  setUp(() async {
    db = AppDatabase.memory();
    await db.seedDefaultCategories();
    repo = TransactionRepository(db);
    service = TransactionService(db, repo);
    reports = ReportService(db);
    allocations = AllocationRepository(db, repo, reports);
  });

  tearDown(() => db.close());

  Future<String> add({
    required String type,
    required double amount,
    String? member,
    String? goalId,
    DateTime? date,
  }) {
    return repo.create(
      date: date ?? DateTime(2026, 11, 10, 12),
      type: type,
      amount: amount,
      memberEmail: member ?? 'bapak@example.com',
      source: TransactionSource.manual,
      goalId: goalId,
    );
  }

  test('D-17: 4 keranjang terpisah, setoran tidak masuk terpakai', () async {
    await add(type: TransactionType.inFlow, amount: 5000000);
    await add(type: TransactionType.outFlow, amount: 1200000);
    await add(type: TransactionType.goalDeposit, amount: 500000, goalId: 'g1');
    await add(type: TransactionType.transfer, amount: 300000);

    final s = await reports.summary(admin, month);

    expect(s.masuk, 5000000);
    expect(s.terpakai, 1200000, reason: 'hanya out yang jadi terpakai');
    expect(s.disisihkan, 500000, reason: 'setoran tujuan = aset');
    expect(
      s.sisaKas,
      3300000,
      reason: 'masuk - terpakai - disisihkan; transfer tidak dihitung',
    );
    expect(s.terpakai == s.disisihkan, isFalse);
  });

  test('D-17: penarikan tujuan masuk keranjang masuk', () async {
    await add(type: TransactionType.inFlow, amount: 1000000);
    await add(type: TransactionType.goalWithdrawal, amount: 200000, goalId: 'g1');

    final s = await reports.summary(admin, month);
    expect(s.masuk, 1200000);
    expect(s.terpakai, 0);
  });

  test('D-16: total level atas = jumlah transaksi level bawah', () async {
    final catId = (await db.select(db.categories).get()).first.id;
    for (var i = 0; i < 5; i++) {
      final id = await add(type: TransactionType.outFlow, amount: 1000.0 * (i + 1));
      final txn = await db.transactionById(id);
      // upsertTransaction = INSERT ... ON CONFLICT UPDATE, jadi drift butuh
      // baris lengkap; kirim semua kolom wajib dari transaksi yang sudah ada.
      await db.upsertTransaction(
        TransactionsCompanion(
          id: Value(txn!.id),
          date: Value(txn.date),
          type: Value(txn.type),
          amount: Value(txn.amount),
          categoryId: Value(catId),
          memberEmail: Value(txn.memberEmail),
          source: Value(txn.source),
          createdAt: Value(txn.createdAt),
          updatedAt: Value(txn.updatedAt),
        ),
      );
    }
    await add(type: TransactionType.outFlow, amount: 7000);

    final groups = await reports.byCategory(admin, month, Basket.terpakai);
    final summary = await reports.summary(admin, month);
    final groupTotal = groups.fold<double>(0, (sum, g) => sum + g.total);
    final rowCount = groups.fold<int>(0, (sum, g) => sum + g.count);

    expect(groupTotal, summary.terpakai);
    expect(rowCount, 6);

    // Level 3.2: daftar penyusun satu grup, jumlahnya sama.
    final rows = await reports.listBasket(
      admin,
      month,
      Basket.terpakai,
      categoryId: catId,
    );
    expect(rows.length, 5);
    expect(rows.fold<double>(0, (s, t) => s + t.amount), 15000);
  });

  test('anggota hanya melihat angkanya sendiri di laporan', () async {
    await add(type: TransactionType.outFlow, amount: 1000);
    await add(type: TransactionType.outFlow, amount: 9000, member: 'anak@example.com');

    final adminSum = await reports.summary(admin, month);
    final anakSum = await reports.summary(anak, month);
    expect(adminSum.terpakai, 10000);
    expect(anakSum.terpakai, 9000);
  });

  test('F10: alokasi melebihi pemasukan diblokir dengan pesan nominal',
      () async {
    await add(type: TransactionType.inFlow, amount: 1000000);
    final cats = await db.select(db.categories).get();

    await expectLater(
      allocations.setAllocation(
        policy: admin,
        monthKey: '2026-11',
        categoryId: cats[0].id,
        amount: 1500000,
      ),
      throwsA(
        isA<AllocationRuleViolation>().having(
          (e) => e.message,
          'message',
          contains(RegExp('alokasi lebih', caseSensitive: false)),
        ),
      ),
    );
  });

  test('F10: pemasukan belum tercatat → alokasi disimpan sebagai rencana',
      () async {
    final cats = await db.select(db.categories).get();
    final result = await allocations.setAllocation(
      policy: admin,
      monthKey: '2026-11',
      categoryId: cats[0].id,
      amount: 300000,
    );
    expect(result.planned, isTrue);
    expect(await allocations.allocationsFor('2026-11'), hasLength(1));
  });

  test('F10: alokasi tidak boleh melebihi budget kategori', () async {
    await add(type: TransactionType.inFlow, amount: 5000000);
    final cats = await db.select(db.categories).get();
    await allocations.setLimit(
      policy: admin,
      monthKey: '2026-11',
      categoryId: cats[0].id,
      amount: 400000,
    );

    await expectLater(
      allocations.setAllocation(
        policy: admin,
        monthKey: '2026-11',
        categoryId: cats[0].id,
        amount: 500000,
      ),
      throwsA(isA<AllocationRuleViolation>()),
    );
  });

  test('F10: belum dialokasikan = pemasukan - total alokasi', () async {
    await add(type: TransactionType.inFlow, amount: 2000000);
    final cats = await db.select(db.categories).get();
    await allocations.setAllocation(
      policy: admin,
      monthKey: '2026-11',
      categoryId: cats[0].id,
      amount: 700000,
    );
    await allocations.setAllocation(
      policy: admin,
      monthKey: '2026-11',
      categoryId: cats[1].id,
      amount: 300000,
    );

    expect(await reports.unallocated(admin, month), 1000000);
  });

  test('F10: anggota tidak bisa menetapkan alokasi', () async {
    final cats = await db.select(db.categories).get();
    await expectLater(
      allocations.setAllocation(
        policy: anak,
        monthKey: '2026-11',
        categoryId: cats[0].id,
        amount: 1000,
      ),
      throwsA(isA<AllocationRuleViolation>()),
    );
  });

  test('F10: setoran tujuan menambah progres dan menjadi Disisihkan', () async {
    final goalId = await allocations.createGoal(
      policy: admin,
      name: 'Dana Sekolah',
      targetAmount: 10000000,
      monthlyAllocation: 1000000,
    );

    // Anggota boleh menyetor (D-20).
    final txnId = await allocations.deposit(
      policy: anak,
      goalId: goalId,
      amount: 2500000,
    );
    final txn = await db.transactionById(txnId);
    expect(txn!.type, TransactionType.goalDeposit);
    expect(txn.goalId, goalId);
    expect(txn.memberEmail, 'anak@example.com');

    final goals = await allocations.goalsWithProgress(admin);
    final g = goals.single;
    expect(g.collected, 2500000);
    expect((g.ratio * 100).round(), 25);
    expect(g.statusLabel, contains('on-track'));

    final s = await reports.summary(admin, month);
    expect(s.disisihkan, 2500000);
    expect(s.terpakai, 0);
  });

  test('F10: tujuan tercapai diberi status eksplisit "tercapai"', () async {
    final goalId = await allocations.createGoal(
      policy: admin,
      name: 'Dana Darurat',
      targetAmount: 1000000,
      monthlyAllocation: 500000,
    );
    await allocations.deposit(policy: admin, goalId: goalId, amount: 1000000);

    final g = (await allocations.goalsWithProgress(admin)).single;
    expect(g.achieved, isTrue);
    expect(g.statusLabel, 'tercapai');
  });

  test('F10: penarikan tujuan mengurangi progres', () async {
    final goalId = await allocations.createGoal(
      policy: admin,
      name: 'Dana Liburan',
      targetAmount: 5000000,
      monthlyAllocation: 500000,
    );
    await allocations.deposit(policy: admin, goalId: goalId, amount: 1000000);
    await allocations.withdraw(policy: admin, goalId: goalId, amount: 400000);

    final g = (await allocations.goalsWithProgress(admin)).single;
    expect(g.collected, 600000);
  });

  test('F10: anggota tidak bisa membuat tujuan', () async {
    await expectLater(
      allocations.createGoal(
        policy: anak,
        name: 'Tujuan anak',
        targetAmount: 100000,
        monthlyAllocation: 10000,
      ),
      throwsA(isA<AllocationRuleViolation>()),
    );
  });

  test('Q-07: 200 transaksi uji termuat dan pencarian < 1 detik', () async {
    final created = await DevSeeder(db).seedTransactions();
    expect(created, 200);

    // Idempoten: seed kedua tidak menambah baris.
    expect(await DevSeeder(db).seedTransactions(), 0);

    final watch = Stopwatch()..start();
    final found = await service.listVisible(admin, query: 'gofood');
    watch.stop();

    expect(found, isNotEmpty);
    expect(
      watch.elapsedMilliseconds,
      lessThan(1000),
      reason: 'pencarian 200 transaksi harus <1 detik (UX-03)',
    );
  });
}
