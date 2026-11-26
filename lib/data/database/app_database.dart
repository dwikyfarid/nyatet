import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

part 'app_database.g.dart';

/// Nilai sah kolom `type` pada [Transactions].
abstract final class TransactionType {
  static const String inFlow = 'in';
  static const String outFlow = 'out';
  static const String transfer = 'transfer';
  // Setoran/penarikan tujuan dana (F10). Setoran BUKAN `out`, jadi tidak
  // dihitung sebagai terpakai (D-17).
  static const String goalDeposit = 'goal_deposit';
  static const String goalWithdrawal = 'goal_withdrawal';
}

/// Nilai sah kolom `source` pada [Transactions].
abstract final class TransactionSource {
  static const String notif = 'notif';
  static const String ocr = 'ocr';
  static const String manual = 'manual';
}

/// Nilai sah kolom `role` pada [Members].
abstract final class MemberRole {
  static const String admin = 'admin';
  static const String member = 'member';
}

// ---------------------------------------------------------------------------
// Skema lokal (drift / SQLite). Kolom mengikuti PRD "Nyatet" hlm. 5.
// ---------------------------------------------------------------------------

@DataClassName('Transaction')
class Transactions extends Table {
  TextColumn get id => text()(); // UUID
  DateTimeColumn get date => dateTime()();
  TextColumn get type => text()(); // in | out | transfer
  RealColumn get amount => real()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get account => text().withDefault(const Constant(''))();
  TextColumn get merchant => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get memberEmail => text()();
  TextColumn get source => text()(); // notif | ocr | manual
  /// Hanya terisi untuk `type` goal_deposit / goal_withdrawal.
  TextColumn get goalId => text().nullable()();
  TextColumn get receiptUrl => text().nullable()();
  TextColumn get rawText => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Member')
class Members extends Table {
  TextColumn get email => text()();
  TextColumn get name => text()();
  TextColumn get role => text()(); // admin | member
  TextColumn get status => text()(); // active | invited | removed
  DateTimeColumn get joinedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {email};
}

@DataClassName('Category')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // in | out
  TextColumn get icon => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Nilai sah kolom `type` pada [Budgets]: rencana (alokasi) vs batas.
abstract final class BudgetType {
  static const String allocation = 'allocation';
  static const String limit = 'limit';
}

/// Alokasi dan batas per kategori per bulan (F7 + F10).
/// `type` membedakan rencana (alokasi) dari batas (budget): alokasi =
/// rencana pemakaian, budget = batas keras, dan alokasi <= budget.
@DataClassName('Budget')
class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get month => text()(); // YYYY-MM
  TextColumn get categoryId => text()();
  /// 'allocation' | 'limit'
  TextColumn get type => text().withDefault(const Constant('limit'))();
  RealColumn get limitAmount => real().withDefault(const Constant(0))();
  RealColumn get allocatedAmount => real().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Tujuan dana (F10): target nominal + tenggat + alokasi per bulan.
@DataClassName('Goal')
class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get targetAmount => real()();
  DateTimeColumn get targetDate => dateTime().nullable()();
  RealColumn get monthlyAllocation => real()();
  TextColumn get categoryId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ConfigParser')
class ConfigParsers extends Table {
  TextColumn get id => text()();
  TextColumn get packageName => text()();
  TextColumn get bankGroup => text().withDefault(const Constant(''))();
  TextColumn get pattern => text()();
  TextColumn get fieldMap => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AuditLog')
class AuditLogs extends Table {
  TextColumn get id => text()();
  DateTimeColumn get ts => dateTime()();
  TextColumn get memberEmail => text()();
  TextColumn get action => text()();
  TextColumn get txnId => text().nullable()();
  // PRD menamainya `before`/`after`; di SQLite dipakai suffix agar aman.
  TextColumn get beforeJson => text().nullable()();
  TextColumn get afterJson => text().nullable()();
}

/// Status draf notifikasi (F4).
abstract final class DraftStatus {
  static const String pending = 'pending';
  static const String saved = 'saved';
  static const String ignored = 'ignored';
  /// Duplikat yang dibuang otomatis (D-12), tetap terlihat di antrean.
  static const String duplicate = 'duplicate';
}

/// Draf transaksi hasil baca notifikasi bank/e-wallet (F3 → F4).
/// Hanya lokal sampai user menekan Simpan; draf tidak langsung ditulis ke Sheet.
@DataClassName('TransactionDraft')
class TransactionDrafts extends Table {
  TextColumn get id => text()();
  TextColumn get bankGroup => text()();
  TextColumn get packageName => text()();
  RealColumn get amount => real()();
  /// in | out | transfer
  TextColumn get type => text()();
  TextColumn get merchant => text().nullable()();
  TextColumn get last4 => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get rawText => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get categoryId => text().nullable()();
  /// Terisi bila draf ditandai duplikat dari draf lain (D-12).
  TextColumn get duplicateOfId => text().nullable()();
  /// Terisi setelah draf disimpan menjadi transaksi.
  TextColumn get savedTxnId => text().nullable()();
  DateTimeColumn get receivedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Antrean sinkronisasi — tabel lokal saja, tidak punya tab di Sheet.
@DataClassName('SyncQueueData')
class SyncQueue extends Table {
  TextColumn get id => text()();
  // Nama kolom SQL sengaja 'table_name'; getter Dart tidak boleh 'tableName'
  // karena bentrok dengan getter bawaan drift `Table.tableName`.
  TextColumn get targetTable => text().named('table_name')();
  TextColumn get rowId => text()();
  TextColumn get action => text()(); // upsert (soft delete ikut upsert)
  TextColumn get payload => text()(); // JSON snapshot baris
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
}

/// Penanda tarik-delta — tabel lokal saja.
@DataClassName('SyncMetaData')
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Transactions,
    Members,
    Categories,
    Budgets,
    Goals,
    TransactionDrafts,
    ConfigParsers,
    AuditLogs,
    SyncQueue,
    SyncMeta,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  factory AppDatabase.open() => AppDatabase(_openConnection());

  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(transactionDrafts);
        },
      );

  static const String _keyLastPullAt = 'last_pull_at';

  // -------------------------------------------------------------------------
  // Data awal
  // -------------------------------------------------------------------------

  /// Kategori awal sesuai PRD/F7, supaya aplikasi bisa dipakai offline sejak
  /// instalasi pertama (Sheet baru mengisi setelah sinkron FS-02).
  Future<void> seedDefaultCategories() async {
    final existing = await select(categories).get();
    if (existing.isNotEmpty) return;
    const seed = [
      ['Makan', 'out'],
      ['Belanja Dapur', 'out'],
      ['Transport', 'out'],
      ['Listrik/Air/Internet', 'out'],
      ['Sekolah', 'out'],
      ['Kesehatan', 'out'],
      ['Cicilan', 'out'],
      ['Hiburan', 'out'],
      ['Gaji', 'in'],
      ['Lain-lain', 'out'],
    ];
    for (final c in seed) {
      await into(categories).insert(
        CategoriesCompanion.insert(
          id: const Uuid().v4(),
          name: c[0],
          type: c[1],
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Sync queue
  // -------------------------------------------------------------------------

  /// Semua perubahan wajib lewat sini agar masuk antrean sinkronisasi.
  Future<String> enqueueSync({
    required String tableName,
    required String rowId,
    required String action,
    required Map<String, Object?> payload,
  }) async {
    final id = const Uuid().v4();
    await into(syncQueue).insert(
      SyncQueueCompanion.insert(
        id: id,
        targetTable: tableName,
        rowId: rowId,
        action: action,
        payload: jsonEncode(payload),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    return id;
  }

  Future<List<SyncQueueData>> pendingSyncBatch({int limit = 100}) {
    return (select(syncQueue)
          ..where((t) => t.syncedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<void> markSynced(String id) async {
    await (update(syncQueue)..where((t) => t.id.equals(id))).write(
      SyncQueueCompanion(syncedAt: Value(DateTime.now().toUtc())),
    );
  }

  Future<void> markSyncFailed(String id) async {
    final row = await (select(syncQueue)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    await (update(syncQueue)..where((t) => t.id.equals(id))).write(
      SyncQueueCompanion(attempts: Value(row.attempts + 1)),
    );
  }

  // -------------------------------------------------------------------------
  // Delta pull marker
  // -------------------------------------------------------------------------

  Future<DateTime?> lastPullAt() async {
    final row = await (select(syncMeta)
          ..where((t) => t.key.equals(_keyLastPullAt)))
        .getSingleOrNull();
    final parsed = row == null ? null : DateTime.tryParse(row.value);
    return parsed;
  }

  Future<void> setLastPullAt(DateTime dt) async {
    await into(syncMeta).insertOnConflictUpdate(
      SyncMetaCompanion.insert(
        key: _keyLastPullAt,
        value: dt.toUtc().toIso8601String(),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Audit log (last-write-wins mencatat versi kalah di sini)
  // -------------------------------------------------------------------------

  Future<void> writeAuditLog({
    required String memberEmail,
    required String action,
    String? txnId,
    String? beforeJson,
    String? afterJson,
  }) async {
    await into(auditLogs).insert(
      AuditLogsCompanion.insert(
        id: const Uuid().v4(),
        ts: DateTime.now().toUtc(),
        memberEmail: memberEmail,
        action: action,
        txnId: Value(txnId),
        beforeJson: Value(beforeJson),
        afterJson: Value(afterJson),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Akses transaksi untuk resolusi konflik
  // -------------------------------------------------------------------------

  Future<Transaction?> transactionById(String id) =>
      (select(transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsertTransaction(TransactionsCompanion companion) =>
      into(transactions).insertOnConflictUpdate(companion);
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'nyatet.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
