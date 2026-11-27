// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../domain/transaction_filters.dart';
import '../format.dart';
import '../providers.dart';
import '../widgets/transaction_detail.dart';
import 'quick_add_screen.dart';

/// L3/F6 — Daftar transaksi: cari + panel filter + chip aktif + urutan.
/// Filter dan posisi gulir dipertahankan saat hasil cari global membuka layar
/// ini (F15/D-16).
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(
      initialScrollOffset: ref.read(txScrollOffsetProvider),
    )..addListener(() {
        if (_controller.hasClients) {
          ref.read(txScrollOffsetProvider.notifier).state =
              _controller.offset;
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _resetFilters() {
    ref.read(txTypeFilterProvider.notifier).state = null;
    ref.read(txSourceFilterProvider.notifier).state = null;
    ref.read(txCategoryFilterProvider.notifier).state = null;
    ref.read(txMemberFilterProvider.notifier).state = null;
  }

  Future<void> _openFilterPanel(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _FilterPanel(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final txs = ref.watch(filteredTransactionsProvider);
    final typeFilter = ref.watch(txTypeFilterProvider);
    final sourceFilter = ref.watch(txSourceFilterProvider);
    final categoryFilter = ref.watch(txCategoryFilterProvider);
    final memberFilter = ref.watch(txMemberFilterProvider);
    final sort = ref.watch(txSortProvider);
    final session = ref.watch(sessionProvider);
    final query = ref.watch(searchQueryProvider);
    final activeCount = activeTransactionFilterCount(
      type: typeFilter,
      source: sourceFilter,
      categoryId: categoryFilter,
      memberEmail: memberFilter,
    );

    String typeLabel(String? v) => switch (v) {
          null => 'Semua',
          TransactionType.outFlow => 'Keluar',
          TransactionType.inFlow => 'Masuk',
          TransactionType.transfer => 'Transfer',
          _ => v,
        };
    String sourceLabel(String? v) => switch (v) {
          null => 'Semua',
          TransactionSource.notif => 'Notifikasi',
          TransactionSource.ocr => 'OCR',
          TransactionSource.manual => 'Manual',
          _ => v,
        };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaksi'),
        actions: [
          if (query.isNotEmpty)
            IconButton(
              tooltip: 'Hapus pencarian',
              onPressed: () =>
                  ref.read(searchQueryProvider.notifier).state = '',
              icon: const Icon(Icons.clear),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Text(
                session.isAdmin ? 'Admin' : 'Anggota',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Semantics(
              label: 'Cari transaksi',
              textField: true,
              child: TextField(
                key: const Key('tx-search'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Cari merchant, catatan, anggota',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) =>
                    ref.read(searchQueryProvider.notifier).state = v,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Semantics(
                  label: 'Filter transaksi, $activeCount aktif',
                  button: true,
                  child: OutlinedButton.icon(
                    onPressed: () => _openFilterPanel(context),
                    icon: const Icon(Icons.filter_list),
                    label: Text(
                      activeCount == 0 ? 'Filter' : 'Filter · $activeCount',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  label: 'Urutan transaksi: ${sort.label}',
                  child: DropdownButton<TxSort>(
                    value: sort,
                    items: [
                      for (final s in TxSort.values)
                        DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        ref.read(txSortProvider.notifier).state = v;
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                if (typeFilter != null)
                  _ActiveFilterChip(
                    label: 'Jenis: ${typeLabel(typeFilter)}',
                    onDeleted: () =>
                        ref.read(txTypeFilterProvider.notifier).state = null,
                  ),
                if (sourceFilter != null)
                  _ActiveFilterChip(
                    label: 'Sumber: ${sourceLabel(sourceFilter)}',
                    onDeleted: () =>
                        ref.read(txSourceFilterProvider.notifier).state = null,
                  ),
                if (categoryFilter != null)
                  _ActiveFilterChip(
                    label: 'Kategori: $categoryFilter',
                    onDeleted: () =>
                        ref.read(txCategoryFilterProvider.notifier).state = null,
                  ),
                if (memberFilter != null)
                  _ActiveFilterChip(
                    label: 'Anggota: $memberFilter',
                    onDeleted: () =>
                        ref.read(txMemberFilterProvider.notifier).state = null,
                  ),
                if (activeCount > 0)
                  ActionChip(
                    avatar: const Icon(Icons.clear, size: 16),
                    label: const Text('Reset semua'),
                    onPressed: _resetFilters,
                  ),
              ],
            ),
          ),
          Expanded(
            child: txs.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Gagal memuat: $e')),
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          activeCount > 0
                              ? 'Tidak ada transaksi dengan filter ini'
                              : 'Belum ada transaksi',
                        ),
                        const SizedBox(height: 12),
                        if (activeCount > 0)
                          OutlinedButton.icon(
                            onPressed: _resetFilters,
                            icon: const Icon(Icons.clear),
                            label: const Text('Hapus filter'),
                          )
                        else
                          FilledButton.icon(
                            onPressed: () => openQuickAdd(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Catat transaksi'),
                          ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${list.length} transaksi',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        controller: _controller,
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) =>
                            _TransactionTile(txn: list[i]),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, required this.onDeleted});

  final String label;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        label: 'Filter aktif $label, ketuk untuk melepas',
        child: InputChip(
          label: Text(label),
          onDeleted: onDeleted,
          deleteButtonTooltipMessage: 'Lepas filter',
        ),
      ),
    );
  }
}

/// Panel filter L15: keadaan tanpa filter, semua pilihan, dan reset.
class _FilterPanel extends ConsumerWidget {
  const _FilterPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(txTypeFilterProvider);
    final source = ref.watch(txSourceFilterProvider);
    final category = ref.watch(txCategoryFilterProvider);
    final member = ref.watch(txMemberFilterProvider);
    final active = activeTransactionFilterCount(
      type: type,
      source: source,
      categoryId: category,
      memberEmail: member,
    );
    final categories = ref.watch(categoriesProvider);

    void reset() {
      ref.read(txTypeFilterProvider.notifier).state = null;
      ref.read(txSourceFilterProvider.notifier).state = null;
      ref.read(txCategoryFilterProvider.notifier).state = null;
      ref.read(txMemberFilterProvider.notifier).state = null;
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    active == 0 ? 'Filter' : 'Filter · $active',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup panel filter',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (active == 0)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Belum ada filter dipilih'),
              ),
            Text('Jenis', style: Theme.of(context).textTheme.titleSmall),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in const [
                  (label: 'Semua', value: null),
                  (label: 'Keluar', value: TransactionType.outFlow),
                  (label: 'Masuk', value: TransactionType.inFlow),
                  (label: 'Transfer', value: TransactionType.transfer),
                ])
                  FilterChip(
                    label: Text(entry.label),
                    selected: type == entry.value,
                    onSelected: (_) =>
                        ref.read(txTypeFilterProvider.notifier).state =
                            entry.value,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Sumber', style: Theme.of(context).textTheme.titleSmall),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in const [
                  (label: 'Semua', value: null),
                  (label: 'Notifikasi', value: TransactionSource.notif),
                  (label: 'OCR', value: TransactionSource.ocr),
                  (label: 'Manual', value: TransactionSource.manual),
                ])
                  FilterChip(
                    label: Text(entry.label),
                    selected: source == entry.value,
                    onSelected: (_) =>
                        ref.read(txSourceFilterProvider.notifier).state =
                            entry.value,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Kategori', style: Theme.of(context).textTheme.titleSmall),
            categories.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Kategori gagal dimuat: $e'),
              data: (list) => Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Semua'),
                    selected: category == null,
                    onSelected: (_) =>
                        ref.read(txCategoryFilterProvider.notifier).state = null,
                  ),
                  for (final c in list.take(7))
                    ChoiceChip(
                      label: Text(c.name),
                      selected: category == c.id,
                      onSelected: (_) => ref
                          .read(txCategoryFilterProvider.notifier)
                          .state = c.id,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('Anggota', style: Theme.of(context).textTheme.titleSmall),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Semua'),
                  selected: member == null,
                  onSelected: (_) =>
                      ref.read(txMemberFilterProvider.notifier).state = null,
                ),
                for (final email
                    in ref.watch(txMemberChoicesProvider).maybeWhen(
                          data: (list) => list,
                          orElse: () => const <String>[],
                        ))
                  ChoiceChip(
                    label: Text(email),
                    selected: member == email,
                    onSelected: (_) =>
                        ref.read(txMemberFilterProvider.notifier).state = email,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: active == 0 ? null : reset,
                    child: const Text('Reset semua'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Terapkan filter'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({required this.txn});

  final Transaction txn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIn = txn.type == TransactionType.inFlow ||
        txn.type == TransactionType.goalWithdrawal;
    final isTransfer = txn.type == TransactionType.transfer;
    final arrow = isTransfer ? '⇄' : (isIn ? '▲' : '▼');
    final sign = isTransfer ? '' : (isIn ? '+' : '−');

    return ListTile(
      title: Text(txn.merchant ?? txn.note ?? labelTipe(txn.type)),
      subtitle: Text(
        '${formatTanggalWaktu(txn.date)} • ${labelTipe(txn.type)}'
        ' • ${txn.memberEmail}',
      ),
      trailing: Text(
        '$arrow $sign${formatRupiah(txn.amount)}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      onTap: () => showTransactionDetail(context, ref, txn),
    );
  }
}

Future<void> openQuickAdd(BuildContext context) async {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const QuickAddScreen()),
  );
  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transaksi tersimpan')),
    );
  }
}
