import '../data/database/app_database.dart';

/// F15/D-50: urutan transaksi dengan label teks (bukan ikon).
enum TxSort {
  dateDesc('Tanggal terbaru'),
  amountDesc('Nominal'),
  merchantAsc('Merchant A–Z');

  const TxSort(this.label);
  final String label;
}

/// Filter transaksi milik layar L3, diterapkan dari data lokal.
List<Transaction> applyTransactionFilters(
  List<Transaction> rows, {
  String? type,
  String? source,
  String? categoryId,
  String? memberEmail,
  TxSort sort = TxSort.dateDesc,
}) {
  final filtered = rows.where((t) {
    if (type != null && t.type != type) return false;
    if (source != null && t.source != source) return false;
    if (categoryId != null && t.categoryId != categoryId) return false;
    if (memberEmail != null && t.memberEmail != memberEmail) return false;
    return true;
  }).toList();

  switch (sort) {
    case TxSort.dateDesc:
      filtered.sort((a, b) => b.date.compareTo(a.date));
    case TxSort.amountDesc:
      filtered.sort((a, b) => b.amount.compareTo(a.amount));
    case TxSort.merchantAsc:
      filtered.sort(
        (a, b) => (a.merchant ?? '').toLowerCase().compareTo(
              (b.merchant ?? '').toLowerCase(),
            ),
      );
  }
  return filtered;
}
