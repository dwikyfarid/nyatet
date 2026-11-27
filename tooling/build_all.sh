#!/bin/bash
# Bangun kedua flavor dengan entrypoint yang BENAR dan simpan satu artefak per
# putaran (nama memuat versi + jam, tidak pernah menimpa — D-38).
#
#   ./tooling/build_all.sh
#
# PENTING: `flutter build apk --debug` tanpa `-t` memakai lib/main.dart
# (cek update AKTIF) dan akan menimpa APK play dengan build yang salah.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')     # 0.1.0+2
STAMP=$(date +%H%M)
OUT="$ROOT/artifacts"
mkdir -p "$OUT"

flutter build apk --debug --flavor sideload -t lib/main_sideload.dart
flutter build apk --debug --flavor play -t lib/main_play.dart

cp build/app/outputs/flutter-apk/app-sideload-debug.apk \
   "$OUT/nyatet-$VERSION-sideload-$STAMP.apk"
cp build/app/outputs/flutter-apk/app-play-debug.apk \
   "$OUT/nyatet-$VERSION-play-$STAMP.apk"

echo "artefak:"
ls -l "$OUT"
shasum -a 256 "$OUT"/*"$STAMP".apk
