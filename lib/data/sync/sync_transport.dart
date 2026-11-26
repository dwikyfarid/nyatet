/// Abstraksi transport sinkronisasi ke Apps Script (FS-02). Bentuk payload
/// mengikuti kontrak backend D-22, bukan bentuk internal antrean lokal.
library;

/// Operasi yang dikenal server. `upsert` tidak sah di `sync.push`.
abstract final class SyncOp {
  static const String create = 'create';
  static const String update = 'update';
  static const String delete = 'delete';
}

/// Satu mutasi: `{entity, op, data, updatedAt}`.
class SyncMutation {
  SyncMutation({
    required this.entity,
    required this.op,
    required this.data,
    required this.updatedAt,
  });

  final String entity;

  /// [SyncOp.create] | [SyncOp.update] | [SyncOp.delete].
  final String op;
  final Map<String, Object?> data;
  final DateTime updatedAt;

  String get rowId => (data['id'] as String?) ?? '';

  Map<String, Object?> toJson() => {
        'entity': entity,
        'op': op,
        'data': data,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };
}

/// Hasil satu mutasi dari `sync.push` / endpoint master data.
class MutationResult {
  const MutationResult({
    required this.ok,
    this.index,
    this.action,
    this.row,
    this.conflict = false,
    this.code,
    this.message,
    this.id,
  });

  factory MutationResult.fromJson(Map<String, Object?> json) {
    final error = json['error'];
    return MutationResult(
      ok: json['ok'] == true,
      index: (json['index'] as num?)?.toInt(),
      action: json['action'] as String?,
      row: json['row'] == null
          ? null
          : Map<String, Object?>.from(json['row']! as Map),
      conflict: json['conflict'] == true,
      code: json['code'] as String? ??
          (error is Map ? error['code'] as String? : null),
      message: json['message'] as String? ??
          (error is Map ? error['message'] as String? : null),
      id: json['id'] as String?,
    );
  }

  final bool ok;

  /// Posisi mutasi di batch (0-based).
  final int? index;

  /// `create` | `update` | `delete` | `stale`.
  final String? action;

  /// Baris versi server — wajib dipakai menimpa lokal saat [isStale].
  final Map<String, Object?>? row;
  final bool conflict;
  final String? code;
  final String? message;
  final String? id;

  /// Server menang (LWW): klien harus menimpa baris lokal dengan [row].
  bool get isStale => action == 'stale' || conflict;

  /// Kegagalan permanen: keluarkan dari antrean, tampilkan ke user.
  /// `LOCK_TIMEOUT`/`INTERNAL`/`OFFLINE` dicoba lagi nanti.
  bool get isPermanentFailure => const [
        'VALIDATION',
        'FORBIDDEN',
        'NOT_FOUND',
        'CONFLICT',
        'SCHEMA_MISMATCH',
      ].contains(code);
}

/// Satu entity pada balasan `sync.pull`.
class PullEntity {
  const PullEntity({
    required this.rows,
    this.nextSince,
    this.truncated = false,
    this.count = 0,
  });

  factory PullEntity.fromJson(Map<String, Object?> json) => PullEntity(
        rows: ((json['rows'] as List?) ?? const [])
            .map((r) => Map<String, Object?>.from(r as Map))
            .toList(),
        nextSince: json['nextSince'] == null
            ? null
            : DateTime.tryParse(json['nextSince']! as String),
        truncated: json['truncated'] == true,
        count: ((json['count'] as num?) ?? 0).toInt(),
      );

  final List<Map<String, Object?>> rows;
  final DateTime? nextSince;
  final bool truncated;
  final int count;
}

/// Balasan `sync.pull`: `{entities, serverTime, truncated}`.
class PullResult {
  const PullResult({
    required this.entities,
    required this.serverTime,
    this.truncated = false,
  });

  factory PullResult.empty() => PullResult(
        entities: const {},
        serverTime: DateTime.now().toUtc(),
      );

  final Map<String, PullEntity> entities;

  /// Kursor berikutnya **dari server**, bukan jam HP.
  final DateTime serverTime;
  final bool truncated;
}

abstract class SyncTransport {
  /// `sync.push` — hanya transaksi. Balasan berisi hasil per mutasi.
  Future<List<MutationResult>> push(List<SyncMutation> mutations);

  /// Master data (members/categories/budgets/goals/config_parser) lewat
  /// endpoint khusus, bukan `sync.push` (D-22).
  Future<MutationResult> pushMaster(SyncMutation mutation);

  /// `sync.pull` — delta sejak [since]; boleh dibatasi [entities].
  Future<PullResult> pull({
    required DateTime? since,
    Set<String>? entities,
  });
}

/// Transport tanpa jaringan: semua mutasi tetap di antrean supaya tidak ada
/// data yang hilang sebelum Apps Script terpasang (F1).
class NoopSyncTransport implements SyncTransport {
  const NoopSyncTransport();

  static const MutationResult _offline = MutationResult(
    ok: false,
    code: 'OFFLINE',
    message: 'Belum terhubung ke Apps Script',
  );

  @override
  Future<List<MutationResult>> push(List<SyncMutation> mutations) async => [
        for (var i = 0; i < mutations.length; i++)
          MutationResult(
            ok: false,
            index: i,
            code: _offline.code,
            message: _offline.message,
          ),
      ];

  @override
  Future<MutationResult> pushMaster(SyncMutation mutation) async => _offline;

  @override
  Future<PullResult> pull({
    required DateTime? since,
    Set<String>? entities,
  }) async =>
      PullResult.empty();
}
