import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'transaction_repository.dart';

/// Antrean draf notifikasi (F4). Draf hidup hanya di perangkat sampai user
/// menekan Simpan, jadi seluruh operasi di sini tetap jalan offline.
class DraftRepository {
  DraftRepository(this._db, this._transactions);

  final AppDatabase _db;
  final TransactionRepository _transactions;

  Future<List<TransactionDraft>> listQueue() {
    return (_db.select(_db.transactionDrafts)
          ..orderBy([(t) => OrderingTerm.desc(t.receivedAt)]))
        .get();
  }

  Stream<List<TransactionDraft>> watchQueue() {
    return (_db.select(_db.transactionDrafts)
          ..orderBy([(t) => OrderingTerm.desc(t.receivedAt)]))
        .watch();
  }

  /// Hanya draf yang masih menunggu keputusan user.
  Future<List<TransactionDraft>> listPending() {
    return (_db.select(_db.transactionDrafts)
          ..where((t) => t.status.equals(DraftStatus.pending))
          ..orderBy([(t) => OrderingTerm.desc(t.receivedAt)]))
        .get();
  }

  /// Simpan satu tap: draf menjadi transaksi `source = notif`.
  /// Mengembalikan id transaksi, atau null bila draf tidak bisa disimpan.
  Future<String?> save(
    String draftId, {
    required String memberEmail,
    String? categoryId,
  }) async {
    final draft = await _byId(draftId);
    if (draft == null || draft.status != DraftStatus.pending) return null;
    if (draft.merchant == null && draft.rawText == null) return null;

    final txnId = await _transactions.create(
      date: draft.occurredAt,
      type: draft.type,
      amount: draft.amount,
      memberEmail: memberEmail,
      source: TransactionSource.notif,
      categoryId: categoryId ?? draft.categoryId,
      merchant: draft.merchant,
      note: draft.merchant == null ? _fallbackNote(draft) : null,
      rawText: draft.rawText,
    );

    await (_db.update(_db.transactionDrafts)..where((t) => t.id.equals(draftId)))
        .write(
      TransactionDraftsCompanion(
        status: const Value(DraftStatus.saved),
        savedTxnId: Value(txnId),
        categoryId: Value(categoryId ?? draft.categoryId),
      ),
    );
    return txnId;
  }

  /// Abaikan: draf tidak menjadi transaksi, tetapi barisnya tetap ada agar
  /// keputusan user tidak hilang (mirip semangat D-04 di sisi draf).
  Future<void> ignore(String draftId) async {
    await (_db.update(_db.transactionDrafts)..where((t) => t.id.equals(draftId)))
        .write(const TransactionDraftsCompanion(
      status: Value(DraftStatus.ignored),
    ));
  }

  /// Tandai draf sebagai transfer antar-rekening sendiri: bukan masuk/keluar,
  /// jadi tidak dihitung di keranjang `masuk`/`terpakai` (D-17).
  Future<void> markAsTransfer(String draftId) async {
    await (_db.update(_db.transactionDrafts)..where((t) => t.id.equals(draftId)))
        .write(const TransactionDraftsCompanion(
      type: Value(TransactionType.transfer),
    ));
  }

  Future<void> setCategory(String draftId, String categoryId) async {
    await (_db.update(_db.transactionDrafts)..where((t) => t.id.equals(draftId)))
        .write(TransactionDraftsCompanion(categoryId: Value(categoryId)));
  }

  /// Draf duplikat (D-12) tidak hilang: ditandai `duplicate` + tetap di antrean.
  Future<void> markDuplicate(String draftId, {required String originalId}) async {
    await (_db.update(_db.transactionDrafts)..where((t) => t.id.equals(draftId)))
        .write(TransactionDraftsCompanion(
      status: const Value(DraftStatus.duplicate),
      duplicateOfId: Value(originalId),
    ));
  }

  /// Pulihkan draf yang salah ditandai duplikat.
  Future<void> restoreDuplicate(String draftId) async {
    await (_db.update(_db.transactionDrafts)..where((t) => t.id.equals(draftId)))
        .write(const TransactionDraftsCompanion(
      status: Value(DraftStatus.pending),
      duplicateOfId: Value(null),
    ));
  }

  Future<void> addRaw({
    required String bankGroup,
    required String packageName,
    required double amount,
    required String type,
    String? merchant,
    String? last4,
    required DateTime occurredAt,
    String? rawText,
    String? categoryId,
  }) async {
    await _db.into(_db.transactionDrafts).insert(
          TransactionDraftsCompanion.insert(
            id: const Uuid().v4(),
            bankGroup: bankGroup,
            packageName: packageName,
            amount: amount,
            type: type,
            merchant: Value(merchant),
            last4: Value(last4),
            occurredAt: occurredAt,
            rawText: Value(rawText),
            categoryId: Value(categoryId),
            receivedAt: DateTime.now().toUtc(),
          ),
        );
  }

  /// Data draf dummy untuk membangun & menguji F4 sebelum F3 (parsing
  /// notifikasi) tersedia. Aman dipanggil berulang: tidak menduplikasi.
  Future<void> seedDummyDrafts() async {
    final existing = await listQueue();
    if (existing.isNotEmpty) return;
    final now = DateTime.now().toUtc();
    await addRaw(
      bankGroup: 'bca',
      packageName: 'com.bca',
      amount: 45800,
      type: TransactionType.outFlow,
      merchant: 'Transportation',
      last4: '1234',
      occurredAt: now.subtract(const Duration(minutes: 3)),
      rawText: 'You spent IDR 45,800.00 at Transportation.',
    );
    await addRaw(
      bankGroup: 'gopay',
      packageName: 'com.gojek.app',
      amount: 25000,
      type: TransactionType.outFlow,
      merchant: 'GoFood',
      occurredAt: now.subtract(const Duration(minutes: 25)),
      rawText: 'Pembayaran GoPay Rp25.000 ke GoFood berhasil',
    );
    await addRaw(
      bankGroup: 'mandiri',
      packageName: 'id.bmri.livin',
      amount: 1500000,
      type: TransactionType.inFlow,
      merchant: 'Transfer masuk',
      last4: '8899',
      occurredAt: now.subtract(const Duration(hours: 2)),
      rawText: 'Dana masuk Rp1.500.000 dari BUDI',
    );
    await addRaw(
      bankGroup: 'dana',
      packageName: 'id.dana',
      amount: 75000,
      type: TransactionType.outFlow,
      occurredAt: now.subtract(const Duration(hours: 5)),
      rawText: 'Notifikasi tidak dikenali #A91F',
    );
  }

  Future<TransactionDraft?> _byId(String id) =>
      (_db.select(_db.transactionDrafts)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  String _fallbackNote(TransactionDraft d) {
    final last4 = d.last4 == null ? '' : ' ••••${d.last4}';
    return '${d.bankGroup.toUpperCase()}$last4';
  }
}
