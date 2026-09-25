#!/usr/bin/env bash
# Phosphor — allow AOSP's build sandbox (nsjail) to create user namespaces.
#
# WHY THIS IS NEEDED
#   Ubuntu sets kernel.apparmor_restrict_unprivileged_userns=1, which blocks
#   unprivileged user namespaces. AOSP's build sandbox probes nsjail once per
#   build; the probe fails, so the build prints
#       "Build sandboxing disabled due to nsjail error."
#   on stderr and continues with sandboxing off. The build itself succeeds —
#   but adevtool's spawnAsync() treats ANY unexpected stderr line as fatal and
#   aborts `generate-all` on that line.
#
#   There is no knob to silence it: USE_NINJA_SANDBOX does not exist anywhere in
#   this tree, and the probe runs unconditionally
#   (build/soong/ui/build/sandbox_linux.go). So the fix is to make nsjail work.
#
# WHY THIS WAY
#   Rather than turning the host-wide restriction off, this grants the userns
#   capability to the specific nsjail binaries via AppArmor — the same pattern
#   Ubuntu itself ships for mmdebstrap and sbuild-unhold. The global restriction
#   stays in place; only these paths are exempted.
#
# Verified by the script: the sysctl is still 1, a plain unshare is still
# blocked, and nsjail now runs.
#
# Idempotent. Re-run after moving or recreating the source tree — the profile
# attaches to an absolute path inside it.
#
# Usage:  sudo bash scripts/host-fix-nsjail-userns.sh

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Needs root. Run: sudo bash $0" >&2
  exit 1
fi

TARGET_USER="${SUDO_USER:-cptjaqx}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TREE="$TARGET_HOME/projects/grapheneos-2026091900"
PROFILE=/etc/apparmor.d/nsjail-userns

if [ ! -x "$TREE/prebuilts/build-tools/linux-x86/bin/nsjail" ]; then
  echo "nsjail not found at $TREE/prebuilts/build-tools/linux-x86/bin/nsjail" >&2
  echo "Is the GrapheneOS tree at the expected path?" >&2
  exit 1
fi

echo "==> Writing $PROFILE"
cat > "$PROFILE" <<EOF
# Allow AOSP's build sandbox (nsjail) to create user namespaces.
# Ubuntu's kernel.apparmor_restrict_unprivileged_userns=1 blocks them
# otherwise, which makes AOSP disable its build sandbox and print a warning
# that adevtool treats as a fatal error.
# Pattern follows /etc/apparmor.d/mmdebstrap.
# Managed by Phosphor scripts/host-fix-nsjail-userns.sh

abi <abi/5.0>,
include <tunables/global>

profile nsjail-aosp $TREE/prebuilts/build-tools/linux-x86/bin/nsjail flags=(unconfined) {
  userns,
  include if exists <local/nsjail-aosp>
}

profile nsjail-aosp-musl $TREE/prebuilts/build-tools/linux_musl-x86/bin/nsjail flags=(unconfined) {
  userns,
  include if exists <local/nsjail-aosp-musl>
}
EOF
chmod 0644 "$PROFILE"

echo "==> Loading the profile"
apparmor_parser -r "$PROFILE"

echo
echo "==> Verification"

echo "-- global restriction should still be ON (1) --"
sysctl -n kernel.apparmor_restrict_unprivileged_userns

echo "-- a plain unprivileged unshare should still FAIL --"
if sudo -u "$TARGET_USER" unshare --user --map-root-user true 2>/dev/null; then
  echo "   WARNING: unshare succeeded — the global restriction is off, which is not what this script does"
else
  echo "   still blocked (correct: restriction intact, only nsjail exempted)"
fi

echo "-- nsjail probe (this is what the build runs) --"
cd "$TREE"
if sudo -u "$TARGET_USER" ./prebuilts/build-tools/linux-x86/bin/nsjail \
     -H android-build -e -u nobody -g nogroup --disable_clone_newcgroup \
     -- /bin/bash -c 'echo   nsjail works now' 2>&1 | grep -E 'works now|Permission denied|Couldn.t launch'; then
  :
fi

cat <<'NOTE'

==> Done.
Next: re-run adevtool from the tree root —
    cd ~/projects/grapheneos-2026091900
    PATH="$HOME/android-sdk/node24/bin:$PATH" vendor/adevtool/bin/run generate-all -d akita
The dependency build can be skipped since it already succeeded:
    ADEVTOOL_SKIP_DEP_BUILD=1
NOTE
