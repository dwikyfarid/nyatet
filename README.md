# Nyatet

Pencatat keuangan keluarga untuk Android: transaksi masuk/keluar, anggaran per kategori, alokasi bulanan, dan tujuan dana — tanpa server milik pengembang, tanpa iklan, dan tetap jalan saat offline.

Nyatet dibuat untuk satu keluarga: satu admin (orang tua) menyiapkan "buku" di Google Spreadsheet miliknya sendiri, lalu mengundang anggota. Anggota hanya melihat transaksinya sendiri, boleh mengubah maksimal 7 hari, dan tidak bisa menghapus.

> **Status: pra-rilis.** Belum ada di Google Play Store. Build dibagikan sebagai APK sideload dari halaman [Releases](../../releases).
>
> Rilis `v0.1.0` ditandai **pre-release** dan **jangan dipasang**: build itu dibuat sebelum perbaikan migrasi basis data, sehingga bisa crash saat naik ke versi berikutnya. Pakai rilis terbaru yang tidak berlabel pre-release.

## Fitur saat ini

- Catat transaksi cepat (nominal, kategori, tanggal, catatan) — offline dulu, sinkron kemudian.
- Antrean draf dari notifikasi bank/e-wallet: notifikasi dibaca di HP, lalu jadi draf yang harus Anda setujui.
- Beranda cockpit: uang masuk, terpakai, disisihkan, sisa kas — tiap angka bisa ditelusuri ke transaksinya.
- Anggaran kategori dengan penanda amber (≥80%) dan merah (≥100%) plus teks persentase.
- Alokasi bulanan dan tujuan dana (setoran/penarikan, progres, status).
- Dua flavor build: `sideload` (cek pembaruan sendiri lewat GitHub) dan `play` (untuk Play Store).

## Memasang dan memperbarui (APK sideload)

1. Buka [Releases](../../releases) dan unduh berkas `*-sideload.apk` dari rilis terbaru.
2. Buka berkasnya di HP; bila diminta, izinkan "pasang aplikasi dari sumber ini" untuk aplikasi yang Anda pakai membuka berkas.
3. Versi baru dipasang **di atas versi lama tanpa uninstall**, karena semua rilis ditandatangani dengan kunci yang sama (sertifikat dicantumkan di catatan rilis, begitu pula SHA-256 tiap APK).

Build `sideload` memeriksa rilis GitHub saat dibuka. Sebelum memasang, aplikasi memverifikasi nama paket, sertifikat, dan ukuran APK. Build `play` tidak memeriksa GitHub — pembaruan lewat Play Store.

## Di mana data disimpan

- Transaksi, kategori, anggaran, tujuan dana, dan daftar anggota disimpan di **Google Spreadsheet milik admin keluarga**, dibuat otomatis saat penyiapan.
- Foto nota (bila dipakai) disimpan di **Google Drive admin keluarga**; aplikasi hanya menyimpan tautannya.
- Backend berjalan sebagai **Google Apps Script** di akun admin yang sama. Aplikasi hanya mengirim token Google; hak akses (admin/anggota) diperiksa di server.
- Semua lalu lintas data memakai HTTPS. Tidak ada server milik pengembang, tidak ada SDK iklan atau analitik.

## Notifikasi bank dan e-wallet

Akses notifikasi bersifat opsional dan hanya untuk aplikasi yang Anda daftarkan sendiri (maksimal 12, daftarnya terlihat di aplikasi). Sebelum meminta izin, aplikasi menampilkan penjelasan khusus. Teks notifikasi tidak dikirim ke mana pun; yang disimpan hanya nominal, arah, waktu, dan aplikasi sumber sebagai draf. Izin bisa dicabut kapan saja di Setelan Android → Aplikasi → Nyatet → Akses notifikasi.

## Privasi dan penghapusan data

- Kebijakan privasi: **belum diterbitkan** (sedang disiapkan; tautan final akan dipasang di sini dan di Play Store).
- Permintaan hapus data/akun: tersedia lewat layar Pengaturan di aplikasi; halaman web permintaan hapus belum terbit.

## Bangun sendiri

Prasyarat: Flutter 3.50.1 (stable), JDK 21, Android SDK dengan build-tools.

```bash
flutter pub get
flutter analyze
flutter test

# debug, dua flavor (sejak REL-04 tidak ada varian debug tanpa flavor)
flutter build apk --debug --flavor sideload -t lib/main_sideload.dart
flutter build apk --debug --flavor play     -t lib/main_play.dart

# Jangan jalankan `flutter build apk --debug` tanpa flavor/-t: perintah itu gagal,
# dan tanpa `-t` entrypoint-nya salah (cek update aktif untuk kedua flavor).

# atau sekaligus, dengan artefak bernama versi + jam
./tooling/build_all.sh
```

Build rilis menandatangani APK dengan keystore rilis yang **tidak** ada di repo. Siapkan `android/key.properties` (berkas ini diabaikan git):

```properties
storePassword=<sandi>
keyPassword=<sandi>
keyAlias=<alias>
storeFile=/jalur/ke/keystore.jks
```

Tanpa `android/key.properties`, build rilis sengaja **gagal** — kunci debug tidak pernah dipakai untuk artefak rilis. Rincian otomasi versi, tag, dan rilis ada di [`docs/RILIS.md`](docs/RILIS.md).

## Struktur repo

| Jalur | Isi |
|---|---|
| `lib/` | aplikasi Flutter (data, domain, UI) |
| `test/` | uji unit & widget |
| `backend/` | Apps Script + template Spreadsheet |
| `tooling/` | skrip build |
| `docs/` | catatan rilis |
| `.github/workflows/` | CI, PR rilis otomatis, rilis bertanda tangan |

Versi aplikasi ditentukan satu baris di `pubspec.yaml` (`version: x.y.z+build`); menaikkannya memicu PR rilis otomatis, dan merge ke `main` menghasilkan tag serta GitHub Release berisi APK bertanda tangan.
