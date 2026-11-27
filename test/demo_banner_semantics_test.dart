// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/home_shell.dart';
import 'package:nyatet/ui/providers.dart';

/// F13: penanda "data demo" wajib terbaca pembaca layar, bukan hanya terlihat.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('banner demo punya label Semantics yang menyebut data tidak sinkron',
      (tester) async {
    final handle = tester.ensureSemantics();

    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.seedDefaultCategories();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          webDemoProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SafeArea(child: HomeShell())),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    while (tester.takeException() != null) {}

    expect(find.bySemanticsLabel(RegExp('Mode demo')), findsAtLeastNWidgets(1));
    expect(
      find.bySemanticsLabel(RegExp('tidak tersinkron')),
      findsAtLeastNWidgets(1),
      reason: 'label harus menyebut data tidak tersinkron, bukan label kosong',
    );
    // Tetap terlihat sebagai teks, bukan hanya label aksesibilitas.
    expect(find.textContaining('Mode demo'), findsWidgets);
    handle.dispose();
  });
}
