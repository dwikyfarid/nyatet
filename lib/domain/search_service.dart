import 'package:drift/drift.dart';

import '../data/database/app_database.dart';
import 'access_policy.dart';

/// F15/D-50: hasil cari global, dikelompokkan per jenis.
class GlobalSearchResult {
  const GlobalSearchResult({
    required this.query,
    required this.transactions,
    required this.categories,
    required this.goals,
    required this.members,
  });

  final String query;
  final List<Transaction> transactions;
  final List<Category> categories;
  final List<Goal> goals;
  final List<Member> members;

  bool get isEmpty =>
      transactions.isEmpty &&
      categories.isEmpty &&
      goals.isEmpty &&
      members.isEmpty;

  int get total =>
      transactions.length + categories.length + goals.length + members.length;
}

/// Pencarian lokal (offline). `raw_text` notifikasi TIDAK pernah diindeks
/// (D-50 keputusan 4: memuat nomor rekening penuh).
class SearchService {
  SearchService(this._db);

  final AppDatabase _db;

  static const int perGroupLimit = 20;

  Future<GlobalSearchResult> search(
    AccessPolicy policy,
    String rawQuery,
  ) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      return const GlobalSearchResult(
        query: '',
        transactions: [],
        categories: [],
        goals: [],
        members: [],
      );
    }
    final like = '%${query.toLowerCase()}%';

    final txQuery = _db.select(_db.transactions)
      ..where(
        (t) =>
            t.isDeleted.equals(false) &
            (_contains(t.merchant, like) |
                _contains(t.note, like) |
                _contains(t.refNo, like) |
                _contains(t.account, like)) &
            // Hanya anggota melihat transaksinya sendiri.
            (policy.isAdmin
                ? const Constant(true)
                : t.memberEmail.equals(policy.email)),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.date)])
      ..limit(perGroupLimit);

    final catQuery = _db.select(_db.categories)
      ..where((c) => _contains(c.name, like))
      ..orderBy([(c) => OrderingTerm.asc(c.name)])
      ..limit(perGroupLimit);

    final goalQuery = _db.select(_db.goals)
      ..where((g) => g.isDeleted.equals(false) & _contains(g.name, like))
      ..orderBy([
        (g) => OrderingTerm.asc(g.dueDate.isNull()),
        (g) => OrderingTerm.asc(g.dueDate),
        (g) => OrderingTerm.asc(g.name),
      ])
      ..limit(perGroupLimit);

    final memberQuery = _db.select(_db.members)
      ..where((m) => m.status.equals('removed').not() & (_contains(m.name, like) | _contains(m.email, like)))
      ..orderBy([(m) => OrderingTerm.asc(m.name)])
      ..limit(perGroupLimit);

    final results = await Future.wait([
      txQuery.get(),
      catQuery.get(),
      goalQuery.get(),
      memberQuery.get(),
    ]);

    return GlobalSearchResult(
      query: query,
      transactions: results[0] as List<Transaction>,
      categories: results[1] as List<Category>,
      goals: results[2] as List<Goal>,
      members: results[3] as List<Member>,
    );
  }

  /// Kolom nullable dibandingkan dengan aman (NULL tidak pernah cocok).
  Expression<bool> _contains(GeneratedColumn<String> column, String like) =>
      column.lower().like(like);
}
