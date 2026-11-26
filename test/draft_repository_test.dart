import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/data/repository/draft_repository.dart';
import 'package:nyatet/data/repository/transaction_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late TransactionRepository txs;
  late DraftRepository drafts;

  setUp(() {
    db = AppDatabase.memory();
    txs = TransactionRepository(db);
    drafts = DraftRepository(db, txs);
  });

  tearDown(() => db.close());

  test('draf dummy termuat dan antrean punya draf menunggu', () async {
    await drafts.seedDummyDrafts();
    final all = await drafts.listQueue();
    final pending = await drafts.listPending();
    expect(all, hasLength(4));
    expect(pending, hasLength(4));
    // Seed idempoten: dipanggil dua kali tidak menggandakan.
    await drafts.seedDummyDrafts();
    expect(await drafts.listQueue(), hasLength(4));
  });

  test('Simpan 1 tap: draf jadi transaksi source=notif dan keluar antrean',
      () async {
    await drafts.seedDummyDrafts();
    final draft = (await drafts.listPending())
        .firstWhere((d) => d.merchant == 'GoFood');

    final txnId = await drafts.save(draft.id, memberEmail: 'anak@example.com');
    expect(txnId, isNotNull);

    final txn = await db.transactionById(txnId!);
    expect(txn, isNotNull);
    expect(txn!.source, TransactionSource.notif);
    expect(txn.amount, 25000);
    expect(txn.memberEmail, 'anak@example.com');
    expect(txn.merchant, 'GoFood');

    final pending = await drafts.listPending();
    expect(pending.any((d) => d.id == draft.id), isFalse);
    final saved = (await drafts.listQueue()).firstWhere((d) => d.id == draft.id);
    expect(saved.status, DraftStatus.saved);
    expect(saved.savedTxnId, txnId);
  });

  test('draf tersimpan tetap masuk sync_queue (offline-first)', () async {
    await drafts.addRaw(
      bankGroup: 'bca',
      packageName: 'com.bca',
      amount: 45800,
      type: TransactionType.outFlow,
      merchant: 'Transportation',
      occurredAt: DateTime.utc(2026, 11, 25, 10),
    );
    final draft = (await drafts.listPending()).single;
    await drafts.save(draft.id, memberEmail: 'bapak@example.com');
    expect(await db.pendingSyncBatch(), hasLength(1));
  });

  test('Abaikan: draf tidak menjadi transaksi tetapi tetap tercatat', () async {
    await drafts.seedDummyDrafts();
    final draft = (await drafts.listPending()).first;
    final before = await txs.listActive();

    await drafts.ignore(draft.id);

    expect(await txs.listActive(), hasLength(before.length));
    final after = (await drafts.listQueue()).firstWhere((d) => d.id == draft.id);
    expect(after.status, DraftStatus.ignored);
    final pending = await drafts.listPending();
    expect(pending.any((d) => d.id == draft.id), isFalse);
  });

  test('Ubah kategori draf tersimpan di draf dan ikut ke transaksi', () async {
    await drafts.seedDummyDrafts();
    final draft = (await drafts.listPending()).first;

    await drafts.setCategory(draft.id, 'cat-makan');
    final updated = (await drafts.listQueue()).firstWhere((d) => d.id == draft.id);
    expect(updated.categoryId, 'cat-makan');

    final txnId = await drafts.save(draft.id, memberEmail: 'bapak@example.com');
    final txn = await db.transactionById(txnId!);
    expect(txn!.categoryId, 'cat-makan');
  });

  test('Transfer antar-rekening: type jadi transfer, bukan masuk/keluar',
      () async {
    await drafts.seedDummyDrafts();
    final draft = (await drafts.listPending())
        .firstWhere((d) => d.type == TransactionType.outFlow);

    await drafts.markAsTransfer(draft.id);
    final updated = (await drafts.listQueue()).firstWhere((d) => d.id == draft.id);
    expect(updated.type, TransactionType.transfer);

    final txnId = await drafts.save(draft.id, memberEmail: 'bapak@example.com');
    final txn = await db.transactionById(txnId!);
    // D-17: transfer tidak masuk keranjang masuk maupun terpakai.
    expect(txn!.type, TransactionType.transfer);
    expect(txn.type == TransactionType.outFlow, isFalse);
    expect(txn.type == TransactionType.inFlow, isFalse);
  });

  test('Draf tanpa merchant disimpan memakai raw_text dan catatan bank',
      () async {
    await drafts.seedDummyDrafts();
    final draft = (await drafts.listPending())
        .firstWhere((d) => d.merchant == null);

    final txnId = await drafts.save(draft.id, memberEmail: 'bapak@example.com');
    final txn = await db.transactionById(txnId!);
    expect(txn!.rawText, contains('Notifikasi tidak dikenali'));
    expect(txn.note, contains('DANA'));
  });

  test('Draf duplikat tidak hilang dan bisa dipulihkan (D-12)', () async {
    await drafts.seedDummyDrafts();
    final list = await drafts.listPending();
    final original = list.first;
    final dup = list.last;

    await drafts.markDuplicate(dup.id, originalId: original.id);
    final marked = (await drafts.listQueue()).firstWhere((d) => d.id == dup.id);
    expect(marked.status, DraftStatus.duplicate);
    expect(marked.duplicateOfId, original.id);

    await drafts.restoreDuplicate(dup.id);
    final restored = (await drafts.listQueue()).firstWhere((d) => d.id == dup.id);
    expect(restored.status, DraftStatus.pending);
  });

  test('Simpan draf yang sudah diabaikan tidak membuat transaksi', () async {
    await drafts.seedDummyDrafts();
    final draft = (await drafts.listPending()).first;
    await drafts.ignore(draft.id);

    final txnId = await drafts.save(draft.id, memberEmail: 'bapak@example.com');
    expect(txnId, isNull);
  });
}
