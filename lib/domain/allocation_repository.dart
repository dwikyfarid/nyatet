import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../data/database/app_database.dart';
import '../data/repository/transaction_repository.dart';
import 'access_policy.dart';
import 'report_service.dart';

/// Pelanggaran aturan alokasi/tujuan. Pesannya siap ditampilkan ke user.
class AllocationRuleViolation implements Exception {
  AllocationRuleViolation(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Progres satu tujuan dana. Status selalu eksplisit, bukan hanya warna.
class GoalProgress {
  const GoalProgress({
    required this.goal,
    required this.collected,
    required this.monthlyAllocation,
  });

  final Goal goal;
  final double collected;
  final double monthlyAllocation;

  double get ratio =>
      goal.targetAmount <= 0 ? 0 : (collected / goal.targetAmount).clamp(0, 1);

  bool get achieved => collected >= goal.targetAmount;

  /// Kurang berapa untuk mencapai target.
  double get remaining =>
      (goal.targetAmount - collected).clamp(0, double.infinity);

  /// Bulan yang dibutuhkan bila menyisihkan `monthlyAllocation` per bulan.
  int? get monthsToTarget {
    if (monthlyAllocation <= 0) return null;
    return (remaining / monthlyAllocation).ceil();
  }

  /// Status eksplisit untuk ditulis di kartu tujuan (UX-01: bukan cuma warna).
  String get statusLabel {
    if (achieved) return 'tercapai';
    final months = monthsToTarget;
    if (months == null) {
      return 'kurang Rp ${_rp(remaining)}';
    }
    return 'on-track — ${months}x setoran lagi';
  }

  static String _rp(double v) {
    final rounded = v.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < rounded.length; i++) {
      if (i > 0 && (rounded.length - i) % 3 == 0) buffer.write('.');
      buffer.write(rounded[i]);
    }
    return buffer.toString();
  }
}

/// F10 — alokasi dana per kategori + tujuan dana, termasuk aturan validasi
/// (D-15) dan setoran tujuan yang tercatat sebagai transaksi (D-20).
class AllocationRepository {
  AllocationRepository(this._db, this._transactions, this._reports);

  final AppDatabase _db;
  final TransactionRepository _transactions;
  final ReportService _reports;

  // ---------------------------------------------------------------------
  // Alokasi per kategori per bulan
  // ---------------------------------------------------------------------

  Future<List<Budget>> allocationsFor(String monthKey) {
    return (_db.select(_db.budgets)
          ..where(
            (b) =>
                b.month.equals(monthKey) & b.type.equals(BudgetType.allocation),
          ))
        .get();
  }

  /// Simpan alokasi satu kategori. Aturan:
  /// - hanya admin (D-03),
  /// - alokasi ≤ budget bila budget kategori itu diisi,
  /// - total alokasi ≤ pemasukan bulan itu; bila pemasukan belum tercatat,
  ///   alokasi boleh disimpan sebagai **rencana** (dikembalikan `planned=true`).
  Future<({bool planned})> setAllocation({
    required AccessPolicy policy,
    required String monthKey,
    required String categoryId,
    required double amount,
  }) async {
    final decision = policy.canManageCategories();
    if (!decision.allowed) throw AllocationRuleViolation(decision.reason!);
    if (amount < 0) {
      throw AllocationRuleViolation('Alokasi tidak boleh negatif');
    }

    final limitRow = await (_db.select(_db.budgets)
          ..where(
            (b) =>
                b.month.equals(monthKey) &
                b.categoryId.equals(categoryId) &
                b.type.equals(BudgetType.limit),
          ))
        .getSingleOrNull();
    if (limitRow != null && amount > limitRow.limitAmount) {
      throw AllocationRuleViolation(
        'Alokasi melebihi budget kategori ini '
        '(batas Rp ${GoalProgress._rp(limitRow.limitAmount)})',
      );
    }

    final month = _monthFromKey(monthKey);
    final income = (await _reports.summary(policy, month)).masuk;
    final existing = await allocationsFor(monthKey);
    final otherTotal = existing
        .where((b) => b.categoryId != categoryId)
        .fold<double>(0, (sum, b) => sum + b.allocatedAmount);
    final planned = income <= 0;
    if (!planned && income - otherTotal - amount < 0) {
      final overflow = GoalProgress._rp((otherTotal + amount) - income);
      throw AllocationRuleViolation(
        'Alokasi lebih Rp $overflow dari pemasukan',
      );
    }

    final current = existing
        .where((b) => b.categoryId == categoryId)
        .toList();
    if (current.isEmpty) {
      await _db.into(_db.budgets).insert(
            BudgetsCompanion.insert(
              id: const Uuid().v4(),
              month: monthKey,
              categoryId: categoryId,
              type: const Value(BudgetType.allocation),
              allocatedAmount: Value(amount),
            ),
          );
    } else {
      await (_db.update(_db.budgets)
            ..where((b) => b.id.equals(current.first.id)))
          .write(BudgetsCompanion(allocatedAmount: Value(amount)));
    }
    return (planned: planned);
  }

  /// Simpan batas (budget) satu kategori — dipakai F7, tetap admin saja.
  Future<void> setLimit({
    required AccessPolicy policy,
    required String monthKey,
    required String categoryId,
    required double amount,
  }) async {
    final decision = policy.canManageCategories();
    if (!decision.allowed) throw AllocationRuleViolation(decision.reason!);
    final existing = await (_db.select(_db.budgets)
          ..where(
            (b) =>
                b.month.equals(monthKey) &
                b.categoryId.equals(categoryId) &
                b.type.equals(BudgetType.limit),
          ))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.budgets).insert(
            BudgetsCompanion.insert(
              id: const Uuid().v4(),
              month: monthKey,
              categoryId: categoryId,
              type: const Value(BudgetType.limit),
              limitAmount: Value(amount),
            ),
          );
    } else {
      await (_db.update(_db.budgets)..where((b) => b.id.equals(existing.id)))
          .write(BudgetsCompanion(limitAmount: Value(amount)));
    }
  }

  // ---------------------------------------------------------------------
  // Tujuan dana
  // ---------------------------------------------------------------------

  Future<List<GoalProgress>> goalsWithProgress(AccessPolicy policy) async {
    final goals = await (_db.select(_db.goals)
          ..where((g) => g.isDeleted.equals(false))
          ..orderBy([(g) => OrderingTerm.asc(g.targetDate)]))
        .get();
    final result = <GoalProgress>[];
    for (final g in goals) {
      final deposits = await (_db.select(_db.transactions)
            ..where(
              (t) =>
                  t.goalId.equals(g.id) &
                  t.isDeleted.equals(false) &
                  (t.type.equals(TransactionType.goalDeposit) |
                      t.type.equals(TransactionType.goalWithdrawal)),
            ))
          .get();
      var collected = 0.0;
      for (final t in deposits) {
        collected += t.type == TransactionType.goalDeposit ? t.amount : -t.amount;
      }
      result.add(
        GoalProgress(
          goal: g,
          collected: collected,
          monthlyAllocation: g.monthlyAllocation,
        ),
      );
    }
    return result;
  }

  /// Buat tujuan — admin saja (D-20).
  Future<String> createGoal({
    required AccessPolicy policy,
    required String name,
    required double targetAmount,
    required double monthlyAllocation,
    DateTime? targetDate,
    String? categoryId,
  }) async {
    final decision = policy.canManageGoals();
    if (!decision.allowed) throw AllocationRuleViolation(decision.reason!);
    if (targetAmount <= 0) {
      throw AllocationRuleViolation('Target dana harus lebih dari nol');
    }
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    await _db.into(_db.goals).insert(
          GoalsCompanion.insert(
            id: id,
            name: name,
            targetAmount: targetAmount,
            targetDate: Value(targetDate),
            monthlyAllocation: monthlyAllocation,
            categoryId: Value(categoryId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  /// Setor ke tujuan: dicatat sebagai transaksi `goal_deposit` milik penyetor
  /// (D-20: anggota boleh), bukan sekadar angka.
  Future<String> deposit({
    required AccessPolicy policy,
    required String goalId,
    required double amount,
    DateTime? date,
  }) async {
    if (amount <= 0) {
      throw AllocationRuleViolation('Nominal setoran harus lebih dari nol');
    }
    final goal = await (_db.select(_db.goals)..where((g) => g.id.equals(goalId)))
        .getSingleOrNull();
    if (goal == null || goal.isDeleted) {
      throw AllocationRuleViolation('Tujuan tidak ditemukan');
    }
    return _transactions.create(
      date: date ?? DateTime.now(),
      type: TransactionType.goalDeposit,
      amount: amount,
      memberEmail: policy.email,
      source: TransactionSource.manual,
      goalId: goalId,
      note: 'Setoran tujuan ${goal.name}',
    );
  }

  /// Penarikan dari tujuan: menambah keranjang `masuk`, mengurangi progres.
  Future<String> withdraw({
    required AccessPolicy policy,
    required String goalId,
    required double amount,
    DateTime? date,
  }) async {
    if (amount <= 0) {
      throw AllocationRuleViolation('Nominal penarikan harus lebih dari nol');
    }
    return _transactions.create(
      date: date ?? DateTime.now(),
      type: TransactionType.goalWithdrawal,
      amount: amount,
      memberEmail: policy.email,
      source: TransactionSource.manual,
      goalId: goalId,
      note: 'Penarikan tujuan',
    );
  }

  static DateTime _monthFromKey(String key) {
    final parts = key.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]));
  }
}
