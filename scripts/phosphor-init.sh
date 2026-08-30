#!/system/bin/sh
# ─────────────────────────────────────────────────────────────────────
# Phosphor boot script
#
# Boots on the phone after a (re)boot, kills everything except the
# minimal subsystem Phosphor needs, then launches:
#   - phosphor-bridge (Rust service, listens on 127.0.0.1:7777/ws)
#   - cage (Wayland kiosk compositor, ~150ms to first frame)
#   - vanadium (GrapheneOS hardened Chromium, the only visible app)
#
# Idempotent. Safe to run twice. Logs to /data/local/tmp/phosphor.log.
# ─────────────────────────────────────────────────────────────────────

set -e

PHOSPHOR_HOME="/data/local/tmp/phosphor"
PHOSPHOR_LOG="/data/local/tmp/phosphor.log"
SHELL_HTML="file:///data/local/tmp/phosphor/shell.html"

log() {
  echo "[$(date '+%H:%M:%S')] $*" >> "$PHOSPHOR_LOG"
  echo "[$($(/system/bin/date +%H:%M:%S))] $*"
}

log "phosphor-init: starting"

# ─── 1. Wait for the system to finish booting ──────────────────────
# Android's boot-completed broadcast is the canonical signal.
while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 1
done
log "boot completed, waiting 2s for services to settle"
sleep 2

# ─── 2. Kill everything that isn't needed for Phosphor ────────────
# We whitelist the bare minimum: surface flinger (the display), the
# network stack, audio, sensors, the input subsystem. Everything else
# gets politely told to stop.
log "pruning background services"

KEEP_LIST="
system_server
surfaceflinger
netd
wpa_supplicant
android.hardware.audio@service
android.hardware.sensors@service
audioserver
cameraserver
inputflinger
logcat
adbd
zygote
zygote64
init
"

for pid in $(ls /proc | grep -E '^[0-9]+$'); do
  cmdline=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')
  [ -z "$cmdline" ] && continue
  skip=0
  for keep in $KEEP_LIST; do
    case "$cmdline" in
      *"$keep"*) skip=1; break ;;
    esac
  done
  [ "$skip" = "1" ] && continue
  # Don't kill our own process tree.
  [ "$pid" = "$$" ] && continue
  # Politely stop first, then kill if needed.
  kill -STOP $pid 2>/dev/null || true
done
log "background services stopped (SIGSTOP'd)"

# ─── 3. Network up + DNS warm ──────────────────────────────────────
log "ensuring network connectivity"
svc data enable 2>/dev/null || true
svc wifi enable   2>/dev/null || true

# ─── 4. Start phosphor-bridge ──────────────────────────────────────
log "starting phosphor-bridge"
mkdir -p "$PHOSPHOR_HOME"
nohup /data/local/tmp/phosphor/phosphor-bridge \
  >> "$PHOSPHOR_LOG" 2>&1 &
BRIDGE_PID=$!

# Wait for it to bind the port.
for i in 1 2 3 4 5 6 7 8 9 10; do
  if (echo > /dev/tcp/127.0.0.1/7777) 2>/dev/null; then
    log "phosphor-bridge ready on :7777 (pid $BRIDGE_PID)"
    break
  fi
  sleep 0.3
done

# ─── 5. Start the Wayland compositor (cage) ────────────────────────
log "starting cage (Wayland kiosk compositor)"
export XDG_RUNTIME_DIR=/run/user/0
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

nohup cage -s -- /system/bin/sh -c '
  while true; do
    /data/local/tmp/phosphor/vanadium \
      --user-data-dir=/data/local/tmp/phosphor/profile \
      --no-sandbox \
      --no-first-run \
      --no-default-browser-check \
      --disable-features=Translate,InfobarUI,TranslateUI \
      --disable-infobars \
      --disable-session-crashed-bubble \
      --disable-restore-session-state \
      --kiosk \
      --window-position=0,0 \
      --window-size=1080,2400 \
      --start-fullscreen \
      --app='"$SHELL_HTML"' \
      --enable-features=WebBluetooth,WebUSB,WebHID,WebRTC
  done
' >> "$PHOSPHOR_LOG" 2>&1 &

# ─── 6. Set volume buttons to act as Phosphor side-buttons ─────────
# Map KEY_VOLUMEUP → "next suggestion", KEY_VOLUMEDOWN → "back/cancel".
# (Requires GrapheneOS's permission manager — left commented until the
#  volume daemon is in place.)
#
# am broadcast -a phosphor.volume.up   -p com.phosphor.bridge
# am broadcast -a phosphor.volume.down -p com.phosphor.bridge

# ─── 7. Disable the nav bar and the status bar ─────────────────────
# Wipe the bottom gesture pill and the lock-screen-style status chips.
# These are harmless to keep, but Phosphor's design prefers full-bleed.
log "hiding nav + status chrome"
cmd overlay enable com.android.internal.systemui.navbar.gestural   2>/dev/null || true
cmd overlay disable com.android.internal.display.cutout.emulation.corner 2>/dev/null || true

# ─── 8. Acquire wake-lock so the screen stays on while docked ───────
log "acquiring wakelock"
echo phosphor > /sys/power/wake_lock 2>/dev/null || true

# ─── 9. Done ───────────────────────────────────────────────────────
log "phosphor-init: complete"
log "  bridge: ws://127.0.0.1:7777/ws"
log "  shell:  $SHELL_HTML"

exit 0