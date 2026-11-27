// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/allocation_repository.dart';
import '../format.dart';
import '../providers.dart';

/// L5 — Tujuan dana (F10). Progres selalu persen + nominal + status eksplisit.
/// Setoran boleh dilakukan anggota (D-20); pembuatan tujuan hanya admin.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tujuan'),
        actions: [
          if (session.isAdmin)
            IconButton(
              tooltip: 'Buat tujuan',
              onPressed: () => _createGoal(context, ref),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: goals.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat tujuan: $e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Belum ada tujuan'),
                  const SizedBox(height: 12),
                  if (session.isAdmin)
                    FilledButton.icon(
                      onPressed: () => _createGoal(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Buat tujuan'),
                    ),
                ],
              ),
            );
          }
          final filter = ref.watch(goalFilterProvider);
          final sort = ref.watch(goalSortProvider);
          final filtered = list.where((g) {
            return switch (filter) {
              GoalFilter.all => true,
              GoalFilter.achieved => g.achieved,
              GoalFilter.active => !g.achieved,
            };
          }).toList();
          if (sort == GoalSort.name) {
            filtered.sort((a, b) => a.goal.name.compareTo(b.goal.name));
          }
          return Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final f in GoalFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(switch (f) {
                            GoalFilter.all => 'Semua tujuan',
                            GoalFilter.achieved => 'Tercapai',
                            GoalFilter.active => 'Aktif',
                          }),
                          selected: filter == f,
                          onSelected: (_) =>
                              ref.read(goalFilterProvider.notifier).state = f,
                        ),
                      ),
                    DropdownButton<GoalSort>(
                      value: sort,
                      items: const [
                        DropdownMenuItem(
                          value: GoalSort.dueDate,
                          child: Text('Tenggat terdekat'),
                        ),
                        DropdownMenuItem(
                          value: GoalSort.name,
                          child: Text('Nama A–Z'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          ref.read(goalSortProvider.notifier).state = v;
                        }
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _GoalCard(progress: filtered[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createGoal(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final target = TextEditingController();
    final monthly = TextEditingController();
    var step = 0;

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Langkah ${step + 1} dari 3',
                style: Theme.of(ctx).textTheme.labelLarge,
              ),
              LinearProgressIndicator(value: (step + 1) / 3),
              const SizedBox(height: 16),
              if (step == 0) ...[
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nama tujuan'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: target,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Target dana',
                    prefixText: 'Rp ',
                  ),
                ),
              ] else if (step == 1)
                TextField(
                  controller: monthly,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Alokasi per bulan',
                    prefixText: 'Rp ',
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nama: ${name.text}'),
                    Text('Target: ${formatRupiah(parseRupiah(target.text))}'),
                    Text(
                      'Alokasi/bulan: ${formatRupiah(parseRupiah(monthly.text))}',
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (step > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => step--),
                        child: const Text('Kembali'),
                      ),
                    ),
                  if (step > 0) const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        if (step < 2) {
                          setState(() => step++);
                          return;
                        }
                        try {
                          await ref.read(allocationRepositoryProvider).createGoal(
                                policy: ref.read(accessPolicyProvider),
                                name: name.text.trim(),
                                targetAmount: parseRupiah(target.text),
                                monthlyAllocation: parseRupiah(monthly.text),
                              );
                          if (ctx.mounted) Navigator.of(ctx).pop(true);
                        } on AllocationRuleViolation catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx)
                                .showSnackBar(SnackBar(content: Text(e.message)));
                          }
                        }
                      },
                      child: Text(step < 2 ? 'Lanjut' : 'Buat tujuan'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (created == true) {
      ref.invalidate(goalsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tujuan dibuat')),
        );
      }
    }
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final g = progress.goal;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(g.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${(progress.ratio * 100).round()}% — '
              '${formatRupiah(progress.collected)} dari '
              '${formatRupiah(g.targetAmount)}',
              key: Key('goal-progress-${g.id}'),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress.ratio,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              progress.statusLabel,
              style: theme.textTheme.bodySmall,
              key: Key('goal-status-${g.id}'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => _deposit(context, ref, progress),
                icon: const Icon(Icons.savings_outlined),
                label: const Text('Setor ke tujuan'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deposit(
    BuildContext context,
    WidgetRef ref,
    GoalProgress progress,
  ) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Setor ke ${progress.goal.name}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
          decoration: const InputDecoration(
            labelText: 'Nominal setoran',
            prefixText: 'Rp ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Simpan setoran'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(allocationRepositoryProvider).deposit(
            policy: ref.read(accessPolicyProvider),
            goalId: progress.goal.id,
            amount: parseRupiah(controller.text),
          );
      ref.invalidate(goalsProvider);
      ref.invalidate(cashSummaryProvider);
      ref.invalidate(visibleTransactionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Setoran tersimpan — tercatat sebagai Disisihkan, bukan pengeluaran'),
          ),
        );
      }
    } on AllocationRuleViolation catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}
