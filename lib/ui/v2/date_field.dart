// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

/// U1: satu komponen input tanggal bersama. Tidak ada `showDatePicker` mentah
/// di layar; keyboard sistem tidak muncul. Label periode seragam `Nov 2026`.
class NyatetDateField extends StatelessWidget {
  const NyatetDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onPicked,
    this.monthOnly = false,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onPicked;
  final bool monthOnly;

  static String monthLabel(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return '${months[date.toLocal().month - 1]} ${date.toLocal().year}';
  }

  static String display(DateTime date, {bool monthOnly = false}) {
    if (monthOnly) return '${monthLabel(date)} ▾';
    final local = date.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: ${display(value, monthOnly: monthOnly)}',
      button: true,
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
            helpText: label,
            initialDatePickerMode:
                monthOnly ? DatePickerMode.year : DatePickerMode.day,
          );
          if (picked != null) onPicked(picked);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_month, size: 18),
              const SizedBox(width: 8),
              Text(display(value, monthOnly: monthOnly)),
            ],
          ),
        ),
      ),
    );
  }
}
