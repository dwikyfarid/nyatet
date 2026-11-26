// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../providers.dart';

/// Pemilih kategori ringkas: chip, maksimal 7 pilihan + "Lainnya" (UX-09).
class CategorySelector extends StatelessWidget {
  const CategorySelector({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    this.accent,
  });

  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final Color? accent;

  static const int _visibleLimit = 6;

  @override
  Widget build(BuildContext context) {
    final visible = categories.take(_visibleLimit).toList();
    final rest = categories.skip(_visibleLimit).toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in visible)
          ChoiceChip(
            label: Text(c.name),
            selected: c.id == selectedId,
            onSelected: (_) => onSelected(c.id),
          ),
        if (rest.isNotEmpty)
          ActionChip(
            label: const Text('Lainnya'),
            onPressed: () async {
              final picked = await showModalBottomSheet<Category>(
                context: context,
                showDragHandle: true,
                builder: (ctx) => SafeArea(
                  child: ListView(
                    children: [
                      for (final c in rest)
                        ListTile(
                          title: Text(c.name),
                          onTap: () => Navigator.of(ctx).pop(c),
                        ),
                    ],
                  ),
                ),
              );
              if (picked != null) onSelected(picked.id);
            },
          ),
      ],
    );
  }
}

/// Bottom sheet pemilih kategori (dipakai antrean F4 & edit F6).
Future<String?> pickCategory(BuildContext context, WidgetRef ref) async {
  final categories = await ref.read(categoriesProvider.future);
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Pilih kategori'),
          ),
          for (final c in categories)
            ListTile(
              title: Text(c.name),
              onTap: () => Navigator.of(ctx).pop(c.id),
            ),
        ],
      ),
    ),
  );
}
