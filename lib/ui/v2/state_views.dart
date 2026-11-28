// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Papan state wajib U1: kosong, memuat (skeleton setinggi kartu asli),
/// error bagian gagal saja, dan offline. Satu komponen untuk semua layar.
class NyatetSkeletonCard extends StatelessWidget {
  const NyatetSkeletonCard({super.key, this.height = 96});

  final double height;

  @override
  Widget build(BuildContext context) {
    final t = NyatetTokens.of(context);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: t.divider.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(t.radius),
      ),
    );
  }
}

class NyatetEmptyState extends StatelessWidget {
  const NyatetEmptyState({
    super.key,
    required this.title,
    this.action,
    this.actionLabel,
  });

  final String title;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final t = NyatetTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: TextStyle(color: t.label)),
            if (action != null && actionLabel != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: action, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error hanya untuk bagian yang gagal (D-30), bukan seluruh layar.
class NyatetErrorSection extends StatelessWidget {
  const NyatetErrorSection({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = NyatetTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.redBg,
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: t.redText, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}

class NyatetOfflineBanner extends StatelessWidget {
  const NyatetOfflineBanner({super.key, this.onRetry});
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = NyatetTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.amberBg,
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: t.amberText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline — data lokal, sinkronisasi tertunda',
              style: TextStyle(color: t.amberText),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}
