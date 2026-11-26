import 'package:drift/drift.dart';

import '../data/database/app_database.dart';
import 'access_policy.dart';

/// Keranjang angka D-17. Uang keluar **tidak** dijumlah jadi satu.
enum Basket { masuk, terpakai, disisihkan, transfer }

extension BasketLabel on Basket {
  String get label => switch (this) {
        Basket.masuk => 'Masuk',
        Basket.terpakai => 'Terpakai',
        Basket.disisihkan => 'Disisihkan',
        Basket.transfer => 'Transfer',
      };

  /// Tipe transaksi yang masuk keranjang ini.
  List<String> get types => switch (this) {
        Basket.masuk =>
          [TransactionType.inFlow, TransactionType.goalWithdrawal],
        Basket.terpakai => [TransactionType.outFlow],
        Basket.disisihkan => [TransactionType.goalDeposit],
        Basket.transfer => [TransactionType.transfer],
      };
}

/// Neraca kas satu bulan. `sisaKas` dihitung dari tiga keranjang terpisah,
/// bukan dari jumlah `out + goal_deposit` (D-17).
class CashSummary {
  const CashSummary({
    required this.masuk,
    required this.terpakai,
    required this.disisihkan,
  });

  /// `in` + `goal_withdrawal`.
  final double masuk;

  /// `out` saja — satu-satunya angka yang boleh dilabeli pengeluaran.
  final double terpakai;

  /// Setoran tujuan (`goal_deposit`) — aset, bukan biaya.
  final double disisihkan;

  double get sisaKas => masuk - terpakai - disisihkan;

  double get totalAlokasiTersedia => masuk;

  static const CashSummary empty =
      CashSummary(masuk: 0, terpakai: 0, disisihkan: 0);
}

/// Total satu grup pada drill-down (kategori / anggota).
class GroupTotal {
  const GroupTotal({
    required this.id,
    required this.label,
    required this.total,
    required this.count,
  });

  final String id;
  final String label;
  final double total;
  final int count;
}

/// Laporan F8/F10 yang dihitung dari database lokal, sehingga cockpit dan
/// drill-down tetap jalan offline (D-16: total atas = jumlah baris di bawah).
class ReportService {
  ReportService(this._db);

  final AppDatabase _db;

  /// `2026-11`
  static String monthKey(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}';
  }

  static DateTime monthStart(DateTime any) {
    final local = any.toLocal();
    return DateTime(local.year, local.month);
  }

  static DateTime nextMonthStart(DateTime any) {
    final start = monthStart(any);
    return DateTime(start.year, start.month + 1);
  }

  SimpleSelectStatement<$TransactionsTable, Transaction> _base(
    AccessPolicy policy,
    DateTime month,
    Basket? basket,
  ) {
    final start = monthStart(month).toUtc();
    final end = nextMonthStart(month).toUtc();
    final q = _db.select(_db.transactions)
      ..where(
        (t) =>
            t.isDeleted.equals(false) &
            t.date.isBiggerOrEqualValue(start) &
            t.date.isSmallerThanValue(end),
      );
    if (!policy.isAdmin) {
      q.where((t) => t.memberEmail.equals(policy.email));
    }
    if (basket != null) {
      q.where((t) => t.type.isIn(basket.types));
    }
    return q;
  }

  Future<CashSummary> summary(AccessPolicy policy, DateTime month) async {
    final rows = await _base(policy, month, null).get();
    var masuk = 0.0;
    var terpakai = 0.0;
    var disisihkan = 0.0;
    for (final t in rows) {
      switch (t.type) {
        case TransactionType.inFlow:
        case TransactionType.goalWithdrawal:
          masuk += t.amount;
        case TransactionType.outFlow:
          terpakai += t.amount;
        case TransactionType.goalDeposit:
          disisihkan += t.amount;
        default:
          // transfer tidak masuk keranjang mana pun
          break;
      }
    }
    return CashSummary(
      masuk: masuk,
      terpakai: terpakai,
      disisihkan: disisihkan,
    );
  }

  /// Daftar transaksi penyusun satu angka (level 3.2 drill-down).
  Future<List<Transaction>> listBasket(
    AccessPolicy policy,
    DateTime month,
    Basket basket, {
    String? categoryId,
    String? memberEmail,
  }) {
    final q = _base(policy, month, basket);
    if (categoryId != null) {
      q.where((t) => t.categoryId.equals(categoryId));
    }
    if (memberEmail != null) {
      q.where((t) => t.memberEmail.equals(memberEmail));
    }
    q.orderBy([(t) => OrderingTerm.desc(t.date)]);
    return q.get();
  }

  /// Rincian per kategori pada satu keranjang.
  Future<List<GroupTotal>> byCategory(
    AccessPolicy policy,
    DateTime month,
    Basket basket,
  ) async {
    final rows = await listBasket(policy, month, basket);
    final categories = await _db.select(_db.categories).get();
    final names = {for (final c in categories) c.id: c.name};
    final sums = <String, ({double total, int count})>{};
    for (final t in rows) {
      final key = t.categoryId ?? '';
      final prev = sums[key] ?? (total: 0.0, count: 0);
      sums[key] = (total: prev.total + t.amount, count: prev.count + 1);
    }
    final out = sums.entries
        .map(
          (e) => GroupTotal(
            id: e.key,
            label: e.key.isEmpty
                ? 'Tanpa kategori'
                : (names[e.key] ?? e.key),
            total: e.value.total,
            count: e.value.count,
          ),
        )
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return out;
  }

  /// Rincian per anggota pada satu keranjang.
  Future<List<GroupTotal>> byMember(
    AccessPolicy policy,
    DateTime month,
    Basket basket,
  ) async {
    final rows = await listBasket(policy, month, basket);
    final sums = <String, ({double total, int count})>{};
    for (final t in rows) {
      final prev = sums[t.memberEmail] ?? (total: 0.0, count: 0);
      sums[t.memberEmail] = (
        total: prev.total + t.amount,
        count: prev.count + 1,
      );
    }
    final out = sums.entries
        .map(
          (e) => GroupTotal(
            id: e.key,
            label: e.key,
            total: e.value.total,
            count: e.value.count,
          ),
        )
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return out;
  }

  /// Total alokasi kategori bulan itu (F10, dari tab budgets `type=allocation`).
  Future<double> totalAllocation(String monthKey) async {
    final rows = await (_db.select(_db.budgets)
          ..where(
            (b) =>
                b.month.equals(monthKey) &
                b.type.equals(BudgetType.allocation),
          ))
        .get();
    return rows.fold<double>(0, (sum, b) => sum + b.allocatedAmount);
  }

  /// "Belum dialokasikan" = pemasukan bulan − total alokasi (D-15).
  Future<double> unallocated(AccessPolicy policy, DateTime month) async {
    final s = await summary(policy, month);
    final alloc = await totalAllocation(monthKey(month));
    return s.masuk - alloc;
  }
}
