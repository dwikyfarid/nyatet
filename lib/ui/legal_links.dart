import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bisa di-override di uji supaya tidak benar-benar membuka browser.
final legalLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

enum LegalLinkAction { openBrowser, disabled }

/// Satu aturan untuk tautan legal (D-45): tanpa flag, tanpa halaman pengganti.
class LegalLinkState {
  const LegalLinkState({required this.action, this.reason});

  final LegalLinkAction action;
  final String? reason;

  bool get enabled => action == LegalLinkAction.openBrowser;

  static LegalLinkState resolve(String url) {
    final value = url.trim();
    if (value.isEmpty) {
      return const LegalLinkState(
        action: LegalLinkAction.disabled,
        reason: 'Halaman belum terbit',
      );
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      return const LegalLinkState(
        action: LegalLinkAction.disabled,
        reason: 'Tautan tidak valid (harus http/https)',
      );
    }
    return const LegalLinkState(action: LegalLinkAction.openBrowser);
  }
}

/// Membuka URL di browser lewat intent ACTION_VIEW. Mengembalikan false bila
/// tautan belum siap atau peluncur gagal — tidak ada jalur halaman in-app.
Future<bool> openLegalUrl(
  String url, {
  Future<bool> Function(Uri)? launcher,
}) async {
  final state = LegalLinkState.resolve(url);
  if (!state.enabled) return false;
  final launch = launcher ??
      (u) => launchUrl(u, mode: LaunchMode.externalApplication);
  try {
    return await launch(Uri.parse(url.trim()));
  } catch (_) {
    return false;
  }
}
