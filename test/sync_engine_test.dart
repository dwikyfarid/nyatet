import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/data/database/mappers.dart';
import 'package:nyatet/data/repository/transaction_repository.dart';
import 'package:nyatet/data/sync/sync_engine.dart';
import 'package:nyatet/data/sync/sync_transport.dart';

class _FakeTransport implements SyncTransport {
  _FakeTransport(this.remote);

  final Map<String, List<Map<String, Object?>>> remote;
  final List<SyncRecord> pushed = [];

  @override
  Future<void> push(List<SyncRecord> batch) async {
    pushed.addAll(batch);
  }

  @override
  Future<Map<String, List<Map<String, Object?>>>> pull({
    required DateTime? since,
  }) async {
    return remote;
  }
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

    final engine = SyncEngine(
      db,
      transport: _FakeTransport({
        'transactions': [remoteRow],
      }),
    );

    await engine.pull();

    final tx = await db.transactionById('remote-1');
    expect(tx, isNotNull);
    expect(tx!.amount, 12345);
    expect(await db.lastPullAt(), isNotNull);
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
      'date': '2026-11-25T00:00:00.000Z',
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
      transport: _FakeTransport({
        'transactions': [remoteRow],
      }),
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
      'date': '2026-11-25T00:00:00.000Z',
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
      transport: _FakeTransport({
        'transactions': [remoteRow],
      }),
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

    final transport = _FakeTransport(const {});
    final engine = SyncEngine(db, transport: transport);

    final sent = await engine.push();
    expect(sent, 1);
    expect(transport.pushed, hasLength(1));

    final pending = await db.pendingSyncBatch();
    expect(pending, isEmpty);
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
    receiptUrl: null,
    rawText: null,
    createdAt: DateTime.utc(2026, 11, 25),
    updatedAt: updatedAt,
    isDeleted: false,
  );
}
