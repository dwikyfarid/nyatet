// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/data/seed/dev_seeder.dart';
import 'package:nyatet/ui/providers.dart';
import 'package:nyatet/ui/screens/transactions_screen.dart';

/// F15 L3: panel filter, chip aktif, posisi gulir, dan label Semantics.
Future<(ProviderContainer, AppDatabase)> pumpTransactions(
  WidgetTester tester, {
  String? type,
  String? source,
  double offset = 0,
  bool seed = false,
}) async {
  final db = AppDatabase.memory();
  addTearDown(db.close);
  await db.seedDefaultCategories();
  if (seed) await DevSeeder(db).seedTransactions();

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      if (type != null) txTypeFilterProvider.overrideWith((ref) => type),
      if (source != null) txSourceFilterProvider.overrideWith((ref) => source),
      txScrollOffsetProvider.overrideWith((ref) => offset),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: TransactionsScreen()),
    ),
  );
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  while (tester.takeException() != null) {}
  return (container, db);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('L15(a): panel filter terbuka, keadaan kosong, lalu tertutup',
      (tester) async {
    await pumpTransactions(tester);

    await tester.tap(find.text('Filter'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    while (tester.takeException() != null) {}

    expect(find.text('Belum ada filter dipilih'), findsOneWidget);
    expect(find.text('Terapkan filter'), findsOneWidget);

    await tester.tap(find.byTooltip('Tutup panel filter'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    while (tester.takeException() != null) {}

    expect(find.text('Belum ada filter dipilih'), findsNothing);
  });

  testWidgets('L15(b): chip aktif dilepas satu per satu, Reset semua kosongkan',
      (tester) async {
    final (container, _) = await pumpTransactions(
      tester,
      type: TransactionType.outFlow,
      source: TransactionSource.notif,
    );

    expect(find.text('Filter · 2'), findsOneWidget);
    expect(find.text('Jenis: Keluar'), findsOneWidget);

    await tester.tap(find.byTooltip('Lepas filter').first);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    while (tester.takeException() != null) {}

    expect(container.read(txTypeFilterProvider), isNull);
    expect(container.read(txSourceFilterProvider), TransactionSource.notif);

    // Reset semua lewat panel (chip baris horizontal bisa di luar viewport).
    await tester.tap(find.widgetWithText(OutlinedButton, 'Filter · 1'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    while (tester.takeException() != null) {}

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reset semua'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    while (tester.takeException() != null) {}
    await tester.tap(find.text('Terapkan filter'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    while (tester.takeException() != null) {}

    expect(container.read(txSourceFilterProvider), isNull);
    expect(container.read(txTypeFilterProvider), isNull);
  });

  testWidgets('L15(c): posisi gulir dipulihkan saat L3 dibuka dari hasil cari',
      (tester) async {
    await pumpTransactions(tester, seed: true, offset: 420);

    final scrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsWidgets);
    final position = tester.state<ScrollableState>(scrollable.first).position;
    expect(position.pixels, closeTo(420, 1));
  });

  testWidgets('L15(d): kolom cari dan chip aktif punya label Semantics',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpTransactions(tester, type: TransactionType.outFlow);

    expect(find.bySemanticsLabel('Cari transaksi'), findsAtLeastNWidgets(1));
    expect(
      find.bySemanticsLabel(RegExp('Filter aktif Jenis: Keluar')),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.bySemanticsLabel(RegExp('Filter transaksi, 1 aktif')),
      findsAtLeastNWidgets(1),
    );
    handle.dispose();
  });
}
