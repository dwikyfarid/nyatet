// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_flow.dart';
import '../providers.dart';

/// L1 / L1a / L1b / L1c (F1). Satu layar yang berubah menurut status auth,
/// termasuk keadaan yang berbeda kalimatnya — bukan layar error kosong.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _familyName = TextEditingController();

  @override
  void dispose() {
    _familyName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(authFlowProvider);
    return Scaffold(
      body: SafeArea(
        child: switch (flow.stage) {
          AuthStage.booting || AuthStage.working => const _Busy(),
          AuthStage.misconfigured => _Misconfigured(flow: flow),
          AuthStage.needsFamilySetup => _FamilySetup(
              flow: flow,
              controller: _familyName,
            ),
          AuthStage.invited => _AccessStatus(flow: flow, invited: true),
          AuthStage.forbidden => _AccessStatus(flow: flow, invited: false),
          AuthStage.noFamily => _NoFamily(flow: flow),
          AuthStage.expired => _SessionExpired(flow: flow),
          AuthStage.error => _ErrorState(flow: flow),
          AuthStage.signedOut || AuthStage.ready => _Login(flow: flow),
        },
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Menyiapkan sesi…'),
          ],
        ),
      );
}

class _Login extends StatelessWidget {
  const _Login({required this.flow});
  final AuthFlow flow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canGoogle = flow.config.productionReady;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Icon(Icons.savings, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text('Nyatet', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text(
          'Rekap keuangan keluarga yang bisa dipastikan sampai ke tujuannya.',
        ),
        const SizedBox(height: 32),
        if (canGoogle)
          FilledButton.icon(
            onPressed: () => flow.signInWithGoogle(),
            icon: const Icon(Icons.login),
            label: const Text('Masuk dengan Google'),
          )
        else
          FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.login),
            label: const Text('Masuk dengan Google'),
          ),
        if (flow.stubAvailable) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => flow.signInWithStub(),
            icon: const Icon(Icons.science_outlined),
            label: const Text('Masuk sebagai admin uji'),
          ),
          const SizedBox(height: 4),
          Text(
            'Tombol uji hanya ada di build debug tanpa CLIENT_ID; tidak memakai '
            'server dan tidak boleh dianggap sesi produksi.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (!canGoogle && !flow.stubAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Login Google belum dikonfigurasi pada build ini '
              '(GOOGLE_CLIENT_ID kosong).',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (flow.message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              flow.message!,
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 32),
        const Text('Data disimpan di Google Sheet keluarga Anda.'),
      ],
    );
  }
}

class _FamilySetup extends StatelessWidget {
  const _FamilySetup({required this.flow, required this.controller});
  final AuthFlow flow;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Langkah 3 dari 3', style: TextStyle(fontSize: 12)),
            ),
            TextButton(
              onPressed: () => flow.signOut(),
              child: const Text('Keluar'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Satu buku untuk satu keluarga', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Google Sheet pribadi sebagai buku kas keluarga; hanya anggota yang '
          'diundang bisa membuka.',
        ),
        const SizedBox(height: 24),
        TextField(
          controller: controller,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: 'Nama keluarga',
            hintText: '2–40 karakter',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('Kamu masuk sebagai admin'),
            subtitle: const Text(
              'Role dibaca server dari Sheet dan tidak dipilih di layar ini.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => flow.createFamily(controller.text),
          child: const Text('Buat buku keluarga'),
        ),
        const SizedBox(height: 8),
        Text(
          'Aman ditekan dua kali atau dibuka ulang — server mengembalikan buku '
          'yang sama (created: false), bukan buku kedua.',
          style: theme.textTheme.bodySmall,
        ),
        if (flow.message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(flow.message!, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _AccessStatus extends StatelessWidget {
  const _AccessStatus({required this.flow, required this.invited});
  final AuthFlow flow;
  final bool invited;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = flow.session?.email ?? '-';
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Text(
          invited ? 'Menunggu diaktifkan' : 'Aksesmu dicabut admin keluarga',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          invited
              ? 'Undanganmu tercatat (status: invited). Akses aktif otomatis '
                  'saat login pertama dengan email yang diundang.'
              : 'Kamu tidak bisa membuka data keluarga ini lagi.',
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(email),
            subtitle: Text(invited ? 'Tertunda' : 'Akses dicabut'),
          ),
        ),
        if (flow.message != null) ...[
          const SizedBox(height: 8),
          Text(flow.message!, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => flow.retry(),
          child: const Text('Periksa lagi'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => flow.signOut(),
          child: const Text('Keluar'),
        ),
      ],
    );
  }
}

class _NoFamily extends StatelessWidget {
  const _NoFamily({required this.flow});
  final AuthFlow flow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Text(
          'Akun ini belum terhubung ke buku keluarga',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'Email ini belum diundang ke keluarga mana pun. Minta admin '
          'mengundangnya, atau buat buku keluarga baru.',
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => flow.retry(),
          child: const Text('Buat buku keluarga'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => flow.signOut(),
          child: const Text('Keluar'),
        ),
      ],
    );
  }
}

class _SessionExpired extends StatelessWidget {
  const _SessionExpired({required this.flow});
  final AuthFlow flow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = flow.pendingDraftsCount;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Text('Sesi login berakhir', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Masuk lagi dengan Google. Draf di HP tidak dihapus.'),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.inbox_outlined),
            title: Text('$count draf menunggu sinkron'),
            subtitle: const Text(
              'Tersimpan di HP, dikirim otomatis setelah login berhasil.',
            ),
          ),
        ),
        if (flow.message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(flow.message!, style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: 16),
        if (flow.config.productionReady)
          FilledButton(
            onPressed: () => flow.signInWithGoogle(),
            child: const Text('Masuk lagi dengan Google'),
          ),
        if (flow.stubAvailable)
          OutlinedButton(
            onPressed: () => flow.signInWithStub(),
            child: const Text('Masuk sebagai admin uji'),
          ),
      ],
    );
  }
}

class _Misconfigured extends StatelessWidget {
  const _Misconfigured({required this.flow});
  final AuthFlow flow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Icon(Icons.gpp_bad_outlined, color: theme.colorScheme.error, size: 48),
        const SizedBox(height: 16),
        Text('Login belum dikonfigurasi', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(flow.message ?? 'Build ini tidak boleh dipakai tanpa CLIENT_ID.'),
        const SizedBox(height: 16),
        const Text(
          'Build rilis wajib diisi GOOGLE_CLIENT_ID dan APPS_SCRIPT_URL. '
          'Tanpa itu aplikasi menolak jalan, bukan memakai login uji.',
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.flow});
  final AuthFlow flow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Text('Tidak bisa masuk', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(flow.message ?? 'Terjadi kesalahan.'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => flow.retry(),
          child: const Text('Coba lagi'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => flow.signOut(),
          child: const Text('Keluar'),
        ),
      ],
    );
  }
}
