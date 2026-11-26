import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Pengganti yang disarankan (package:material_ui) belum tersedia di SDK ini,
// jadi import Flutter Material tetap dipakai.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'data/sync/sync_scheduler.dart';
import 'home_shell.dart';
import 'ui/auth_gate.dart';
import 'ui/providers.dart';
import 'ui/widgets/update_dialog.dart';

/// Titik masuk default = build `sideload` (memuat cek update, REL-03).
/// Build Play memakai `lib/main_play.dart` yang mematikan fitur ini (REL-04).
Future<void> main() => bootstrap(enableUpdateChecker: true);

Future<void> bootstrap({required bool enableUpdateChecker}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer(
    overrides: [
      updateEnabledProvider.overrideWithValue(enableUpdateChecker),
    ],
  );
  // Kategori awal supaya pemilihan kategori bisa dipakai offline (F6/F7).
  await container.read(databaseProvider).seedDefaultCategories();
  unawaited(registerBackgroundSync());
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const NyatetApp(),
    ),
  );
}

class NyatetApp extends ConsumerStatefulWidget {
  const NyatetApp({super.key});

  @override
  ConsumerState<NyatetApp> createState() => _NyatetAppState();
}

class _NyatetAppState extends ConsumerState<NyatetApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _connectivitySub = registerConnectivityTrigger();
    // REL-03: cek otomatis maks 1×/24 jam, tidak memblokir UI. Build `play`
    // tidak pernah membaca layanan update.
    if (ref.read(updateEnabledProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoCheckUpdate());
    }
  }

  Future<void> _autoCheckUpdate() async {
    final service = ref.read(updateServiceProvider);
    final result = await service.autoCheckIfDue();
    final release = result?.release;
    if (release == null || result?.hasUpdate != true) return;
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await showUpdateDialog(
      context,
      service: service,
      release: release,
      onBusyChanged: () {},
      onFinished: (install) async {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(install.message)),
        );
      },
    );
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nyatet',
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1B5FB0),
        useMaterial3: true,
      ),
      home: const AuthGate(child: _Shell()),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(child: HomeShell()),
    );
  }
}
