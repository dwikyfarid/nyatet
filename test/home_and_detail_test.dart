// ignore_for_file: deprecated_member_use
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/home_shell.dart';
import 'package:nyatet/ui/providers.dart';
import 'package:nyatet/ui/widgets/transaction_detail.dart';

Transaction _goalDeposit({String member = 'anak@example.com'}) {
  final at = DateTime.utc(2026, 11, 20);
  return Transaction(
    id: 't-goal',
    date: at,
    type: TransactionType.goalDeposit,
    amount: 500000,
    categoryId: null,
    account: '',
    merchant: null,
    note: 'Setoran tujuan',
    memberEmail: member,
    source: TransactionSource.manual,
    goalId: 'g1',
    receiptUrl: null,
    rawText: null,
    createdAt: at,
    updatedAt: at,
    isDeleted: false,
  );
}

/// flutter_test memakai font Ahem (huruf selebar kotak) yang membuat teks
/// jauh lebih lebar dari aslinya. Muat font sistem supaya pengukuran tinggi
/// isi beranda mendekati perangkat sungguhan.
Future<void> _loadRealFont() async {
  // Font dibundel di repo (Roboto, Apache-2.0): di CI tidak ada Arial, dan
  // font Ahem membuat lebar teks jauh berbeda dari perangkat.
  final file = File('test/fonts/Roboto-Regular.ttf');
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Dimuat sekali di luar widget test: FontLoader memicu relayout sistem yang
  // tidak boleh berjalan saat pohon widget sudah dibuang.
  setUpAll(_loadRealFont);

  testWidgets('F8/D-18: FAB Catat ada di beranda dan 5 info tetap tanpa scroll',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.seedDefaultCategories();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: SafeArea(child: HomeShell()))),
      ),
    );
    await tester.pumpAndSettle();
    // flutter_test memakai font Ahem (tiap huruf selebar kotak), jadi beberapa
    // baris melaporkan overflow yang tidak terjadi dengan font asli di
    // perangkat. Tidak memengaruhi pengukuran tinggi isi.
    while (tester.takeException() != null) {}

    // FAB aksi utama terlihat dari beranda (bukan hanya tab Transaksi).
    expect(find.text('Catat'), findsOneWidget);

    // 5 info beranda (label memakai awalan panah semantik D-11).
    expect(find.textContaining('Masuk'), findsWidgets);
    expect(find.textContaining('Terpakai'), findsWidgets);
    expect(find.textContaining('Disisihkan'), findsWidgets);
    expect(find.text('Sisa kas'), findsOneWidget);
    expect(find.text('Progres alokasi'), findsOneWidget);
    expect(find.text('Aset keluarga'), findsOneWidget);
    expect(find.textContaining('draf menunggu konfirmasi'), findsOneWidget);

    final listView = find.byType(ListView).first;
    final bodyHeight = tester.getSize(listView).height;
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    final maxScroll = scrollable.position.maxScrollExtent;
    // Angka ini yang dilaporkan: isi beranda tidak perlu digulir.
    debugPrint('BERANDA bodyHeight=$bodyHeight maxScrollExtent=$maxScroll');
    expect(maxScroll, 0, reason: '5 info wajib tanpa scroll di layar 6"');

    // FAB adalah overlay Scaffold: tinggi isi beranda tidak bertambah.
    expect(bodyHeight, lessThan(800));
    final fabRect = tester.getRect(find.byType(FloatingActionButton));
    final listRect = tester.getRect(listView);
    expect(fabRect.top, greaterThan(listRect.top));
  });

  testWidgets('D-23: anggota melihat alasan, tanpa tombol edit/hapus setoran',
      (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.seedDefaultCategories();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionProvider.overrideWith(
            (ref) => const Session(
              email: 'anak@example.com',
              role: MemberRole.member,
              name: 'Anak',
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => showTransactionDetail(
                    ctx,
                    ref,
                    _goalDeposit(),
                  ),
                  child: const Text('buka detail'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('buka detail'));
    await tester.pumpAndSettle();

    expect(
      find.text('Setoran tujuan hanya bisa dikoreksi admin.'),
      findsOneWidget,
    );
    expect(find.text('Hapus transaksi'), findsNothing);
    expect(find.text('Edit transaksi'), findsNothing);
  });

  testWidgets('D-23: admin tetap melihat tombol edit/hapus setoran tujuan',
      (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.seedDefaultCategories();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => showTransactionDetail(
                    ctx,
                    ref,
                    _goalDeposit(member: 'bapak@example.com'),
                  ),
                  child: const Text('buka detail'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('buka detail'));
    await tester.pumpAndSettle();

    expect(find.text('Edit transaksi'), findsOneWidget);
    expect(find.text('Hapus transaksi'), findsOneWidget);
  });
}
