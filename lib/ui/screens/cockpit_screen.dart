// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../domain/allocation_repository.dart';
import '../../domain/report_service.dart';
import '../format.dart';
import '../../home_shell.dart';
import '../providers.dart';
import 'draft_queue_screen.dart';
import 'drilldown_screen.dart';

/// L2 — Beranda cockpit (F8): 4 keranjang D-17, alokasi teratas, tujuan,
/// draf menunggu. Setiap angka bisa diketuk (D-16).
class CockpitScreen extends ConsumerWidget {
  const CockpitScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthKey = ref.watch(selectedMonthProvider);
    final month = DateTime.parse('$monthKey-01');
    final summary = ref.watch(cashSummaryProvider);
    final goals = ref.watch(goalsProvider);
    final allocations = ref.watch(allocationRowsProvider);
    final pending = ref.watch(pendingDraftsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nyatet'),
        actions: [
          ActionChip(
            avatar: const Icon(Icons.calendar_month, size: 18),
            label: Text(monthLabel(month)),
            onPressed: () => _pickMonth(context, ref),
          ),
          const DevMenu(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(cashSummaryProvider);
          ref.invalidate(goalsProvider);
          ref.invalidate(allocationRowsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            summary.when(
              loading: () => const _SkeletonCard(),
              error: (e, _) => _ErrorBanner(message: '$e'),
              data: (s) => _BalanceCard(summary: s, month: month),
            ),
            const SizedBox(height: 12),
            allocations.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => _ErrorBanner(message: '$e'),
              data: (rows) => _AllocationTopCard(rows: rows),
            ),
            const SizedBox(height: 12),
            goals.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => _ErrorBanner(message: '$e'),
              data: (list) => _GoalsCard(goals: list),
            ),
            const SizedBox(height: 12),
            pending.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => _ErrorBanner(message: '$e'),
              data: (list) => Card(
                child: ListTile(
                  leading: const Icon(Icons.inbox_outlined),
                  title: Text('${list.length} draf menunggu konfirmasi'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DraftQueueScreen(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMonth(BuildContext context, WidgetRef ref) async {
    final current = DateTime.parse('${ref.read(selectedMonthProvider)}-01');
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Pilih bulan',
    );
    if (picked != null) {
      ref.read(selectedMonthProvider.notifier).state = ReportService.monthKey(picked);
    }
  }
}

String monthLabel(DateTime month) {
  const names = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];
  final local = month.toLocal();
  return '${names[local.month - 1]} ${local.year}';
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary, required this.month});

  final CashSummary summary;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hero = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BasketRow(
              label: 'Masuk',
              arrow: '▲',
              amount: summary.masuk,
              basket: Basket.masuk,
              month: month,
              emphasis: true,
            ),
            const SizedBox(height: 8),
            _BasketRow(
              label: 'Terpakai',
              arrow: '▼',
              amount: summary.terpakai,
              basket: Basket.terpakai,
              month: month,
            ),
            const SizedBox(height: 8),
            _BasketRow(
              label: 'Disisihkan (tujuan)',
              arrow: '◆',
              amount: summary.disisihkan,
              basket: Basket.disisihkan,
              month: month,
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Sisa kas', style: theme.textTheme.titleMedium),
                Text(
                  formatRupiah(summary.sisaKas),
                  style: hero,
                  key: const Key('sisa-kas'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const _UnallocatedLine(),
          ],
        ),
      ),
    );
  }
}

class _UnallocatedLine extends ConsumerWidget {
  const _UnallocatedLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(unallocatedProvider);
    return value.when(
      loading: () => const Text('Belum dialokasikan —'),
      error: (e, _) => Text('Belum dialokasikan gagal dihitung'),
      data: (amount) => Text(
        'Belum dialokasikan ${formatRupiah(amount)}',
        style: Theme.of(context).textTheme.bodySmall,
        key: const Key('belum-dialokasikan'),
      ),
    );
  }
}

class _BasketRow extends StatelessWidget {
  const _BasketRow({
    required this.label,
    required this.arrow,
    required this.amount,
    required this.basket,
    required this.month,
    this.emphasis = false,
  });

  final String label;
  final String arrow;
  final double amount;
  final Basket basket;
  final DateTime month;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: Key('basket-${basket.name}'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DrillDownScreen(
            title: label,
            basket: basket,
            month: month,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$arrow $label',
              style: emphasis
                  ? theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    )
                  : theme.textTheme.bodyLarge,
            ),
            Text(
              formatRupiah(amount),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllocationTopCard extends ConsumerWidget {
  const _AllocationTopCard({required this.rows});

  final List<Budget> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Progres alokasi',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () => ref.read(homeTabProvider.notifier).state = 2,
                  child: const Text('Kelola alokasi'),
                ),
              ],
            ),
            if (rows.isEmpty)
              const Text('Belum ada alokasi bulan ini')
            else
              ...rows.take(3).map((b) {
                final name = categories.maybeWhen(
                  data: (list) => list
                      .where((c) => c.id == b.categoryId)
                      .map((c) => c.name)
                      .firstOrNull,
                  orElse: () => null,
                );
                final limit = b.limitAmount;
                final ratio = limit <= 0
                    ? 0.0
                    : (b.allocatedAmount / limit).clamp(0, 1).toDouble();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(name ?? 'Kategori'),
                          Text(
                            '${formatRupiah(b.allocatedAmount)} / '
                            '${formatRupiah(limit)}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _GoalsCard extends ConsumerWidget {
  const _GoalsCard({required this.goals});

  final List<GoalProgress> goals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Aset keluarga',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () => ref.read(homeTabProvider.notifier).state = 3,
                  child: const Text('Semua tujuan'),
                ),
              ],
            ),
            if (goals.isEmpty)
              const Text('Belum ada tujuan dana')
            else
              ...goals.take(2).map(
                    (g) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(g.goal.name),
                      subtitle: Text(
                        '${(g.ratio * 100).round()}% — '
                        '${formatRupiah(g.collected)} dari '
                        '${formatRupiah(g.goal.targetAmount)} · '
                        '${g.statusLabel}',
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Data belum bisa dimuat: $message'),
      ),
    );
  }
}
