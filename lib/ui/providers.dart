import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/database/app_database.dart';
import '../data/repository/draft_repository.dart';
import '../data/repository/transaction_repository.dart';
import '../domain/access_policy.dart';
import '../domain/allocation_repository.dart';
import '../domain/budget_repository.dart';
import '../domain/report_service.dart';
import '../domain/transaction_service.dart';

/// True pada build web demo (F13): tanpa login, backend, maupun sinkronisasi.
final webDemoProvider = Provider<bool>((ref) => kIsWeb);

/// Database tunggal selama aplikasi hidup.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepository(ref.watch(databaseProvider)),
);

final draftRepositoryProvider = Provider<DraftRepository>(
  (ref) => DraftRepository(
    ref.watch(databaseProvider),
    ref.watch(transactionRepositoryProvider),
  ),
);

final transactionServiceProvider = Provider<TransactionService>(
  (ref) => TransactionService(
    ref.watch(databaseProvider),
    ref.watch(transactionRepositoryProvider),
  ),
);

/// Identitas berjalan. F1 (login Google) belum dibangun, jadi sesi lokal
/// memakai admin default; role bisa diganti untuk menguji hak akses anggota.
class Session {
  const Session({required this.email, required this.role, this.name = ''});

  final String email;
  final String role;
  final String name;

  AccessPolicy get policy => AccessPolicy(email: email, role: role);

  bool get isAdmin => role == MemberRole.admin;

  Session copyWith({String? email, String? role, String? name}) => Session(
        email: email ?? this.email,
        role: role ?? this.role,
        name: name ?? this.name,
      );
}

final sessionProvider = StateProvider<Session>(
  (ref) => const Session(
    email: 'bapak@example.com',
    role: MemberRole.admin,
    name: 'Bapak',
  ),
);

final accessPolicyProvider = Provider<AccessPolicy>(
  (ref) => ref.watch(sessionProvider).policy,
);

/// Kata kunci pencarian transaksi (UX-03).
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Daftar transaksi yang boleh dilihat sesi berjalan.
final visibleTransactionsProvider = FutureProvider<List<Transaction>>((ref) {
  final service = ref.watch(transactionServiceProvider);
  final policy = ref.watch(accessPolicyProvider);
  final query = ref.watch(searchQueryProvider);
  return service.listVisible(policy, query: query);
});

/// Antrean draf notifikasi (F4).
final draftQueueProvider = FutureProvider<List<TransactionDraft>>(
  (ref) => ref.watch(draftRepositoryProvider).listQueue(),
);

/// Draf yang masih menunggu keputusan — sumber angka progres "x dari y".
final pendingDraftsProvider = FutureProvider<List<TransactionDraft>>(
  (ref) => ref.watch(draftRepositoryProvider).listPending(),
);

/// Daftar kategori aktif (dipakai pemilih kategori, alokasi, cockpit).
final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.categories)
        ..where((c) => c.isActive.equals(true))
        ..orderBy([(c) => OrderingTerm.asc(c.name)]))
      .get();
});

final reportServiceProvider = Provider<ReportService>(
  (ref) => ReportService(ref.watch(databaseProvider)),
);

final allocationRepositoryProvider = Provider<AllocationRepository>(
  (ref) => AllocationRepository(
    ref.watch(databaseProvider),
    ref.watch(transactionRepositoryProvider),
    ref.watch(reportServiceProvider),
  ),
);

/// Bulan yang sedang dilihat (cockpit, alokasi). Format `YYYY-MM`.
final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(
    ref.watch(databaseProvider),
    ref.watch(reportServiceProvider),
  ),
);

/// Kategori + budget + terpakai bulan berjalan (F7/L8).
final budgetStatusProvider = FutureProvider<List<CategoryBudgetStatus>>((ref) {
  return ref.watch(budgetRepositoryProvider).status(
        ref.watch(accessPolicyProvider),
        ref.watch(selectedMonthProvider),
      );
});

final selectedMonthProvider = StateProvider<String>(
  (ref) => ReportService.monthKey(DateTime.now()),
);

/// Tab aktif beranda: 0 transaksi, 1 antrean, 2 antrean (badge), 3 alokasi.
final homeTabProvider = StateProvider<int>((ref) => 0);

final cashSummaryProvider = FutureProvider<CashSummary>((ref) {
  final service = ref.watch(reportServiceProvider);
  final policy = ref.watch(accessPolicyProvider);
  final monthKey = ref.watch(selectedMonthProvider);
  return service.summary(policy, DateTime.parse('$monthKey-01'));
});

final unallocatedProvider = FutureProvider<double>((ref) {
  final service = ref.watch(reportServiceProvider);
  final policy = ref.watch(accessPolicyProvider);
  final monthKey = ref.watch(selectedMonthProvider);
  return service.unallocated(policy, DateTime.parse('$monthKey-01'));
});

final allocationRowsProvider = FutureProvider<List<Budget>>((ref) {
  final repo = ref.watch(allocationRepositoryProvider);
  return repo.allocationsFor(ref.watch(selectedMonthProvider));
});

final goalsProvider = FutureProvider<List<GoalProgress>>((ref) {
  final repo = ref.watch(allocationRepositoryProvider);
  return repo.goalsWithProgress(ref.watch(accessPolicyProvider));
});


/// F13/P1: setelah simpan, semua angka ikut berubah (bukan hanya daftar).
extension MoneyRefresh on WidgetRef {
  void refreshMoneyProviders() {
    invalidate(visibleTransactionsProvider);
    invalidate(cashSummaryProvider);
    invalidate(unallocatedProvider);
    invalidate(allocationRowsProvider);
    invalidate(goalsProvider);
    invalidate(draftQueueProvider);
    invalidate(pendingDraftsProvider);
  }
}
