import 'package:google_sign_in/google_sign_in.dart';

/// Identitas hasil login Google (ID token, bukan access token).
class GoogleIdentity {
  const GoogleIdentity({
    required this.idToken,
    required this.email,
    this.name = '',
  });

  final String idToken;
  final String email;
  final String name;
}

abstract class AuthGateway {
  Future<GoogleIdentity> signIn();
  Future<void> signOut();
}

/// Stub khusus build debug tanpa CLIENT_ID. Tombolnya jelas ditandai
/// ("Masuk sebagai admin uji") dan bisa dimatikan lewat
/// `--dart-define=ALLOW_STUB_LOGIN=false`.
class StubAuthGateway implements AuthGateway {
  const StubAuthGateway();

  @override
  Future<GoogleIdentity> signIn() async => const GoogleIdentity(
        idToken: 'debug-stub-token',
        email: 'bapak@example.com',
        name: 'Admin uji',
      );

  @override
  Future<void> signOut() async {}
}

/// Login Google sungguhan. `clientId` wajib ada; tanpa itu tidak dipanggil.
class GoogleAuthGateway implements AuthGateway {
  GoogleAuthGateway({required this.clientId});

  final String clientId;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(clientId: clientId);
    _initialized = true;
  }

  @override
  Future<GoogleIdentity> signIn() async {
    await _ensureInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    final token = account.authentication.idToken;
    if (token == null || token.isEmpty) {
      throw StateError('ID token tidak diterima dari Google');
    }
    return GoogleIdentity(
      idToken: token,
      email: account.email,
      name: account.displayName ?? '',
    );
  }

  @override
  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
  }
}
