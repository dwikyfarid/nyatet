import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nyatet/auth/account_deletion.dart';
import 'package:nyatet/auth/apps_script_api.dart';
import 'package:nyatet/ui/format.dart';
import 'package:nyatet/ui/screens/delete_account_flow.dart';

const _base = 'https://script.example/exec';

http.Response _ok(Map<String, Object?> data) =>
    http.Response(jsonEncode({'ok': true, 'data': data}), 200);

http.Response _err(String code, String message) => http.Response(
      jsonEncode({
        'ok': false,
        'error': {'code': code, 'message': message},
      }),
      200,
    );

AccountDeletionService _service({
  required MockClient client,
  String role = 'member',
  String familyName = 'Keluarga Contoh',
  void Function()? onSignOut,
}) =>
    AccountDeletionService(
      api: AppsScriptApi(baseUrl: _base, client: client),
      token: 'token-1',
      email: 'anak@example.com',
      role: role,
      familyName: familyName,
      signOut: () async => onSignOut?.call(),
    );

void main() {
  test('F12: account.delete sukses → sesi berakhir, pesan jujur', () async {
    var signedOut = false;
    String? action;
    final service = _service(
      client: MockClient((request) async {
        final body = Map<String, Object?>.from(jsonDecode(request.body) as Map);
        action = body['action'] as String?;
        return _ok({
          'deleted': true,
          'alreadyDeleted': false,
          'memberId': 'm-1',
          'transactionsAnonymized': true,
          'auditsScrubbed': true,
        });
      }),
      onSignOut: () => signedOut = true,
    );

    final outcome = await service.deleteAccount();

    expect(action, 'account.delete');
    expect(outcome.ok, isTrue);
    expect(outcome.message, contains('Anggota dihapus'));
    expect(signedOut, isTrue);
  });

  test('F12: alreadyDeleted:true dianggap sukses (idempoten)', () async {
    var signedOut = false;
    final service = _service(
      client: MockClient((_) async => _ok({
            'deleted': false,
            'alreadyDeleted': true,
          })),
      onSignOut: () => signedOut = true,
    );

    final outcome = await service.deleteAccount();
    expect(outcome.ok, isTrue);
    expect(outcome.alreadyDeleted, isTrue);
    expect(signedOut, isTrue);
  });

  test('F12: gagal jaringan/500 → tidak ada sukses, sesi tidak berakhir',
      () async {
    var signedOut = false;
    final service = _service(
      client: MockClient((_) async => _err('INTERNAL', 'Kesalahan server')),
      onSignOut: () => signedOut = true,
    );

    final outcome = await service.deleteAccount();
    expect(outcome.ok, isFalse);
    expect(outcome.message, contains('Tidak ada data yang dihapus'));
    expect(signedOut, isFalse);
  });

  test('F12: UNAUTHENTICATED → tidak menghapus apa pun, minta masuk lagi',
      () async {
    var signedOut = false;
    final service = _service(
      client: MockClient(
        (_) async => _err('UNAUTHENTICATED', 'Token tidak valid'),
      ),
      onSignOut: () => signedOut = true,
    );

    final outcome = await service.deleteAccount();
    expect(outcome.ok, isFalse);
    expect(outcome.message, contains('Sesi berakhir'));
    expect(signedOut, isFalse);
  });

  test('F12: family.delete mengirim confirmName persis', () async {
    Map<String, Object?>? params;
    var signedOut = false;
    final service = _service(
      role: 'admin',
      client: MockClient((request) async {
        final body = Map<String, Object?>.from(jsonDecode(request.body) as Map);
        params = Map<String, Object?>.from(body['params']! as Map);
        return _ok({
          'deleted': true,
          'alreadyDeleted': false,
          'familyId': 'sheet-1',
          'rowsRemoved': 129,
          'mappingsRemoved': 4,
          'fileTrashed': true,
          'receiptFolderTrashed': true,
        });
      }),
      onSignOut: () => signedOut = true,
    );

    final outcome = await service.deleteFamily('Keluarga Contoh');

    expect(params!['confirmName'], 'Keluarga Contoh');
    expect(outcome.ok, isTrue);
    expect(outcome.message, contains('129 baris'));
    expect(outcome.message, contains('foto nota ikut di-trash'));
    expect(signedOut, isTrue);
  });

  test('F12: nama keluarga salah → tidak ada panggilan jaringan', () async {
    var calls = 0;
    final service = _service(
      role: 'admin',
      client: MockClient((_) async {
        calls++;
        return _ok({'deleted': true});
      }),
    );

    final outcome = await service.deleteFamily('Salah');
    expect(outcome.ok, isFalse);
    expect(calls, 0);
  });

  test('F12: mode — anggota, admin dengan anggota lain, admin terakhir',
      () async {
    Future<DeletionPlan> planFor({
      required String role,
      required List<Map<String, Object?>> members,
    }) =>
        _service(
          role: role,
          client: MockClient((_) async => _ok({'members': members})),
        ).plan();

    // Anggota biasa tidak perlu melihat daftar anggota.
    expect((await planFor(role: 'member', members: const [])).mode,
        DeletionMode.member);

    final withOthers = await planFor(
      role: 'admin',
      members: [
        {'email': 'anak@example.com', 'role': 'admin', 'status': 'active'},
        {'email': 'ibu@example.com', 'role': 'member', 'status': 'active'},
      ],
    );
    expect(withOthers.mode, DeletionMode.adminWithOthers);
    expect(withOthers.message, contains('Masih ada anggota aktif lain'));

    final lastAdmin = await planFor(
      role: 'admin',
      members: [
        {'email': 'anak@example.com', 'role': 'admin', 'status': 'active'},
        {'email': 'ibu@example.com', 'role': 'member', 'status': 'removed'},
      ],
    );
    expect(lastAdmin.mode, DeletionMode.lastAdmin);
    expect(lastAdmin.familyName, 'Keluarga Contoh');
  });

  test('D-33: baris transaksi anggota terhapus tampil sebagai Anggota dihapus',
      () {
    expect(memberLabel('deleted:m-123'), 'Anggota dihapus');
    expect(memberLabel('bapak@example.com'), 'bapak@example.com');
    expect(memberLabel(''), 'Tanpa anggota');
  });

  test('F12: teks dialog menyebut 3 akibat dan label destruktif', () {
    expect(kMemberDeletionBulletTransactions, contains('Transaksi keluarga tetap ada'));
    expect(kMemberDeletionBulletTransactions, contains('Anggota dihapus'));
    expect(kMemberDeletionBulletIrreversible, contains('tidak bisa dipulihkan'));
    expect(kMemberDeletionBulletSession, contains('Sesi'));
    expect(kMemberDeletionButton, 'Hapus akun saya');
    expect(kLastAdminWarning, contains('7 tab'));
    expect(kLastAdminWarning, contains('tidak bisa dikembalikan'));
    expect(kLastAdminWarning, contains('Folder nota'));
  });

  test('D-46(c): receiptFolderTrashed=false tetap disebut jujur', () async {
    final service = AccountDeletionService(
      api: AppsScriptApi(
        baseUrl: _base,
        client: MockClient((_) async => _ok({
              'deleted': true,
              'alreadyDeleted': false,
              'rowsRemoved': 10,
              'fileTrashed': true,
              'receiptFolderTrashed': false,
            })),
      ),
      token: 't',
      email: 'anak@example.com',
      role: 'admin',
      familyName: 'Keluarga Contoh',
      signOut: () async {},
    );

    final outcome = await service.deleteFamily('Keluarga Contoh');
    expect(outcome.ok, isTrue);
    expect(outcome.message, contains('foto nota'));
    expect(outcome.message, contains('tidak ditemukan'));
    expect(outcome.message, isNot(contains('foto nota ikut di-trash')));
  });
}
