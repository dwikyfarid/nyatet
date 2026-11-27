import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

/// Data uji Q-07: 200 transaksi supaya QA bisa mengukur pencarian <1 detik,
/// plus 3 anggota, 3 tujuan dana (on-track / kurang / tercapai), setoran
/// tujuan, dan satu bulan tanpa pemasukan untuk menguji label "rencana"
/// (D-19). Deterministik (seed tetap) agar hasil uji bisa diulang.
class DevSeeder {
  DevSeeder(this._db);

  final AppDatabase _db;

  static const int defaultCount = 200;

  static const List<({String email, String name, String role})> members = [
    (email: 'bapak@example.com', name: 'Bapak', role: MemberRole.admin),
    (email: 'ibu@example.com', name: 'Ibu', role: MemberRole.member),
    (email: 'anak@example.com', name: 'Anak', role: MemberRole.member),
  ];

  /// Isi database dengan [count] transaksi (default 200) di dua bulan:
  /// bulan ini (ada pemasukan) dan bulan lalu (tanpa pemasukan).
  /// Mengembalikan jumlah baris yang dibuat (0 bila database sudah berisi).
  Future<int> seedTransactions({int count = defaultCount}) async {
    final existing = await _db.select(_db.transactions).get();
    if (existing.isNotEmpty) return 0;

    await _db.seedDefaultCategories();
    await _seedMembers();

    final categories = await _db.select(_db.categories).get();
    final outCats =
        categories.where((c) => c.type == TransactionType.outFlow).toList();
    final inCat = categories.firstWhere(
      (c) => c.type == TransactionType.inFlow,
      orElse: () => categories.first,
    );

    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    final lastMonth = DateTime(now.year, now.month - 1);
    final lastDayThisMonth =
        now.day < 28 ? (now.day < 1 ? 1 : now.day) : 28;

    const merchants = [
      'GoFood', 'Indomaret', 'Alfamart', 'Grab', 'Pertamina',
      'Tokopedia', 'Shopee', 'Apotek K-24', 'PLN', 'Telkomsel',
      'Warteg Bahari', 'Kopi Kenangan', 'Bioskop XXI', 'SPP Sekolah',
    ];
    const sources = [
      TransactionSource.manual,
      TransactionSource.notif,
      TransactionSource.ocr,
    ];

    final rows = <TransactionsCompanion>[];

    TransactionsCompanion txn({
      required DateTime date,
      required String type,
      required double amount,
      required String memberEmail,
      required String source,
      String? categoryId,
      String? merchant,
      String? note,
      String? goalId,
    }) {
      final at = DateTime(date.year, date.month, date.day, 9, 0).toUtc();
      return TransactionsCompanion.insert(
        id: const Uuid().v4(),
        date: date,
        type: type,
        amount: amount,
        memberEmail: memberEmail,
        source: source,
        categoryId: Value(categoryId),
        merchant: Value(merchant),
        note: Value(note),
        goalId: Value(goalId),
        createdAt: at,
        updatedAt: at,
      );
    }

    // 1) Pemasukan — hanya bulan ini. Bulan lalu sengaja tanpa pemasukan.
    rows.add(txn(
      date: DateTime(thisMonth.year, thisMonth.month, 1),
      type: TransactionType.inFlow,
      amount: 8000000,
      memberEmail: 'bapak@example.com',
      source: TransactionSource.manual,
      categoryId: inCat.id,
      merchant: 'Gaji Bapak',
      note: 'Gaji bulan ini',
    ));
    rows.add(txn(
      date: DateTime(thisMonth.year, thisMonth.month, 2),
      type: TransactionType.inFlow,
      amount: 4500000,
      memberEmail: 'ibu@example.com',
      source: TransactionSource.manual,
      categoryId: inCat.id,
      merchant: 'Gaji Ibu',
      note: 'Gaji bulan ini',
    ));

    // 2) Tiga tujuan dana + setoran (total 6 setoran).
    final goals = await _seedGoals();
    final deposits = <({String id, double amount})>[
      (id: goals.school, amount: 3000000),
      (id: goals.school, amount: 3400000),
      (id: goals.emergency, amount: 1000000),
      (id: goals.emergency, amount: 1000000),
      (id: goals.holiday, amount: 1500000),
      (id: goals.holiday, amount: 1500000),
    ];
    for (var i = 0; i < deposits.length; i++) {
      final d = deposits[i];
      final month = i.isEven ? lastMonth : thisMonth;
      rows.add(txn(
        date: DateTime(month.year, month.month, 3 + i),
        type: TransactionType.goalDeposit,
        amount: d.amount,
        memberEmail: members[i % members.length].email,
        source: TransactionSource.manual,
        goalId: d.id,
        note: 'Setoran tujuan',
      ));
    }

    // 3) Sisa transaksi = pengeluaran, dibagi rata dua bulan.
    final expenseCount = count - rows.length;
    for (var i = 0; i < expenseCount; i++) {
      final thisMonthSide = i.isEven;
      final month = thisMonthSide ? thisMonth : lastMonth;
      final maxDay = thisMonthSide ? lastDayThisMonth : 28;
      final day = 1 + ((i * 5) % maxDay);
      rows.add(txn(
        date: DateTime(month.year, month.month, day),
        type: TransactionType.outFlow,
        amount: 5000.0 + ((i * 1750) % 240) * 250,
        memberEmail: members[i % members.length].email,
        source: sources[i % sources.length],
        categoryId: outCats[i % outCats.length].id,
        merchant: merchants[i % merchants.length],
        note: 'Data uji #$i',
      ));
    }

    // 4) Alokasi & budget: bulan ini punya pemasukan, bulan lalu tidak
    //    (supaya label "rencana" bisa diuji di sana).
    await _seedBudgets(
      thisMonth: thisMonth,
      lastMonth: lastMonth,
      categories: outCats,
    );

    await _db.batch((b) => b.insertAll(_db.transactions, rows));
    return rows.length;
  }

  /// F13 demo web: kosongkan data demo lalu isi ulang 200 transaksi.
  /// Hanya menyentuh tabel demo di database browser.
  Future<int> resetDemo() async {
    await _db.transaction(() async {
      await _db.delete(_db.transactions).go();
      await _db.delete(_db.transactionDrafts).go();
      await _db.delete(_db.budgets).go();
      await _db.delete(_db.goals).go();
      await _db.delete(_db.members).go();
      await _db.delete(_db.syncQueue).go();
      await _db.delete(_db.auditLogs).go();
      await _db.delete(_db.categories).go();
    });
    return seedTransactions();
  }

  Future<void> _seedMembers() async {
    final existing = await _db.select(_db.members).get();
    final have = existing.map((m) => m.email).toSet();
    final now = DateTime.now().toUtc();
    for (final m in members) {
      if (have.contains(m.email)) continue;
      await _db.into(_db.members).insert(
            MembersCompanion.insert(
              email: m.email,
              name: m.name,
              role: m.role,
              status: 'active',
              joinedAt: now,
              id: Value(const Uuid().v4()),
              updatedAt: Value(now),
            ),
          );
    }
  }

  /// Tiga tujuan: satu on-track, satu kurang (tanpa alokasi bulanan), satu
  /// tercapai — masing-masing dengan setoran nyata.
  Future<({String school, String emergency, String holiday})> _seedGoals() async {
    final now = DateTime.now().toUtc();
    final school = const Uuid().v4();
    final emergency = const Uuid().v4();
    final holiday = const Uuid().v4();
    final rows = [
      GoalsCompanion.insert(
        id: school,
        name: 'Dana Sekolah',
        targetAmount: 10000000,
        monthlyAllocation: 1500000,
        dueDate: Value(DateTime(now.year, now.month + 8, 28)),
        status: const Value('active'),
        updatedAt: now,
      ),
      GoalsCompanion.insert(
        id: emergency,
        name: 'Dana Darurat',
        targetAmount: 20000000,
        monthlyAllocation: 0,
        status: const Value('active'),
        updatedAt: now,
      ),
      GoalsCompanion.insert(
        id: holiday,
        name: 'Liburan Keluarga',
        targetAmount: 3000000,
        monthlyAllocation: 500000,
        dueDate: Value(DateTime(now.year, now.month + 2, 20)),
        status: const Value('active'),
        updatedAt: now,
      ),
    ];
    await _db.batch((b) => b.insertAll(_db.goals, rows));
    return (school: school, emergency: emergency, holiday: holiday);
  }

  Future<void> _seedBudgets({
    required DateTime thisMonth,
    required DateTime lastMonth,
    required List<Category> categories,
  }) async {
    String key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final now = DateTime.now().toUtc();
    final rows = <BudgetsCompanion>[];
    // Lima kategori teratas dapat alokasi rencana.
    for (var i = 0; i < 5 && i < categories.length; i++) {
      final c = categories[i];
      rows.add(
        BudgetsCompanion.insert(
          id: const Uuid().v4(),
          month: key(thisMonth),
          categoryId: c.id,
          type: const Value(BudgetType.allocation),
          allocatedAmount: Value(1000000.0 + i * 250000),
          updatedAt: Value(now),
        ),
      );
      rows.add(
        BudgetsCompanion.insert(
          id: const Uuid().v4(),
          month: key(lastMonth),
          categoryId: c.id,
          type: const Value(BudgetType.allocation),
          allocatedAmount: Value(750000.0 + i * 150000),
          updatedAt: Value(now),
        ),
      );
    }
    // Budget (batas) hanya bulan ini untuk tiga kategori pertama.
    for (var i = 0; i < 3 && i < categories.length; i++) {
      rows.add(
        BudgetsCompanion.insert(
          id: const Uuid().v4(),
          month: key(thisMonth),
          categoryId: categories[i].id,
          type: const Value(BudgetType.limit),
          limitAmount: Value(1500000.0 + i * 500000),
          updatedAt: Value(now),
        ),
      );
    }
    await _db.batch((b) => b.insertAll(_db.budgets, rows));
  }
}
