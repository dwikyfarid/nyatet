// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/ui/v2/date_field.dart';
import 'package:nyatet/ui/v2/number_source_sheet.dart';
import 'package:nyatet/ui/v2/state_views.dart';
import 'package:nyatet/ui/v2/tokens.dart';

void main() {
  test('U1: token D-70 dipakai (amber #7A5200, primary, radius 16)', () {
    const t = NyatetTokens.light;
    expect(t.amberText, const Color(0xFF7A5200));
    expect(t.amberBg, const Color(0xFFFFEFCF));
    expect(t.primary, const Color(0xFF39579C));
    expect(t.controlLine, const Color(0xFF767680));
    expect(t.label, const Color(0xFF46464F));
    expect(t.radius, 16);
    // D-73: hanya tema terang.
    expect(NyatetTheme.light().brightness, Brightness.light);
  });

  testWidgets('U1: NumberSourceSheet menampilkan rumus, jumlah, dan aksi',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: NyatetTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showNumberSourceSheet(
                ctx,
                NumberSourceData(
                  title: 'Sisa kas',
                  periodLabel: 'Nov 2026',
                  value: 3450000,
                  formulaLines: const [
                    ('Masuk', 12500000),
                    ('Terpakai', -3125000),
                    ('Disisihkan', -5900000),
                  ],
                  count: 203,
                  rangeLabel: '1 Nov 2026 – 30 Nov 2026',
                  topRows: const [('Warung Bu Sri', 85000)],
                  onOpenTransactions: () => opened = true,
                ),
              ),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    expect(find.text('Sisa kas · Nov 2026'), findsOneWidget);
    expect(find.text('Rp 3.450.000'), findsOneWidget);
    expect(find.text('Masuk'), findsOneWidget);
    expect(find.text('203 transaksi · 1 Nov 2026 – 30 Nov 2026'), findsOneWidget);
    expect(find.text('Warung Bu Sri'), findsOneWidget);

    await tester.tap(find.text('Buka di Transaksi'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('U1: komponen tanggal bersama berlabel Semantics & ≥48dp',
      (tester) async {
    final handle = tester.ensureSemantics();
    DateTime picked = DateTime(2026, 11, 27);
    await tester.pumpWidget(
      MaterialApp(
        theme: NyatetTheme.light(),
        home: Scaffold(
          body: NyatetDateField(
            label: 'Tanggal transaksi',
            value: picked,
            onPicked: (v) => picked = v,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(RegExp('Tanggal transaksi: 27 Nov 2026')),
      findsWidgets,
    );
    final size = tester.getSize(find.byType(NyatetDateField));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(NyatetDateField.display(DateTime(2026, 11, 1), monthOnly: true),
        'Nov 2026 ▾');
    handle.dispose();
  });

  testWidgets('U1: papan state kosong/error/offline/skeleton tampil',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NyatetTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              const NyatetSkeletonCard(height: 96),
              NyatetEmptyState(title: 'Belum ada transaksi'),
              NyatetErrorSection(
                message: 'Gagal memuat bagian ini',
                onRetry: () {},
              ),
              const NyatetOfflineBanner(),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Belum ada transaksi'), findsOneWidget);
    expect(find.text('Gagal memuat bagian ini'), findsOneWidget);
    expect(find.textContaining('Offline'), findsOneWidget);
    expect(tester.getSize(find.byType(NyatetSkeletonCard)).height, 96);
  });
}
