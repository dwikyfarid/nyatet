// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final installed = InstalledVersion(versionName: '0.1.0', versionCode: 1);

  Widget app({required bool updateEnabled, required UpdateService service}) {
    return ProviderScope(
      overrides: [
        updateEnabledProvider.overrideWithValue(updateEnabled),
        installedVersionProvider.overrideWith((ref) async => installed),
        updateServiceProvider.overrideWithValue(service),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    );
  }

  UpdateService service(UpdateStore store) => UpdateService(
        api: GitHubUpdateApi(
          client: MockClient((_) async => http.Response('{}', 404)),
        ),
        bridge: _NoopBridge(),
        installedVersion: () async => installed,
        store: store,
        network: _Offline(),
      );

  testWidgets('REL-04: build play tidak punya baris "Cek update sekarang"',
      (tester) async {
    await tester.pumpWidget(
      app(updateEnabled: false, service: service(InMemoryUpdateStore())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pengaturan'), findsOneWidget);
    expect(find.text('Versi aplikasi'), findsOneWidget);
    expect(find.text('0.1.0 (1)'), findsOneWidget);
    expect(find.text('Cek update sekarang'), findsNothing);
    expect(find.textContaining('Terakhir dicek'), findsNothing);
  });

  testWidgets('REL-03: build sideload menampilkan versi, tombol, dan waktu cek',
      (tester) async {
    final store = InMemoryUpdateStore()
      ..lastCheck = DateTime.now()
      ..snooze = null;
    await tester.pumpWidget(
      app(updateEnabled: true, service: service(store)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cek update sekarang'), findsOneWidget);
    expect(find.textContaining('Terakhir dicek'), findsOneWidget);
    expect(find.text('0.1.0 (1)'), findsOneWidget);
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
