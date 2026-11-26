import 'package:flutter/foundation.dart';

/// Konfigurasi F1. Semua nilai masuk lewat `--dart-define`, tidak ada
/// CLIENT_ID atau URL yang di-hardcode di kode.
///
/// Build produksi WAJIB punya `GOOGLE_CLIENT_ID` + `APPS_SCRIPT_URL`; tanpa
/// itu aplikasi menolak berjalan (bukan diam-diam memakai stub).
class AuthConfig {
  const AuthConfig({
    this.clientId = const String.fromEnvironment('GOOGLE_CLIENT_ID'),
    this.scriptUrl = const String.fromEnvironment('APPS_SCRIPT_URL'),
    this.stubFlag = const bool.fromEnvironment(
      'ALLOW_STUB_LOGIN',
      defaultValue: true,
    ),
    this.isDebugBuild = kDebugMode,
  });

  final String clientId;
  final String scriptUrl;

  /// Satu flag untuk mematikan stub: `--dart-define=ALLOW_STUB_LOGIN=false`.
  final bool stubFlag;
  final bool isDebugBuild;

  bool get hasClientId => clientId.trim().isNotEmpty;
  bool get hasServer => scriptUrl.trim().isNotEmpty;

  /// Stub hanya untuk build debug tanpa CLIENT_ID, dan bisa dimatikan flag.
  bool get stubVisible => isDebugBuild && stubFlag && !hasClientId;

  /// Jalur produksi: butuh CLIENT_ID dan URL Apps Script.
  bool get productionReady => hasClientId && hasServer;

  /// Build yang tidak boleh jalan sama sekali (rilis tanpa konfigurasi).
  bool get misconfigured => !isDebugBuild && !productionReady;
}
