import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/data/seed/dev_seeder.dart';
import 'package:nyatet/ui/providers.dart';

/// F13: setelah "Reset data demo", alokasi harus tetap punya nama kategori.
/// Bug yang dilaporkan: baris berubah menjadi "Kategori" generik karena cache
/// kategori lama (id lama) tidak dibuang.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reset demo: setiap alokasi menunjuk kategori yang ada di cache baru',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await DevSeeder(db).seedTransactions();

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    // Cache awal (dipakai layar sebelum reset).
    final catsBefore = await container.read(categoriesProvider.future);
    final budgetsBefore = await container.read(allocationRowsProvider.future);
    expect(budgetsBefore, isNotEmpty);

    String? nameFor(List<Category> cats, String id) =>
        cats.where((c) => c.id == id).map((c) => c.name).firstOrNull;

    expect(
      budgetsBefore.every((b) => nameFor(catsBefore, b.categoryId) != null),
      isTrue,
      reason: 'sebelum reset semua alokasi punya nama',
    );

    await DevSeeder(db).resetDemo();

    // Tanpa invalidate: id kategori baru tidak ada di cache lama → penyebab
    // tampilan "Kategori".
    final staleLookup = budgetsBefore.every(
      (b) => nameFor(catsBefore, b.categoryId) != null,
    );
    expect(staleLookup, isTrue, reason: 'cache lama masih menunjuk baris lama');

    // Perbaikan: reset harus membuang cache kategori.
    container.invalidate(categoriesProvider);
    container.refreshMoneyProviders();
    final catsAfter = await container.read(categoriesProvider.future);
    final budgetsAfter = await container.read(allocationRowsProvider.future);

    for (final b in budgetsAfter) {
      expect(
        nameFor(catsAfter, b.categoryId),
        isNotNull,
        reason: 'alokasi ${b.id} kehilangan nama kategori setelah reset',
      );
    }
    // Nama yang dikenal tetap ada (bukan "Kategori" generik).
    final names = budgetsAfter.map((b) => nameFor(catsAfter, b.categoryId)!);
    expect(names, contains('Makan'));
    expect(names, contains('Belanja Dapur'));
  });

  test('cold start setelah reset: nama kategori langsung benar (bukan bug awal)',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await DevSeeder(db).seedTransactions();
    await DevSeeder(db).resetDemo();

    // Container baru = seperti aplikasi dibuka ulang: cache kosong, jadi nama
    // kategori langsung benar tanpa perlu invalidate apa pun.
    final cold = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(cold.dispose);

    final cats = await cold.read(categoriesProvider.future);
    final budgets = await cold.read(allocationRowsProvider.future);
    for (final b in budgets) {
      expect(
        cats.where((c) => c.id == b.categoryId).map((c) => c.name).firstOrNull,
        isNotNull,
        reason: 'cold start tidak boleh menampilkan "Kategori" generik',
      );
    }
  });
}
