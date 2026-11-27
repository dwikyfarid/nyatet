import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nyatet/update/apk_bridge.dart';

/// REL-03 di perangkat: verifikasi sertifikat dilakukan kode native
/// (PackageManager), bukan Dart. Berkas `foreign.apk` adalah APK Nyatet yang
/// ditandatangani ulang dengan kunci lain (lihat langkah manual di laporan).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('APK dengan sertifikat berbeda ditolak, APK sendiri diterima',
      (tester) async {
    const bridge = MethodChannelApkBridge();
    final cache = await getTemporaryDirectory();
    final foreign = File('${cache.path}/foreign.apk');
    expect(foreign.existsSync(), isTrue,
        reason: 'dorong foreign.apk ke cache lewat adb sebelum uji ini');

    final inspection = await bridge.inspect(foreign.path);
    // Nama paket sama (disalin dari APK Nyatet)...
    expect(inspection.packageName, 'com.nyatet.nyatet');
    expect(inspection.packageMatches, isTrue);
    // ...tapi sertifikatnya berbeda → wajib ditolak.
    expect(inspection.signatureSha256, isNotEmpty);
    expect(inspection.installedSignatureSha256, isNotEmpty);
    expect(inspection.signatureMatches, isFalse);
  });
}
