import 'package:drift/drift.dart' show OrderingTerm;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/database/app_database.dart';
import '../data/repository/draft_repository.dart';
import '../data/repository/transaction_repository.dart';
import '../domain/access_policy.dart';
import '../domain/allocation_repository.dart';
import '../domain/budget_repository.dart';
import '../domain/report_service.dart';
import '../auth/apps_script_api.dart';
import '../auth/auth_config.dart';
import '../auth/auth_flow.dart';
import '../auth/auth_gateway.dart';
import '../domain/transaction_service.dart';
import '../update/apk_bridge.dart';
import '../update/github_api.dart';
import '../update/update_models.dart';
import '../update/update_service.dart';

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


// ---------------------------------------------------------------------------
// REL-03/REL-04 — cek update hanya untuk build sideload. Build `play`
// meng-override [updateEnabledProvider] menjadi false dan tidak pernah
// membaca [updateServiceProvider], jadi tidak ada permintaan ke api.github.com.
// ---------------------------------------------------------------------------

final updateEnabledProvider = Provider<bool>((ref) => true);

Future<InstalledVersion> _installedVersion() async {
  final info = await PackageInfo.fromPlatform();
  return InstalledVersion(
    versionName: info.version,
    versionCode: int.tryParse(info.buildNumber) ?? 0,
  );
}

final installedVersionProvider = FutureProvider<InstalledVersion>(
  (ref) => _installedVersion(),
);

final updateServiceProvider = Provider<UpdateService>(
  (ref) => UpdateService(
    api: GitHubUpdateApi(),
    bridge: const MethodChannelApkBridge(),
    installedVersion: _installedVersion,
    store: PrefsUpdateStore(),
    network: const ConnectivityProbe(),
  ),
);


// ---------------------------------------------------------------------------
// F1 — login Google + setup keluarga
// ---------------------------------------------------------------------------

final authConfigProvider = Provider<AuthConfig>((ref) => const AuthConfig());

final authFlowProvider = ChangeNotifierProvider<AuthFlow>((ref) {
  final config = ref.watch(authConfigProvider);
  final flow = AuthFlow(
    config: config,
    api: AppsScriptApi(baseUrl: config.scriptUrl),
    gateway: GoogleAuthGateway(clientId: config.clientId),
    stubGateway: const StubAuthGateway(),
    pendingDrafts: () async {
      final db = ref.read(databaseProvider);
      final rows = await (db.select(db.transactionDrafts)
            ..where((d) => d.status.equals(DraftStatus.pending)))
          .get();
      return rows.length;
    },
  );
  return flow;
});
