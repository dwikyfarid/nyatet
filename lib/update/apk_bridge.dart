import 'package:flutter/services.dart';

/// Hasil pemeriksaan satu berkas APK terhadap aplikasi yang terpasang.
class ApkInspection {
  const ApkInspection({
    required this.packageName,
    required this.installedPackageName,
    required this.signatureSha256,
    required this.installedSignatureSha256,
  });

  final String packageName;
  final String installedPackageName;
  final String signatureSha256;
  final String installedSignatureSha256;

  bool get packageMatches =>
      packageName.isNotEmpty && packageName == installedPackageName;

  bool get signatureMatches =>
      signatureSha256.isNotEmpty &&
      signatureSha256 == installedSignatureSha256;
}

/// Jembatan ke Android untuk hal yang tidak bisa dilakukan Dart: membaca
/// paket & sertifikat APK, dan membuka layar pemasangan sistem.
abstract class ApkBridge {
  Future<ApkInspection> inspect(String path);

  /// Membuka intent pemasangan Android. Selalu butuh persetujuan user di
  /// layar sistem; tidak pernah memasang diam-diam.
  Future<bool> openInstaller(String path);
}

class MethodChannelApkBridge implements ApkBridge {
  const MethodChannelApkBridge();

  static const MethodChannel channel = MethodChannel('nyatet/update');

  @override
  Future<ApkInspection> inspect(String path) async {
    final result = await channel.invokeMapMethod<String, Object?>(
      'inspectApk',
      {'path': path},
    );
    if (result == null) {
      throw PlatformException(
        code: 'INSPECT_FAILED',
        message: 'APK tidak bisa dibaca',
      );
    }
    return ApkInspection(
      packageName: '${result['packageName'] ?? ''}',
      installedPackageName: '${result['installedPackageName'] ?? ''}',
      signatureSha256: '${result['signatureSha256'] ?? ''}',
      installedSignatureSha256: '${result['installedSignatureSha256'] ?? ''}',
    );
  }

  @override
  Future<bool> openInstaller(String path) async {
    final opened = await channel.invokeMethod<bool>(
      'installApk',
      {'path': path},
    );
    return opened ?? false;
  }
}
