// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_links.dart';
import '../../update/update_models.dart';
import '../../update/update_service.dart';
import '../providers.dart';
import '../widgets/update_dialog.dart';
import 'legal_placeholder_screen.dart';

/// Pengaturan (REL-03). Baris cek update hanya dirender pada build
/// `sideload`; build `play` tidak pernah membaca layanan update sama sekali.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  UpdateCheckResult? _result;
  DateTime? _lastChecked;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(updateEnabledProvider)) {
      _loadLastChecked();
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoCheck());
    }
  }

  Future<void> _loadLastChecked() async {
    final service = ref.read(updateServiceProvider);
    final at = await service.lastCheckedAt();
    if (!mounted) return;
    setState(() => _lastChecked = at);
  }

  /// Cek otomatis: tidak memblokir UI, tidak jalan saat offline.
  Future<void> _autoCheck() async {
    final service = ref.read(updateServiceProvider);
    final result = await service.autoCheckIfDue();
    if (!mounted || result == null) return;
    setState(() {
      _result = result;
      _lastChecked = result.checkedAt;
    });
    if (result.hasUpdate) {
      await _showUpdate(service, result.release!);
    }
  }

  Future<void> _checkNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    final service = ref.read(updateServiceProvider);
    final result = await service.check();
    if (!mounted) return;
    setState(() {
      _result = result;
      _lastChecked = result.checkedAt;
      _busy = false;
    });
    if (result.hasUpdate) {
      await _showUpdate(service, result.release!);
    } else if (result.status == UpdateStatus.upToDate) {
      // UX: menekan tombol harus selalu memberi jawaban, termasuk saat
      // hasilnya "tidak ada versi baru".
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Diperiksa ${_clock(result.checkedAt)} — sudah versi terbaru',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Tidak bisa cek update')),
      );
    }
  }

  Future<void> _showUpdate(UpdateService service, ReleaseInfo release) async {
    if (!mounted) return;
    await showUpdateDialog(
      context,
      service: service,
      release: release,
      onBusyChanged: () {
        if (mounted) setState(() => _busy = !_busy);
      },
      onFinished: (InstallResult result) async {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      },
    );
  }

  String _clock(DateTime at) {
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  String _timeLabel(DateTime? at) {
    if (at == null) return 'Belum pernah';
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final updateEnabled = ref.watch(updateEnabledProvider);
    final installed = ref.watch(installedVersionProvider);
    final result = _result;
    final failure = result != null &&
        (result.status == UpdateStatus.failed ||
            result.status == UpdateStatus.offline);

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          installed.when(
            loading: () => const ListTile(
              title: Text('Versi aplikasi'),
              subtitle: Text('Memuat…'),
            ),
            error: (_, __) => const ListTile(
              title: Text('Versi aplikasi'),
              subtitle: Text('Tidak bisa dibaca'),
            ),
            data: (v) => ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Versi aplikasi'),
              subtitle: Text(v.label),
            ),
          ),
          const Divider(),
          // F9/F12: tautan kebijakan privasi & hapus data, URL dari satu
          // konstanta konfigurasi (bukan hardcode di widget).
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Kebijakan privasi'),
            subtitle: const Text(AppLinks.privacyPolicy),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LegalPlaceholderScreen(
                  title: 'Kebijakan privasi',
                  url: AppLinks.privacyPolicy,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined),
            title: const Text('Hapus data akun'),
            subtitle: const Text(AppLinks.deleteData),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LegalPlaceholderScreen(
                  title: 'Hapus data akun',
                  url: AppLinks.deleteData,
                ),
              ),
            ),
          ),
          if (updateEnabled) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.system_update_alt),
              title: const Text('Cek update sekarang'),
              subtitle: Text('Terakhir dicek: ${_timeLabel(_lastChecked)}'),
              trailing: _busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _busy ? null : _checkNow,
            ),
            if (failure)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.cloud_off),
                    title: Text(result.message ?? 'Tidak bisa cek update'),
                    trailing: TextButton(
                      onPressed: _busy ? null : _checkNow,
                      child: const Text('Coba lagi'),
                    ),
                  ),
                ),
              ),
            if (result?.status == UpdateStatus.upToDate)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('Sudah versi terbaru'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
