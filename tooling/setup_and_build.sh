#!/bin/bash
# Setup Flutter SDK + build & verifikasi project Nyatet.
# Idempoten: aman dijalankan ulang. Log ke /tmp/nyatet_build.log
set -uo pipefail

WORK=/Users/dwikyfarid/OpenBot/Agents/agent-d0d2dbf5-8669-4822-a48a-37d9b885beeb
TC=$WORK/.toolchain
PROJ=$WORK/nyatet
EXPECTED=2141226529

export JAVA_HOME=$TC/jdk21/Contents/Home
export ANDROID_HOME=$HOME/Library/Android/sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME
export PATH=$TC/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH

log() { echo "[$(date +%H:%M:%S)] $*"; }

# 1. Tunggu flutter.zip selesai (maks ~4 jam)
log "waiting for flutter.zip (target $EXPECTED bytes)..."
for i in $(seq 1 720); do
  sz=$(stat -f%z "$TC/flutter.zip" 2>/dev/null || echo 0)
  if [ "$sz" -ge "$EXPECTED" ]; then log "zip ready ($sz bytes)"; break; fi
  sleep 20
done
sz=$(stat -f%z "$TC/flutter.zip" 2>/dev/null || echo 0)
if [ "$sz" -lt "$EXPECTED" ]; then log "ERROR: flutter.zip belum lengkap: $sz"; exit 1; fi

# 2. Ekstrak SDK
if [ ! -x "$TC/flutter/bin/flutter" ]; then
  log "extracting flutter.zip..."
  unzip -q "$TC/flutter.zip" -d "$TC/"
fi
log "flutter version:"
"$TC/flutter/bin/flutter" --version 2>&1 | head -4

# 3. Arahkan ke Android SDK
"$TC/flutter/bin/flutter" config --android-sdk "$ANDROID_HOME" 2>&1 | tail -2

# 4. Scaffold platform Android (file lib/ & pubspec yang sudah ada tidak ditimpa)
cd "$PROJ" || exit 1
log "flutter create --platforms android"
"$TC/flutter/bin/flutter" create --platforms android --org com.nyatet . 2>&1 | tail -5
rm -f test/widget_test.dart

# 5. Dependensi
log "flutter pub get"
"$TC/flutter/bin/flutter" pub get 2>&1 | tail -25

# 6. Codegen drift
log "build_runner (drift codegen)"
"$TC/flutter/bin/dart" run build_runner build --delete-conflicting-outputs 2>&1 | tail -35

# 7. Analisis statik
log "flutter analyze"
"$TC/flutter/bin/flutter" analyze 2>&1 | tail -50
ANALYZE_EXIT=${PIPESTATUS[0]}

# 8. Unit test
log "flutter test"
"$TC/flutter/bin/flutter" test 2>&1 | tail -50
TEST_EXIT=${PIPESTATUS[0]}

# 9. Build APK debug
log "flutter build apk --debug"
"$TC/flutter/bin/flutter" build apk --debug 2>&1 | tail -70
BUILD_EXIT=${PIPESTATUS[0]}

log "EXIT analyze=$ANALYZE_EXIT test=$TEST_EXIT build=$BUILD_EXIT"
exit 0
