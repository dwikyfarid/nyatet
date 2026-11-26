// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../config/app_links.dart';

/// Halaman F9/F12 sebelum situs terbit. Menjelaskan keadaan sebenarnya dan
/// menampilkan alamat resmi, bukan tautan mati tanpa keterangan.
class LegalPlaceholderScreen extends StatelessWidget {
  const LegalPlaceholderScreen({
    super.key,
    required this.title,
    required this.url,
  });

  final String title;
  final String url;

  @override
  Widget build(BuildContext context) {
    final pending = AppLinks.notPublishedYet.contains(url);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (pending) ...[
            Row(
              children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Halaman belum terbit',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Tautan ini sudah tersedia di aplikasi, tetapi halamannya belum '
              'dipublikasikan. Sampai terbit, permintaan privasi dan hapus data '
              'dilayani lewat alamat di bawah.',
            ),
            const SizedBox(height: 16),
          ],
          SelectableText(
            url,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}
