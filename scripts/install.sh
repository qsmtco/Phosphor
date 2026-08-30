#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# Phosphor installer
#
# One-shot installer: builds the bridge, packages shell.html, pushes
# everything to the phone over adb, and configures autostart.
#
# Usage:
#   ./scripts/install.sh                      # default (adb device 0)
#   ./scripts/install.sh -s <serial>          # specific device
#   ./scripts/install.sh --no-build           # skip cargo build
#   ./scripts/install.sh --phone-only         # only adb push, don't build
#
# What it does:
#   1. cargo build --release phosphor-bridge (Linux binary)
#   2. tarballs shell.html + SYSTEM_PROMPT.md + scripts/
#   3. adb push everything to /data/local/tmp/phosphor/
#   4. chmod +x the bridge + scripts
#   5. registers phosphor-init.sh to run on boot via init.d or a Magisk
#      module (we default to a Magisk module since GrapheneOS works fine
#      with Magisk).
#
# Requires:
#   • adb (apt install adb / brew install android-platform-tools)
#   • cargo (rustup.rs)
#   • A connected, USB-debugging-enabled Pixel running GrapheneOS
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PHONE_DIR="/data/local/tmp/phosphor"
LOG="$PROJECT_ROOT/install.log"

# ─── arg parse ──────────────────────────────────────────────────────
BUILD=true
SERIAL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build)  BUILD=false; shift ;;
    --phone-only) BUILD=false; shift ;;
    -s)          SERIAL="-s $2"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

log() {
  echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"
}

log "phosphor install starting"
log "project root: $PROJECT_ROOT"

# ─── 1. Build the bridge (unless skipped) ──────────────────────────
if [[ "$BUILD" == "true" ]]; then
  log "building phosphor-bridge (release, opt-level z, LTO)"
  cd "$PROJECT_ROOT/bridge"
  cargo build --release 2>&1 | tee -a "$LOG"
  BRIDGE_BIN="$PROJECT_ROOT/bridge/target/release/phosphor-bridge"
  if [[ ! -x "$BRIDGE_BIN" ]]; then
    log "ERROR: bridge binary not found at $BRIDGE_BIN"
    exit 1
  fi
  log "built: $(ls -lh "$BRIDGE_BIN" | awk '{print $5}')"
else
  BRIDGE_BIN="$PROJECT_ROOT/bridge/target/release/phosphor-bridge"
  if [[ ! -x "$BRIDGE_BIN" ]]; then
    log "ERROR: --no-build passed but bridge binary not found at $BRIDGE_BIN"
    log "       run without --no-build first, or cargo build --release"
    exit 1
  fi
fi

# ─── 2. Stage locally so we can push ───────────────────────────────
STAGING="$(mktemp -d)"
trap "rm -rf $STAGING" EXIT
mkdir -p "$STAGING/phosphor"

cp "$PROJECT_ROOT/shell.html"                "$STAGING/phosphor/"
cp "$PROJECT_ROOT/SYSTEM_PROMPT.md"          "$STAGING/phosphor/"
cp "$BRIDGE_BIN"                             "$STAGING/phosphor/phosphor-bridge"
cp "$PROJECT_ROOT/scripts/phosphor-init.sh"  "$STAGING/phosphor/"
chmod +x "$STAGING/phosphor/phosphor-bridge" "$STAGING/phosphor/phosphor-init.sh"

log "staged $(du -sh "$STAGING/phosphor" | awk '{print $1}') in $STAGING"

# ─── 3. Check adb / device ─────────────────────────────────────────
if ! command -v adb >/dev/null 2>&1; then
  log "ERROR: adb not on PATH. Install android-platform-tools."
  exit 1
fi
adb $SERIAL get-state >/dev/null 2>&1 || {
  log "ERROR: no adb device. Plug in the phone, enable USB debugging."
  exit 1
}
DEVICE=$(adb $SERIAL shell getprop ro.product.model 2>/dev/null | tr -d '\r')
log "device: $DEVICE"

# ─── 4. Push to /data/local/tmp/phosphor ───────────────────────────
log "creating $PHONE_DIR on device"
adb $SERIAL shell "mkdir -p $PHONE_DIR && chmod 755 $PHONE_DIR"

for f in shell.html SYSTEM_PROMPT.md phosphor-bridge phosphor-init.sh; do
  log "pushing $f"
  adb $SERIAL push "$STAGING/phosphor/$f" "$PHONE_DIR/$f" >/dev/null
done
adb $SERIAL shell "chmod +x $PHONE_DIR/phosphor-bridge $PHONE_DIR/phosphor-init.sh"

log "verifying files on device:"
adb $SERIAL shell "ls -lh $PHONE_DIR" | tee -a "$LOG"

# ─── 5. Install Magisk autostart module ────────────────────────────
# Phosphor boots via a Magisk module so it survives OTA updates and
# survives GrapheneOS Verified Boot relock. Create it on the device.
MODULE_DIR="/data/adb/modules/phosphor"
log "creating Magisk module at $MODULE_DIR"
adb $SERIAL shell "mkdir -p $MODULE_DIR"
adb $SERIAL push "$PROJECT_ROOT/scripts/phosphor-init.sh" "$MODULE_DIR/service.sh" >/dev/null
adb $SERIAL shell "chmod +x $MODULE_DIR/service.sh"

# Magisk module.prop + post-fs-data hook
adb $SERIAL shell "cat > $MODULE_DIR/module.prop" <<'EOF'
id=phosphor
name=Phosphor
version=0.1.0
versionCode=1
author=you
description=AI-rendered kiosk shell (Phosphor)
EOF

adb $SERIAL shell "cat > $MODULE_DIR/post-fs-data.sh" <<'EOF'
#!/system/bin/sh
# Wait for the system to settle, then launch the Phosphor stack.
# This runs once at boot before any user-space service.
sleep 5
nohup /data/local/tmp/phosphor/phosphor-init.sh \
  > /data/local/tmp/phosphor.log 2>&1 &
EOF

adb $SERIAL shell "chmod +x $MODULE_DIR/post-fs-data.sh"

log "Magisk module installed. Phosphor will boot on next reboot."

# ─── 6. Optional: install Termux (used by phosphor-bridge) ────────
# Termux:API is the cleanest path to sensors/battery/wifi/bt/clipboard
# on GrapheneOS without writing our own AOSP service.
if adb $SERIAL shell pm list packages | grep -q com.termux; then
  log "Termux already installed"
else
  log "downloading Termux + Termux:API APK (will require user tap to install)"
  TERMUX_APK="$STAGING/com.termux_1020.apk"
  TERMUX_API_APK="$STAGING/com.termux.api_1000.apk"
  curl -sL -o "$TERMUX_APK" \
    https://github.com/termux/termux-app/releases/download/v0.118.0/termux-app_v0.118.0+github-debug.apk
  curl -sL -o "$TERMUX_API_APK" \
    https://github.com/termux/termux-api/releases/download/v0.50/termux-api_v0.50+github-debug.apk
  adb $SERIAL install "$TERMUX_APK" || log "(user will need to install Termux manually)"
  adb $SERIAL install "$TERMUX_API_APK" || log "(user will need to install Termux:API manually)"
fi

# ─── 7. Done ────────────────────────────────────────────────────────
log ""
log "✓ install complete"
log ""
log "Next steps:"
log "  1. Open the Termux app once on the phone and run:  termux-setup-storage"
log "  2. Reboot the phone:  adb $SERIAL reboot"
log "  3. Phosphor should boot to a dark screen with the orb."
log "  4. To debug, run:  adb $SERIAL logcat -s phosphor-bridge:*"
log "  5. To push code changes after editing shell.html on your laptop:"
log "       adb $SERIAL push $PROJECT_ROOT/shell.html $PHONE_DIR/shell.html"
log ""
log "Log written to $LOG"

exit 0
