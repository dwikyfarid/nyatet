import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../data/database/app_database.dart';
import '../data/database/mappers.dart';
import '../data/sync/sync_transport.dart';
import 'access_policy.dart';
import 'allocation_repository.dart';
import 'report_service.dart';

/// Ambang peringatan budget (F7): hijau <80%, amber ≥80%, merah ≥100%.
enum BudgetLevel { aman, waspada, lewat }

/// Satu baris L8: budget (batas) satu kategori pada satu bulan, dibandingkan
/// dengan **terpakai saja** (D-17: setoran tujuan tidak memakan budget).
class CategoryBudgetStatus {
  const CategoryBudgetStatus({
    required this.category,
    required this.limit,
    required this.spent,
  });

  final Category category;
  final double limit;

  /// Hanya kategori pengeluaran yang punya budget (D-34).
  bool get isExpense => category.type == TransactionType.outFlow;

  /// Konsumsi (`type = out`) kategori ini pada bulan berjalan.
  final double spent;

  double get ratio => limit <= 0 ? 0 : spent / limit;

  bool get hasBudget => isExpense && limit > 0;

  BudgetLevel get level {
    if (!hasBudget) return BudgetLevel.aman;
    if (ratio >= 1) return BudgetLevel.lewat;
    if (ratio >= 0.8) return BudgetLevel.waspada;
    return BudgetLevel.aman;
  }

  /// Selalu teks persen + panah (UX-01: warna tidak boleh jadi satu-satunya
  /// penanda). D-11 mengunci arti panah: ▲ = masuk, ▼ = keluar. Baris budget
  /// adalah kategori pengeluaran, jadi panahnya selalu ▼; tingkat bahaya
  /// ditulis sebagai teks ("mendekati batas"/"melewati batas") + warna.
  String get percentLabel {
    if (!isExpense) return 'tanpa budget';
    if (!hasBudget) return 'belum ada budget';
    final pct = (ratio * 100).round();
    return '$pct% ▼';
  }

  String get levelLabel => !isExpense
      ? 'masuk · tanpa budget'
      : switch (level) {
          BudgetLevel.aman => 'aman',
          BudgetLevel.waspada => 'mendekati batas',
          BudgetLevel.lewat => 'melewati batas',
        };

  String get spentLabel => '${rupiah(spent)} / ${rupiah(limit)}';
}

/// F7 — kategori & budget bulanan. Semua tulisan admin saja; perhitungan
/// "terpakai" memakai [ReportService] keranjang `terpakai` sehingga setoran
/// tujuan tidak pernah ikut (D-17).
class BudgetRepository {
  BudgetRepository(this._db, this._reports);

  final AppDatabase _db;
  final ReportService _reports;

  Future<List<CategoryBudgetStatus>> status(
    AccessPolicy policy,
    String monthKey, {
    bool includeInactive = false,
  }) async {
    final month = DateTime.parse('$monthKey-01');
    final categoriesQuery = _db.select(_db.categories)
      ..orderBy([(c) => OrderingTerm.asc(c.name)]);
    if (!includeInactive) {
      categoriesQuery.where((c) => c.isActive.equals(true));
    }
    final categories = await categoriesQuery.get();
    final limits = await (_db.select(_db.budgets)
          ..where(
            (b) =>
                b.month.equals(monthKey) & b.type.equals(BudgetType.limit),
          ))
        .get();
    final limitByCategory = {
      for (final b in limits) b.categoryId: b.limitAmount,
    };

    // Hanya keranjang `terpakai` — bukan out + goal_deposit.
    final rows = await _reports.listBasket(policy, month, Basket.terpakai);
    final spentByCategory = <String, double>{};
    for (final t in rows) {
      final key = t.categoryId ?? '';
      spentByCategory[key] = (spentByCategory[key] ?? 0) + t.amount;
    }

    return [
      for (final c in categories)
        CategoryBudgetStatus(
          category: c,
          limit: c.type == TransactionType.outFlow
              ? (limitByCategory[c.id] ?? 0)
              : 0,
          // Kategori masuk tidak punya budget; angka "terpakai" tetap 0
          // karena keranjang terpakai hanya berisi `out`.
          spent: spentByCategory[c.id] ?? 0,
        ),
    ];
  }

  // -------------------------------------------------------------------------
  // Kategori (F7): tambah / ubah / nonaktifkan — admin saja.
  // -------------------------------------------------------------------------

  Future<String> createCategory({
    required AccessPolicy policy,
    required String name,
    required String type,
    String icon = '',
  }) async {
    _requireAdmin(policy);
    if (name.trim().isEmpty) {
      throw AllocationRuleViolation('Nama kategori wajib diisi');
    }
    if (type != TransactionType.inFlow && type != TransactionType.outFlow) {
      throw AllocationRuleViolation('Tipe kategori harus in atau out');
    }
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db.into(_db.categories).insert(
            CategoriesCompanion.insert(
              id: id,
              name: name.trim(),
              type: type,
              icon: Value(icon),
              isActive: const Value(true),
              updatedAt: Value(now),
            ),
          );
      final saved =
          await (_db.select(_db.categories)..where((c) => c.id.equals(id)))
              .getSingle();
      await _db.enqueueSync(
        tableName: 'categories',
        rowId: id,
        action: SyncOp.create,
        payload: categoryToMap(saved),
      );
    });
    return id;
  }

  Future<void> updateCategory({
    required AccessPolicy policy,
    required String id,
    String? name,
    String? icon,
    bool? isActive,
  }) async {
    _requireAdmin(policy);
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      final existing =
          await (_db.select(_db.categories)..where((c) => c.id.equals(id)))
              .getSingleOrNull();
      if (existing == null) {
        throw AllocationRuleViolation('Kategori tidak ditemukan');
      }
      await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          name: name == null ? const Value.absent() : Value(name.trim()),
          icon: icon == null ? const Value.absent() : Value(icon),
          isActive: isActive == null ? const Value.absent() : Value(isActive),
          updatedAt: Value(now),
        ),
      );
      final saved =
          await (_db.select(_db.categories)..where((c) => c.id.equals(id)))
              .getSingle();
      await _db.enqueueSync(
        tableName: 'categories',
        rowId: id,
        action: SyncOp.update,
        payload: categoryToMap(saved),
      );
    });
  }

  /// Nonaktifkan = soft delete kategori (`is_active = false`), bukan hapus
  /// baris (D-04). Transaksi lama tetap menunjuk kategori ini.
  Future<void> deactivateCategory({
    required AccessPolicy policy,
    required String id,
  }) async {
    _requireAdmin(policy);
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          isActive: const Value(false),
          updatedAt: Value(now),
        ),
      );
      await _db.enqueueSync(
        tableName: 'categories',
        rowId: id,
        // Server memakai endpoint `category.deactivate` untuk op ini.
        action: SyncOp.delete,
        payload: {'id': id},
      );
    });
  }

  void _requireAdmin(AccessPolicy policy) {
    final decision = policy.canManageCategories();
    if (!decision.allowed) {
      throw AllocationRuleViolation(decision.reason!);
    }
  }

}

/// Format rupiah ringkas tanpa bergantung pada lapisan UI.
String rupiah(double value) {
  final rounded = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < rounded.length; i++) {
    if (i > 0 && (rounded.length - i) % 3 == 0) buffer.write('.');
    buffer.write(rounded[i]);
  }
  return 'Rp $buffer';
}
