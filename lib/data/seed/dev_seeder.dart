import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

/// Data uji Q-07: 200 transaksi supaya QA bisa mengukur pencarian <1 detik.
/// Deterministik (seed tetap) agar hasil uji bisa diulang.
class DevSeeder {
  DevSeeder(this._db);

  final AppDatabase _db;

  static const int defaultCount = 200;

  /// Mengisi [count] transaksi tersebar di 3 bulan terakhir + beberapa setoran
  /// tujuan. Mengembalikan jumlah baris yang dibuat (0 bila sudah ada data).
  Future<int> seedTransactions({int count = defaultCount}) async {
    final existing = await _db.select(_db.transactions).get();
    if (existing.isNotEmpty) return 0;

    await _db.seedDefaultCategories();
    final categories = await _db.select(_db.categories).get();
    final outCats = categories
        .where((c) => c.type == TransactionType.outFlow)
        .toList();
    final inCat = categories.firstWhere(
      (c) => c.type == TransactionType.inFlow,
      orElse: () => categories.first,
    );

    const merchants = [
      'GoFood', 'Indomaret', 'Alfamart', 'Grab', 'Pertamina',
      'Tokopedia', 'Shopee', 'Apotek K-24', 'PLN', 'Telkomsel',
      'Warteg Bahari', 'Kopi Kenangan', 'Bioskop XXI', 'SPP Sekolah',
    ];
    const members = ['bapak@example.com', 'ibu@example.com', 'anak@example.com'];
    const sources = [
      TransactionSource.manual,
      TransactionSource.notif,
      TransactionSource.ocr,
    ];

    final now = DateTime.now();
    final rows = <TransactionsCompanion>[];
    for (var i = 0; i < count; i++) {
      final dayOffset = (i * 7) % 90;
      final date = now.subtract(Duration(days: dayOffset, minutes: i % 60));
      final isIncome = i % 17 == 0;
      final member = members[i % members.length];
      final amount = isIncome
          ? 500000.0 + (i % 5) * 250000
          : 5000.0 + ((i * 1300) % 200) * 250;
      rows.add(
        TransactionsCompanion.insert(
          id: const Uuid().v4(),
          date: date.toUtc(),
          type: isIncome ? TransactionType.inFlow : TransactionType.outFlow,
          amount: amount,
          memberEmail: member,
          source: sources[i % sources.length],
          categoryId: Value(isIncome ? inCat.id : outCats[i % outCats.length].id),
          merchant: Value(merchants[i % merchants.length]),
          note: Value('Data uji #$i'),
          createdAt: date.toUtc(),
          updatedAt: date.toUtc(),
        ),
      );
    }

    await _db.batch((b) => b.insertAll(_db.transactions, rows));
    return rows.length;
  }
}
