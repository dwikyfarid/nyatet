/// Data rilis GitHub yang dipakai fitur cek update (REL-03).
///
/// Repo publik, tanpa token: semua data di sini berasal dari GitHub Releases
/// API dan tidak boleh dipercaya sebelum APK-nya diverifikasi
/// (ukuran + nama paket + sertifikat tanda tangan).
library;

/// Versi yang sedang terpasang di HP (dari PackageInfo).
class InstalledVersion {
  const InstalledVersion({
    required this.versionName,
    required this.versionCode,
  });

  final String versionName;
  final int versionCode;

  String get label => '$versionName ($versionCode)';
}

/// Satu rilis GitHub yang punya aset APK.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.versionName,
    required this.assetName,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.notes,
    this.versionCode,
  });

  final String tag;

  /// Tanpa awalan `v`, mis. `0.2.0`.
  final String versionName;
  final int? versionCode;
  final String assetName;
  final Uri downloadUrl;
  final int sizeBytes;

  /// Maksimal 3 baris (UX: dialog tidak boleh penuh).
  final List<String> notes;

  /// Versi lebih baru bila versionCode lebih tinggi; bila rilis tidak
  /// menyertakan versionCode, bandingkan versionName secara numerik.
  bool isNewerThan(InstalledVersion installed) {
    final remoteCode = versionCode;
    if (remoteCode != null) return remoteCode > installed.versionCode;
    return compareVersionNames(versionName, installed.versionName) > 0;
  }

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024) {
      final mb = sizeBytes / (1024 * 1024);
      return '${mb.toStringAsFixed(1)} MB';
    }
    final kb = sizeBytes / 1024;
    return '${kb.toStringAsFixed(0)} KB';
  }
}

/// Bandingkan `1.10.0` vs `1.9.2` secara numerik per bagian.
/// Mengembalikan >0 bila [a] lebih baru.
int compareVersionNames(String a, String b) {
  List<int> parts(String v) {
    final clean = v.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final core = clean.split('+').first.split('-').first;
    return core
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }

  final pa = parts(a);
  final pb = parts(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va - vb;
  }
  return 0;
}

/// `v0.2.0+3`, `v0.2.0-code3`, `0.2.0 (build 3)` → 3.
int? versionCodeFromText(String? text) {
  if (text == null) return null;
  final match = RegExp(r'(?:\+|build\s*|code\s*)(\d+)', caseSensitive: false)
      .firstMatch(text);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// Buang penanda versi dari tag: `v0.2.0+3` → `0.2.0`.
String versionNameFromTag(String tag) {
  var name = tag.trim().replaceFirst(RegExp(r'^[vV]'), '');
  name = name.split('+').first;
  name = name.split(RegExp(r'-(?:code|build)')).first;
  return name;
}

/// Ambil maksimal [maxLines] baris pertama yang tidak kosong.
List<String> trimReleaseNotes(String body, {int maxLines = 3}) {
  final lines = body
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .take(maxLines)
      .toList();
  return lines;
}

/// Ubah balasan `releases/latest` menjadi [ReleaseInfo]. Null bila tidak ada
/// aset APK (mis. rilis catatan saja) supaya app menampilkan "tidak ada update"
/// daripada memasang berkas yang salah.
ReleaseInfo? parseReleaseJson(Map<String, Object?> json) {
  final assets = (json['assets'] as List?) ?? const [];
  final apkAssets = assets
      .whereType<Map>()
      .where((a) => '${a['name']}'.toLowerCase().endsWith('.apk'))
      .toList();
  if (apkAssets.isEmpty) return null;

  // Utamakan aset sideload bila rilis menyediakan dua APK.
  final asset = apkAssets.firstWhere(
    (a) => '${a['name']}'.toLowerCase().contains('sideload'),
    orElse: () => apkAssets.first,
  );

  final tag = (json['tag_name'] as String?)?.trim().isNotEmpty == true
      ? json['tag_name']! as String
      : '${json['name'] ?? 'rilis'}';
  final url = Uri.tryParse('${asset['browser_download_url'] ?? ''}');
  if (url == null || !url.isScheme('https')) return null;

  final assetName = '${asset['name']}';
  return ReleaseInfo(
    tag: tag,
    versionName: versionNameFromTag(tag),
    versionCode: versionCodeFromText(tag) ?? versionCodeFromText(assetName),
    assetName: assetName,
    downloadUrl: url,
    sizeBytes: ((asset['size'] as num?) ?? 0).toInt(),
    notes: trimReleaseNotes('${json['body'] ?? ''}'),
  );
}
