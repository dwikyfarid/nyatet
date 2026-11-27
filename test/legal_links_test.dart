// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nyatet/config/app_links.dart';
import 'package:nyatet/update/apk_bridge.dart';
import 'package:nyatet/update/github_api.dart';
import 'package:nyatet/ui/legal_links.dart';
import 'package:nyatet/ui/providers.dart';
import 'package:nyatet/ui/screens/settings_screen.dart';
import 'package:nyatet/update/update_models.dart';
import 'package:nyatet/update/update_service.dart';

class _Offline implements NetworkProbe {
  @override
  Future<bool> isOnline() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final installed = InstalledVersion(versionName: '0.1.0', versionCode: 2);

  UpdateService service(UpdateStore store) => UpdateService(
        api: GitHubUpdateApi(
          client: MockClient((_) async => http.Response('{}', 404)),
        ),
        bridge: _NoopBridge(),
        installedVersion: () async => installed,
        store: store,
        network: _Offline(),
      );

  test('P3: URL kosong → tautan nonaktif dengan alasan', () {
    final state = LegalLinkState.resolve('  ', live: true);
    expect(state.enabled, isFalse);
    expect(state.reason, contains('belum diisi'));
  });

  test('P3: URL bukan http/https → nonaktif', () {
    expect(LegalLinkState.resolve('/privasi', live: true).enabled, isFalse);
    expect(LegalLinkState.resolve('ftp://x/y', live: true).enabled, isFalse);
  });

  test('P3: LINKS_LIVE=true membuka browser lewat intent', () async {
    Uri? opened;
    final ok = await openLegalUrl(
      AppLinks.privacyPolicy,
      live: true,
      launcher: (uri) async {
        opened = uri;
        return true;
      },
    );
    expect(ok, isTrue);
    expect(opened, Uri.parse('https://nyatet.app/privasi'));
  });

  test('P3: LINKS_LIVE=false tidak memanggil launcher sama sekali', () async {
    var calls = 0;
    final ok = await openLegalUrl(
      AppLinks.privacyPolicy,
      live: false,
      launcher: (_) async {
        calls++;
        return true;
      },
    );
    expect(ok, isFalse);
    expect(calls, 0);
    expect(
      LegalLinkState.resolve(AppLinks.privacyPolicy, live: false).reason,
      contains('belum terbit'),
    );
  });

  testWidgets('P3: LINKS_LIVE=true → kedua tautan memanggil browser dengan URL-nya',
      (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateEnabledProvider.overrideWithValue(false),
          installedVersionProvider.overrideWith((ref) async => installed),
          updateServiceProvider.overrideWithValue(service(InMemoryUpdateStore())),
          linksLiveProvider.overrideWithValue(true),
          legalLauncherProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.open_in_new), findsNWidgets(2));

    await tester.tap(find.text('Kebijakan privasi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus data akun'));
    await tester.pumpAndSettle();

    expect(opened, [
      Uri.parse(AppLinks.privacyPolicy),
      Uri.parse(AppLinks.deleteData),
    ]);
    // Tidak pindah layar: browser yang dibuka, bukan halaman in-app.
    expect(find.text('Pengaturan'), findsOneWidget);
  });

  testWidgets('P3: LINKS_LIVE=false → pemberitahuan jujur, tanpa launcher',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateEnabledProvider.overrideWithValue(false),
          installedVersionProvider.overrideWith((ref) async => installed),
          updateServiceProvider.overrideWithValue(service(InMemoryUpdateStore())),
          linksLiveProvider.overrideWithValue(false),
          legalLauncherProvider.overrideWithValue((_) async {
            calls++;
            return true;
          }),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kebijakan privasi'));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.textContaining('Halaman belum terbit'), findsOneWidget);
  });

  testWidgets('P2: build play tidak pernah membangun layanan update', (tester) async {
    // Kalau ada kode build play yang membaca penyedia ini, uji gagal — itu
    // berarti permintaan ke api.github.com mungkin terjadi.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateEnabledProvider.overrideWithValue(false),
          installedVersionProvider
              .overrideWith((ref) async => installed),
          updateServiceProvider.overrideWith(
            (ref) => throw StateError(
              'Layanan update tidak boleh dibuat pada build play',
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cek update sekarang'), findsNothing);
    expect(find.textContaining('Terakhir dicek'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _NoopBridge implements ApkBridge {
  @override
  Future<ApkInspection> inspect(String path) async => const ApkInspection(
        packageName: '',
        installedPackageName: '',
        signatureSha256: '',
        installedSignatureSha256: '',
      );

  @override
  Future<bool> openInstaller(String path) async => false;
}
