// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../domain/report_service.dart';
import '../format.dart';
import '../providers.dart';
import '../widgets/transaction_detail.dart';
import 'cockpit_screen.dart';

/// L3 — Drill-down D-16: level 3.1 grup → 3.2 daftar transaksi → 3.3 detail.
/// Maksimal 3 ketuk dari cockpit, dan total level atas = jumlah baris di bawah.
class DrillDownScreen extends ConsumerWidget {
  const DrillDownScreen({
    super.key,
    required this.title,
    required this.basket,
    required this.month,
    this.categoryId,
    this.memberEmail,
    this.showGroups = true,
  });

  final String title;
  final Basket basket;
  final DateTime month;
  final String? categoryId;
  final String? memberEmail;
  final bool showGroups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthKey = ReportService.monthKey(month);
    if (showGroups) {
      final groups = ref.watch(_groupProvider((
        monthKey: monthKey,
        basket: basket,
        byMember: false,
      )));
      final byMember =
          ref.watch(_groupProvider((monthKey: monthKey, basket: basket, byMember: true)));

      return Scaffold(
        appBar: AppBar(title: Text('$title · ${monthLabel(month)}')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _SectionHeader(
              'Per kategori',
              onTap: () => _openList(context, null),
            ),
            groups.when(
              loading: () => const _Loading(),
              error: (e, _) => Text('Gagal: $e'),
              data: (rows) => Column(
                children: [
                  for (final g in rows)
                    ListTile(
                      title: Text(g.label),
                      subtitle: Text('${g.count} transaksi'),
                      trailing: Text(formatRupiah(g.total)),
                      onTap: () => _openList(context, g.id),
                    ),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Belum ada transaksi di keranjang ini'),
                    ),
                ],
              ),
            ),
            const Divider(),
            _SectionHeader(
              'Per anggota',
              onTap: () => _openListByMember(context),
            ),
            byMember.when(
              loading: () => const _Loading(),
              error: (e, _) => Text('Gagal: $e'),
              data: (rows) => Column(
                children: [
                  for (final g in rows)
                    ListTile(
                      title: Text(g.label),
                      subtitle: Text('${g.count} transaksi'),
                      trailing: Text(formatRupiah(g.total)),
                      onTap: () => _openListByMember(context, g.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final txs = ref.watch(_txListProvider((
      monthKey: monthKey,
      basket: basket,
      categoryId: categoryId,
      memberEmail: memberEmail,
    )));
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: txs.when(
        loading: () => const _Loading(),
        error: (e, _) => Center(child: Text('Gagal memuat: $e')),
        data: (list) {
          final total = list.fold<double>(0, (sum, t) => sum + t.amount);
          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Text(
                  '${monthLabel(month)} · ${list.length} transaksi · '
                  'total ${formatRupiah(total)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                  key: const Key('drill-context'),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const Center(child: Text('Belum ada transaksi'))
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final t = list[i];
                          return ListTile(
                            title: Text(t.merchant ?? t.note ?? labelTipe(t.type)),
                            subtitle: Text(
                              '${formatTanggalWaktu(t.date)} • ${t.memberEmail}',
                            ),
                            trailing: Text(formatRupiah(t.amount)),
                            onTap: () => showTransactionDetail(context, ref, t),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openList(BuildContext context, String? catId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DrillDownScreen(
          title: catId == null ? title : 'Kategori',
          basket: basket,
          month: month,
          categoryId: catId,
          showGroups: false,
        ),
      ),
    );
  }

  void _openListByMember(BuildContext context, [String? email]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DrillDownScreen(
          title: email ?? '$title · Anggota',
          basket: basket,
          month: month,
          memberEmail: email,
          showGroups: false,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text, {this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text, style: Theme.of(context).textTheme.titleMedium),
          if (onTap != null)
            TextButton(onPressed: onTap, child: const Text('Lihat semua')),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
}

typedef _GroupArgs = ({String monthKey, Basket basket, bool byMember});
typedef _ListArgs = ({
  String monthKey,
  Basket basket,
  String? categoryId,
  String? memberEmail,
});

final _groupProvider =
    FutureProvider.family<List<GroupTotal>, _GroupArgs>((ref, args) {
  final service = ref.watch(reportServiceProvider);
  final policy = ref.watch(accessPolicyProvider);
  final month = DateTime.parse('${args.monthKey}-01');
  return args.byMember
      ? service.byMember(policy, month, args.basket)
      : service.byCategory(policy, month, args.basket);
});

final _txListProvider =
    FutureProvider.family<List<Transaction>, _ListArgs>((ref, args) {
  final service = ref.watch(reportServiceProvider);
  final policy = ref.watch(accessPolicyProvider);
  final month = DateTime.parse('${args.monthKey}-01');
  return service.listBasket(
    policy,
    month,
    args.basket,
    categoryId: args.categoryId,
    memberEmail: args.memberEmail,
  );
});
