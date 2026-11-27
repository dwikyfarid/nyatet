import 'dart:convert';

import 'package:http/http.dart' as http;

/// Kode error server (docs/API.md). `UNAUTHENTICATED` wajib login ulang.
abstract final class ApiErrorCode {
  static const unauthenticated = 'UNAUTHENTICATED';
  static const noFamily = 'NO_FAMILY';
  static const forbidden = 'FORBIDDEN';
  static const validation = 'VALIDATION';
  static const internal = 'INTERNAL';
  static const unknownAction = 'UNKNOWN_ACTION';
}

class ApiException implements Exception {
  ApiException(this.code, this.message);
  final String code;
  final String message;

  bool get isUnauthenticated => code == ApiErrorCode.unauthenticated;
  bool get isNoFamily => code == ApiErrorCode.noFamily;

  @override
  String toString() => '$code: $message';
}

class FamilyInfo {
  const FamilyInfo({
    required this.id,
    required this.name,
    required this.url,
    required this.created,
  });

  factory FamilyInfo.fromJson(Map<String, Object?> json) => FamilyInfo(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        url: '${json['url'] ?? ''}',
        created: json['created'] == true,
      );

  final String id;
  final String name;
  final String url;

  /// `false` = buku sudah ada (idempoten, bukan buku kedua).
  final bool created;
}

class MeInfo {
  const MeInfo({
    required this.email,
    required this.name,
    required this.role,
    required this.status,
    required this.needsFamilySetup,
    this.family,
    this.memberId,
  });

  factory MeInfo.fromJson(Map<String, Object?> json) => MeInfo(
        email: '${json['email'] ?? ''}',
        name: '${json['name'] ?? ''}',
        role: '${json['role'] ?? ''}',
        status: '${json['status'] ?? ''}',
        needsFamilySetup: json['needsFamilySetup'] == true,
        family: json['family'] is Map
            ? FamilyInfo.fromJson(
                Map<String, Object?>.from(json['family']! as Map),
              )
            : null,
        memberId: json['memberId']?.toString(),
      );

  final String email;
  final String name;

  /// Selalu dari server/Sheet, tidak pernah dikirim aplikasi sebagai penentu.
  final String role;
  final String status;
  final bool needsFamilySetup;
  final FamilyInfo? family;
  final String? memberId;
}

/// Hasil `account.delete` (F12). Idempoten: `alreadyDeleted` dianggap sukses.
class AccountDeleteResult {
  const AccountDeleteResult({
    required this.deleted,
    required this.alreadyDeleted,
    this.memberId,
    this.transactionsAnonymized,
    this.auditsScrubbed,
  });

  factory AccountDeleteResult.fromJson(Map<String, Object?> json) =>
      AccountDeleteResult(
        deleted: json['deleted'] == true,
        alreadyDeleted: json['alreadyDeleted'] == true,
        memberId: json['memberId']?.toString(),
        transactionsAnonymized: json['transactionsAnonymized'] == true,
        auditsScrubbed: json['auditsScrubbed'] == true,
      );

  final bool deleted;
  final bool alreadyDeleted;
  final String? memberId;
  final bool? transactionsAnonymized;
  final bool? auditsScrubbed;

  bool get ok => deleted || alreadyDeleted;
}

/// Hasil `family.delete` (F12). Hanya admin terakhir.
class FamilyDeleteResult {
  const FamilyDeleteResult({
    required this.deleted,
    required this.alreadyDeleted,
    this.familyId,
    this.rowsRemoved,
    this.mappingsRemoved,
    this.fileTrashed,
    this.receiptFolderTrashed,
  });

  factory FamilyDeleteResult.fromJson(Map<String, Object?> json) =>
      FamilyDeleteResult(
        deleted: json['deleted'] == true,
        alreadyDeleted: json['alreadyDeleted'] == true,
        familyId: json['familyId']?.toString(),
        rowsRemoved: (json['rowsRemoved'] as num?)?.toInt(),
        mappingsRemoved: (json['mappingsRemoved'] as num?)?.toInt(),
        fileTrashed: json['fileTrashed'] == true,
        receiptFolderTrashed: json['receiptFolderTrashed'] == true,
      );

  final bool deleted;
  final bool alreadyDeleted;
  final String? familyId;
  final int? rowsRemoved;
  final int? mappingsRemoved;
  final bool? fileTrashed;

  /// Backend ikut men-trash folder nota (F5) — disebut di ringkasan hasil.
  final bool? receiptFolderTrashed;

  bool get ok => deleted || alreadyDeleted;
}

/// Anggota untuk menentukan "admin terakhir" sebelum menghapus.
class MemberSummary {
  const MemberSummary({
    required this.email,
    required this.role,
    required this.status,
    this.id,
  });

  factory MemberSummary.fromJson(Map<String, Object?> json) => MemberSummary(
        email: '${json['email'] ?? ''}',
        role: '${json['role'] ?? ''}',
        status: '${json['status'] ?? ''}',
        id: json['id']?.toString(),
      );

  final String email;
  final String role;
  final String status;
  final String? id;

  bool get isActive => status == 'active' || status == 'invited';
  bool get isAdmin => role == 'admin';
}

/// Klien Apps Script Web App untuk F1. Setiap request membawa ID token;
/// aplikasi tidak pernah mengirim role/familyId sebagai penentu hak (D-22).
class AppsScriptApi {
  AppsScriptApi({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  Future<void> ping() async {
    await _call<void>('ping', null, null);
  }

  Future<MeInfo> me(String idToken) async {
    final data = await _call<Map<String, Object?>>('me', idToken, null);
    return MeInfo.fromJson(data ?? const {});
  }

  /// Idempoten: pemanggilan kedua mengembalikan `created:false` untuk buku
  /// yang sama (bukan buku kedua).
  Future<FamilyInfo> createFamily(
    String idToken, {
    required String familyName,
  }) async {
    final data = await _call<Map<String, Object?>>(
      'setup.createFamily',
      idToken,
      {
        'familyName': familyName,
        // Sengaja TIDAK ada role/familyId: server yang menentukan.
      },
    );
    final family = (data?['family'] as Map?) ?? const {};
    return FamilyInfo.fromJson(Map<String, Object?>.from(family));
  }

  Future<List<MemberSummary>> memberList(String idToken) async {
    final data = await _call<Map<String, Object?>>('member.list', idToken, null);
    final rows = (data?['members'] as List?) ?? const [];
    return rows
        .whereType<Map>()
        .map((m) => MemberSummary.fromJson(Map<String, Object?>.from(m)))
        .toList();
  }

  /// Hapus akun sendiri (F12/D-33). Transaksi keluarga TIDAK dihapus; server
  /// mengganti `member_email` menjadi `deleted:<memberId>`.
  Future<AccountDeleteResult> deleteAccount(String idToken) async {
    final data = await _call<Map<String, Object?>>(
      'account.delete',
      idToken,
      null,
    );
    return AccountDeleteResult.fromJson(data ?? const {});
  }

  /// Hapus seluruh keluarga (admin terakhir). `confirmName` harus sama persis
  /// dengan nama keluarga; server menolak dengan VALIDATION bila tidak.
  Future<FamilyDeleteResult> deleteFamily(
    String idToken, {
    required String confirmName,
  }) async {
    final data = await _call<Map<String, Object?>>(
      'family.delete',
      idToken,
      {'confirmName': confirmName},
    );
    return FamilyDeleteResult.fromJson(data ?? const {});
  }

  Future<T?> _call<T>(
    String action,
    String? idToken,
    Map<String, Object?>? params,
  ) async {
    final body = <String, Object?>{
      'action': action,
      if (idToken != null) 'idToken': idToken,
      if (params != null) 'params': params,
    };

    late http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(baseUrl),
            headers: const {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } catch (_) {
      throw ApiException(ApiErrorCode.internal, 'Tidak bisa menghubungi server');
    }

    Map<String, Object?> json;
    try {
      json = Map<String, Object?>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw ApiException(
        ApiErrorCode.internal,
        'Balasan server tidak bisa dibaca',
      );
    }

    if (json['ok'] != true) {
      final error = json['error'];
      final map = error is Map ? Map<String, Object?>.from(error) : const {};
      throw ApiException(
        '${map['code'] ?? ApiErrorCode.internal}',
        '${map['message'] ?? 'Permintaan gagal'}',
      );
    }
    return json['data'] as T?;
  }
}
