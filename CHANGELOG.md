# Changelog

Format mengikuti [Keep a Changelog](https://keepachangelog.com/id/1.1.0/).
Versi mengikuti `x.y.z+build` di `pubspec.yaml`, dengan `build` = versionCode Android.
Bagian teratas berkas ini dipakai otomatis sebagai catatan rilis GitHub.

## v0.1.0+3 — 2026-11-28

Rilis pertama lewat GitHub Releases sejak v0.1.0. Sudah mencakup semua perubahan v0.1.0+2 (tidak dirilis terpisah).

### Diperbaiki
- Menu pengujian (ganti sesi admin/anggota, muat data uji) tidak lagi ikut di build rilis (D-47).

### Ditambahkan
- Layar alokasi menampilkan dana terpakai, persentase, dan bar per alokasi (F7, D-48).

## v0.1.0+2 — digabung ke v0.1.0+3

Menunggu PR #2 lulus QA.

### Diperbaiki
- Migrasi basis data v2/v3 → v4 tidak lagi crash (D-32, D-34, D-36); `updated_at` dijamin terisi setelah migrasi.
- Panah budget selalu turun dan bahaya disampaikan lewat teks, bukan warna saja (D-11).
- Tombol Catat di beranda, setoran ke tujuan (D-23), serta alasan aksi yang ditolak ditampilkan.
- Angka beranda tidak lagi basi setelah transaksi disimpan.

### Ditambahkan
- Cek pembaruan lewat GitHub Releases untuk build sideload (REL-03/REL-04), dengan verifikasi paket dan sertifikat sebelum memasang APK.
- Dua flavor build: `sideload` (cek update aktif) dan `play` (bersih untuk Play Store).
- Tautan kebijakan privasi dan hapus data di layar Pengaturan.
- `tooling/build_all.sh` untuk membangun kedua flavor dengan entrypoint yang benar.

### Catatan teknis
- versionName tetap `0.1.0`, versionCode naik ke `2` supaya pembaruan bisa dipasang di atas build 1 tanpa uninstall.

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
