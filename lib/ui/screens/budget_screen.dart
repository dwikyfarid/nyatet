// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../domain/allocation_repository.dart';
import '../../domain/budget_repository.dart';
import '../format.dart';
import '../providers.dart';
import 'cockpit_screen.dart' show monthLabel;

/// L8 — Kategori & Budget (F7), khusus admin.
/// Daftar kategori + budget bulan berjalan (limit), indikator amber ≥80% /
/// merah ≥100%, selalu dengan teks persen + panah (UX-01). Budget hanya
/// mengukur "terpakai"; setoran tujuan tidak dihitung (D-17).
class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key});

  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  String _query = '';

  static const Color _amberText = Color(0xFF9A6700);
  static const Color _amberBg = Color(0xFFFFEFCF);
  static const Color _redText = Color(0xFFBA1A1A);
  static const Color _redBg = Color(0xFFFFDAD6);
  static const Color _greenText = Color(0xFF1B5E20);
  static const Color _greenBg = Color(0xFFD7F5D9);

  @override
  Widget build(BuildContext context) {
    final monthKey = ref.watch(selectedMonthProvider);
    final month = DateTime.parse('$monthKey-01');
    final isAdmin = ref.watch(sessionProvider).isAdmin;
    final rows = ref.watch(budgetStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kategori & Budget'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: Text(monthLabel(month))),
          ),
          if (isAdmin)
            IconButton(
              tooltip: 'Tambah kategori',
              onPressed: () => _editCategory(context, null),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat budget: $e')),
        data: (list) {
          final filtered = list
              .where(
                (r) => r.category.name.toLowerCase().contains(
                      _query.toLowerCase(),
                    ),
              )
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Cari kategori',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (!isAdmin)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Hanya admin yang bisa mengelola kategori & budget'),
                  ),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('Kategori tidak ditemukan'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final row = filtered[i];
                          return _BudgetRow(
                            status: row,
                            isAdmin: isAdmin,
                            amberText: _amberText,
                            amberBg: _amberBg,
                            redText: _redText,
                            redBg: _redBg,
                            greenText: _greenText,
                            greenBg: _greenBg,
                            onSetBudget: () => _setBudget(row),
                            onEditCategory: () => _editCategory(context, row.category),
                            onDeactivate: () => _deactivate(row.category),
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

  Future<void> _setBudget(CategoryBudgetStatus row) async {
    final controller = TextEditingController(
      text: row.limit > 0 ? formatRupiah(row.limit).replaceFirst('Rp ', '') : '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Budget ${row.category.name}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
          decoration: const InputDecoration(
            labelText: 'Batas bulanan',
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
            child: const Text('Simpan budget'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;

    try {
      await ref.read(allocationRepositoryProvider).setLimit(
            policy: ref.read(accessPolicyProvider),
            monthKey: ref.read(selectedMonthProvider),
            categoryId: row.category.id,
            amount: parseRupiah(controller.text),
          );
      ref.invalidate(budgetStatusProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Budget ${row.category.name} tersimpan — '
            'sisa ${formatRupiah((row.limit - row.spent).clamp(0, double.infinity))}',
          ),
        ),
      );
    } on AllocationRuleViolation catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _editCategory(BuildContext context, Category? existing) async {
    final name = TextEditingController(text: existing?.name ?? '');
    var type = existing?.type ?? TransactionType.outFlow;
    var active = existing?.isActive ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'Tambah kategori' : 'Ubah kategori'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nama kategori'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'out', label: Text('Keluar')),
                  ButtonSegment(value: 'in', label: Text('Masuk')),
                ],
                selected: {type},
                onSelectionChanged: (v) => setState(() => type = v.first),
              ),
              if (existing != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  value: active,
                  onChanged: (v) => setState(() => active = v),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Simpan kategori'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !context.mounted) return;

    try {
      final repo = ref.read(budgetRepositoryProvider);
      final policy = ref.read(accessPolicyProvider);
      if (existing == null) {
        await repo.createCategory(
          policy: policy,
          name: name.text,
          type: type,
        );
      } else {
        await repo.updateCategory(
          policy: policy,
          id: existing.id,
          name: name.text,
          isActive: active,
        );
      }
      ref.invalidate(budgetStatusProvider);
      ref.invalidate(categoriesProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null ? 'Kategori ditambahkan' : 'Kategori tersimpan',
          ),
        ),
      );
    } on AllocationRuleViolation catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deactivate(Category category) async {
    try {
      await ref.read(budgetRepositoryProvider).deactivateCategory(
            policy: ref.read(accessPolicyProvider),
            id: category.id,
          );
      ref.invalidate(budgetStatusProvider);
      ref.invalidate(categoriesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${category.name} dinonaktifkan')),
      );
    } on AllocationRuleViolation catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.status,
    required this.isAdmin,
    required this.amberText,
    required this.amberBg,
    required this.redText,
    required this.redBg,
    required this.greenText,
    required this.greenBg,
    required this.onSetBudget,
    required this.onEditCategory,
    required this.onDeactivate,
  });

  final CategoryBudgetStatus status;
  final bool isAdmin;
  final Color amberText;
  final Color amberBg;
  final Color redText;
  final Color redBg;
  final Color greenText;
  final Color greenBg;
  final VoidCallback onSetBudget;
  final VoidCallback onEditCategory;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status.level) {
      BudgetLevel.lewat => (redText, redBg),
      BudgetLevel.waspada => (amberText, amberBg),
      BudgetLevel.aman => (greenText, greenBg),
    };
    final ratio = status.ratio.clamp(0, 1).toDouble();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      title: Row(
        children: [
          Expanded(child: Text(status.category.name)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              status.percentLabel,
              style: TextStyle(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            labelTipe(status.category.type),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              color: fg,
              backgroundColor: bg,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            status.hasBudget
                ? '${status.spentLabel} · ${status.levelLabel}'
                : 'Belum ada budget · terpakai ${status.spentLabel.split(' / ').first}',
          ),
        ],
      ),
      trailing: isAdmin
          ? PopupMenuButton<String>(
              tooltip: 'Aksi kategori',
              onSelected: (v) {
                if (v == 'budget') onSetBudget();
                if (v == 'edit') onEditCategory();
                if (v == 'off') onDeactivate();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'budget', child: Text('Atur budget')),
                PopupMenuItem(value: 'edit', child: Text('Ubah kategori')),
                PopupMenuItem(value: 'off', child: Text('Nonaktifkan')),
              ],
            )
          : null,
      onTap: isAdmin ? onSetBudget : null,
    );
  }
}
