// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../domain/transaction_service.dart';
import '../format.dart';
import '../providers.dart';

/// Level 3.3 drill-down (D-16): detail satu transaksi + aksi sesuai role.
/// Dipakai dari daftar transaksi maupun dari cockpit/drill-down.
Future<void> showTransactionDetail(
  BuildContext context,
  WidgetRef ref,
  Transaction txn,
) async {
  final policy = ref.read(accessPolicyProvider);
  final editDecision = policy.canEdit(txn);
  final deleteDecision = policy.canDelete(txn);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              'No. transaksi ${txn.txnNo ?? '-'}',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              txn.merchant ?? labelTipe(txn.type),
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('${labelTipe(txn.type)} ${formatRupiah(txn.amount)}'),
            const SizedBox(height: 4),
            Text(formatTanggalWaktu(txn.date)),
            const SizedBox(height: 4),
            Text('${txn.memberEmail} • sumber ${txn.source}'),
            if (txn.refNo != null && txn.refNo!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('No. referensi: ${txn.refNo}'),
            ],
            if (txn.note != null) ...[
              const SizedBox(height: 8),
              Text('Catatan: ${txn.note}'),
            ],
            if (txn.rawText != null) ...[
              const SizedBox(height: 8),
              Text('Teks asli: ${txn.rawText}'),
            ],
            const SizedBox(height: 16),
            // Aksi yang pasti ditolak tidak ditampilkan sebagai tombol mati:
            // alasannya ditulis di tempat, bukan hilang di balik sheet.
            for (final reason in {
              if (!editDecision.allowed) editDecision.reason,
              if (!deleteDecision.allowed) deleteDecision.reason,
            })
              if (reason != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lock_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(reason)),
                    ],
                  ),
                ),
            if (editDecision.allowed || deleteDecision.allowed)
              Row(
                children: [
                  if (editDecision.allowed)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          editTransaction(context, ref, txn);
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit transaksi'),
                      ),
                    ),
                  if (editDecision.allowed && deleteDecision.allowed)
                    const SizedBox(width: 12),
                  if (deleteDecision.allowed)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          deleteTransaction(context, ref, txn);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Hapus transaksi'),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> editTransaction(
  BuildContext context,
  WidgetRef ref,
  Transaction txn,
) async {
  final controller = TextEditingController(
    text: formatRupiah(txn.amount).replaceFirst('Rp ', ''),
  );
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        top: 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Edit transaksi', style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Jumlah',
              prefixText: 'Rp ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Simpan perubahan'),
            ),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return;

  try {
    await ref.read(transactionServiceProvider).updateManual(
          policy: ref.read(accessPolicyProvider),
          txn: txn,
          date: txn.date,
          type: txn.type,
          amount: parseRupiah(controller.text),
          categoryId: txn.categoryId,
          note: txn.note,
        );
    _refreshReports(ref);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perubahan tersimpan, tercatat di audit log')),
      );
    }
  } on AccessDenied catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.reason)));
    }
  }
}

Future<void> deleteTransaction(
  BuildContext context,
  WidgetRef ref,
  Transaction txn,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Hapus transaksi ini?'),
      content: const Text(
        'Transaksi tidak dihapus permanen — hanya ditandai terhapus dan tetap bisa diaudit.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Hapus transaksi'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    await ref.read(transactionServiceProvider).delete(
          policy: ref.read(accessPolicyProvider),
          txn: txn,
        );
    _refreshReports(ref);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaksi ditandai terhapus (soft delete)')),
      );
    }
  } on AccessDenied catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.reason)));
    }
  }
}

void _refreshReports(WidgetRef ref) => ref.refreshMoneyProviders();
