// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../format.dart';
import '../providers.dart';
import '../widgets/category_selector.dart';

/// L7 — Antrean konfirmasi notifikasi (F4).
/// Draf hidup lokal, jadi layar ini tetap jalan tanpa jaringan.
class DraftQueueScreen extends ConsumerWidget {
  const DraftQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(draftQueueProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Konfirmasi Transaksi')),
      body: drafts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(
          message: 'Antrean gagal dibuka: $e',
          onRetry: () => ref.invalidate(draftQueueProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return _EmptyState(
              onSeed: () async {
                await ref.read(draftRepositoryProvider).seedDummyDrafts();
                ref.invalidate(draftQueueProvider);
                ref.invalidate(pendingDraftsProvider);
              },
            );
          }
          final pending = list.where((d) => d.status == DraftStatus.pending).length;
          final decided = list.length - pending;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: list.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _ProgressHeader(decided: decided, total: list.length);
              }
              return _DraftCard(draft: list[index - 1]);
            },
          );
        },
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.decided, required this.total});

  final int decided;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : decided / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$decided dari $total draf dikonfirmasi',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: ratio, minHeight: 8),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _DraftCard extends ConsumerWidget {
  const _DraftCard({required this.draft});

  final TransactionDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isIn = draft.type == TransactionType.inFlow;
    final isTransfer = draft.type == TransactionType.transfer;
    final arrow = isTransfer ? '⇄' : (isIn ? '▲' : '▼');
    final sign = isTransfer ? '' : (isIn ? '+' : '−');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    draft.merchant ?? 'Transaksi tanpa nama',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  '$arrow $sign${formatRupiah(draft.amount)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${formatTanggalWaktu(draft.occurredAt)}'
              '${draft.last4 == null ? '' : ' • ••••${draft.last4}'}'
              ' • ${draft.bankGroup.toUpperCase()}',
              style: theme.textTheme.bodySmall,
            ),
            if (draft.merchant == null && draft.rawText != null) ...[
              const SizedBox(height: 8),
              Chip(
                visualDensity: VisualDensity.compact,
                label: const Text('belum dikenali'),
              ),
              const SizedBox(height: 4),
              Text(draft.rawText!, style: theme.textTheme.bodySmall),
            ],
            if (draft.status == DraftStatus.duplicate) ...[
              const SizedBox(height: 8),
              Text(
                'duplikat — diabaikan otomatis',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            if (draft.status == DraftStatus.pending)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => _save(context, ref),
                    child: const Text('Simpan'),
                  ),
                  OutlinedButton(
                    onPressed: () => _changeCategory(context, ref),
                    child: const Text('Ubah kategori'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      await ref
                          .read(draftRepositoryProvider)
                          .markAsTransfer(draft.id);
                      _refresh(ref);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Ditandai transfer antar-rekening — tidak dihitung masuk/keluar',
                            ),
                          ),
                        );
                      }
                    },
                    child: const Text('⇄ Transfer antar-rekening'),
                  ),
                  IconButton(
                    tooltip: 'Abaikan draf',
                    onPressed: () async {
                      await ref.read(draftRepositoryProvider).ignore(draft.id);
                      _refresh(ref);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Draf diabaikan')),
                        );
                      }
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              )
            else if (draft.status == DraftStatus.duplicate)
              OutlinedButton(
                onPressed: () async {
                  await ref
                      .read(draftRepositoryProvider)
                      .restoreDuplicate(draft.id);
                  _refresh(ref);
                },
                child: const Text('Pulihkan draf'),
              )
            else
              Text(
                draft.status == DraftStatus.saved
                    ? 'Sudah disimpan sebagai transaksi'
                    : 'Draf diabaikan',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  void _refresh(WidgetRef ref) {
    ref.refreshMoneyProviders();
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final session = ref.read(sessionProvider);
    final id = await ref
        .read(draftRepositoryProvider)
        .save(draft.id, memberEmail: session.email);
    _refresh(ref);
    ref.refreshMoneyProviders();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          id == null
              ? 'Draf tidak bisa disimpan'
              : 'Tersimpan — ${labelTipe(draft.type)} ${formatRupiah(draft.amount)}',
        ),
      ),
    );
  }

  Future<void> _changeCategory(BuildContext context, WidgetRef ref) async {
    final categoryId = await pickCategory(context, ref);
    if (categoryId == null) return;
    await ref.read(draftRepositoryProvider).setCategory(draft.id, categoryId);
    _refresh(ref);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kategori draf diperbarui')),
      );
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSeed});

  final Future<void> Function() onSeed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('Tidak ada draf notifikasi'),
            const SizedBox(height: 4),
            Text(
              'Draf muncul otomatis dari notifikasi bank/e-wallet.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onSeed,
              icon: const Icon(Icons.science_outlined),
              label: const Text('Muat draf contoh (uji F4)'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}
