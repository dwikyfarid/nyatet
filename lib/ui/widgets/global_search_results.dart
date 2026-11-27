// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../domain/search_service.dart';
import '../format.dart';
import '../providers.dart';
import '../screens/budget_screen.dart';
import '../screens/goals_screen.dart';
import 'transaction_detail.dart';

/// Hasil cari global di beranda (F15/L15). Menggantikan isi beranda saat ada
/// kata kunci; tidak membuka layar baru.
class GlobalSearchResults extends ConsumerWidget {
  const GlobalSearchResults({super.key, required this.result});

  final GlobalSearchResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (result.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: [
          Text('Tidak ada hasil untuk "${result.query}"',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('Coba kata lain, atau hapus filter pencarian.'),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () =>
                  ref.read(globalQueryProvider.notifier).state = '',
              icon: const Icon(Icons.clear),
              label: const Text('Hapus filter'),
            ),
          ),
        ],
      );
    }

    Widget group(String title, int count, List<Widget> children) {
      if (children.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('$title $count', style: theme.textTheme.titleSmall),
          ),
          ...children,
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        group('Transaksi', result.transactions.length, [
          for (final t in result.transactions)
            ListTile(
              leading: Icon(
                t.type == TransactionType.inFlow
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                size: 18,
              ),
              title: Text(t.merchant ?? labelTipe(t.type)),
              subtitle: Text(
                '${formatTanggalWaktu(t.date)}'
                '${t.account.isEmpty ? '' : ' · ${t.account}'}'
                ' · ${t.refNo == null || t.refNo!.isEmpty ? 'tanpa nomor referensi' : 'No. referensi ${t.refNo}'}',
              ),
              trailing: Text(formatRupiah(t.amount)),
              onTap: () => showTransactionDetail(context, ref, t),
            ),
        ]),
        group('Kategori', result.categories.length, [
          for (final c in result.categories)
            ListTile(
              leading: const Icon(Icons.category_outlined, size: 18),
              title: Text(c.name),
              subtitle: Text(
                '${labelTipe(c.type)} · ${c.isActive ? 'aktif' : 'nonaktif'}',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const BudgetScreen()),
              ),
            ),
        ]),
        group('Tujuan', result.goals.length, [
          for (final g in result.goals)
            ListTile(
              leading: const Icon(Icons.savings_outlined, size: 18),
              title: Text(g.name),
              subtitle: Text(
                g.dueDate == null
                    ? 'tanpa tenggat'
                    : 'tenggat ${formatTanggalWaktu(g.dueDate!)}',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const GoalsScreen()),
              ),
            ),
        ]),
        group('Anggota', result.members.length, [
          for (final m in result.members)
            ListTile(
              leading: const Icon(Icons.person_outline, size: 18),
              title: Text(m.name),
              subtitle: Text('${m.email} · ${m.status}'),
              onTap: () {
                ref.read(txMemberFilterProvider.notifier).state = m.email;
                ref.read(globalQueryProvider.notifier).state = '';
                ref.read(homeTabProvider.notifier).state = 1;
              },
            ),
        ]),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'raw_text notifikasi tidak pernah diindeks (D-50)',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}
