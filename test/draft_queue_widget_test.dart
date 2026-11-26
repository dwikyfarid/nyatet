// ignore_for_file: deprecated_member_use
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/ui/providers.dart';
import 'package:nyatet/ui/screens/draft_queue_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.seedDefaultCategories();
  });

  tearDown(() => db.close());

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(home: child),
    );
  }

  testWidgets('antrean kosong menampilkan penjelasan + aksi', (tester) async {
    await tester.pumpWidget(wrap(const DraftQueueScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Tidak ada draf notifikasi'), findsOneWidget);
    expect(find.text('Muat draf contoh (uji F4)'), findsOneWidget);
  });

  testWidgets('antrean menampilkan progres dan draf bisa disimpan',
      (tester) async {
    await tester.runAsync(() async {
      await db.into(db.transactionDrafts).insert(
            TransactionDraftsCompanion.insert(
              id: 'd1',
              bankGroup: 'gopay',
              packageName: 'com.gojek.app',
              amount: 25000,
              type: TransactionType.outFlow,
              merchant: const Value('GoFood'),
              occurredAt: DateTime.now().toUtc(),
              receivedAt: DateTime.now().toUtc(),
            ),
          );
      await db.into(db.transactionDrafts).insert(
            TransactionDraftsCompanion.insert(
              id: 'd2',
              bankGroup: 'bca',
              packageName: 'com.bca',
              amount: 45800,
              type: TransactionType.outFlow,
              merchant: const Value('Transportation'),
              occurredAt: DateTime.now().toUtc(),
              receivedAt: DateTime.now().toUtc(),
            ),
          );
    });

    await tester.pumpWidget(wrap(const DraftQueueScreen()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('0 dari 2 draf dikonfirmasi'), findsOneWidget);
    expect(find.text('GoFood'), findsOneWidget);
    expect(find.text('Simpan'), findsNWidgets(2));

    // Simpan draf pertama (1 tap).
    await tester.tap(find.text('Simpan').first);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();

    expect(find.text('1 dari 2 draf dikonfirmasi'), findsOneWidget);
    expect(find.text('Sudah disimpan sebagai transaksi'), findsOneWidget);

    await tester.runAsync(() async {
      final txs = await db.select(db.transactions).get();
      expect(txs, hasLength(1));
      expect(txs.single.source, TransactionSource.notif);
    });
  });
}
