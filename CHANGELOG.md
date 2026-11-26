# Changelog

Format mengikuti [Keep a Changelog](https://keepachangelog.com/id/1.1.0/).
Versi mengikuti `x.y.z+build` di `pubspec.yaml`, dengan `build` = versionCode Android.
Bagian teratas berkas ini dipakai otomatis sebagai catatan rilis GitHub.

## v0.1.0 — 2026-11-26

Rilis internal pertama (bukan rilis Play Store).

### Ditambahkan
- FS-01: fondasi offline-first — basis data lokal (drift), antrean sinkronisasi, dan kontrak API ke backend Apps Script.
- F4: antrean draf transaksi dari notifikasi bank/e-wallet, termasuk aturan duplikat lintas aplikasi satu bank (D-12).
- F6: input cepat transaksi dan daftar transaksi.
- F8: cockpit/beranda dengan ringkasan masuk, terpakai, disisihkan, dan sisa kas.
- F10: alokasi bulanan dan tujuan dana (setoran/penarikan, progres, status).

### Catatan teknis
- applicationId `com.nyatet.nyatet`, minSdk 24, versi `0.1.0+1`.
- APK rilis ditandatangani keystore rilis terpisah; artefak debug tidak pernah dipakai untuk rilis.
