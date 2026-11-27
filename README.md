# nyatet

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Build APK (sejak REL-04 ada dua flavor)

Tidak ada lagi variant `debug` tanpa flavor — `flutter build apk --debug` akan gagal
("Gradle build failed to produce an .apk file"). Perintah yang benar:

```bash
flutter build apk --debug --flavor sideload   # APK uji, memuat cek update GitHub
flutter build apk --debug --flavor play       # build Play, tanpa fitur update
```

Hasilnya `build/app/outputs/flutter-apk/app-sideload-debug.apk` dan
`app-play-debug.apk`.

**Jangan** menjalankan `flutter build apk --debug` tanpa `-t`: perintah itu
memakai `lib/main.dart` (cek update AKTIF) untuk kedua flavor dan bisa menimpa
APK play dengan build yang salah. Pakai `./tooling/build_all.sh` yang membangun
kedua flavor dengan entrypoint benar dan menyimpan artefak bernama versi+jam. Artefak yang diserahkan ke QA disalin ke
`artifacts/nyatet-<versi>-<flavor>-<jam>.apk` supaya satu putaran = satu berkas.
