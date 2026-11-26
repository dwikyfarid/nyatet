// ignore_for_file: library_private_types_in_public_api
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nyatet/auth/apps_script_api.dart';
import 'package:nyatet/auth/auth_config.dart';
import 'package:nyatet/auth/auth_flow.dart';
import 'package:nyatet/auth/auth_gateway.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/data/repository/draft_repository.dart';
import 'package:nyatet/data/repository/transaction_repository.dart';

class _FakeGateway implements AuthGateway {
  _FakeGateway({this.email = 'bapak@example.com'});
  final String email;
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  Future<GoogleIdentity> signIn() async {
    signInCalls++;
    return GoogleIdentity(idToken: 'token-1', email: email, name: 'Bapak');
  }

  @override
  Future<void> signOut() async => signOutCalls++;
}

class _FakeApi extends AppsScriptApi {
  _FakeApi()
      : super(baseUrl: 'https://script.example/exec');

  MeInfo meResult = const MeInfo(
    email: 'bapak@example.com',
    name: 'Bapak',
    role: 'admin',
    status: 'active',
    needsFamilySetup: true,
  );
  ApiException? meError;
  FamilyInfo familyResult = const FamilyInfo(
    id: 'sheet-1',
    name: 'Keluarga Contoh',
    url: 'https://docs.google.com/spreadsheets/d/sheet-1',
    created: true,
  );
  ApiException? pingError;
  int pingCalls = 0;
  int createCalls = 0;
  final List<String> familyNames = [];

  @override
  Future<void> ping() async {
    pingCalls++;
    if (pingError != null) throw pingError!;
  }

  @override
  Future<MeInfo> me(String idToken) async {
    if (meError != null) throw meError!;
    return meResult;
  }

  @override
  Future<FamilyInfo> createFamily(String idToken, {required String familyName}) async {
    createCalls++;
    familyNames.add(familyName);
    // Idempoten seperti server: panggilan kedua = buku yang sama, created:false.
    return FamilyInfo(
      id: familyResult.id,
      name: familyResult.name,
      url: familyResult.url,
      created: createCalls == 1,
    );
  }
}

AuthFlow buildFlow({
  required AuthConfig config,
  required _FakeApi api,
  _FakeGateway? gateway,
  Future<int> Function()? drafts,
}) =>
    AuthFlow(
      config: config,
      api: api,
      gateway: gateway ?? _FakeGateway(),
      stubGateway: const StubAuthGateway(),
      pendingDrafts: drafts ?? () async => 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const prod = AuthConfig(
    clientId: 'client-id.apps.googleusercontent.com',
    scriptUrl: 'https://script.example/exec',
    isDebugBuild: false,
  );
  const debugNoClient = AuthConfig(
    clientId: '',
    scriptUrl: '',
    isDebugBuild: true,
  );

  test('F1: build produksi tanpa CLIENT_ID menolak jalan, stub tidak ada', () async {
    const config = AuthConfig(
      clientId: '',
      scriptUrl: 'https://script.example/exec',
      isDebugBuild: false,
    );
    final flow = buildFlow(config: config, api: _FakeApi());

    await flow.start();
    expect(flow.stage, AuthStage.misconfigured);
    expect(flow.stubAvailable, isFalse);

    await flow.signInWithStub();
    expect(flow.stage, AuthStage.error);
    expect(flow.session, isNull);
  });

  test('F1: stub debug terlihat hanya tanpa CLIENT_ID dan bisa dimatikan flag', () {
    expect(debugNoClient.stubVisible, isTrue);
    const debugWithFlagOff = AuthConfig(
      clientId: '',
      scriptUrl: '',
      isDebugBuild: true,
      stubFlag: false,
    );
    expect(debugWithFlagOff.stubVisible, isFalse);
    expect(prod.stubVisible, isFalse);
  });

  test('F1: stub debug masuk sebagai admin uji dan ditandai stub', () async {
    final flow = buildFlow(config: debugNoClient, api: _FakeApi());
    await flow.start();
    expect(flow.stage, AuthStage.signedOut);

    await flow.signInWithStub();
    expect(flow.stage, AuthStage.ready);
    expect(flow.session!.isStub, isTrue);
    expect(flow.session!.role, 'admin');
  });

  test('F1: role datang dari server, bukan dari aplikasi', () async {
    final api = _FakeApi()
      ..meResult = const MeInfo(
        email: 'anak@example.com',
        name: 'Anak',
        role: 'member',
        status: 'active',
        needsFamilySetup: false,
        family: FamilyInfo(
          id: 'sheet-9',
          name: 'Keluarga Contoh',
          url: '',
          created: false,
        ),
      );
    final flow = buildFlow(config: prod, api: api);

    await flow.start();
    await flow.signInWithGoogle();

    expect(flow.stage, AuthStage.ready);
    expect(flow.session!.role, 'member');
    expect(flow.session!.familyId, 'sheet-9');
  });

  test('F1: createFamily idempoten — dua tekan tidak membuat buku kedua', () async {
    final api = _FakeApi();
    final flow = buildFlow(config: prod, api: api);

    await flow.start();
    await flow.signInWithGoogle();
    expect(flow.stage, AuthStage.needsFamilySetup);

    await flow.createFamily('Keluarga Contoh');
    final afterFirst = flow.session!.familyId;
    expect(flow.stage, AuthStage.ready);

    await flow.createFamily('Keluarga Contoh');
    expect(flow.session!.familyId, afterFirst);
    expect(api.createCalls, 2);
    expect(api.familyNames, ['Keluarga Contoh', 'Keluarga Contoh']);
  });

  test('F1/L1b: undangan tertunda dan akses dicabut punya layar berbeda', () async {
    final api = _FakeApi()
      ..meResult = const MeInfo(
        email: 'anak@example.com',
        name: 'Anak',
        role: 'member',
        status: 'invited',
        needsFamilySetup: false,
      );
    final flow = buildFlow(config: prod, api: api);
    await flow.start();
    await flow.signInWithGoogle();
    expect(flow.stage, AuthStage.invited);

    api.meError = ApiException(
      ApiErrorCode.forbidden,
      'Akses anggota ini sudah dicabut admin.',
    );
    await flow.retry();
    expect(flow.stage, AuthStage.forbidden);
    expect(flow.message, contains('dicabut'));
  });

  test('F1/L1c: UNAUTHENTICATED tidak menghapus draf yang belum tersinkron',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final drafts = DraftRepository(db, TransactionRepository(db));
    await drafts.seedDummyDrafts();
    final before = await drafts.listPending();
    expect(before.length, greaterThan(0));

    final api = _FakeApi()
      ..meError = ApiException(
        ApiErrorCode.unauthenticated,
        'Token tidak valid atau email Google belum diverifikasi',
      );
    final flow = buildFlow(
      config: prod,
      api: api,
      drafts: () async => (await drafts.listPending()).length,
    );

    await flow.start();
    await flow.signInWithGoogle();

    expect(flow.stage, AuthStage.expired);
    expect(flow.pendingDraftsCount, before.length);
    // Draf masih ada di database setelah sesi berakhir.
    expect(await drafts.listPending(), hasLength(before.length));
  });

  test('F1: NO_FAMILY menampilkan layar belum terhubung', () async {
    final api = _FakeApi()
      ..meError = ApiException(ApiErrorCode.noFamily, 'Belum punya buku');
    final flow = buildFlow(config: prod, api: api);
    await flow.start();
    await flow.signInWithGoogle();
    expect(flow.stage, AuthStage.noFamily);
  });

  group('AppsScriptApi F1', () {
    test('setup.createFamily mengirim familyName tanpa role/familyId', () async {
      Map<String, Object?>? sent;
      final api = AppsScriptApi(
        baseUrl: 'https://script.example/exec',
        client: MockClient((request) async {
          sent = Map<String, Object?>.from(jsonDecode(request.body) as Map);
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'family': {
                  'id': 'sheet-1',
                  'name': 'Keluarga Contoh',
                  'url': 'https://docs.google.com/spreadsheets/d/sheet-1',
                  'created': false,
                },
                'role': 'admin',
              },
            }),
            200,
          );
        }),
      );

      final family = await api.createFamily(
        'token-1',
        familyName: 'Keluarga Contoh',
      );

      expect(sent!['action'], 'setup.createFamily');
      expect(sent!['idToken'], 'token-1');
      final params = Map<String, Object?>.from(sent!['params']! as Map);
      expect(params['familyName'], 'Keluarga Contoh');
      expect(params.containsKey('role'), isFalse);
      expect(params.containsKey('familyId'), isFalse);
      expect(family.id, 'sheet-1');
      expect(family.created, isFalse, reason: 'idempoten: buku sudah ada');
    });

    test('UNAUTHENTICATED dipetakan menjadi ApiException', () async {
      final api = AppsScriptApi(
        baseUrl: 'https://script.example/exec',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'ok': false,
              'error': {
                'code': 'UNAUTHENTICATED',
                'message': 'Token tidak valid',
              },
            }),
            200,
          ),
        ),
      );

      expect(
        api.me('bad-token'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiErrorCode.unauthenticated)
              .having((e) => e.isUnauthenticated, 'isUnauthenticated', isTrue),
        ),
      );
    });
  });
}
