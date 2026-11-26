import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/data/repository/transaction_repository.dart';
import 'package:nyatet/data/seed/dev_seeder.dart';
import 'package:nyatet/domain/access_policy.dart';
import 'package:nyatet/domain/allocation_repository.dart';
import 'package:nyatet/domain/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  test('seed Q-07: 200 transaksi, 2 bulan, 3 anggota, 3 tujuan, 1 bulan rencana',
      () async {
    final created = await DevSeeder(db).seedTransactions();
    expect(created, 200);

    final txns = await db.select(db.transactions).get();
    expect(txns, hasLength(200));

    final members = await db.select(db.members).get();
    expect(members, hasLength(3));
    expect(members.where((m) => m.role == MemberRole.admin), hasLength(1));

    final categories = await db.select(db.categories).get();
    expect(categories.where((c) => c.isActive).length, greaterThanOrEqualTo(8));

    final goals = await db.select(db.goals).get();
    expect(goals, hasLength(3));
    expect(txns.where((t) => t.type == TransactionType.goalDeposit),
        isNotEmpty);

    final now = DateTime.now();
    final reports = ReportService(db);
    final admin =
        AccessPolicy(email: 'bapak@example.com', role: MemberRole.admin);
    final thisMonth = await reports.summary(admin, DateTime(now.year, now.month));
    final lastMonth =
        await reports.summary(admin, DateTime(now.year, now.month - 1));

    expect(thisMonth.masuk, greaterThan(0));
    // Bulan lalu sengaja tanpa pemasukan → alokasi tampil sebagai "rencana".
    expect(lastMonth.masuk, 0);

    // Alokasi tersedia di dua bulan supaya QA bisa menguji label rencana.
    final allocs = AllocationRepository(db, TransactionRepository(db), reports);
    expect(await allocs.allocationsFor(_key(now)), isNotEmpty);
    expect(
      await allocs.allocationsFor(_key(DateTime(now.year, now.month - 1))),
      isNotEmpty,
    );

    // Tiga status tujuan harus bisa diverifikasi QA.
    final progress = await allocs.goalsWithProgress(admin);
    expect(progress, hasLength(3));
    expect(progress.any((g) => g.statusLabel == 'tercapai'), isTrue);
    expect(progress.any((g) => g.statusLabel.startsWith('kurang Rp')), isTrue);
    expect(progress.any((g) => g.statusLabel.startsWith('on-track')), isTrue);
  });
}

String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
