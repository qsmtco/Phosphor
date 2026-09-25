#!/usr/bin/env bash
#
# Phosphor Phase 3 — sign a release with the token-gated key set
#
#   bash scripts/keys-sign-release.sh [BUILD_NUMBER]
#
# Run as your normal user. You will be prompted once for the YubiKey PIN, and
# possibly once for your sudo password (swap must be off during signing).
#
# WHAT THIS DOES, in order — the order is load-bearing:
#
#   1. Links the out-of-tree key set to <tree>/keys/akita, because
#      script/generate-release.sh reads PERSISTENT_KEY_DIR=keys/$DEVICE relative
#      to the tree root. A symlink only; no key material is copied or moved.
#   2. Turns SWAP OFF before anything is decrypted. /dev/shm is tmpfs and tmpfs
#      pages can be swapped out to disk; /swap.img on this host sits on plain
#      ext4 with no LUKS layer. Turning swap off after decrypting would already
#      be too late.
#   3. Unseals the passphrase with the YubiKey (token + PIN), into a private
#      temp dir, and exports it as $password.
#   4. Runs GrapheneOS's own release pipeline unchanged:
#        m otatools-package      -> the otatools zip finalize.sh expects
#        script/finalize.sh      -> copies otatools + target_files into
#                                   releases/$BUILD_NUMBER/
#        script/generate-release.sh akita $BUILD_NUMBER
#      generate-release.sh copies keys to /dev/shm, calls script/decrypt-keys
#      (which reads $password from the environment instead of prompting, because
#      we exported it), signs, and removes the plaintext via its own EXIT trap.
#   5. Wipes the temp passphrase and turns swap back on, on any exit path.
#
# OFFICIAL_BUILD is deliberately NOT set: it points the Updater app at
# GrapheneOS's real update server, which would be a DoS on their infrastructure
# from a differently-signed build.
#
set -o errexit -o nounset -o pipefail

TREE="${PHOSPHOR_TREE:-$HOME/projects/grapheneos-2026091900}"
KEY_DIR_ROOT="${PHOSPHOR_KEY_DIR_ROOT:-$HOME/phosphor-keys}"
KEYS_REAL="${PHOSPHOR_KEYS_DIR:-$KEY_DIR_ROOT/akita}"
DEVICE=akita
SEALER="$HOME/projects/Phosphor/scripts/keys-yubikey-seal.sh"

# The release number must match the build number baked into the target_files we
# are signing. If it doesn't, the images carry one version internally and another
# in their filename. So derive it from the target_files rather than guessing from
# today's date — a build made yesterday would otherwise silently mismatch.
BUILD_NUMBER="${1:-}"
if [[ -z $BUILD_NUMBER ]]; then
  tf="$TREE/out/target/product/$DEVICE/obj/PACKAGING/target_files_intermediates/$DEVICE-target_files.zip"
  if [[ -f $tf ]]; then
    BUILD_NUMBER="$(unzip -p "$tf" SYSTEM/build.prop 2>/dev/null \
        | sed -n 's/^ro\.build\.version\.incremental=//p' | tr -d '\r' | head -1)"
    if [[ -z $BUILD_NUMBER ]]; then
      # fail() is defined further down, so inline this one
      echo "ERROR: could not read the build number from:" >&2
      echo "       $tf" >&2
      echo "       Pass one explicitly: bash scripts/keys-sign-release.sh <BUILD_NUMBER>" >&2
      exit 1
    fi
  else
    BUILD_NUMBER="$(date -u +%Y%m%d)00"
    echo "NOTE: no target_files found, using today's date as the build number."
    echo "      You will need to build one before this can sign anything."
  fi
fi

fail() { echo "ERROR: $*" >&2; exit 1; }
say()  { printf '%s\n' "$*"; }

# --------------------------------------------------------------- trap state
UNSEAL_DIR=""
SWAP_STOPPED=0

cleanup() {
  if [[ -n $UNSEAL_DIR && -d $UNSEAL_DIR ]]; then
    # shred anything that may hold the passphrase, then remove the dir
    find "$UNSEAL_DIR" -type f -exec shred -u {} \; 2>/dev/null || true
    rm -rf "$UNSEAL_DIR"
    say "==> temp passphrase wiped"
  fi
  if [[ $SWAP_STOPPED -eq 1 ]]; then
    say "==> turning swap back on"
    sudo swapon -a 2>/dev/null || say "    WARNING: could not re-enable swap; run: sudo swapon -a"
  fi
}
trap cleanup EXIT

say "==> Phosphor Phase 3 — sign a release"
say "    tree:         $TREE"
say "    key set:      $KEYS_REAL"
say "    build number: $BUILD_NUMBER"
say

# ---------------------------------------------------------------- preflight
[[ -d $TREE ]] || fail "source tree not found at $TREE (set PHOSPHOR_TREE)"
[[ -d $KEYS_REAL ]] || fail "key set not found at $KEYS_REAL"

for k in releasekey bluetooth avb.pem avb_pkmd.bin platform shared media networkstack nfc sdk_sandbox gmscompat_lib; do
  [[ -e "$KEYS_REAL/$k" || -e "$KEYS_REAL/$k.pk8" ]] || fail "missing key: $k in $KEYS_REAL"
done
say "    key set complete (releasekey, bluetooth, avb.pem + the rest)"

[[ -f $KEY_DIR_ROOT/passphrase.sealed ]] || fail "no sealed passphrase at $KEY_DIR_ROOT/passphrase.sealed"
[[ -f $SEALER ]] || fail "seal helper not found at $SEALER"

# The token must be reachable BEFORE we touch the key set: discovering a dead
# token after swapoff and a partial pipeline would leave a mess.
command -v ykman >/dev/null 2>&1 || fail "ykman not found"
if ! timeout 25 ykman piv info </dev/null 2>&1 | grep -q 'PIV version'; then
  fail "the YubiKey's PIV applet is not reachable.
       Check the token is plugged in, then:
           sudo bash scripts/host-fix-yubikey-ccid.sh"
fi
say "    token reachable"
say

# ------------------------------------------------------------------- symlink
# generate-release.sh wants keys/$DEVICE relative to the tree root. A symlink
# keeps the real key material outside the tree, as the design requires — the
# tree is 1057 git repositories and no place for a private key.
mkdir -p "$TREE/keys"
if [[ -L $TREE/keys/$DEVICE ]]; then
  current="$(readlink "$TREE/keys/$DEVICE")"
  if [[ $current != "$KEYS_REAL" ]]; then
    say "==> re-pointing $TREE/keys/$DEVICE"
    say "    was: $current"
    ln -sfn "$KEYS_REAL" "$TREE/keys/$DEVICE"
    say "    now: $KEYS_REAL"
  else
    say "==> $TREE/keys/$DEVICE already points at the key set"
  fi
elif [[ -e $TREE/keys/$DEVICE ]]; then
  fail "$TREE/keys/$DEVICE exists and is not a symlink.
       Refusing to touch it — the real key set is at $KEYS_REAL."
else
  say "==> linking $TREE/keys/$DEVICE -> $KEYS_REAL"
  ln -s "$KEYS_REAL" "$TREE/keys/$DEVICE"
fi
say

# -------------------------------------------------------------------- swap
# Order matters: swap off BEFORE any plaintext key exists.
say "==> Checking swap"
if swapon --show 2>/dev/null | grep -q .; then
  say "    swap is active:"
  swapon --show | sed 's/^/      /'
  say "    /dev/shm is tmpfs and can be swapped to disk; this host's swap has no"
  say "    LUKS layer, so plaintext keys could survive there. Turning it off."
  say "    (you may be prompted for your sudo password)"
  sudo swapoff -a || fail "could not turn swap off — refusing to sign with swap active"
  SWAP_STOPPED=1
  if swapon --show 2>/dev/null | grep -q .; then
    fail "swap is still active after swapoff"
  fi
  say "    swap is off"
else
  say "    swap already off"
fi
say

# ------------------------------------------------------------------ unseal
say "==> Unsealing the passphrase with the YubiKey (prompting for your PIN)"
# /dev/shm, not the key directory: this is tmpfs, and swap is already off, so the
# plaintext passphrase exists only in RAM and cannot reach disk. Writing it under
# ~/phosphor-keys would put it on plain ext4 the moment it was created.
UNSEAL_DIR="$(mktemp -d /dev/shm/phosphor-unseal.XXXXXX)"
chmod 700 "$UNSEAL_DIR"

# Attach the terminal explicitly. Two traps here, both of which bite at the PIN
# prompt and are easy to introduce accidentally:
#   - Running this inside a command substitution (or any pipe) steals stdin;
#     pkcs11-tool then fails with "util_getpass error" before reaching C_Login.
#   - Redirecting stdout AWAY from a terminal breaks the prompt too, even though
#     the prompt is a read. An earlier version of this wrapper sent stdout to
#     /dev/null and the unseal died before ever calling C_Login.
# Naming /dev/tty explicitly survives both, and also works if the caller pipes
# this script's own output somewhere.
bash "$SEALER" --unseal -o "$UNSEAL_DIR/pass" </dev/tty >/dev/tty
[[ -s $UNSEAL_DIR/pass ]] || fail "unseal produced nothing"
export password
password="$(cat "$UNSEAL_DIR/pass")"
[[ -n $password ]] || fail "empty passphrase"
say "    unsealed (${#password} characters)"
say

# ------------------------------------------------------------- the pipeline
cd "$TREE"

say "==> Setting up the build environment"
# shellcheck source=/dev/null
source build/envsetup.sh > /dev/null
lunch "$DEVICE-cur-user" > /dev/null 2>&1 || fail "lunch $DEVICE-cur-user failed"
say "    TARGET_PRODUCT=${TARGET_PRODUCT:-?}  BUILD_ID=${BUILD_ID:-?}"

# lunch sets AND exports BUILD_NUMBER from state persisted in out/, clobbering the
# value derived earlier — and because it exports it, child processes would inherit
# lunch's value while this script's messages and output paths used ours. Re-assert
# it here, after lunch, so everything agrees and the number used is the one baked
# into the target_files being signed.
if [[ $# -gt 0 ]]; then
  BUILD_NUMBER="$1"
elif [[ -n ${tf:-} && -f ${tf:-} ]]; then
  BUILD_NUMBER="$(unzip -p "$tf" SYSTEM/build.prop 2>/dev/null \
      | sed -n 's/^ro\.build\.version\.incremental=//p' | tr -d '\r' | head -1)"
fi
[[ -n ${BUILD_NUMBER:-} ]] || fail "could not determine the build number"
export BUILD_NUMBER
say "    BUILD_NUMBER=$BUILD_NUMBER"

OTATOOLS_ZIP="${ANDROID_HOST_OUT:-}/obj/ETC/otatools-packagelinux_glibc_x86_64_intermediates/otatools-packagelinux_glibc_x86_64"
if [[ -n ${ANDROID_HOST_OUT:-} && -f $OTATOOLS_ZIP ]]; then
  say "    otatools already built"
else
  say "==> Building otatools (m otatools-package) — this takes a while"
  m otatools-package
  [[ -f $OTATOOLS_ZIP ]] || fail "otatools zip not found after the build:
       $OTATOOLS_ZIP"
  say "    otatools built"
fi
say

say "==> finalize.sh — staging otatools and target_files into releases/$BUILD_NUMBER/"
script/finalize.sh
ls -la "releases/$BUILD_NUMBER/" | sed 's/^/    /'
say

say "==> generate-release.sh — signing (GrapheneOS's pipeline, keys from \$password)"
script/generate-release.sh "$DEVICE" "$BUILD_NUMBER"
say

# ------------------------------------------------------------------- report
OUTDIR="$TREE/releases/$BUILD_NUMBER/release-$DEVICE-$BUILD_NUMBER"
say "==> Artifacts"
if [[ -d $OUTDIR ]]; then
  ls -la "$OUTDIR" | sed 's/^/    /'
else
  say "    WARNING: expected output dir not found: $OUTDIR"
fi
say
say "==> Done."
say
say "Verify before flashing (see docs/PHASE-3-FLASHING-AND-RECOVERY.md):"
say "  - the factory images in $OUTDIR"
say "  - that signatures are OURS, not test-keys"
say "  - that the bootloader is still LOCKED and nothing was flashed by this script"
say
say "This script did not touch the device."
