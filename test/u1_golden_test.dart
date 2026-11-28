// ignore_for_file: deprecated_member_use
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/ui/v2/date_field.dart';
import 'package:nyatet/ui/v2/state_views.dart';
import 'package:nyatet/ui/v2/tokens.dart';

Future<void> _loadFont() async {
  final file = File('test/fonts/Roboto-Regular.ttf');
  if (!file.existsSync()) return;
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  await loader.load();
}

/// Galeri komponen U1 untuk screenshot PR (360dp light & dark).
class _U1Gallery extends StatelessWidget {
  const _U1Gallery();

  @override
  Widget build(BuildContext context) {
    final t = NyatetTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('U1 · komponen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Sisa kas', style: TextStyle(fontSize: 13, color: t.label)),
          const Text(
            'Rp 3.450.000',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          NyatetDateField(
            label: 'Bulan',
            value: DateTime(2026, 11, 27),
            monthOnly: true,
            onPicked: (_) {},
          ),
          NyatetDateField(
            label: 'Tanggal transaksi',
            value: DateTime(2026, 11, 27),
            onPicked: (_) {},
          ),
          const SizedBox(height: 12),
          const NyatetSkeletonCard(height: 96),
          const SizedBox(height: 12),
          const NyatetOfflineBanner(),
          const SizedBox(height: 12),
          NyatetErrorSection(message: 'Gagal memuat bagian ini', onRetry: () {}),
          const SizedBox(height: 12),
          const NyatetEmptyState(title: 'Belum ada transaksi'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.amberBg,
              borderRadius: BorderRadius.circular(t.radius),
            ),
            child: Text('81% ▲ mendekati batas', style: TextStyle(color: t.amberText)),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.redBg,
              borderRadius: BorderRadius.circular(t.radius),
            ),
            child: Text('101% ▲ melewati batas', style: TextStyle(color: t.redText)),
          ),
        ],
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFont);

  for (final (name, theme) in [('light', NyatetTheme.light())]) {
    testWidgets('U1 gallery $name 360dp', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 760 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: theme, home: const _U1Gallery()),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(_U1Gallery),
        matchesGoldenFile('goldens/u1_$name.png'),
      );
    });
  }
}
