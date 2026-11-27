import 'package:flutter/foundation.dart';

/// D-47: alat uji (Menu pengujian: ganti sesi admin/anggota, muat data uji)
/// TIDAK boleh ikut build rilis.
///
/// Default: aktif hanya di debug, mati di release. Bisa dipaksa untuk build
/// uji khusus dengan `--dart-define=DEV_TOOLS=true`, tetapi build rilis tidak
/// pernah mengaktifkannya secara default.
const bool kDevToolsEnabled = bool.fromEnvironment(
  'DEV_TOOLS',
  defaultValue: kDebugMode,
);
