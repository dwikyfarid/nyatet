#!/bin/bash
# Build mandiri: jaga unduhan Flutter tetap hidup, lalu setup + verifikasi.
# Aman dijalankan ulang. Log: /tmp/nyatet_build.log
set -uo pipefail

WORK=/Users/dwikyfarid/OpenBot/Agents/agent-d0d2dbf5-8669-4822-a48a-37d9b885beeb
TC=$WORK/.toolchain
EXPECTED=2141226529
URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_3.50.1-stable.zip"
LOG=/tmp/nyatet_build.log

log() { echo "[$(date +%H:%M:%S)] $*" >>"$LOG"; }

size() { stat -f%z "$TC/flutter.zip" 2>/dev/null || echo 0; }

# --- 1. Jaga unduhan: restart curl bila berhenti / macet >5 menit -----------
log "=== watcher unduhan dimulai (size=$(size)) ==="
stall=0
prev=$(size)
while [ "$(size)" -lt "$EXPECTED" ]; do
  sleep 30
  cur=$(size)
  if ! pgrep -f "curl.*flutter_macos_3.50.1-stable.zip" >/dev/null; then
    log "curl mati, restart (size=$cur)"
    (cd "$TC" && setsid curl -sL -C - --retry 50 --retry-all-errors --retry-delay 5 \
        --max-time 36000 -o flutter.zip "$URL" >/dev/null 2>&1) &
  fi
  if [ "$cur" -le "$prev" ]; then
    stall=$((stall+30))
    if [ "$stall" -ge 300 ]; then
      log "macet 5 menit (size=$cur), paksa restart curl"
      pkill -f "curl.*flutter_macos_3.50.1-stable.zip" 2>/dev/null
      stall=0
    fi
  else
    stall=0
  fi
  prev=$cur
  log "progress $((cur/1024/1024)) MB / $((EXPECTED/1024/1024)) MB"
done
log "=== unduhan selesai: $(size) bytes ==="

# --- 2. Setup + verifikasi --------------------------------------------------
export JAVA_HOME=$TC/jdk21/Contents/Home
export ANDROID_HOME=$HOME/Library/Android/sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME
export PATH=$TC/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH

if [ ! -x "$TC/flutter/bin/flutter" ]; then
  log "ekstrak flutter.zip"
  unzip -q -o "$TC/flutter.zip" -d "$TC/" >>"$LOG" 2>&1
fi
log "flutter: $("$TC/flutter/bin/flutter" --version 2>&1 | head -1)"
"$TC/flutter/bin/flutter" config --android-sdk "$ANDROID_HOME" >>"$LOG" 2>&1

cd "$WORK/nyatet" || exit 1

log "=== flutter create --platforms android ==="
"$TC/flutter/bin/flutter" create --platforms android --org com.nyatet . >>"$LOG" 2>&1
rm -f test/widget_test.dart

log "=== flutter pub get ==="
"$TC/flutter/bin/flutter" pub get >>"$LOG" 2>&1; log "pub get exit=$?"

log "=== build_runner ==="
"$TC/flutter/bin/dart" run build_runner build --delete-conflicting-outputs >>"$LOG" 2>&1
log "build_runner exit=$?"

log "=== flutter analyze ==="
"$TC/flutter/bin/flutter" analyze >>"$LOG" 2>&1; log "analyze exit=$?"

log "=== flutter test ==="
"$TC/flutter/bin/flutter" test >>"$LOG" 2>&1; log "test exit=$?"

log "=== flutter build apk --debug ==="
"$TC/flutter/bin/flutter" build apk --debug >>"$LOG" 2>&1; log "build exit=$?"

ls -la build/app/outputs/flutter-apk/ >>"$LOG" 2>&1
log "=== SELESAI: $(grep -c 'exit=0' "$LOG") tahap OK ==="
touch /tmp/nyatet_build.done
