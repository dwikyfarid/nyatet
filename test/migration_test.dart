// ignore_for_file: prefer_single_quotes
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/data/database/mappers.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// D-32/D-36: jalur upgrade tidak boleh crash dan tidak boleh kehilangan data.
/// Basis data lama dibuat dengan DDL v2/v3 apa adanya, lalu dibuka memakai
/// [AppDatabase] sehingga `onUpgrade` benar-benar dijalankan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nyatet_migration');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  void createOldSchema(
    String path, {
    required int version,
  }) {
    final db = raw.sqlite3.open(path);
    // v2: belum ada id/updated_at. v3 (dibuat baru oleh createAll) sudah
    // punya semua kolom penanda delta, tapi goals masih menyimpan created_at.
    final memberIdColumn = version < 3 ? '' : 'id TEXT NULL,';
    final memberUpdatedAt = version < 3 ? '' : 'updated_at INTEGER NOT NULL,';
    final categoryUpdatedAt = version < 3 ? '' : 'updated_at INTEGER NOT NULL,';
    final budgetUpdatedAt = version < 3 ? '' : 'updated_at INTEGER NOT NULL,';
    final parserExtra = version < 3
        ? ''
        : "app_name TEXT NOT NULL DEFAULT '', "
            "is_active INTEGER NOT NULL DEFAULT 0, "
            'updated_at INTEGER NOT NULL,';
    db.execute('''
      CREATE TABLE members (
        $memberIdColumn email TEXT NOT NULL, name TEXT NOT NULL,
        role TEXT NOT NULL, status TEXT NOT NULL, joined_at INTEGER NOT NULL,
        $memberUpdatedAt
        PRIMARY KEY (email)
      );
      CREATE TABLE categories (
        id TEXT NOT NULL, name TEXT NOT NULL, type TEXT NOT NULL,
        icon TEXT NOT NULL DEFAULT '', is_active INTEGER NOT NULL DEFAULT 1,
        $categoryUpdatedAt
        PRIMARY KEY (id)
      );
      CREATE TABLE budgets (
        id TEXT NOT NULL, month TEXT NOT NULL, category_id TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'limit',
        limit_amount REAL NOT NULL DEFAULT 0,
        allocated_amount REAL NOT NULL DEFAULT 0,
        $budgetUpdatedAt
        PRIMARY KEY (id)
      );
      CREATE TABLE config_parsers (
        id TEXT NOT NULL, package_name TEXT NOT NULL,
        bank_group TEXT NOT NULL DEFAULT '', pattern TEXT NOT NULL,
        field_map TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1,
        $parserExtra
        PRIMARY KEY (id)
      );
    ''');
    if (version < 3) {
      db.execute('''
        CREATE TABLE goals (
          id TEXT NOT NULL, name TEXT NOT NULL, target_amount REAL NOT NULL,
          target_date INTEGER NULL, monthly_allocation REAL NOT NULL,
          category_id TEXT NULL, created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL, is_deleted INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (id)
        );
      ''');
    } else {
      db.execute('''
        CREATE TABLE goals (
          id TEXT NOT NULL, name TEXT NOT NULL, target_amount REAL NOT NULL,
          due_date INTEGER NULL, monthly_allocation REAL NOT NULL,
          status TEXT NOT NULL DEFAULT 'active', created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL, is_deleted INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (id)
        );
      ''');
    }

    final catCols = version < 3 ? '(id, name, type)' : '(id, name, type, updated_at)';
    final catVals = version < 3
        ? "('cat_makan','Makan','out')"
        : "('cat_makan','Makan','out',1700000000)";
    db.execute('INSERT INTO categories $catCols VALUES $catVals');
    final budgetCols = version < 3
        ? '(id, month, category_id, type, limit_amount)'
        : '(id, month, category_id, type, limit_amount, updated_at)';
    db.execute(
      version < 3
          ? 'INSERT INTO budgets $budgetCols '
              "VALUES ('b1','2026-11','cat_makan','limit',500000)"
          : 'INSERT INTO budgets $budgetCols '
              "VALUES ('b1','2026-11','cat_makan','limit',500000,1700000000)",
    );
    db.execute(
      version < 3
          ? 'INSERT INTO budgets '
              '(id, month, category_id, type, allocated_amount) '
              "VALUES ('b2','2026-11','cat_makan','allocation',300000)"
          : 'INSERT INTO budgets '
              '(id, month, category_id, type, allocated_amount, updated_at) '
              "VALUES ('b2','2026-11','cat_makan','allocation',300000,1700000000)",
    );
    final due = version < 3
        ? "INSERT INTO goals (id,name,target_amount,target_date,monthly_allocation,category_id,created_at,updated_at,is_deleted) "
            "VALUES ('g1','Dana Sekolah',10000000,1798761600,1500000,'cat_makan',1700000000,1700000000,0)"
        : "INSERT INTO goals (id,name,target_amount,due_date,monthly_allocation,status,created_at,updated_at,is_deleted) "
            "VALUES ('g1','Dana Sekolah',10000000,1798761600,1500000,'active',1700000000,1700000000,0)";
    db.execute(due);
    db.execute('PRAGMA user_version = $version');
    db.close();
  }

  Future<void> expectMigrated(String path) async {
    final db = AppDatabase(NativeDatabase(File(path)));
    addTearDown(db.close);

    final goals = await db.select(db.goals).get();
    expect(goals, hasLength(1), reason: 'data tujuan tidak boleh hilang');
    expect(goals.single.name, 'Dana Sekolah');
    expect(goals.single.targetAmount, 10000000);
    expect(goals.single.dueDate, isNotNull);
    expect(goals.single.status, 'active');

    final columns = await db
        .customSelect('PRAGMA table_info(goals)')
        .get()
        .then((rows) => rows.map((r) => r.read<String>('name')).toSet());
    expect(columns, isNot(contains('created_at')));
    expect(columns, isNot(contains('category_id')));
    expect(columns, contains('due_date'));

    final budgets = await db.select(db.budgets).get();
    expect(
      budgets.map((b) => b.type).toSet(),
      {BudgetType.limit, BudgetType.allocation},
      reason: 'enum lama limit/allocation harus jadi budget/alokasi',
    );

    final parserColumns = await db
        .customSelect('PRAGMA table_info(config_parsers)')
        .get()
        .then((rows) => rows.map((r) => r.read<String>('name')).toSet());
    expect(parserColumns, containsAll(['app_name', 'is_active', 'updated_at']));

    // Tabel baru tetap bisa dipakai setelah migrasi.
    expect(await db.select(db.members).get(), isEmpty);
    await db.into(db.goals).insert(
          GoalsCompanion.insert(
            id: 'g2',
            name: 'Baru',
            targetAmount: 1000,
            monthlyAllocation: 100,
            updatedAt: DateTime.now(),
          ),
        );
  }

  test('upgrade v2 → v4 tidak crash dan data tujuan/budget terjaga', () async {
    final file = File('${dir.path}/v2.sqlite');
    createOldSchema(file.path, version: 2);
    await expectMigrated(file.path);
  });

  test('upgrade v3 → v4 membuang created_at tanpa kehilangan data', () async {
    final file = File('${dir.path}/v3.sqlite');
    createOldSchema(file.path, version: 3);
    await expectMigrated(file.path);
  });

  test('D-36: mapper goal stabil dan tidak punya created_at', () {
    final goal = Goal(
      id: 'g1',
      name: 'Dana Sekolah',
      targetAmount: 10000000,
      dueDate: DateTime(2027, 6, 30),
      monthlyAllocation: 1500000,
      status: 'active',
      updatedAt: DateTime.utc(2026, 11, 26, 8),
      isDeleted: false,
    );

    final first = goalToMap(goal);
    final second = goalToMap(goal);
    expect(first, second, reason: 'mapper tidak boleh menghasilkan nilai baru');
    expect(first.containsKey('created_at'), isFalse);

    final back = goalFromMap(first);
    expect(back.updatedAt.value, goal.updatedAt);
    expect(back.dueDate.value, DateTime(2027, 6, 30));
  });
}
