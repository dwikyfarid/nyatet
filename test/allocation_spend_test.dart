import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/ui/format.dart';

/// F7: layar alokasi harus menyebut terpakai, alokasi, persen, dan tidak
/// membagi nol untuk kategori tanpa alokasi.
void main() {
  test('F7: kategori tanpa belanja tampil Rp 0, bukan kosong', () {
    expect(
      allocationSpendLabel(0, 1000000),
      'Terpakai Rp 0 dari Rp 1.000.000 (0%)',
    );
  });

  test('F7: terpakai dari alokasi menampilkan persen', () {
    expect(
      allocationSpendLabel(405000, 400000),
      'Terpakai Rp 405.000 dari Rp 400.000 (101%)',
    );
    expect(allocationSpendLabel(500000, 1000000), contains('(50%)'));
  });

  test('F7: alokasi 0 tidak membagi nol dan tidak menghasilkan NaN', () {
    final label = allocationSpendLabel(250000, 0);
    expect(label, contains('belum ada alokasi'));
    expect(label, isNot(contains('NaN')));
    expect(allocationRatio(250000, 0), 0);
  });

  test('F7: rasio bar dibatasi 0..1', () {
    expect(allocationRatio(0, 1000), 0);
    expect(allocationRatio(500, 1000), 0.5);
    expect(allocationRatio(2000, 1000), 1);
  });
}
