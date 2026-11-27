// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/home_shell.dart';
import 'package:nyatet/ui/providers.dart';

/// P1: transaksi yang disimpan lewat jalur FAB (sama seperti user) harus
/// langsung mengubah angka cockpit — tanpa membuka ulang aplikasi.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P1: simpan dari FAB beranda → angka cockpit berubah', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.seedDefaultCategories();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          home: Scaffold(body: SafeArea(child: HomeShell())),
        ),
      ),
    );
    // Pump terbatas: beberapa widget punya indikator animasi berulang.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    while (tester.takeException() != null) {}

    expect(find.textContaining('Rp 0'), findsWidgets);

    await tester.tap(find.text('Catat'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    while (tester.takeException() != null) {}

    await tester.enterText(find.byType(TextField).first, '30000');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Simpan transaksi'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    while (tester.takeException() != null) {}

    // Angka cockpit langsung memakai data baru.
    expect(find.text('Rp 30.000'), findsWidgets);

    final rows = await db.select(db.transactions).get();
    expect(rows.single.amount, 30000);
  });
}
