// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/auth/auth_config.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/home_shell.dart';
import 'package:nyatet/ui/auth_gate.dart';
import 'package:nyatet/ui/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('F1: build debug tanpa CLIENT_ID menampilkan tombol uji dan bisa masuk',
      (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.seedDefaultCategories();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          authConfigProvider.overrideWithValue(
            const AuthConfig(clientId: '', scriptUrl: '', isDebugBuild: true),
          ),
        ],
        child: const MaterialApp(
          home: AuthGate(child: Scaffold(body: HomeShell())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Masuk dengan Google'), findsOneWidget);
    expect(find.text('Masuk sebagai admin uji'), findsOneWidget);
    expect(
      find.textContaining('tidak memakai server'),
      findsOneWidget,
      reason: 'stub harus jelas ditandai, bukan disangka produksi',
    );

    await tester.tap(find.text('Masuk sebagai admin uji'));
    await tester.pumpAndSettle();

    // Setelah sesi uji siap, aplikasi masuk ke beranda.
    expect(find.text('Nyatet'), findsOneWidget);
    expect(find.text('Catat'), findsOneWidget);
  });

  testWidgets('F1: build produksi tanpa CLIENT_ID terkunci dan tanpa tombol uji',
      (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          authConfigProvider.overrideWithValue(
            const AuthConfig(
              clientId: '',
              scriptUrl: 'https://script.example/exec',
              isDebugBuild: false,
            ),
          ),
        ],
        child: const MaterialApp(home: AuthGate(child: Text('beranda'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Login belum dikonfigurasi'), findsOneWidget);
    expect(find.text('Masuk sebagai admin uji'), findsNothing);
    expect(find.text('beranda'), findsNothing);
  });
}
