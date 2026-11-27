# Changelog

Format mengikuti [Keep a Changelog](https://keepachangelog.com/id/1.1.0/).
Versi mengikuti `x.y.z+build` di `pubspec.yaml`, dengan `build` = versionCode Android.
Bagian teratas berkas ini dipakai otomatis sebagai catatan rilis GitHub.

## v0.1.0+3 — 2026-11-28

### Diperbaiki
- **D-47 / D-51 — alat uji tidak dirender di build rilis.** "Menu pengujian" (ganti sesi jadi admin tanpa login, muat 200 transaksi uji) digerbang `!kReleaseMode`; `--dart-define=DEV_TOOLS` tidak bisa mengaktifkannya. Bukti artefak: `libapp.so` identik untuk `DEV_TOOLS=true` dan `false` pada kedua flavor; QA mengonfirmasi 0 elemen menu uji di perangkat.
- **D-48 / F7 — layar alokasi** menampilkan terpakai, persen, dan bar.

### Ditambahkan
- **D-45 — tautan legal satu perilaku.** Selama URL belum terbit, barisnya nonaktif dengan alasan yang terlihat; browser hanya dibuka setelah URL diisi. Tidak memakai flag build.
- **D-53 — cek pembaruan.** Pemeriksaan otomatis paling sering sekali per 24 jam; cek manual dari layar Pengaturan tidak menunggu jeda itu.
- Dua flavor build: `sideload` (cek pembaruan lewat GitHub Releases) dan `play` (tanpa cek pembaruan, untuk Play Store).

### Catatan teknis
- versionName tetap `0.1.0`, versionCode `3`.
- Upgrade dari versionCode 1/2 ke 3 tanpa uninstall sudah diuji (migrasi skema, angka tetap sama).
- Pemasang `v0.1.0` dan `v0.1.0+2` silakan perbarui ke versi ini; keduanya ditarik (pre-release sebelum perbaikan migrasi, dan `+2` masih memuat Menu pengujian).

## v0.1.0+2 — belum dirilis

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
