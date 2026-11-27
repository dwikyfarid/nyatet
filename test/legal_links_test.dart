// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nyatet/config/app_links.dart';
import 'package:nyatet/ui/legal_links.dart';
import 'package:nyatet/ui/providers.dart';
import 'package:nyatet/ui/screens/settings_screen.dart';
import 'package:nyatet/update/apk_bridge.dart';
import 'package:nyatet/update/github_api.dart';
import 'package:nyatet/update/update_models.dart';
import 'package:nyatet/update/update_service.dart';

class _Offline implements NetworkProbe {
  @override
  Future<bool> isOnline() async => false;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final installed = InstalledVersion(versionName: '0.1.0', versionCode: 2);

  UpdateService service() => UpdateService(
        api: GitHubUpdateApi(
          client: MockClient((_) async => http.Response('{}', 404)),
        ),
        bridge: _NoopBridge(),
        installedVersion: () async => installed,
        store: InMemoryUpdateStore(),
        network: _Offline(),
      );

  test('D-45: URL kosong → disabled dengan alasan "Halaman belum terbit"', () {
    final state = LegalLinkState.resolve('');
    expect(state.action, LegalLinkAction.disabled);
    expect(state.enabled, isFalse);
    expect(state.reason, 'Halaman belum terbit');
  });

  test('D-45: URL bukan http/https → disabled', () {
    expect(LegalLinkState.resolve('/privasi').action, LegalLinkAction.disabled);
    expect(LegalLinkState.resolve('ftp://x/y').action, LegalLinkAction.disabled);
  });

  test('D-45: URL terisi → openBrowser dan launcher dipanggil dengan URI itu',
      () async {
    const url = 'https://nyatet.app/privasi';
    expect(LegalLinkState.resolve(url).action, LegalLinkAction.openBrowser);

    Uri? opened;
    final ok = await openLegalUrl(
      url,
      launcher: (uri) async {
        opened = uri;
        return true;
      },
    );
    expect(ok, isTrue);
    expect(opened, Uri.parse(url));
  });

  test('D-45: tautan nonaktif tidak memanggil launcher', () async {
    var calls = 0;
    final ok = await openLegalUrl(
      '',
      launcher: (_) async {
        calls++;
        return true;
      },
    );
    expect(ok, isFalse);
    expect(calls, 0);
  });

  testWidgets('D-45: Pengaturan menampilkan baris nonaktif saat URL kosong',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateEnabledProvider.overrideWithValue(false),
          installedVersionProvider.overrideWith((ref) async => installed),
          updateServiceProvider.overrideWithValue(service()),
          legalLauncherProvider.overrideWithValue((_) async {
            calls++;
            return true;
          }),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // AppLinks.* kosong sampai halaman terbit.
    expect(AppLinks.privacyPolicy, isEmpty);
    expect(find.text('Kebijakan privasi'), findsOneWidget);
    expect(find.text('Hapus data akun'), findsOneWidget);
    expect(find.text('Halaman belum terbit'), findsNWidgets(2));
    expect(find.byIcon(Icons.open_in_new), findsNothing);

    await tester.tap(find.text('Kebijakan privasi'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(calls, 0, reason: 'baris nonaktif tidak memanggil browser');
  });

  testWidgets('P2: build play tidak pernah membangun layanan update',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateEnabledProvider.overrideWithValue(false),
          installedVersionProvider.overrideWith((ref) async => installed),
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
