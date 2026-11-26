// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_flow.dart';
import 'providers.dart';
import 'screens/onboarding_screen.dart';

/// Gerbang F1: aplikasi hanya bisa dipakai setelah sesi siap. Sesi stub debug
/// tetap ditandai supaya tidak pernah disangka sesi produksi.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authFlowProvider).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(authFlowProvider);
    if (flow.stage == AuthStage.ready) return widget.child;
    return OnboardingScreen();
  }
}
