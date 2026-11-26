import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nyatet/update/apk_bridge.dart';
import 'package:nyatet/update/github_api.dart';
import 'package:nyatet/update/update_models.dart';
import 'package:nyatet/update/update_service.dart';

class _FakeNetwork implements NetworkProbe {
  _FakeNetwork(this.online);
  bool online;

  @override
  Future<bool> isOnline() async => online;
}

class _FakeBridge implements ApkBridge {
  _FakeBridge({
    this.packageName = kAppPackageName,
    this.signature = 'abc',
    this.installedSignature = 'abc',
  });

  final String packageName;
  final String signature;
  final String installedSignature;
  final List<String> installedPaths = [];

  @override
  Future<ApkInspection> inspect(String path) async => ApkInspection(
        packageName: packageName,
        installedPackageName: kAppPackageName,
        signatureSha256: signature,
        installedSignatureSha256: installedSignature,
      );

  @override
  Future<bool> openInstaller(String path) async {
    installedPaths.add(path);
    return true;
  }
}

Map<String, Object?> _releaseJson({
  String tag = 'v0.2.0+2',
  int size = 8,
  String assetName = 'nyatet-v0.2.0.apk',
  String body = 'Perbaikan bug\nLaporan bulanan baru\nCatatan ketiga\nBaris keempat',
}) =>
    {
      'tag_name': tag,
      'name': 'Nyatet $tag',
      'body': body,
      'assets': [
        {
          'name': 'nyatet-v0.2.0.apk.sha256',
          'size': 64,
          'browser_download_url':
              'https://github.com/dwikyfarid/nyatet/releases/download/$tag/sha',
        },
        {
          'name': assetName,
          'size': size,
          'browser_download_url':
              'https://github.com/dwikyfarid/nyatet/releases/download/$tag/$assetName',
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const installed = InstalledVersion(versionName: '0.1.0', versionCode: 1);
  late InMemoryUpdateStore store;
  late _FakeNetwork network;
  late _FakeBridge bridge;
  late Directory tempDir;

  setUp(() async {
    store = InMemoryUpdateStore();
    network = _FakeNetwork(true);
    bridge = _FakeBridge();
    tempDir = await Directory.systemTemp.createTemp('nyatet_update_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  UpdateService serviceWith(
    http.Client client, {
    DateTime Function()? now,
  }) =>
      UpdateService(
        api: GitHubUpdateApi(client: client, timeout: const Duration(seconds: 2)),
        bridge: bridge,
        installedVersion: () async => installed,
        store: store,
        network: network,
        client: client,
        now: now,
        cacheDir: () async => tempDir,
      );

  MockClient releaseClient({Map<String, Object?>? json, int status = 200}) =>
      MockClient((request) async {
        if (request.url.host != 'api.github.com') {
          // Unduhan aset (8 byte).
          return http.Response.bytes(List.filled(8, 7), 200);
        }
        return http.Response(
          jsonEncode(json ?? _releaseJson()),
          status,
          headers: {'content-type': 'application/json'},
        );
      });

  test('parseReleaseJson: aset APK, ukuran, ≤3 baris catatan, versi', () {
    final release = parseReleaseJson(_releaseJson())!;
    expect(release.assetName, 'nyatet-v0.2.0.apk');
    expect(release.sizeBytes, 8);
    expect(release.versionName, '0.2.0');
    expect(release.versionCode, 2);
    expect(release.notes, hasLength(3));
    expect(release.downloadUrl.isScheme('https'), isTrue);
  });

  test('parseReleaseJson: tanpa aset APK → null, bukan memasang aset lain', () {
    final json = _releaseJson();
    json['assets'] = [
      {'name': 'catatan.txt', 'size': 1, 'browser_download_url': 'https://x/y'},
    ];
    expect(parseReleaseJson(json), isNull);
  });

  test('perbandingan: versionCode diutamakan, versionName sebagai cadangan', () {
    final r = parseReleaseJson(_releaseJson())!;
    expect(r.isNewerThan(installed), isTrue);
    expect(r.isNewerThan(const InstalledVersion(versionName: '0.2.0', versionCode: 2)),
        isFalse);

    final tanpaCode = parseReleaseJson(_releaseJson(tag: 'v1.10.0'))!;
    expect(tanpaCode.versionCode, isNull);
    expect(
      tanpaCode.isNewerThan(const InstalledVersion(versionName: '1.9.2', versionCode: 99)),
      isTrue,
    );
    expect(compareVersionNames('1.10.0', '1.9.2'), greaterThan(0));
    expect(compareVersionNames('0.1.0', '0.1'), 0);
  });

  test('check: ada versi baru → available + waktu cek disimpan', () async {
    final service = serviceWith(releaseClient());
    final at = DateTime(2026, 11, 26, 10);
    final service2 = serviceWith(releaseClient(), now: () => at);

    final result = await service2.check();
    expect(result.status, UpdateStatus.available);
    expect(result.release!.versionName, '0.2.0');
    expect(await store.lastCheckedAt(), at);
    // service hanya dipakai untuk memastikan tidak error saat dibuang
    expect(service, isNotNull);
  });

  test('cek otomatis maksimal 1×/24 jam', () async {
    store.lastCheck = DateTime(2026, 11, 26, 8);
    final now = DateTime(2026, 11, 27, 6); // 22 jam
    final service = serviceWith(releaseClient(), now: () => now);
    expect(await service.shouldAutoCheck(), isFalse);
    expect(await service.autoCheckIfDue(), isNull);

    store.lastCheck = DateTime(2026, 11, 25, 8); // 46 jam
    expect(await service.shouldAutoCheck(), isTrue);
    final result = await service.autoCheckIfDue();
    expect(result, isNotNull);
  });

  test('Nanti: tidak menanyakan versi yang sama selama 24 jam', () async {
    final now = DateTime(2026, 11, 26, 10);
    final service = serviceWith(releaseClient(), now: () => now);

    final first = await service.check();
    expect(first.status, UpdateStatus.available);

    await service.snooze();
    final second = await service.check();
    expect(second.status, UpdateStatus.upToDate);
    expect(second.hasUpdate, isFalse);
  });

  test('offline: "Tidak bisa cek update", tanpa permintaan jaringan', () async {
    network.online = false;
    var calls = 0;
    final service = serviceWith(MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    }));

    final result = await service.check();
    expect(result.status, UpdateStatus.offline);
    expect(result.message, contains('Tidak bisa cek update'));
    expect(calls, 0);
  });

  test('rate limit GitHub (403) → gagal dengan pesan, tidak crash', () async {
    final service = serviceWith(
      MockClient((_) async => http.Response('{"message":"rate limit"}', 403)),
    );
    final result = await service.check();
    expect(result.status, UpdateStatus.failed);
    expect(result.message, contains('Tidak bisa cek update'));
  });

  test('verifikasi: ukuran beda → tolak + berkas dihapus', () async {
    final json = _releaseJson(size: 999);
    final service = serviceWith(releaseClient(json: json));
    final release = parseReleaseJson(json)!;

    final result = await service.downloadAndInstall(release);

    expect(result.ok, isFalse);
    expect(result.message, contains('APK tidak cocok'));
    expect(bridge.installedPaths, isEmpty);
    expect(await File('${tempDir.path}/${release.assetName}').exists(), isFalse);
  });

  test('verifikasi: sertifikat beda → tolak "APK tidak cocok" + hapus', () async {
    bridge = _FakeBridge(signature: 'beda', installedSignature: 'asli');
    final service = serviceWith(releaseClient());
    final release = parseReleaseJson(_releaseJson())!;

    final result = await service.downloadAndInstall(release);

    expect(result.ok, isFalse);
    expect(result.message, 'APK tidak cocok dengan aplikasi ini');
    expect(bridge.installedPaths, isEmpty);
    expect(await File('${tempDir.path}/${release.assetName}').exists(), isFalse);
  });

  test('verifikasi: nama paket lain → tolak', () async {
    bridge = _FakeBridge(packageName: 'com.penipu.app');
    final service = serviceWith(releaseClient());
    final release = parseReleaseJson(_releaseJson())!;

    final result = await service.downloadAndInstall(release);

    expect(result.ok, isFalse);
    expect(result.message, 'APK tidak cocok dengan aplikasi ini');
    expect(bridge.installedPaths, isEmpty);
  });

  test('APK lolos verifikasi → intent pemasangan dibuka', () async {
    final service = serviceWith(releaseClient());
    final release = parseReleaseJson(_releaseJson())!;

    final result = await service.downloadAndInstall(release);

    expect(result.ok, isTrue);
    expect(bridge.installedPaths, hasLength(1));
    expect(await File(bridge.installedPaths.single).exists(), isTrue);
  });
}
