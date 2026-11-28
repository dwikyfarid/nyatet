/// F18: nomor transaksi buatan aplikasi — `NYT-YYMMDD-NNN`.
/// Berbeda tegas dari No. referensi bank (`ref_no`, boleh kosong).
String txnNumberDayKey(DateTime date) {
  final local = date.toLocal();
  final yy = (local.year % 100).toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  return '$yy$mm$dd';
}

String formatTxnNumber(DateTime date, int sequence) {
  final number = sequence < 1000
      ? sequence.toString().padLeft(3, '0')
      : sequence.toString();
  return 'NYT-${txnNumberDayKey(date)}-$number';
}
