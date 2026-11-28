// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../format.dart';
import '../providers.dart';
import '../widgets/transaction_detail.dart';
import 'quick_add_screen.dart';

/// L3/F6 — Daftar transaksi dengan cari + scroll (UX-03).
class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(visibleTransactionsProvider);
    final session = ref.watch(sessionProvider);
    final query = ref.watch(searchQueryProvider);

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
            child: TextField(
              key: const Key('tx-search'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cari merchant, catatan, anggota',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => ref.read(searchQueryProvider.notifier).state = v,
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
                        const Text('Belum ada transaksi'),
                        const SizedBox(height: 12),
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
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final t = list[i];
                          return _TransactionTile(txn: t);
                        },
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
        '${txn.txnNo ?? ''}'
        '${txn.txnNo == null ? '' : ' · '}'
        '${formatTanggalWaktu(txn.date)} • ${labelTipe(txn.type)}'
        ' • ${txn.memberEmail}',
        style: const TextStyle(fontSize: 12),
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
