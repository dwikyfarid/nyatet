// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../domain/allocation_repository.dart';
import '../format.dart';
import '../providers.dart';
import 'cockpit_screen.dart';

/// L4 — Alokasi dana per kategori (F10). Alokasi = rencana, budget = batas,
/// dan alokasi ≤ budget. Angka "belum dialokasikan" selalu ditampilkan (D-15).
class AllocationScreen extends ConsumerWidget {
  const AllocationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthKey = ref.watch(selectedMonthProvider);
    final month = DateTime.parse('$monthKey-01');
    final summary = ref.watch(cashSummaryProvider);
    final allocations = ref.watch(allocationRowsProvider);
    final categories = ref.watch(categoriesProvider);
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alokasi'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Text(monthLabel(month))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          summary.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Ringkasan gagal: $e'),
            data: (s) => allocations.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Alokasi gagal: $e'),
              data: (rows) {
                final total = rows.fold<double>(
                  0,
                  (sum, b) => sum + b.allocatedAmount,
                );
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Masuk ${formatRupiah(s.masuk)}'),
                        Text('Total alokasi ${formatRupiah(total)}'),
                        const SizedBox(height: 6),
                        Text(
                          'Belum dialokasikan ${formatRupiah(s.masuk - total)}',
                          key: const Key('alokasi-unallocated'),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (s.masuk <= 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'rencana — pemasukan belum masuk',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          if (!session.isAdmin)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Hanya admin yang bisa mengubah alokasi',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          categories.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Kategori gagal dimuat: $e'),
            data: (cats) => allocations.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text('Alokasi gagal: $e'),
              data: (rows) => Column(
                children: [
                  for (final c in cats)
                    _AllocationRow(
                      category: c,
                      allocation: rows
                          .where((b) => b.categoryId == c.id)
                          .map((b) => b.allocatedAmount)
                          .firstOrNull,
                      editable: session.isAdmin,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllocationRow extends ConsumerWidget {
  const _AllocationRow({
    required this.category,
    required this.allocation,
    required this.editable,
  });

  final Category category;
  final double? allocation;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(category.name),
      subtitle: Text(labelTipe(category.type)),
      trailing: Text(
        allocation == null
            ? 'Belum dialokasikan'
            : formatRupiah(allocation!),
      ),
      onTap: editable ? () => _edit(context, ref) : null,
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(
      text: allocation == null
          ? ''
          : formatRupiah(allocation!).replaceFirst('Rp ', ''),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Alokasi ${category.name}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
          decoration: const InputDecoration(
            labelText: 'Alokasi per bulan',
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
            child: const Text('Simpan alokasi'),
          ),
        ],
      ),
    );
    if (saved != true) return;

    final monthKey = ref.read(selectedMonthProvider);
    try {
      final result = await ref.read(allocationRepositoryProvider).setAllocation(
            policy: ref.read(accessPolicyProvider),
            monthKey: monthKey,
            categoryId: category.id,
            amount: parseRupiah(controller.text),
          );
      ref.invalidate(allocationRowsProvider);
      ref.invalidate(unallocatedProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.planned
                  ? 'Alokasi disimpan sebagai rencana — pemasukan belum masuk'
                  : 'Alokasi tersimpan — belum dialokasikan '
                      '${formatRupiah((await _unallocated(ref)))}',
            ),
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

  Future<double> _unallocated(WidgetRef ref) async {
    final monthKey = ref.read(selectedMonthProvider);
    final service = ref.read(reportServiceProvider);
    return service.unallocated(
      ref.read(accessPolicyProvider),
      DateTime.parse('$monthKey-01'),
    );
  }
}
