import 'package:flutter/foundation.dart';

import 'apps_script_api.dart';
import 'auth_config.dart';
import 'auth_gateway.dart';

/// Layar F1 yang harus ditampilkan (lihat UI-SPEC L1/L1a/L1b/L1c).
enum AuthStage {
  booting,
  signedOut,
  working,
  needsFamilySetup,
  invited,
  forbidden,
  noFamily,
  expired,
  ready,
  misconfigured,
  error,
}

class AuthSession {
  const AuthSession({
    required this.token,
    required this.email,
    required this.name,
    required this.role,
    this.familyId,
    this.familyName,
    this.familyUrl,
    this.isStub = false,
  });

  final String token;
  final String email;
  final String name;

  /// Dibaca dari server/Sheet (D-22). Pada stub debug nilainya 'admin' dan
  /// [isStub] true supaya tidak pernah disangka sesi produksi.
  final String role;
  final String? familyId;
  final String? familyName;
  final String? familyUrl;
  final bool isStub;

  AuthSession copyWith({
    String? name,
    String? familyId,
    String? familyName,
    String? familyUrl,
  }) =>
      AuthSession(
        token: token,
        email: email,
        name: name ?? this.name,
        role: role,
        familyId: familyId ?? this.familyId,
        familyName: familyName ?? this.familyName,
        familyUrl: familyUrl ?? this.familyUrl,
        isStub: isStub,
      );
}

/// Mesin status F1. Tidak menyentuh database sama sekali: sesi kedaluwarsa
/// tidak boleh menghapus draf yang belum tersinkron (L1c).
class AuthFlow extends ChangeNotifier {
  AuthFlow({
    required this.config,
    required this.api,
    required this.gateway,
    required this.stubGateway,
    required this.pendingDrafts,
  });

  final AuthConfig config;
  final AppsScriptApi api;
  final AuthGateway gateway;
  final AuthGateway stubGateway;

  /// Jumlah draf menunggu sinkron, untuk kartu di L1c.
  final Future<int> Function() pendingDrafts;

  AuthStage _stage = AuthStage.booting;
  AuthSession? _session;
  String? _message;
  int _drafts = 0;
  ApiException? _lastError;

  AuthStage get stage => _stage;
  AuthSession? get session => _session;
  String? get message => _message;
  int get pendingDraftsCount => _drafts;
  ApiException? get lastError => _lastError;

  bool get stubAvailable => config.stubVisible;

  void _set(AuthStage stage, {String? message, ApiException? error}) {
    _stage = stage;
    _message = message;
    if (error != null) _lastError = error;
    notifyListeners();
  }

  Future<void> start() async {
    if (config.misconfigured) {
      _set(
        AuthStage.misconfigured,
        message: 'Login belum dikonfigurasi: CLIENT_ID dan URL server belum '
            'diisi pada build ini.',
      );
      return;
    }
    if (!config.hasServer) {
      // Build debug tanpa server: boleh masuk lewat stub, tetapi tidak ada
      // klaim bahwa sesi ini produksi.
      _set(AuthStage.signedOut);
      return;
    }
    try {
      await api.ping();
      _set(AuthStage.signedOut);
    } on ApiException catch (e) {
      // Offline tidak mengunci aplikasi; login akan mencoba lagi.
      _set(AuthStage.signedOut, message: e.message, error: e);
    }
  }

  Future<void> signInWithGoogle() async {
    if (!config.productionReady) {
      _set(
        AuthStage.error,
        message: config.stubVisible
            ? 'CLIENT_ID belum ada. Pakai "Masuk sebagai admin uji" untuk '
                'mencoba, atau isi GOOGLE_CLIENT_ID pada build.'
            : 'Login Google belum dikonfigurasi pada build ini.',
      );
      return;
    }
    _set(AuthStage.working);
    try {
      final identity = await gateway.signIn();
      _session = AuthSession(
        token: identity.idToken,
        email: identity.email,
        name: identity.name,
        role: '',
      );
      await _loadMe();
    } catch (e) {
      _set(AuthStage.error, message: 'Login gagal: $e');
    }
  }

  /// Hanya untuk build debug tanpa CLIENT_ID.
  Future<void> signInWithStub() async {
    if (!stubAvailable) {
      _set(AuthStage.error, message: 'Login uji tidak tersedia pada build ini.');
      return;
    }
    final identity = await stubGateway.signIn();
    _session = AuthSession(
      token: identity.idToken,
      email: identity.email,
      name: identity.name,
      role: 'admin',
      isStub: true,
      familyName: 'Mode lokal (uji)',
    );
    _set(AuthStage.ready);
  }

  Future<void> _loadMe() async {
    final session = _session;
    if (session == null) return;
    try {
      final me = await api.me(session.token);
      _session = AuthSession(
        token: session.token,
        email: me.email.isEmpty ? session.email : me.email,
        name: me.name.isEmpty ? session.name : me.name,
        role: me.role,
        familyId: me.family?.id,
        familyName: me.family?.name,
        familyUrl: me.family?.url,
        isStub: false,
      );
      if (me.needsFamilySetup) {
        _set(AuthStage.needsFamilySetup);
        return;
      }
      if (me.status == 'invited') {
        _set(AuthStage.invited);
        return;
      }
      if (me.family == null) {
        _set(AuthStage.noFamily);
        return;
      }
      _set(AuthStage.ready);
    } on ApiException catch (e) {
      switch (e.code) {
        case ApiErrorCode.unauthenticated:
          await sessionExpired(error: e);
        case ApiErrorCode.noFamily:
          _set(AuthStage.noFamily, message: e.message);
        case ApiErrorCode.forbidden:
          _set(AuthStage.forbidden, message: e.message, error: e);
        default:
          _set(AuthStage.error, message: e.message, error: e);
      }
    }
  }

  /// Sesi kedaluwarsa: draf tetap di HP, user hanya perlu login ulang.
  Future<void> sessionExpired({ApiException? error}) async {
    _drafts = await pendingDrafts();
    _session = null;
    _set(
      AuthStage.expired,
      message: error?.message ??
          'Token tidak valid atau email Google belum diverifikasi',
      error: error,
    );
  }

  Future<void> retry() async {
    if (_session != null && _stage != AuthStage.expired) {
      await _loadMe();
      return;
    }
    if (config.stubVisible && !config.hasServer) {
      _set(AuthStage.signedOut);
      return;
    }
    await signInWithGoogle();
  }

  /// Idempoten: memanggil dua kali / membuka ulang layar tidak membuat buku
  /// kedua — server mengembalikan `created:false` untuk buku yang sama.
  Future<void> createFamily(String familyName) async {
    final session = _session;
    if (session == null || session.isStub) {
      _set(AuthStage.error, message: 'Masuk dulu sebelum membuat buku keluarga.');
      return;
    }
    final name = familyName.trim();
    if (name.length < 2 || name.length > 40) {
      _set(AuthStage.needsFamilySetup, message: 'Nama keluarga 2–40 karakter.');
      return;
    }
    _set(AuthStage.working);
    try {
      final family = await api.createFamily(
        session.token,
        familyName: name,
      );
      _session = session.copyWith(
        familyId: family.id,
        familyName: family.name,
        familyUrl: family.url,
      );
      _set(AuthStage.ready);
    } on ApiException catch (e) {
      if (e.code == ApiErrorCode.unauthenticated) {
        await sessionExpired(error: e);
      } else {
        _set(AuthStage.needsFamilySetup, message: e.message, error: e);
      }
    }
  }

  Future<void> signOut() async {
    try {
      if (!(_session?.isStub ?? false)) await gateway.signOut();
    } catch (_) {
      // Keluar tetap jalan walau gateway gagal.
    }
    _session = null;
    _set(AuthStage.signedOut);
  }
}
