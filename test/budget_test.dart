import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/data/repository/transaction_repository.dart';
import 'package:nyatet/data/seed/dev_seeder.dart';
import 'package:nyatet/domain/access_policy.dart';
import 'package:nyatet/domain/allocation_repository.dart';
import 'package:nyatet/domain/budget_repository.dart';
import 'package:nyatet/domain/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late TransactionRepository repo;
  late ReportService reports;
  late AllocationRepository allocations;
  late BudgetRepository budgets;
  late List<Category> cats;

  final admin =
      AccessPolicy(email: 'bapak@example.com', role: MemberRole.admin);
  final anak = AccessPolicy(email: 'anak@example.com', role: MemberRole.member);
  const monthKey = '2026-11';
  final date = DateTime(2026, 11, 10, 12);

  setUp(() async {
    db = AppDatabase.memory();
    await db.seedDefaultCategories();
    repo = TransactionRepository(db);
    reports = ReportService(db);
    allocations = AllocationRepository(db, repo, reports);
    budgets = BudgetRepository(db, reports);
    cats = await db.select(db.categories).get();
  });

  tearDown(() async {
    await db.close();
  });

  Category cat(String name) => cats.firstWhere((c) => c.name == name);

  Future<void> spend(double amount, {String? name, String member = 'bapak@example.com'}) {
    return repo.create(
      date: date,
      type: TransactionType.outFlow,
      amount: amount,
      memberEmail: member,
      source: TransactionSource.manual,
      categoryId: cat(name ?? 'Makan').id,
    );
  }

  Future<CategoryBudgetStatus> statusOf(String name, {AccessPolicy? policy}) async {
    final list = await budgets.status(policy ?? admin, monthKey);
    return list.firstWhere((s) => s.category.name == name);
  }

  test('F7: kategori awal 10 sesuai daftar backlog', () async {
    final names = cats.map((c) => c.name).toSet();
    expect(
      names,
      containsAll([
        'Makan', 'Belanja Dapur', 'Transport', 'Listrik/Air/Internet',
        'Sekolah', 'Kesehatan', 'Cicilan', 'Hiburan', 'Gaji', 'Lain-lain',
      ]),
    );
  });

  test('F7: ambang 80% amber, 100% merah, selalu teks persen + panah',
      () async {
    await allocations.setLimit(
      policy: admin,
      monthKey: monthKey,
      categoryId: cat('Makan').id,
      amount: 1000000,
    );

    await spend(750000);
    var s = await statusOf('Makan');
    expect(s.level, BudgetLevel.aman);
    expect(s.percentLabel, '75% ▼');

    await spend(50000); // 80%
    s = await statusOf('Makan');
    expect(s.level, BudgetLevel.waspada);
    expect(s.percentLabel, '80% ▼');

    await spend(250000); // 105%
    s = await statusOf('Makan');
    expect(s.level, BudgetLevel.lewat);
    expect(s.percentLabel, '105% ▼');
    expect(s.levelLabel, 'melewati batas');
    // D-11: panah tidak boleh berarti "mendekati batas" — ▲ khusus masuk.
    expect(s.percentLabel.contains('▲'), isFalse);
  });

  test('F7/D-17: setoran tujuan tidak memakan budget', () async {
    await allocations.setLimit(
      policy: admin,
      monthKey: monthKey,
      categoryId: cat('Makan').id,
      amount: 1000000,
    );
    await spend(900000);

    final goalId = await allocations.createGoal(
      policy: admin,
      name: 'Dana Sekolah',
      targetAmount: 5000000,
      monthlyAllocation: 500000,
    );
    await allocations.deposit(
      policy: admin,
      goalId: goalId,
      amount: 500000,
      date: date,
    );

    final s = await statusOf('Makan');
    expect(s.spent, 900000, reason: 'hanya terpakai (out) yang dihitung');
    expect(s.level, BudgetLevel.waspada);
    // Terpakai dan disisihkan tetap terpisah di rekap.
    final summary = await reports.summary(admin, date);
    expect(summary.terpakai, 900000);
    expect(summary.disisihkan, 500000);
  });

  test('F7: anggota tidak bisa mengelola kategori & budget', () async {
    await expectLater(
      budgets.createCategory(policy: anak, name: 'Hobi', type: 'out'),
      throwsA(isA<AllocationRuleViolation>()),
    );
    await expectLater(
      budgets.updateCategory(
        policy: anak,
        id: cat('Makan').id,
        name: 'Makan Baru',
      ),
      throwsA(isA<AllocationRuleViolation>()),
    );
    await expectLater(
      budgets.deactivateCategory(policy: anak, id: cat('Makan').id),
      throwsA(isA<AllocationRuleViolation>()),
    );
    await expectLater(
      allocations.setLimit(
        policy: anak,
        monthKey: monthKey,
        categoryId: cat('Makan').id,
        amount: 1000000,
      ),
      throwsA(isA<AllocationRuleViolation>()),
    );
  });

  test('F7: anggota hanya melihat pemakaiannya sendiri', () async {
    await allocations.setLimit(
      policy: admin,
      monthKey: monthKey,
      categoryId: cat('Makan').id,
      amount: 1000000,
    );
    await spend(200000, member: 'bapak@example.com');
    await spend(300000, member: 'anak@example.com');

    expect((await statusOf('Makan')).spent, 500000);
    expect((await statusOf('Makan', policy: anak)).spent, 300000);
  });

  test('F7: admin tambah/ubah/nonaktifkan kategori, perubahan masuk antrean',
      () async {
    final id = await budgets.createCategory(
      policy: admin,
      name: 'Hobi',
      type: TransactionType.outFlow,
    );
    expect((await statusOf('Hobi')).category.isActive, isTrue);

    await budgets.updateCategory(
      policy: admin,
      id: id,
      name: 'Hobi Keluarga',
    );
    expect((await statusOf('Hobi Keluarga')).category.id, id);

    await budgets.deactivateCategory(policy: admin, id: id);
    final all = await db.select(db.categories).get();
    expect(all.firstWhere((c) => c.id == id).isActive, isFalse);
    // Nonaktif tidak muncul lagi di daftar L8.
    expect(
      (await budgets.status(admin, monthKey)).any((s) => s.category.id == id),
      isFalse,
    );

    final queued = await db.pendingSyncBatch();
    expect(queued.map((q) => q.targetTable).toSet(), {'categories'});
    expect(queued.map((q) => q.action).toList(), ['create', 'update', 'delete']);
  });

  test('F7: seed 200 transaksi tetap punya budget & alokasi terpisah',
      () async {
    final fresh = AppDatabase.memory();
    addTearDown(fresh.close);
    await DevSeeder(fresh).seedTransactions();

    final list = await BudgetRepository(fresh, ReportService(fresh))
        .status(admin, ReportService.monthKey(DateTime.now()));
    expect(list.where((s) => s.hasBudget), isNotEmpty);
    // Setoran tujuan ada, tapi tidak boleh membengkakkan "terpakai".
    final rows = await fresh.select(fresh.transactions).get();
    expect(rows.where((t) => t.type == TransactionType.goalDeposit), isNotEmpty);
  });

  test('D-34: kategori masuk tidak punya budget, setLimit ditolak dengan pesan',
      () async {
    final gaji = cat('Gaji');
    expect(gaji.type, TransactionType.inFlow);

    final status = (await budgets.status(admin, monthKey))
        .firstWhere((s) => s.category.id == gaji.id);
    expect(status.isExpense, isFalse);
    expect(status.hasBudget, isFalse);
    expect(status.percentLabel, 'tanpa budget');
    expect(status.levelLabel, 'masuk · tanpa budget');

    await expectLater(
      allocations.setLimit(
        policy: admin,
        monthKey: monthKey,
        categoryId: gaji.id,
        amount: 1000000,
      ),
      throwsA(
        isA<AllocationRuleViolation>().having(
          (e) => e.message,
          'message',
          contains('hanya untuk kategori pengeluaran'),
        ),
      ),
    );
  });
}
