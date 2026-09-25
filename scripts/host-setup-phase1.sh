#!/usr/bin/env bash
# Phosphor — Phase 1 build-host setup (run with sudo)
#
# Installs the host-side dependencies for building a GrapheneOS-derived
# Phosphor image for the Pixel 8a (akita), per grapheneos.org/build.
#
# Host: Ubuntu 26.04 LTS ("resolute") — NOT on GrapheneOS's supported list
# (Arch, Debian bookworm, Ubuntu 24.10, Ubuntu 24.04 LTS). Decision
# 2026-09-24: proceed as-is; fall back to a systemd-nspawn container of a
# supported distro if the build fails. See docs/PHASE-1-BUILD-HOST-READINESS.md.
#
# Idempotent: safe to re-run.
#
# Usage:  sudo bash scripts/host-setup-phase1.sh

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "This script installs packages and needs root. Run: sudo bash $0" >&2
  exit 1
fi

TARGET_USER="${SUDO_USER:-cptjaqx}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

echo "==> Updating package lists"
apt-get update

# ---------------------------------------------------------------------------
# GrapheneOS / AOSP build dependencies
#
#   repo        — intentionally NOT installed from apt: the self-updating
#                 standalone from AOSP is already installed at
#                 ~/.local/bin/repo (version 2.65) and is what GrapheneOS
#                 recommends over out-of-date distribution packages.
#   yarnpkg     — Debian/Ubuntu reserve `yarn` for cmdtest, hence yarnpkg.
#                 Needed for vendor/adevtool (Node 24 LTS at
#                 ~/android-sdk/node24).
#   libc6-i386, lib32gcc-s1 — the "32-bit glibc" and "32-bit gcc runtime
#                 library" that Vanadium (Chromium) needs.
#   font stack  — OpenJDK is a headless variant but still needs
#                 freetype2/fontconfig/a TrueType font.
#   android-sdk-platform-tools-common — udev rules so the Pixel can be used
#                 as non-root (GrapheneOS's own recommendation for Debian
#                 and Ubuntu).
# ---------------------------------------------------------------------------
PKGS=(
  # GrapheneOS "required packages"
  yarnpkg zip rsync

  # AOSP source fetch / verification
  python3 git diffutils gnupg openssh-client openssl rsync unzip zip

  # AOSP host build dependencies not provided by the source tree
  fontconfig fonts-dejavu-core libfreetype6

  # adevtool (Pixel vendor file extraction)
  #   Node.js 24 LTS is installed user-locally at ~/android-sdk/node24
  #   (the distro nodejs is 22.x and the user node is 26.x).

  # Vanadium (Chromium) build dependencies
  git-lfs gperf libc6-i386 lib32gcc-s1

  # udev rules for Pixel devices
  android-sdk-platform-tools-common
)

echo "==> Installing: ${PKGS[*]}"
DEBIAN_FRONTEND=noninteractive apt-get install -y "${PKGS[@]}"

# ---------------------------------------------------------------------------
# PATH
# ---------------------------------------------------------------------------
# GrapheneOS notes that /sbin and friends may be missing from PATH, which
# breaks system administration commands during the build. AOSP's envsetup.sh
# also has to run from bash/zsh.
PATH_BLOCK='# --- Phosphor Phase 1 (build host) ---
export PATH="$PATH:/sbin:/usr/sbin:/usr/local/sbin"
export PATH="$HOME/.local/bin:$HOME/android-sdk/platform-tools:$HOME/android-sdk/node24/bin:$PATH"
# --- end Phosphor Phase 1 ---'

BASHRC="$TARGET_HOME/.bashrc"
if ! grep -q 'Phosphor Phase 1' "$BASHRC" 2>/dev/null; then
  echo "==> Adding PATH block to $BASHRC"
  printf '\n%s\n' "$PATH_BLOCK" >> "$BASHRC"
  chown "$TARGET_USER:$TARGET_USER" "$BASHRC"
else
  echo "==> PATH block already present in $BASHRC"
fi

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
echo
echo "==> Verification"
fail=0
check() {
  local name="$1" want="$2" got="$3"
  if [ -n "$got" ]; then printf '  %-14s %s\n' "$name" "$got"
  else printf '  %-14s MISSING (%s)\n' "$name" "$want"; fail=1; fi
}
check gperf     >=3.1   "$(command -v gperf && gperf --version | head -1)"
check git-lfs   any     "$(command -v git-lfs && git-lfs version)"
check yarnpkg   any     "$(command -v yarnpkg && yarnpkg --version 2>/dev/null | head -1)"
check libc6-i386 32-bit "$(dpkg-query -W -f='${Version}' libc6-i386 2>/dev/null || echo '')"
check lib32gcc-s1 32-bit "$(dpkg-query -W -f='${Version}' lib32gcc-s1 2>/dev/null || echo '')"
check udev-rules any     "$(ls /lib/udev/rules.d/51-android.rules /usr/lib/udev/rules.d/51-android.rules 2>/dev/null | head -1)"
check python3   >=3.8   "$(python3 --version)"
check git       any     "$(git --version)"
check repo      any     "$(sudo -u "$TARGET_USER" "$TARGET_HOME/.local/bin/repo" --version 2>/dev/null | head -1)"
check adb       any     "$("$TARGET_HOME/android-sdk/platform-tools/adb" version 2>/dev/null | tail -1)"
check fastboot  >=35.0.1 "$("$TARGET_HOME/android-sdk/platform-tools/fastboot" --version 2>/dev/null | head -1)"
check node24    any     "$("$TARGET_HOME/android-sdk/node24/bin/node" --version 2>/dev/null)"

echo
if [ "$fail" -eq 0 ]; then
  echo "==> Phase 1 host setup complete. Open a new shell (or 'source ~/.bashrc')."
else
  echo "==> Some checks failed — see above." >&2
fi

cat <<'NOTE'

Reminder (not needed until the Pixel is on the desk):
  fwupd is running on this host and GrapheneOS warns it can claim devices
  speaking the fastboot protocol, blocking fastboot itself. Before any
  flash operation:
      sudo systemctl stop fwupd.service
  (Stopping it is temporary; it returns on reboot. No need to disable it now.)

NOTE

exit "$fail"
