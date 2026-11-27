import 'package:flutter/services.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// `Rp 1.250.000` — pemisah ribuan titik, tanpa desimal bila bulat.
String formatRupiah(num value) {
  final negative = value < 0;
  final abs = value.abs();
  final isWhole = abs == abs.roundToDouble();
  final text = isWhole ? abs.round().toString() : abs.toStringAsFixed(2);
  final parts = text.split('.');
  final digits = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  final decimals = parts.length > 1 ? ',${parts[1]}' : '';
  return '${negative ? '-' : ''}Rp $buffer$decimals';
}

/// `26 Nov 2026 14:00` — 24 jam (aturan tampilan PRD).
String formatTanggalWaktu(DateTime dt) {
  final local = dt.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final m = _months[local.month - 1];
  final y = local.year;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$d $m $y $hh:$mm';
}

String formatTanggal(DateTime dt) {
  final local = dt.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  return '$d ${_months[local.month - 1]} ${local.year}';
}

/// Label arah transaksi untuk tampilan.
String labelTipe(String type) {
  switch (type) {
    case 'in':
      return 'Masuk';
    case 'out':
      return 'Keluar';
    case 'transfer':
      return 'Transfer';
    case 'goal_deposit':
      return 'Setoran tujuan';
    case 'goal_withdrawal':
      return 'Penarikan tujuan';
    default:
      return type;
  }
}

/// Input mask Rupiah (UX-04): hanya digit, otomatis diberi titik ribuan.
class RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue();
    }
    final number = int.parse(digits);
    final formatted = formatRupiah(number).replaceFirst('Rp ', '');
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// `45.800` → 45800
double parseRupiah(String text) {
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 0;
  return double.parse(digits);
}

/// D-33: transaksi anggota terhapus tetap ada, pemiliknya ditampilkan jujur.
String memberLabel(String email) {
  if (email.startsWith('deleted:')) return 'Anggota dihapus';
  if (email.trim().isEmpty) return 'Tanpa anggota';
  return email;
}
