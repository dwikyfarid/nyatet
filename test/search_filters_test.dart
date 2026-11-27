import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/data/repository/transaction_repository.dart';
import 'package:nyatet/data/seed/dev_seeder.dart';
import 'package:nyatet/domain/access_policy.dart';
import 'package:nyatet/domain/budget_repository.dart';
import 'package:nyatet/domain/report_service.dart';
import 'package:nyatet/domain/search_service.dart';
import 'package:nyatet/domain/transaction_filters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late TransactionRepository repo;
  late SearchService search;
  final admin =
      AccessPolicy(email: 'bapak@example.com', role: MemberRole.admin);
  final anak = AccessPolicy(email: 'anak@example.com', role: MemberRole.member);

  setUp(() async {
    db = AppDatabase.memory();
    await db.seedDefaultCategories();
    repo = TransactionRepository(db);
    search = SearchService(db);
  });

  tearDown(() async => db.close());

  test('F15: cari transaksi lewat merchant, catatan, ref_no, dan akun', () async {
    await repo.create(
      date: DateTime(2026, 11, 20),
      type: TransactionType.outFlow,
      amount: 85000,
      memberEmail: admin.email,
      source: TransactionSource.manual,
      merchant: 'Warung Bu Sri',
      note: 'sarapan',
      account: 'BCA',
      refNo: 'TRX-8891',
    );

    for (final q in ['warung', 'sarapan', 'TRX-8891', 'bca']) {
      final result = await search.search(admin, q);
      expect(result.transactions, hasLength(1), reason: 'kata "$q"');
    }
  });

  test('F15/D-50: raw_text TIDAK pernah diindeks', () async {
    await repo.create(
      date: DateTime(2026, 11, 20),
      type: TransactionType.outFlow,
      amount: 45000,
      memberEmail: admin.email,
      source: TransactionSource.notif,
      merchant: 'Transport',
      rawText: 'rekening 1234567890 a/n BUDI',
    );

    final result = await search.search(admin, '1234567890');
    expect(result.transactions, isEmpty);
    expect(result.isEmpty, isTrue);
  });

  test('F15: hasil dikelompokkan dengan jumlah per jenis', () async {
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: 'cat-sekolah-uji',
            name: 'Sekolah Anak',
            type: TransactionType.outFlow,
            updatedAt: Value(DateTime.now()),
          ),
        );
    await repo.create(
      date: DateTime(2026, 11, 20),
      type: TransactionType.outFlow,
      amount: 1000,
      memberEmail: admin.email,
      source: TransactionSource.manual,
      merchant: 'Sekolah',
    );

    final result = await search.search(admin, 'sekolah');
    expect(result.transactions, hasLength(1));
    // Kategori seed 'Sekolah' ikut cocok, jadi ada 2 kategori + 1 transaksi.
    expect(result.categories.map((c) => c.name), contains('Sekolah Anak'));
    expect(result.transactions, hasLength(1));
    expect(result.categories, hasLength(2));
    expect(result.total, 3);
  });

  test('F15: anggota hanya menemukan transaksinya sendiri', () async {
    await repo.create(
      date: DateTime(2026, 11, 20),
      type: TransactionType.outFlow,
      amount: 1000,
      memberEmail: admin.email,
      source: TransactionSource.manual,
      merchant: 'Warung',
    );
    await repo.create(
      date: DateTime(2026, 11, 20),
      type: TransactionType.outFlow,
      amount: 2000,
      memberEmail: anak.email,
      source: TransactionSource.manual,
      merchant: 'Warung',
    );

    expect((await search.search(admin, 'warung')).transactions, hasLength(2));
    expect((await search.search(anak, 'warung')).transactions, hasLength(1));
  });

  test('Q-07: cari 200 transaksi selesai <1 detik', () async {
    await DevSeeder(db).seedTransactions();
    final watch = Stopwatch()..start();
    final result = await search.search(admin, 'gofood');
    watch.stop();
    expect(result.transactions, isNotEmpty);
    expect(watch.elapsedMilliseconds, lessThan(1000));
  });

  test('F15: filter transaksi + urutan berlabel', () {
    Transaction txn({
      required String id,
      required String type,
      required String source,
      String? category,
      String member = 'bapak@example.com',
      double amount = 1000,
      String? merchant,
      int day = 1,
    }) =>
        Transaction(
          id: id,
          date: DateTime(2026, 11, day),
          type: type,
          amount: amount,
          categoryId: category,
          account: '',
          merchant: merchant,
          note: null,
          memberEmail: member,
          source: source,
          goalId: null,
          refNo: null,
          receiptUrl: null,
          rawText: null,
          createdAt: DateTime(2026, 11, day),
          updatedAt: DateTime(2026, 11, day),
          isDeleted: false,
        );

    final rows = [
      txn(id: 'a', type: TransactionType.outFlow, source: 'manual', amount: 500, merchant: 'Zebra', day: 1),
      txn(id: 'b', type: TransactionType.inFlow, source: 'notif', amount: 2000, merchant: 'Apotek', day: 2),
      txn(id: 'c', type: TransactionType.outFlow, source: 'manual', amount: 100, merchant: 'Makan', day: 3, member: 'anak@example.com'),
    ];

    expect(applyTransactionFilters(rows, type: TransactionType.outFlow).map((t) => t.id), ['c', 'a']);
    expect(applyTransactionFilters(rows, source: 'notif').map((t) => t.id), ['b']);
    expect(applyTransactionFilters(rows, memberEmail: 'anak@example.com').map((t) => t.id), ['c']);
    expect(applyTransactionFilters(rows, sort: TxSort.amountDesc).first.id, 'b');
    expect(applyTransactionFilters(rows, sort: TxSort.merchantAsc).first.merchant, 'Apotek');
    expect(TxSort.values.map((s) => s.label), [
      'Tanggal terbaru',
      'Nominal',
      'Merchant A–Z',
    ]);
  });

  test('F15: kategori nonaktif hanya muncul saat filter Nonaktif diminta',
      () async {
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: 'cat-off',
            name: 'Kategori Lama',
            type: TransactionType.outFlow,
            isActive: const Value(false),
            updatedAt: Value(DateTime.now()),
          ),
        );
    final budgets = BudgetRepository(db, ReportService(db));

    final activeOnly = await budgets.status(admin, '2026-11');
    expect(activeOnly.any((s) => s.category.id == 'cat-off'), isFalse);

    final withInactive =
        await budgets.status(admin, '2026-11', includeInactive: true);
    expect(withInactive.any((s) => s.category.id == 'cat-off'), isTrue);
  });

  test('F15: hitungan filter aktif untuk label "Filter · N"', () {
    expect(activeTransactionFilterCount(), 0);
    expect(
      activeTransactionFilterCount(
        type: TransactionType.outFlow,
        source: TransactionSource.notif,
        categoryId: 'cat',
        memberEmail: 'anak@example.com',
      ),
      4,
    );
    expect(activeTransactionFilterCount(categoryId: 'cat'), 1);
  });
}
