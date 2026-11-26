import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/data/database/mappers.dart';
import 'package:nyatet/data/repository/transaction_repository.dart';
import 'package:nyatet/data/sync/sync_engine.dart';
import 'package:nyatet/data/sync/sync_transport.dart';

/// Transport palsu yang meniru Apps Script: balasan per mutasi, `pull`
/// berbentuk `{entities, serverTime, truncated}`.
class _FakeTransport implements SyncTransport {
  _FakeTransport({
    this.remote = const {},
    DateTime? serverTime,
  }) : serverTime = serverTime ?? DateTime.utc(2026, 11, 26, 15);

  final Map<String, List<Map<String, Object?>>> remote;
  final DateTime serverTime;
  final List<SyncMutation> pushed = [];
  final List<SyncMutation> pushedMaster = [];

  @override
  Future<List<MutationResult>> push(List<SyncMutation> mutations) async {
    pushed.addAll(mutations);
    return [
      for (var i = 0; i < mutations.length; i++)
        MutationResult(ok: true, index: i, action: mutations[i].op),
    ];
  }

  @override
  Future<MutationResult> pushMaster(SyncMutation mutation) async {
    pushedMaster.add(mutation);
    return MutationResult(ok: true, action: mutation.op);
  }

  @override
  Future<PullResult> pull({
    required DateTime? since,
    Set<String>? entities,
  }) async {
    return PullResult(
      entities: {
        for (final e in remote.entries)
          if (entities == null || entities.contains(e.key))
            e.key: PullEntity(rows: e.value, count: e.value.length),
      },
      serverTime: serverTime,
    );
  }
}

/// Transport yang menolak satu mutasi karena VALIDATION.
class _RejectingTransport extends _FakeTransport {
  @override
  Future<List<MutationResult>> push(List<SyncMutation> mutations) async => [
        for (var i = 0; i < mutations.length; i++)
          MutationResult(
            ok: false,
            index: i,
            code: 'VALIDATION',
            message: 'date tidak sah',
          ),
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late TransactionRepository repo;

  setUp(() {
    db = AppDatabase.memory();
    repo = TransactionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('pull delta: baris baru dari server masuk ke lokal', () async {
    final remoteRow = transactionToMap(
      // Ganti payload id agar tidak bentrok dengan data lokal.
      _tx(
        id: 'remote-1',
        amount: 12345,
        updatedAt: DateTime.utc(2026, 11, 26),
      ),
    );

    final serverTime = DateTime.utc(2026, 11, 26, 16, 30);
    final engine = SyncEngine(
      db,
      transport: _FakeTransport(
        remote: {
          'transactions': [remoteRow],
        },
        serverTime: serverTime,
      ),
    );

    await engine.pull();

    final tx = await db.transactionById('remote-1');
    expect(tx, isNotNull);
    expect(tx!.amount, 12345);
    expect(await db.lastPullAt(), isNotNull);
    // Kursor memakai jam server, bukan jam HP.
    expect(await db.lastPullAt(), serverTime);
  });

  test('last-write-wins: server lebih baru menang dan versi lokal diaudit',
      () async {
    final id = await repo.create(
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.outFlow,
      amount: 1000,
      memberEmail: 'bapak@example.com',
      source: TransactionSource.manual,
    );

    // Server punya updated_at lebih baru dari lokal (lokal ≈ sekarang).
    final newer = DateTime.now().toUtc().add(const Duration(days: 1));
    final remoteRow = {
      'id': id,
      'date': '2026-11-25',
      'type': 'out',
      'amount': 9999.0,
      'category_id': null,
      'account': '',
      'merchant': null,
      'note': null,
      'member_email': 'bapak@example.com',
      'source': 'manual',
      'receipt_url': null,
      'raw_text': null,
      'created_at': '2026-11-25T00:00:00.000Z',
      'updated_at': newer.toIso8601String(),
      'is_deleted': false,
    };

    final engine = SyncEngine(
      db,
      transport: _FakeTransport(
        remote: {
          'transactions': [remoteRow],
        },
      ),
    );

    await engine.pull();

    final tx = await db.transactionById(id);
    expect(tx!.amount, 9999);

    final audit = await db.select(db.auditLogs).get();
    expect(audit.any((a) => a.action == 'conflict_server_won'), isTrue);
  });

  test('last-write-wins: lokal lebih baru dipertahankan dan diantrekan ulang',
      () async {
    final id = await repo.create(
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.outFlow,
      amount: 2000,
      memberEmail: 'bapak@example.com',
      source: TransactionSource.manual,
    );

    final older = DateTime.now().toUtc().subtract(const Duration(days: 1));
    final remoteRow = {
      'id': id,
      'date': '2026-11-25',
      'type': 'out',
      'amount': 8888.0,
      'category_id': null,
      'account': '',
      'merchant': null,
      'note': null,
      'member_email': 'bapak@example.com',
      'source': 'manual',
      'receipt_url': null,
      'raw_text': null,
      'created_at': '2026-11-25T00:00:00.000Z',
      'updated_at': older.toIso8601String(),
      'is_deleted': false,
    };

    final beforeQueue = (await db.pendingSyncBatch()).length;

    final engine = SyncEngine(
      db,
      transport: _FakeTransport(
        remote: {
          'transactions': [remoteRow],
        },
      ),
    );

    await engine.pull();

    final tx = await db.transactionById(id);
    expect(tx!.amount, 2000); // lokal dipertahankan

    // Lokal yang menang diantrekan ulang supaya menimpa server.
    final afterQueue = await db.pendingSyncBatch();
    expect(afterQueue.length, greaterThan(beforeQueue));
  });

  test('push: batch antrean terkirim dan ditandai synced', () async {
    await repo.create(
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.outFlow,
      amount: 75000,
      memberEmail: 'bapak@example.com',
      source: TransactionSource.manual,
    );

    final transport = _FakeTransport();
    final engine = SyncEngine(db, transport: transport);

    final sent = await engine.push();
    expect(sent, 1);
    expect(transport.pushed, hasLength(1));

    final pending = await db.pendingSyncBatch();
    expect(pending, isEmpty);
  });

  test('push: mutasi ditolak VALIDATION keluar dari antrean, tidak diulang',
      () async {
    await repo.create(
      date: DateTime.utc(2026, 11, 25),
      type: TransactionType.outFlow,
      amount: 10000,
      memberEmail: 'bapak@example.com',
      source: TransactionSource.manual,
    );

    final engine = SyncEngine(db, transport: _RejectingTransport());
    final sent = await engine.push();

    expect(sent, 0);
    expect(await db.pendingSyncBatch(), isEmpty);
    final audit = await db.select(db.auditLogs).get();
    expect(audit.any((a) => a.action == 'sync_rejected'), isTrue);
  });

  test('pull: master data (members/categories/goals) ikut diterapkan',
      () async {
    final engine = SyncEngine(
      db,
      transport: _FakeTransport(
        remote: {
          'members': [
            {
              'id': 'm-1',
              'email': 'ibu@example.com',
              'name': 'Ibu',
              'role': 'member',
              'status': 'active',
              'joined_at': '2026-11-01T00:00:00.000Z',
              'updated_at': '2026-11-20T00:00:00.000Z',
            },
          ],
          'categories': [
            {
              'id': 'cat_school',
              'name': 'Sekolah',
              'type': 'out',
              'icon': '',
              'is_active': true,
              'updated_at': '2026-11-20T00:00:00.000Z',
            },
          ],
          'goals': [
            {
              'id': 'goal-1',
              'name': 'Dana Sekolah',
              'target_amount': 5000000,
              'monthly_allocation': 500000,
              'due_date': '2027-06-30',
              'status': 'active',
              'is_deleted': false,
              'updated_at': '2026-11-20T00:00:00.000Z',
            },
          ],
          'config_parser': [
            {
              'id': 'p-1',
              'package_name': 'com.bca',
              'bank_group': 'bca',
              'app_name': 'myBCA',
              'pattern': r'You spent IDR ([\d,\.]+)',
              'field_map': '{"amount":1}',
              'version': 1,
              'is_active': true,
              'updated_at': '2026-11-20T00:00:00.000Z',
            },
            {
              // Parser tanpa pola diabaikan (F12/D-22).
              'id': 'p-2',
              'package_name': 'com.kosong',
              'bank_group': 'lain',
              'pattern': '',
              'field_map': '{}',
              'is_active': false,
              'updated_at': '2026-11-20T00:00:00.000Z',
            },
          ],
        },
      ),
    );

    await engine.pull();

    expect(
      (await db.select(db.members).get()).single.email,
      'ibu@example.com',
    );
    expect((await db.select(db.categories).get()).single.name, 'Sekolah');
    final goal = (await db.select(db.goals).get()).single;
    expect(goal.dueDate, DateTime(2027, 6, 30));
    expect(goal.status, 'active');
    final parsers = await db.select(db.configParsers).get();
    expect(parsers, hasLength(1));
    expect(parsers.single.appName, 'myBCA');
  });
}

Transaction _tx({
  required String id,
  required double amount,
  required DateTime updatedAt,
}) {
  return Transaction(
    id: id,
    date: DateTime.utc(2026, 11, 25),
    type: 'out',
    amount: amount,
    categoryId: null,
    account: '',
    merchant: null,
    note: null,
    memberEmail: 'bapak@example.com',
    source: 'manual',
    goalId: null,
    receiptUrl: null,
    rawText: null,
    createdAt: DateTime.utc(2026, 11, 25),
    updatedAt: updatedAt,
    isDeleted: false,
  );
}
