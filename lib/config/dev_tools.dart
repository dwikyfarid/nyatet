import 'package:flutter/foundation.dart';

/// D-47: alat uji (Menu pengujian: ganti sesi admin/anggota, muat data uji)
/// TIDAK boleh ikut build rilis.
///
/// Aturan: `kReleaseMode` SELALU menang. Build rilis tidak bisa mengaktifkan
/// alat uji lewat `--dart-define=DEV_TOOLS=true`; hanya build non-rilis yang
/// boleh memakai flag itu (mis. build uji khusus).
bool resolveDevToolsEnabled({
  required bool releaseMode,
  required bool flag,
}) =>
    !releaseMode && flag;

const bool kDevToolsEnabled = !kReleaseMode &&
    bool.fromEnvironment('DEV_TOOLS', defaultValue: true);
