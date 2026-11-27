import 'package:drift/drift.dart';

import '../data/database/app_database.dart';
import '../data/repository/transaction_repository.dart';
import 'access_policy.dart';

/// Dilempar saat UI mencoba aksi yang tidak diizinkan role. Pesannya sudah
/// siap ditampilkan ke user.
class AccessDenied implements Exception {
  AccessDenied(this.reason);
  final String reason;

  @override
  String toString() => reason;
}

/// Lapisan use-case F6: membaca & mengubah transaksi dengan hak akses D-03
/// ditegakkan di satu tempat (bukan tersebar di widget).
class TransactionService {
  TransactionService(this._db, this._repo);

  final AppDatabase _db;
  final TransactionRepository _repo;

  /// Daftar transaksi yang boleh dilihat [policy], dengan pencarian teks
  /// (UX-03: cari + scroll, 200 transaksi tetap <1 detik karena difilter di
  /// query SQL, bukan di widget).
  Future<List<Transaction>> listVisible(
    AccessPolicy policy, {
    String query = '',
  }) async {
    final q = _db.select(_db.transactions)
      ..where((t) => t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.date)]);

    // Anggota hanya melihat transaksinya sendiri (D-03).
    if (!policy.isAdmin) {
      q.where((t) => t.memberEmail.equals(policy.email));
    }

    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      final like = '%${trimmed.toLowerCase()}%';
      q.where(
        (t) =>
            t.merchant.lower().like(like) |
            t.note.lower().like(like) |
            t.account.lower().like(like) |
            t.memberEmail.lower().like(like),
      );
    }
    return q.get();
  }

  Future<Transaction?> byId(String id) => _db.transactionById(id);

  Future<String> createManual({
    required AccessPolicy policy,
    required DateTime date,
    required String type,
    required double amount,
    String? categoryId,
    String? memberEmail,
    String? note,
    String? merchant,
    String? refNo,
  }) async {
    final decision = policy.canCreate();
    if (!decision.allowed) throw AccessDenied(decision.reason!);
    if (amount <= 0) {
      throw AccessDenied('Nominal harus lebih dari nol');
    }
    // Admin boleh mencatat atas nama anggota; anggota selalu atas namanya.
    final owner = policy.isAdmin ? (memberEmail ?? policy.email) : policy.email;
    return _repo.create(
      date: date,
      type: type,
      amount: amount,
      memberEmail: owner,
      source: TransactionSource.manual,
      categoryId: categoryId,
      note: note,
      merchant: merchant,
    );
  }

  Future<void> updateManual({
    required AccessPolicy policy,
    required Transaction txn,
    required DateTime date,
    required String type,
    required double amount,
    String? categoryId,
    String? note,
    String? refNo,
  }) async {
    final decision = policy.canEdit(txn);
    if (!decision.allowed) throw AccessDenied(decision.reason!);
    if (amount <= 0) {
      throw AccessDenied('Nominal harus lebih dari nol');
    }
    await _repo.update(
      id: txn.id,
      actorEmail: policy.email,
      date: date,
      type: type,
      amount: amount,
      source: txn.source,
      categoryId: categoryId,
      account: txn.account,
      merchant: txn.merchant,
      note: note,
      receiptUrl: txn.receiptUrl,
      rawText: txn.rawText,
      goalId: txn.goalId,
    );
  }

  /// Soft delete hanya untuk admin (D-03, D-04).
  Future<void> delete({required AccessPolicy policy, required Transaction txn}) async {
    final decision = policy.canDelete(txn);
    if (!decision.allowed) throw AccessDenied(decision.reason!);
    await _repo.softDelete(txn.id, policy.email);
  }
}
