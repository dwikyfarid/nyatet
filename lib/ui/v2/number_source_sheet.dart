// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../format.dart';
import 'tokens.dart';

/// U1: sheet asal-usul angka. Judul `angka · periode`, nilai, kotak rumus
/// dengan angka sebenarnya, jumlah + rentang tanggal, 5 transaksi teratas,
/// dan tombol buka daftar dengan filter yang sama.
class NumberSourceData {
  const NumberSourceData({
    required this.title,
    required this.periodLabel,
    required this.value,
    required this.formulaLines,
    required this.count,
    required this.rangeLabel,
    required this.topRows,
    required this.onOpenTransactions,
  });

  final String title;
  final String periodLabel;
  final double value;

  /// Label + nominal, mis. ('Masuk', 12500000).
  final List<(String, double)> formulaLines;
  final int count;
  final String rangeLabel;

  /// Pasangan (judul baris, nominal) maksimal 5.
  final List<(String, double)> topRows;
  final VoidCallback onOpenTransactions;
}

Future<void> showNumberSourceSheet(
  BuildContext context,
  NumberSourceData data,
) {
  final t = NyatetTokens.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${data.title} · ${data.periodLabel}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              formatRupiah(data.value),
              style: TextStyle(
                fontSize: t.heroSize,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: t.divider),
                borderRadius: BorderRadius.circular(t.radius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in data.formulaLines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(line.$1),
                          Text(formatRupiah(line.$2)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${data.count} transaksi · ${data.rangeLabel}',
              style: TextStyle(fontSize: 12, color: t.label),
            ),
            const SizedBox(height: 8),
            for (final row in data.topRows.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(row.$1)),
                    Text(formatRupiah(row.$2)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  data.onOpenTransactions();
                },
                child: const Text('Buka di Transaksi'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
