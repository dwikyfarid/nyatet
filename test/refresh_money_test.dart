import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/data/repository/transaction_repository.dart';
import 'package:nyatet/domain/access_policy.dart';
import 'package:nyatet/domain/report_service.dart';
import 'package:nyatet/ui/providers.dart';

/// F8/D-16: setelah transaksi disimpan, angka ringkasan harus dihitung ulang.
/// Uji di level provider (tanpa widget) supaya deterministik di CI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;
  late TransactionRepository repo;

  final admin =
      AccessPolicy(email: 'bapak@example.com', role: MemberRole.admin);

  setUp(() async {
    db = AppDatabase.memory();
    await db.seedDefaultCategories();
    repo = TransactionRepository(db);
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<double> terpakai() async =>
      (await container.read(cashSummaryProvider.future)).terpakai;

  test('simpan transaksi lalu refresh: ringkasan, alokasi, tujuan ikut baru',
      () async {
    expect(await terpakai(), 0);
    expect(await container.read(allocationRowsProvider.future), isEmpty);

    // Simpan seperti quick-add: transaksi keluar 30.000.
    await repo.create(
      date: DateTime.now(),
      type: TransactionType.outFlow,
      amount: 30000,
      memberEmail: admin.email,
      source: TransactionSource.manual,
    );
    container.refreshMoneyProviders();

    expect(await terpakai(), 30000, reason: 'beranda harus ikut berubah');
    final summary = await container.read(cashSummaryProvider.future);
    expect(summary.sisaKas, -30000);

    // Progres alokasi juga dihitung ulang dari data yang sama.
    final rows = await container.read(allocationRowsProvider.future);
    expect(rows, isEmpty, reason: 'belum ada alokasi bulan ini');

    // Transaksi kedua menambah angka, bukan menimpa.
    await repo.create(
      date: DateTime.now(),
      type: TransactionType.outFlow,
      amount: 20000,
      memberEmail: admin.email,
      source: TransactionSource.manual,
    );
    container.refreshMoneyProviders();
    expect(await terpakai(), 50000);
  });

  test('tanpa refresh, FutureProvider memang menyajikan angka lama (alasan fix)',
      () async {
    // Layar memegang listener; tanpa invalidate, cache inilah yang tampil.
    final sub = container.listen(cashSummaryProvider, (_, __) {});
    addTearDown(sub.close);
    expect(await terpakai(), 0);

    await repo.create(
      date: DateTime.now(),
      type: TransactionType.outFlow,
      amount: 10000,
      memberEmail: admin.email,
      source: TransactionSource.manual,
    );

    // Tanpa invalidate: cache masih 0 — inilah cacat yang dilaporkan QA.
    expect(await terpakai(), 0);
    container.refreshMoneyProviders();
    expect(await terpakai(), 10000);
  });

  test('rincian kategori ikut berubah setelah refresh', () async {
    final services = container.read(reportServiceProvider);
    final cats = await db.select(db.categories).get();
    final makan = cats.firstWhere((c) => c.name == 'Makan');

    await repo.create(
      date: DateTime.now(),
      type: TransactionType.outFlow,
      amount: 45000,
      memberEmail: admin.email,
      source: TransactionSource.manual,
      categoryId: makan.id,
    );
    container.refreshMoneyProviders();

    final groups = await services.byCategory(admin, DateTime.now(), Basket.terpakai);
    expect(groups.single.total, 45000);
    expect(groups.single.label, 'Makan');
  });
}
