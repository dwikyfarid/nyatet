import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/data/database/mappers.dart';
import 'package:nyatet/data/repository/transaction_repository.dart';
import 'package:nyatet/data/sync/sync_engine.dart';
import 'package:nyatet/data/sync/sync_transport.dart';
import 'package:nyatet/domain/access_policy.dart';
import 'package:nyatet/domain/allocation_repository.dart';
import 'package:nyatet/domain/report_service.dart';

class _RecordingTransport implements SyncTransport {
  final List<SyncMutation> pushed = [];
  final List<SyncMutation> master = [];
  DateTime cursor = DateTime.utc(2026, 11, 26, 12);

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
    master.add(mutation);
    return MutationResult(ok: true, action: mutation.op);
  }

  @override
  Future<PullResult> pull({
    required DateTime? since,
    Set<String>? entities,
  }) async =>
      PullResult(entities: const {}, serverTime: cursor);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late TransactionRepository repo;
  late AllocationRepository allocations;
  late ReportService reports;
  late _RecordingTransport transport;
  late SyncEngine engine;

  final admin =
      AccessPolicy(email: 'bapak@example.com', role: MemberRole.admin);
  final anak = AccessPolicy(email: 'anak@example.com', role: MemberRole.member);

  setUp(() async {
    db = AppDatabase.memory();
    await db.seedDefaultCategories();
    repo = TransactionRepository(db);
    reports = ReportService(db);
    allocations = AllocationRepository(db, repo, reports);
    transport = _RecordingTransport();
    engine = SyncEngine(db, transport: transport);
  });

  tearDown(() async {
    await db.close();
  });

  test('format tanggal: dikirim YYYY-MM-DD lokal, bukan ISO UTC', () async {
    // 00:30 WIB tanggal 26 Nov = 25 Nov 17:30 UTC — dulu mundur sehari.
    final date = DateTime(2026, 11, 26, 0, 30);
    await repo.create(
      date: date,
      type: TransactionType.outFlow,
      amount: 25000,
      memberEmail: 'bapak@example.com',
      source: TransactionSource.manual,
    );

    await engine.push();

    final sent = transport.pushed.single;
    expect(sent.data['date'], '2026-11-26');
    expect(sent.data['date'], isNot(contains('T')));
    expect(dateOnly(date), '2026-11-26');
  });

  test('pemetaan op: create, update, delete', () async {
    final id = await repo.create(
      date: DateTime(2026, 11, 20),
      type: TransactionType.outFlow,
      amount: 10000,
      memberEmail: 'bapak@example.com',
      source: TransactionSource.manual,
    );
    await repo.update(
      id: id,
      actorEmail: 'bapak@example.com',
      date: DateTime(2026, 11, 20),
      type: TransactionType.outFlow,
      amount: 12000,
      source: TransactionSource.manual,
    );
    await repo.softDelete(id, 'bapak@example.com');

    final queued = await db.pendingSyncBatch();
    expect(queued.map((q) => q.action).toList(), ['create', 'update', 'delete']);
    // Soft delete tidak pernah mengirim is_deleted untuk menimpa server.
    final deletePayload = queued.last.payload;
    expect(deletePayload, contains('"id"'));

    await engine.push();
    expect(transport.pushed.map((m) => m.op).toList(),
        ['create', 'update', 'delete']);
  });

  test('kursor pull memakai serverTime server, bukan jam HP', () async {
    final past = DateTime.utc(2026, 11, 26, 12);
    transport.cursor = past;
    await engine.pull();
    expect(await db.lastPullAt(), past);

    // Jam HP maju 1 tahun: kursor tetap ikut server, bukan DateTime.now().
    transport.cursor = DateTime.utc(2026, 12, 1, 8);
    await engine.pull();
    expect(await db.lastPullAt(), DateTime.utc(2026, 12, 1, 8));
  });

  test('setoran tujuan boleh anggota, penarikan hanya admin (D-20/D-22)',
      () async {
    final goalId = await allocations.createGoal(
      policy: admin,
      name: 'Dana Darurat',
      targetAmount: 5000000,
      monthlyAllocation: 500000,
    );

    final depositId = await allocations.deposit(
      policy: anak,
      goalId: goalId,
      amount: 100000,
    );
    final deposit = await db.transactionById(depositId);
    expect(deposit!.type, TransactionType.goalDeposit);
    expect(deposit.memberEmail, 'anak@example.com');

    await expectLater(
      allocations.withdraw(
        policy: anak,
        goalId: goalId,
        amount: 50000,
      ),
      throwsA(isA<AllocationRuleViolation>()),
    );

    final withdrawn = await allocations.withdraw(
      policy: admin,
      goalId: goalId,
      amount: 50000,
    );
    expect(
      (await db.transactionById(withdrawn))!.type,
      TransactionType.goalWithdrawal,
    );
  });

  test('tulisan budgets & goals masuk antrean, dikirim lewat endpoint khusus',
      () async {
    final cats = await db.select(db.categories).get();
    await allocations.setAllocation(
      policy: admin,
      monthKey: '2026-11',
      categoryId: cats.first.id,
      amount: 300000,
    );
    await allocations.setLimit(
      policy: admin,
      monthKey: '2026-11',
      categoryId: cats.first.id,
      amount: 500000,
    );
    await allocations.createGoal(
      policy: admin,
      name: 'Dana Sekolah',
      targetAmount: 10000000,
      monthlyAllocation: 1000000,
    );

    final queued = await db.pendingSyncBatch();
    expect(queued.map((q) => q.targetTable).toSet(), {'budgets', 'goals'});

    // Enum budget disamakan dengan Sheet (D-22).
    final types = (await db.select(db.budgets).get()).map((b) => b.type).toSet();
    expect(types, {BudgetType.allocation, BudgetType.limit});
    expect(BudgetType.allocation, 'alokasi');
    expect(BudgetType.limit, 'budget');

    await engine.push();

    // Master data tidak pernah masuk sync.push, hanya endpoint khusus.
    expect(transport.pushed, isEmpty);
    expect(
      transport.master.map((m) => m.entity).toSet(),
      {'budgets', 'goals'},
    );
  });

  test('status tujuan: on-track, kurang, tercapai', () async {
    final onTrack = await allocations.createGoal(
      policy: admin,
      name: 'Sekolah',
      targetAmount: 10000000,
      monthlyAllocation: 1000000,
      dueDate: DateTime.now().add(const Duration(days: 365)),
    );
    final noAllocation = await allocations.createGoal(
      policy: admin,
      name: 'Darurat',
      targetAmount: 20000000,
      monthlyAllocation: 0,
    );
    final done = await allocations.createGoal(
      policy: admin,
      name: 'Liburan',
      targetAmount: 1000000,
      monthlyAllocation: 0,
    );

    await allocations.deposit(policy: admin, goalId: onTrack, amount: 1000000);
    await allocations.deposit(policy: admin, goalId: done, amount: 1000000);

    final list = await allocations.goalsWithProgress(admin);
    String labelFor(String id) =>
        list.firstWhere((g) => g.goal.id == id).statusLabel;

    expect(labelFor(onTrack), startsWith('on-track'));
    expect(labelFor(noAllocation), startsWith('kurang Rp'));
    expect(labelFor(done), 'tercapai');
  });
}
