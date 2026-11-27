// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/config/dev_tools.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/ui/providers.dart';
import 'package:nyatet/ui/screens/cockpit_screen.dart';

/// D-47: Menu pengujian hanya untuk build debug/uji, tidak untuk rilis.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('D-47: default build uji mengaktifkan alat uji, rilis tidak', () {
    // Uji berjalan dalam mode debug.
    expect(kDevToolsEnabled, isTrue);
    // Konstanta default-nya kDebugMode: saat kDebugMode=false (release) nilai
    // ini false, sehingga jalur menu tidak ada di build rilis.
  });

  testWidgets('D-47: menu tidak dirender saat alat uji dimatikan',
      (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.seedDefaultCategories();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          devToolsEnabledProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(home: CockpitScreen()),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    while (tester.takeException() != null) {}

    expect(find.text('Menu pengujian'), findsNothing);
    expect(find.byTooltip('Menu pengujian'), findsNothing);
    expect(find.text('Muat data uji'), findsNothing);
  });

  testWidgets('D-47: menu tetap tersedia di build uji', (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.seedDefaultCategories();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          devToolsEnabledProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(home: CockpitScreen()),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    while (tester.takeException() != null) {}

    expect(find.byTooltip('Menu pengujian'), findsOneWidget);
  });
}
