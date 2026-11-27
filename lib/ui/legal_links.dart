import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// `LINKS_LIVE=true` (build-time) menandai URL legal sudah final. Sebelum itu
/// ketukan hanya memberi pemberitahuan jujur — tidak membuka halaman palsu.
const bool kLinksLive = bool.fromEnvironment('LINKS_LIVE', defaultValue: false);

/// Bisa di-override di uji.
final linksLiveProvider = Provider<bool>((ref) => kLinksLive);

final legalLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

const String kLinksPendingMessage = 'Halaman belum terbit — URL final belum ada';

enum LegalLinkAction {
  /// Buka browser (intent ACTION_VIEW).
  openBrowser,

  /// Tautan belum final: tampilkan pemberitahuan, jangan buka apa pun.
  showPendingNotice,

  /// URL kosong/tidak sah: baris nonaktif dengan alasan.
  disabled,
}

class LegalLinkState {
  const LegalLinkState({required this.action, this.reason});

  final LegalLinkAction action;
  final String? reason;

  bool get enabled => action != LegalLinkAction.disabled;

  /// Aturan tunggal, dipakai widget dan uji.
  static LegalLinkState resolve(String url, {required bool live}) {
    final value = url.trim();
    if (value.isEmpty) {
      return const LegalLinkState(
        action: LegalLinkAction.disabled,
        reason: 'Tautan belum diisi pada build ini',
      );
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      return const LegalLinkState(
        action: LegalLinkAction.disabled,
        reason: 'Tautan tidak valid (harus http/https)',
      );
    }
    return LegalLinkState(
      action: live ? LegalLinkAction.openBrowser : LegalLinkAction.showPendingNotice,
      reason: live ? null : kLinksPendingMessage,
    );
  }
}

/// Membuka URL di browser lewat intent ACTION_VIEW. Saat `live=false`,
/// launcher TIDAK dipanggil sama sekali.
Future<bool> openLegalUrl(
  String url, {
  required bool live,
  Future<bool> Function(Uri)? launcher,
}) async {
  final state = LegalLinkState.resolve(url, live: live);
  if (state.action != LegalLinkAction.openBrowser) return false;
  final launch = launcher ??
      (u) => launchUrl(u, mode: LaunchMode.externalApplication);
  try {
    return await launch(Uri.parse(url.trim()));
  } catch (_) {
    return false;
  }
}
