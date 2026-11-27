// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/account_deletion.dart';
import '../../auth/apps_script_api.dart';
import '../providers.dart';

/// Teks dialog F12 — diekspor supaya bisa diuji tanpa widget test.
const String kMemberDeletionBulletTransactions =
    '• Transaksi keluarga tetap ada dan berubah menjadi "Anggota dihapus".';
const String kMemberDeletionBulletIrreversible = '• Akun tidak bisa dipulihkan.';
const String kMemberDeletionBulletSession = '• Sesi di perangkat ini berakhir.';
const String kMemberDeletionButton = 'Hapus akun saya';
const String kLastAdminWarning =
    'Semua baris di 7 tab keluarga dihapus dan tidak bisa dikembalikan. '
    'Folder nota ikut di-trash.';

/// F12 — jalur hapus akun dari Pengaturan. Tidak pernah menghapus data lokal
/// dan tidak pernah menampilkan sukses sebelum server menjawab.
Future<void> startDeleteAccount(BuildContext context, WidgetRef ref) async {
  final flow = ref.read(authFlowProvider);
  final session = flow.session;
  if (session == null || session.isStub) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Hapus akun butuh sesi Google, bukan mode uji.'),
      ),
    );
    return;
  }

  final service = AccountDeletionService(
    api: flow.api,
    token: session.token,
    email: session.email,
    role: session.role,
    familyName: session.familyName ?? '',
    signOut: flow.signOut,
  );

  DeletionPlan plan;
  try {
    plan = await service.plan();
  } on ApiException catch (e) {
    if (context.mounted) await _showFailure(context, e.message);
    return;
  }
  if (!context.mounted) return;

  switch (plan.mode) {
    case DeletionMode.member:
      await showMemberDeletionConfirm(context, service);
    case DeletionMode.adminWithOthers:
      await _adminBlocked(context, plan.message ?? 'Masih ada anggota aktif.');
    case DeletionMode.lastAdmin:
      await showLastAdminDeletionConfirm(context, service, plan.familyName);
  }
}

Future<void> showMemberDeletionConfirm(
  BuildContext context,
  AccountDeletionService service,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Hapus akun ini?'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kMemberDeletionBulletTransactions),
          SizedBox(height: 6),
          Text(kMemberDeletionBulletIrreversible),
          SizedBox(height: 6),
          Text(kMemberDeletionBulletSession),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text(kMemberDeletionButton),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final outcome = await service.deleteAccount();
  if (!context.mounted) return;
  if (outcome.ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(outcome.message)),
    );
  } else {
    await _showFailure(context, outcome.message, retry: service.deleteAccount);
  }
}

Future<void> _adminBlocked(BuildContext context, String message) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Belum bisa menghapus akun'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}

Future<void> showLastAdminDeletionConfirm(
  BuildContext context,
  AccountDeletionService service,
  String familyName,
) async {
  final controller = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Hapus seluruh keluarga?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(kLastAdminWarning),
            const SizedBox(height: 12),
            Text('Ketik nama keluarga persis: $familyName'),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Nama keluarga',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: controller.text == familyName
                ? () => Navigator.of(ctx).pop(true)
                : null,
            child: const Text('Hapus keluarga'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final outcome = await service.deleteFamily(controller.text);
  if (!context.mounted) return;
  if (outcome.ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(outcome.message)),
    );
  } else {
    await _showFailure(
      context,
      outcome.message,
      retry: () => service.deleteFamily(controller.text),
    );
  }
}

/// Kegagalan: tidak ada perubahan lokal, ada tombol coba lagi.
Future<void> _showFailure(
  BuildContext context,
  String message, {
  Future<DeletionOutcome> Function()? retry,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Penghapusan gagal'),
      content: Text('$message\n\nTidak ada data yang dihapus.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Tutup'),
        ),
        if (retry != null)
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Coba lagi'),
          ),
      ],
    ),
  );
}
