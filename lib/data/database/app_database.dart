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
  /// Id baris di Sheet — dibutuhkan `member.setRole` / `member.remove`.
  /// Kunci lokal tetap `email` supaya sesi bisa dipakai sebelum sinkron.
  TextColumn get id => text().nullable()();
  TextColumn get email => text()();
  TextColumn get name => text()();
  TextColumn get role => text()(); // admin | member
  TextColumn get status => text()(); // active | invited | removed
  DateTimeColumn get joinedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

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
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Nilai sah kolom `type` pada [Budgets]: rencana (alokasi) vs batas.
/// Nilai disamakan dengan tab Sheet (`alokasi` / `budget`) supaya payload
/// sinkron bisa dikirim apa adanya (D-22).
abstract final class BudgetType {
  static const String allocation = 'alokasi';
  static const String limit = 'budget';
}

/// Alokasi dan batas per kategori per bulan (F7 + F10).
/// `type` membedakan rencana (alokasi) dari batas (budget): alokasi =
/// rencana pemakaian, budget = batas keras, dan alokasi <= budget.
@DataClassName('Budget')
class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get month => text()(); // YYYY-MM
  TextColumn get categoryId => text()();
  /// 'alokasi' | 'budget'
  TextColumn get type => text().withDefault(const Constant('budget'))();
  RealColumn get limitAmount => real().withDefault(const Constant(0))();
  RealColumn get allocatedAmount => real().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Tujuan dana (F10): target nominal + tenggat + alokasi per bulan.
@DataClassName('Goal')
class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get targetAmount => real()();
  /// `due_date` di Sheet. Tujuan tidak terikat kategori (D-22/P5).
  DateTimeColumn get dueDate => dateTime().nullable()();
  RealColumn get monthlyAllocation => real()();
  /// `active` | `done` — status manual dari Sheet.
  TextColumn get status => text().withDefault(const Constant('active'))();
  // Tidak ada createdAt: Sheet tidak punya kolomnya (D-36). Urutan daftar
  // memakai tenggat, bukan tanggal dibuat.
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
  /// Label aplikasi untuk antrean draf (mis. "myBCA").
  TextColumn get appName => text().withDefault(const Constant(''))();
  /// Boleh kosong di Sheet untuk parser yang belum punya contoh; baris
  /// seperti itu diabaikan saat dipakai (D-22/F12).
  TextColumn get pattern => text().nullable()();
  TextColumn get fieldMap => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

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
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(transactionDrafts);
          if (from < 3) {
            // D-22: kolom penanda delta + enum budget + bentuk goals Sheet.
            await m.addColumn(members, members.id);
            await m.addColumn(configParsers, configParsers.appName);
            await m.addColumn(configParsers, configParsers.isActive);
            // `updated_at` TIDAK ditambahkan lewat addColumn: drift memakai
            // default `currentDateAndTime` (ekspresi), dan SQLite menolak
            // "Cannot add a column with non-constant default" — inilah crash
            // upgrade. Tambahkan sebagai kolom biasa lalu isi ulang.
            for (final table in [
              'members',
              'categories',
              'budgets',
              'config_parsers',
            ]) {
              await customStatement(
                'ALTER TABLE $table ADD COLUMN updated_at INTEGER',
              );
            }
            // Baris lama berisi NULL setelah ADD COLUMN; mapping drift akan
            // crash kalau tidak diisi (D-32).
            for (final table in [
              'members',
              'categories',
              'budgets',
              'config_parsers',
            ]) {
              await customStatement(
                'UPDATE $table SET updated_at = CAST(strftime(\'%s\', \'now\') '
                'AS INTEGER) WHERE updated_at IS NULL',
              );
            }
          }
          // Idempoten: berlaku untuk semua jalur upgrade (v2 maupun v3).
          await customStatement(
            "UPDATE budgets SET type = 'alokasi' WHERE type = 'allocation'",
          );
          await customStatement(
            "UPDATE budgets SET type = 'budget' WHERE type = 'limit'",
          );
          // v2: goals.target_date + category_id; v3: due_date + status +
          // created_at; v4: tanpa created_at (D-36). Dibangun ulang dengan SQL
          // eksplisit supaya migrasi tidak bergantung pada kolom lama yang
          // sudah dihapus dari model drift.
          if (from < 4) await _rebuildGoals(from);
        },
      );

  /// Bangun ulang tabel `goals` ke bentuk terbaru (v4).
  /// Nilai `due_date` diambil dari `target_date` pada basis data v2.
  Future<void> _rebuildGoals(int from) async {
    final hasTargetDate = from < 3;
    // Sisa percobaan migrasi sebelumnya tidak boleh menghalangi upgrade.
    await customStatement('DROP TABLE IF EXISTS goals_old');
    await customStatement('ALTER TABLE goals RENAME TO goals_old');
    await customStatement('''
      CREATE TABLE goals (
        id TEXT NOT NULL,
        name TEXT NOT NULL,
        target_amount REAL NOT NULL,
        due_date INTEGER NULL,
        monthly_allocation REAL NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        updated_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', 'now') AS INTEGER)),
        is_deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (id)
      )
    ''');
    final dueSource = hasTargetDate ? 'target_date' : 'due_date';
    final statusSource = hasTargetDate ? "'active'" : 'status';
    await customStatement('''
      INSERT INTO goals
        (id, name, target_amount, due_date, monthly_allocation, status,
         updated_at, is_deleted)
      SELECT id, name, target_amount, $dueSource, monthly_allocation,
             $statusSource, updated_at, is_deleted
      FROM goals_old
    ''');
    await customStatement('DROP TABLE goals_old');
  }

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
          // Eksplisit: kolom hasil upgrade tidak punya default SQL (D-32).
          updatedAt: Value(DateTime.now().toUtc()),
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

  /// Buang satu baris antrean tanpa menyentuh data lokal — dipakai saat
  /// server menolak permanen (VALIDATION/FORBIDDEN), supaya tidak dicoba
  /// berulang selamanya.
  Future<void> removeSyncRow(String id) async {
    await (delete(syncQueue)..where((t) => t.id.equals(id))).go();
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

  /// Upsert transaksi. Companion yang hanya membawa sebagian kolom (mis.
  /// hanya `categoryId`) digabung dulu dengan baris lokal, karena drift
  /// menolak insert parsial untuk kolom wajib.
  Future<void> upsertTransaction(TransactionsCompanion companion) async {
    final id = companion.id.value;
    final existing = await transactionById(id);
    if (existing == null) {
      await into(transactions).insert(companion);
      return;
    }
    await (update(transactions)..where((t) => t.id.equals(id))).write(
      companion.copyWith(
        date: companion.date.present ? null : Value(existing.date),
        type: companion.type.present ? null : Value(existing.type),
        amount: companion.amount.present ? null : Value(existing.amount),
        categoryId:
            companion.categoryId.present ? null : Value(existing.categoryId),
        account: companion.account.present ? null : Value(existing.account),
        merchant: companion.merchant.present ? null : Value(existing.merchant),
        note: companion.note.present ? null : Value(existing.note),
        memberEmail:
            companion.memberEmail.present ? null : Value(existing.memberEmail),
        source: companion.source.present ? null : Value(existing.source),
        goalId: companion.goalId.present ? null : Value(existing.goalId),
        receiptUrl:
            companion.receiptUrl.present ? null : Value(existing.receiptUrl),
        rawText: companion.rawText.present ? null : Value(existing.rawText),
        createdAt:
            companion.createdAt.present ? null : Value(existing.createdAt),
        updatedAt:
            companion.updatedAt.present ? null : Value(existing.updatedAt),
        isDeleted:
            companion.isDeleted.present ? null : Value(existing.isDeleted),
      ),
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'nyatet.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
