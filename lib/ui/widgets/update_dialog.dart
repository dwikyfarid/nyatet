// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../update/update_models.dart';
import '../../update/update_service.dart';

/// Dialog update (REL-03): versi baru, ukuran, ≤3 baris catatan, dua tombol.
/// "Nanti" hanya menunda 24 jam — tidak pernah memasang apa pun sendiri;
/// pemasangan tetap lewat layar persetujuan Android.
Future<void> showUpdateDialog(
  BuildContext context, {
  required UpdateService service,
  required ReleaseInfo release,
  required VoidCallback onBusyChanged,
  required Future<void> Function(InstallResult result) onFinished,
}) async {
  final action = await showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      title: Text('Versi ${release.versionName} tersedia'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ukuran: ${release.sizeLabel}'),
          if (release.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final line in release.notes.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $line'),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop('later'),
          child: const Text('Nanti'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop('install'),
          child: const Text('Unduh & pasang'),
        ),
      ],
    ),
  );

  if (action == 'later') {
    await service.snooze();
    return;
  }
  if (action != 'install') return;

  onBusyChanged();
  final result = await service.downloadAndInstall(release);
  onBusyChanged();
  await onFinished(result);
}
