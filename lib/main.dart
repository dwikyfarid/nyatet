import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Pengganti yang disarankan (package:material_ui) belum tersedia di SDK ini,
// jadi import Flutter Material tetap dipakai.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'data/sync/sync_scheduler.dart';
import 'home_shell.dart';
import 'ui/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _connectivitySub = registerConnectivityTrigger();
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
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1B5FB0), useMaterial3: true),
      home: const _Shell(),
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
