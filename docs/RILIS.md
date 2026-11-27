# Rilis Nyatet — versi, tanda tangan, otomasi

## Naik versi (satu-satunya pemicu rilis)

Ubah satu baris di `pubspec.yaml`:

```yaml
version: 1.0.0+1000001   # x.y.z+versionCode
```

- `x.y.z` = versionName; `+1000001` = versionCode Android. versionCode **tidak boleh** dipakai dua kali untuk package `com.nyatet.nyatet`.
- Skema yang dipakai tim rilis: `MAJOR*1000000 + MINOR*10000 + PATCH*100 + build`, build 1–99 (mis. `1.0.0+1000001`, `1.0.1+1000101`).
- Commit di branch mana pun selain `main`, lalu push. Workflow `release-pr` akan membuat PR `release: vX.Y.Z+build` dan mengaktifkan auto-merge (squash). Merge hanya terjadi bila check `ci` hijau.
- Selama bercabang, workflow `release-pr` hanya mengurus PR yang judulnya `release: v...`; PR buatan manusia tidak disentuh.
- Setelah merge ke `main`, workflow `release` membuat tag annotated `vX.Y.Z+build` (mis. `v0.1.0+2`) dan GitHub Release berisi APK signed + catatan dari bagian teratas `CHANGELOG.md` + SHA-256 tiap APK.
- Kenaikan `build` saja tetap menjadi rilis baru; aplikasi membaca versionCode dari tag. Tag lama `v0.1.0` (tanpa `+build`) dihitung sebagai build 1.
- Tag hanya dibuat bila versi benar-benar bertambah dibanding tag terakhir, dan hanya setelah build + verifikasi tanda tangan berhasil. Build gagal = tidak ada tag, tidak ada Release.
- Sejak REL-04 ada dua flavor: rilis memuat `nyatet-v<versi>-sideload.apk` dan `nyatet-v<versi>-play.apk`; aplikasi sideload memilih aset yang namanya memuat `sideload`.
- Tulis bagian `## ` baru di `CHANGELOG.md` untuk setiap versi — bagian teratas dipakai sebagai catatan rilis.

## Secrets yang dibutuhkan (nama saja)

| Secret | Isi |
|---|---|
| `KEYSTORE_BASE64` | isi file keystore rilis, base64 |
| `KEYSTORE_PASSWORD` | kata sandi keystore |
| `KEY_ALIAS` | alias kunci (`nyatet-upload`) |
| `KEY_PASSWORD` | kata sandi kunci |

Keystore rilis disimpan **di luar repo**; `android/key.properties` dibuat saat CI berjalan dan tidak pernah di-commit (lihat `.gitignore`).

## Build rilis lokal

```bash
cat > android/key.properties <<PW
storePassword=<sandi>
keyPassword=<sandi>
keyAlias=nyatet-upload
storeFile=/jalur/ke/nyatet-upload.jks
PW
flutter build apk --release
```

Build rilis **gagal dengan pesan jelas** bila `android/key.properties` tidak ada — kunci debug tidak dipakai untuk rilis.

Verifikasi tanda tangan:

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

Sidik sertifikat harus sama di setiap versi supaya update bisa dipasang di atas versi lama tanpa uninstall.

## Dua flavor build

```bash
flutter build apk --release --flavor sideload -t lib/main_sideload.dart
flutter build apk --release --flavor play     -t lib/main_play.dart
```

CI dan workflow rilis mendeteksi sendiri apakah gradle punya `productFlavors`; tanpa flavor, satu APK dibangun seperti sebelumnya.
