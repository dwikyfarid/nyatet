// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../domain/transaction_service.dart';
import '../format.dart';
import '../providers.dart';
import '../widgets/category_selector.dart';

/// L6a — Quick-add transaksi (D-18): satu layar, maks 5 field, default
/// keluar / hari ini / diri sendiri. Dipakai untuk F6.
class QuickAddScreen extends ConsumerStatefulWidget {
  const QuickAddScreen({super.key});

  @override
  ConsumerState<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends ConsumerState<QuickAddScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _refController = TextEditingController();
  String _type = TransactionType.outFlow;
  DateTime _date = DateTime.now();
  String? _categoryId;
  String? _memberEmail;
  bool _showNote = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _refController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseRupiah(_amountController.text);
    if (amount <= 0) {
      setState(() => _error = 'Nominal wajib diisi dan lebih dari nol');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final service = ref.read(transactionServiceProvider);
      final policy = ref.read(accessPolicyProvider);
      await service.createManual(
        policy: policy,
        date: _date,
        type: _type,
        amount: amount,
        categoryId: _categoryId,
        memberEmail: _memberEmail,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        refNo: _refController.text.trim().isEmpty
            ? null
            : _refController.text.trim(),
      );
      // F8: beranda harus langsung ikut berubah, bukan setelah restart.
      ref.refreshMoneyProviders();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AccessDenied catch (e) {
      setState(() {
        _error = e.reason;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Catat Transaksi')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: TransactionType.outFlow, label: Text('Keluar')),
              ButtonSegment(value: TransactionType.inFlow, label: Text('Masuk')),
              ButtonSegment(value: TransactionType.transfer, label: Text('Transfer')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            style: Theme.of(context).textTheme.headlineMedium,
            decoration: InputDecoration(
              labelText: 'Jumlah',
              prefixText: 'Rp ',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Text('Kategori', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          categories.when(
            data: (list) => CategorySelector(
              categories: list,
              selectedId: _categoryId,
              onSelected: (id) => setState(() => _categoryId = id),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Kategori gagal dimuat: $e'),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: const Text('Tanggal'),
            subtitle: Text(formatTanggal(_date)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          if (session.isAdmin)
            DropdownButtonFormField<String>(
              initialValue: _memberEmail ?? session.email,
              decoration: const InputDecoration(
                labelText: 'Anggota',
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: session.email, child: Text('${session.name} (saya)')),
              ],
              onChanged: (v) => setState(() => _memberEmail = v),
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: const Text('Anggota'),
              subtitle: Text(session.email),
            ),
          const SizedBox(height: 8),
          if (!_showNote)
            TextButton.icon(
              onPressed: () => setState(() => _showNote = true),
              icon: const Icon(Icons.notes),
              label: const Text('Tambah catatan'),
            )
          else
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                border: OutlineInputBorder(),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Simpan transaksi'),
          ),
        ),
      ),
    );
  }
}
