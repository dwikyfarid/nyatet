import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apk_bridge.dart';
import 'github_api.dart';
import 'update_models.dart';

const String kAppPackageName = 'com.nyatet.nyatet';

enum UpdateStatus { available, upToDate, offline, failed }

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    required this.checkedAt,
    this.release,
    this.message,
  });

  final UpdateStatus status;
  final DateTime checkedAt;
  final ReleaseInfo? release;
  final String? message;

  bool get hasUpdate => status == UpdateStatus.available && release != null;
}

class InstallResult {
  const InstallResult({required this.ok, required this.message});
  final bool ok;
  final String message;
}

/// Penyimpanan kecil untuk jadwal cek otomatis & "Nanti" (24 jam).
abstract class UpdateStore {
  Future<DateTime?> lastCheckedAt();
  Future<void> setLastCheckedAt(DateTime value);
  Future<DateTime?> snoozeUntil();
  Future<void> setSnoozeUntil(DateTime value);
}

class PrefsUpdateStore implements UpdateStore {
  static const _kLastCheck = 'update_last_check_at';
  static const _kSnooze = 'update_snooze_until';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<DateTime?> lastCheckedAt() async {
    final raw = (await _prefs).getString(_kLastCheck);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  @override
  Future<void> setLastCheckedAt(DateTime value) async {
    await (await _prefs).setString(_kLastCheck, value.toIso8601String());
  }

  @override
  Future<DateTime?> snoozeUntil() async {
    final raw = (await _prefs).getString(_kSnooze);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  @override
  Future<void> setSnoozeUntil(DateTime value) async {
    await (await _prefs).setString(_kSnooze, value.toIso8601String());
  }
}

class InMemoryUpdateStore implements UpdateStore {
  DateTime? lastCheck;
  DateTime? snooze;

  @override
  Future<DateTime?> lastCheckedAt() async => lastCheck;

  @override
  Future<void> setLastCheckedAt(DateTime value) async => lastCheck = value;

  @override
  Future<DateTime?> snoozeUntil() async => snooze;

  @override
  Future<void> setSnoozeUntil(DateTime value) async => snooze = value;
}

/// Cek konektivitas supaya cek otomatis tidak pernah jalan saat offline.
abstract class NetworkProbe {
  Future<bool> isOnline();
}

class ConnectivityProbe implements NetworkProbe {
  const ConnectivityProbe();

  @override
  Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result.any((r) => r != ConnectivityResult.none);
  }
}

class UpdateService {
  UpdateService({
    required this.api,
    required this.bridge,
    required this.installedVersion,
    required this.store,
    required this.network,
    http.Client? client,
    DateTime Function()? now,
    Future<Directory> Function()? cacheDir,
  })  : _client = client ?? http.Client(),
        _now = now ?? DateTime.now,
        _cacheDir = cacheDir ?? getTemporaryDirectory;

  final GitHubUpdateApi api;
  final ApkBridge bridge;
  final Future<InstalledVersion> Function() installedVersion;
  final UpdateStore store;
  final NetworkProbe network;
  final http.Client _client;
  final DateTime Function() _now;
  final Future<Directory> Function() _cacheDir;

  /// Cek otomatis maksimal 1×/24 jam (REL-03).
  static const Duration checkInterval = Duration(hours: 24);

  Future<UpdateCheckResult> check() async {
    final at = _now();
    if (!await network.isOnline()) {
      return UpdateCheckResult(
        status: UpdateStatus.offline,
        checkedAt: at,
        message: 'Tidak bisa cek update — sedang offline',
      );
    }
    try {
      final release = await api.latest();
      await store.setLastCheckedAt(at);
      if (release == null) {
        return UpdateCheckResult(status: UpdateStatus.upToDate, checkedAt: at);
      }
      final installed = await installedVersion();
      if (release.isNewerThan(installed)) {
        // Versi baru tidak menanyakan lagi selama user memilih "Nanti".
        if (await isSnoozed()) {
          return UpdateCheckResult(
            status: UpdateStatus.upToDate,
            checkedAt: at,
            release: release,
          );
        }
        return UpdateCheckResult(
          status: UpdateStatus.available,
          checkedAt: at,
          release: release,
        );
      }
      return UpdateCheckResult(status: UpdateStatus.upToDate, checkedAt: at);
    } on UpdateCheckException catch (e) {
      return UpdateCheckResult(
        status: UpdateStatus.failed,
        checkedAt: at,
        message: e.message,
      );
    } catch (_) {
      return UpdateCheckResult(
        status: UpdateStatus.failed,
        checkedAt: at,
        message: 'Tidak bisa cek update',
      );
    }
  }

  /// Dipanggil saat aplikasi dibuka: tidak memblokir UI, tidak saat offline,
  /// maksimal sekali per 24 jam.
  Future<UpdateCheckResult?> autoCheckIfDue() async {
    if (!await shouldAutoCheck()) return null;
    return check();
  }

  Future<bool> shouldAutoCheck() async {
    final last = await store.lastCheckedAt();
    if (last == null) return true;
    return _now().difference(last) >= checkInterval;
  }

  Future<bool> isSnoozed() async {
    final until = await store.snoozeUntil();
    return until != null && until.isAfter(_now());
  }

  /// Tombol "Nanti": jangan tanya lagi sampai 24 jam berikutnya.
  Future<void> snooze() async {
    await store.setSnoozeUntil(_now().add(checkInterval));
  }

  Future<DateTime?> lastCheckedAt() => store.lastCheckedAt();

  /// Unduh → verifikasi (ukuran, nama paket, sertifikat) → buka pemasangan.
  /// Berkas yang gagal verifikasi selalu dihapus.
  Future<InstallResult> downloadAndInstall(ReleaseInfo release) async {
    File? file;
    try {
      final dir = await _cacheDir();
      file = File('${dir.path}/${release.assetName}');
      final downloaded = await _download(release.downloadUrl, file);
      if (!downloaded) {
        await _delete(file);
        return const InstallResult(
          ok: false,
          message: 'Unduhan gagal — coba lagi',
        );
      }

      final length = await file.length();
      if (release.sizeBytes > 0 && length != release.sizeBytes) {
        await _delete(file);
        return const InstallResult(
          ok: false,
          message: 'APK tidak cocok dengan aplikasi ini',
        );
      }

      final inspection = await bridge.inspect(file.path);
      if (inspection.packageName != kAppPackageName ||
          !inspection.packageMatches ||
          !inspection.signatureMatches) {
        await _delete(file);
        return const InstallResult(
          ok: false,
          message: 'APK tidak cocok dengan aplikasi ini',
        );
      }

      final opened = await bridge.openInstaller(file.path);
      if (!opened) {
        return const InstallResult(
          ok: false,
          message: 'Layar pemasangan tidak bisa dibuka',
        );
      }
      return const InstallResult(
        ok: true,
        message: 'Ikuti panduan di layar pemasangan Android',
      );
    } catch (_) {
      if (file != null) await _delete(file);
      return const InstallResult(
        ok: false,
        message: 'Unduhan gagal — coba lagi',
      );
    }
  }

  Future<bool> _download(Uri url, File target) async {
    final request = http.Request('GET', url);
    final response =
        await _client.send(request).timeout(const Duration(minutes: 5));
    if (response.statusCode != 200) return false;
    final sink = target.openWrite();
    try {
      await response.stream.pipe(sink);
    } finally {
      await sink.close();
    }
    return true;
  }

  Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Berkas cache yang tidak bisa dihapus tidak boleh membuat app crash.
    }
  }
}
