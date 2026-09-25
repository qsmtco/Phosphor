#!/usr/bin/env bash
# Phosphor — make qoder's motherboard sensors readable.
#
# WHY THIS IS NEEDED
#   qoder's ASRock B850 Pro RS WiFi carries a Nuvoton NCT6687-R Super I/O. The
#   in-kernel nct6683 driver will not bind to it:
#       sudo modprobe nct6683 force=1
#       modprobe: ERROR: could not insert 'nct6683': No such device
#   and it logs nothing, so there is no obvious cause. This board also exposes
#   no ACPI thermal zones (0 of them) and no fan RPM source at all. So with
#   stock drivers the chipset, VRM, socket and M.2 temperatures plus every fan
#   are simply invisible — we can see the CPU, NVMe, DIMMs and iGPU only.
#
#   That matters here because qoder runs hour-long AOSP builds at full load and
#   "did anything run hot?" is a question worth being able to answer.
#
# WHAT THIS INSTALLS
#   The widely used out-of-tree DKMS module for that exact chip:
#       https://github.com/Fred78290/nct6687d
#   It exposes System / VRM MOS / PCH / CPU Socket / PCIe / M2_1 temperatures,
#   all eight fan channels, and the voltage rails.
#
# SAFETY
#   Read-only sensor driver — it reports values, it does not control fans or
#   voltages. Installed as a DKMS package, so it rebuilds itself on kernel
#   upgrades instead of silently breaking. Uninstall with:
#       sudo apt-get remove --purge nct6687d-dkms && sudo dkms autoinstall
#   The source is cloned to /opt/nct6687d, deliberately NOT under ~/projects,
#   so develcakes does not list it as a project.
#
# Idempotent — safe to re-run.
#
# Usage:  sudo bash scripts/host-install-nct6687d.sh

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Needs root. Run: sudo bash $0" >&2
  exit 1
fi

KVER="$(uname -r)"
SRC=/opt/nct6687d

echo "==> Kernel: $KVER"

if [ ! -d "/lib/modules/$KVER/build" ]; then
  echo "!! Kernel headers for $KVER are missing — DKMS cannot build." >&2
  echo "   Install: sudo apt-get install linux-headers-$KVER" >&2
  exit 1
fi
echo "    headers present"

echo
echo "==> Installing build/packaging dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# build-essential and linux-headers are usually already present; harmless here.
apt-get install -y --no-install-recommends \
  build-essential "linux-headers-$KVER" dkms dh-dkms git lm-sensors

echo
echo "==> Fetching the driver source into $SRC"
if [ -d "$SRC/.git" ]; then
  echo "    already cloned — updating"
  git -C "$SRC" pull --ff-only || echo "    (pull failed; continuing with what is there)"
else
  git clone --depth 1 https://github.com/Fred78290/nct6687d "$SRC"
fi

echo
echo "==> Building the DKMS package"
cd "$SRC"
make deb

echo
echo "==> Installing the package"
DEB="$(ls -1 "$SRC"/../nct6687d-dkms_*.deb "$SRC"/nct6687d-dkms_*.deb 2>/dev/null | head -1 || true)"
if [ -z "${DEB:-}" ]; then
  echo "!! No .deb was produced — build failed. Nothing installed." >&2
  exit 1
fi
echo "    $DEB"
dpkg -i "$DEB"

echo
echo "==> Making sure DKMS actually built it for $KVER"
dkms status || true
if ! dkms status | grep -qi "nct6687.*$KVER"; then
  echo "    DKMS has no module for $KVER yet — running autoinstall"
  dkms autoinstall -k "$KVER" || true
fi
depmod -a

echo
echo "==> Loading the module"
# force=1 is REQUIRED on this board. Its chip ID is not in the driver's table,
# so the probe falls through to -ENODEV. Those diagnostics are pr_debug, so
# WITHOUT force=1 the load fails completely silently — which is exactly what
# happened on the first attempt. force=1 attaches to any unrecognised NCT668x
# ID in the 0xD000-0xDFFF range, which is what the author intends for a new
# variant like the NCT6687-R. (If the ID is outside that range the driver
# refuses on purpose and says so — see the fail path in nct6687.c.)
LOADED=""
if modprobe nct6687 force=1; then
  LOADED=nct6687
  echo "    loaded with force=1"
elif modprobe nct6687; then
  LOADED=nct6687
  echo "    loaded (no force needed)"
else
  echo "!! Still not loading. Capturing the driver's debug output so we can see"
  echo "   the actual chip ID instead of guessing at it."
  mountpoint -q /sys/kernel/debug 2>/dev/null || mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
  if [ -w /sys/kernel/debug/dynamic_debug/control ]; then
    echo 'file nct6687.c +p' > /sys/kernel/debug/dynamic_debug/control 2>/dev/null || true
    modprobe nct6687 force=1 || true
    echo "-- driver debug output --"
    dmesg 2>/dev/null | grep -i nct6687 | tail -12
    echo "-- end --"
  else
    echo "   (dynamic debug unavailable; try: sudo dmesg | grep -i nct6687)"
  fi
  exit 1
fi

# Persist the option, not just the module name — without it, a reboot reloads
# the module with no force and the sensors silently vanish again.
echo "options nct6687 force=1" > /etc/modprobe.d/nct6687.conf
echo "$LOADED" > /etc/modules-load.d/nct6687.conf

echo
echo "==> Verification"
echo "-- new hwmon entries (temps and fans) --"
found=0
for h in /sys/class/hwmon/hwmon*; do
  name="$(cat "$h/name" 2>/dev/null || true)"
  case "$name" in
    *nct6687*)
      found=1
      echo "   chip: $name ($h)"
      for t in "$h"/temp*_input; do
        [ -r "$t" ] || continue
        idx="$(basename "$t" _input | tr -dc '0-9')"
        lbl="$(cat "$h/temp${idx}_label" 2>/dev/null || echo "temp$idx")"
        printf "     %-14s %s C\n" "$lbl" "$(awk '{printf "%.0f", $1/1000}' "$t")"
      done
      for f in "$h"/fan*_input; do
        [ -r "$f" ] || continue
        idx="$(basename "$f" _input | tr -dc '0-9')"
        lbl="$(cat "$h/fan${idx}_label" 2>/dev/null || echo "fan$idx")"
        printf "     %-14s %s RPM\n" "$lbl" "$(cat "$f")"
      done
      ;;
  esac
done
[ "$found" -eq 1 ] || echo "   (no nct6687 hwmon entry appeared — see dmesg)"

echo
echo "-- sensors --"
sensors 2>/dev/null | grep -A40 -i nct6687 || true

cat <<'NOTE'

==> Done.
From here, `sensors` shows the board sensors; they also load at boot.
Re-run any time; it is idempotent.
To undo:  sudo apt-get remove --purge nct6687d-dkms && sudo dkms autoinstall
NOTE
