#!/usr/bin/env bash
#
# Phosphor — back up the encrypted signing key set to the escrow USB.
#
# WHY THIS EXISTS
#   Today, losing the key set costs nothing: regenerate and re-sign. Once a build
#   signed with it has been flashed, the AVB key is PINNED to that device, so a
#   lost key set means another wipe to adopt a new one. Back up before flashing,
#   not after.
#
# WHAT IT COPIES
#   The encrypted key set (scrypt + AES-256 at rest, so a copy is safe offline),
#   plus the non-secret custody metadata needed to interpret it. It never copies
#   or prints key material, a PIN, or a passphrase — only names, sizes, hashes.
#
# WHAT IT REFUSES TO DO
#   Refuse to run as root, refuse a destination that is not the removable
#   PHOSPHOR-ESCROW volume, refuse an incomplete source, refuse to copy key
#   material that is no longer encrypted, and abort if any copied file does not
#   hash-match. On a failed verification the untrusted copy is deleted.
#
# Run as the ordinary user — no sudo needed; the USB auto-mounts.

set -uo pipefail

SRC="${PHOSPHOR_KEY_DIR:-$HOME/phosphor-keys}"
KEYDIR="$SRC/akita"
LABEL="PHOSPHOR-ESCROW"
EXPECT_PKMD="2256f03c5d5189debf9466e6dfb8a63d2f66e8abb96f10c074cc289ccb36b602"
ESCROW_GLOB="ESCROW-passphrase-*.txt"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; }
err()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; }
say()  { printf '%s\n' "$*"; }
die()  { err "$*"; say ""; say "Aborted."; exit 1; }

say "==> Phosphor — back up the encrypted key set"
say ""

# ---------------------------------------------------------------- guards -----
[[ $EUID -eq 0 ]] && die "Run this as your normal user, not root (root-owned files on the USB are unhelpful)."

[[ -d "$SRC"    ]] || die "Key directory not found: $SRC"
[[ -d "$KEYDIR" ]] || die "Key set not found: $KEYDIR"

for t in lsblk findmnt sha256sum openssl; do
  command -v "$t" >/dev/null 2>&1 || die "Required tool missing: $t"
done

say "-- source: $KEYDIR"
npk8=$(find "$KEYDIR" -maxdepth 1 -name '*.pk8'      | wc -l)
nx509=$(find "$KEYDIR" -maxdepth 1 -name '*.x509.pem' | wc -l)
[[ "$npk8"  -eq 9 ]] || die "Expected 9 .pk8 files, found $npk8 — incomplete key set."
[[ "$nx509" -eq 9 ]] || die "Expected 9 .x509.pem files, found $nx509 — incomplete key set."
[[ -s "$KEYDIR/avb.pem"      ]] || die "avb.pem missing or empty."
[[ -s "$KEYDIR/avb_pkmd.bin" ]] || die "avb_pkmd.bin missing or empty."
ok "9 .pk8, 9 .x509.pem, avb.pem, avb_pkmd.bin"

# Tripwire: make sure this is the key set we think it is.
got_pkmd=$(sha256sum "$KEYDIR/avb_pkmd.bin" | awk '{print $1}')
if [[ "$got_pkmd" == "$EXPECT_PKMD" ]]; then
  ok "avb_pkmd.bin sha256 matches the recorded value"
else
  warn "avb_pkmd.bin sha256 is $got_pkmd"
  warn "expected                     $EXPECT_PKMD"
  say  ""
  read -rp "  This is not the key set on record. Continue anyway? [y/N] " a
  [[ "${a,,}" == "y" ]] || die "Declined."
fi

# Tripwire: the .pk8 files must still be ENCRYPTED, or we would be copying raw
# signing keys onto removable media.
#
# Do NOT test this by trying a passphrase: `openssl pkcs8 -passin pass:wrong`
# exits non-zero for an *unencrypted* key too (verified empirically), so it cannot
# distinguish the two. Test the DER structure instead. An EncryptedPrivateKeyInfo
# is SEQUENCE { SEQUENCE(algid), OCTET STRING }, whereas a plaintext
# PrivateKeyInfo is SEQUENCE { INTEGER version, ... } — so the element at depth 1
# is a constructed SEQUENCE when encrypted and a primitive INTEGER when not.
say ""
say "-- confirming the key material is still encrypted"
plain=0
for f in "$KEYDIR"/*.pk8; do
  lvl1=$(openssl asn1parse -inform DER -in "$f" 2>/dev/null | sed -n '2p')
  if [[ "$lvl1" == *"prim: INTEGER"* ]]; then
    err "$(basename "$f") is a PLAINTEXT PKCS#8 (depth-1 element is an INTEGER)"
    plain=1
  fi
done
[[ "$plain" -eq 0 ]] || die "Refusing to copy unencrypted key material."
ok "all 9 .pk8 are encrypted PKCS#8 (EncryptedPrivateKeyInfo)"

# ------------------------------------------------------------ destination ----
say ""
say "-- locating the escrow volume"

# Look the device up from live sysfs. Do NOT use `blkid -L`: its cache can report
# a device that is no longer attached (observed here — it claimed /dev/sda1 while
# the USB was unplugged), and these guards exist precisely so keys cannot land in
# the wrong place.
dev=$(lsblk -rno NAME,LABEL 2>/dev/null | awk -v L="$LABEL" '$2==L {print "/dev/"$1; exit}')
[[ -n "$dev" ]] || {
  say ""
  say "  The '$LABEL' USB is not attached."
  say "  Plug it in, then re-run this script."
  say "  (Do not trust 'blkid -L' to answer this — it can report a cached device"
  say "   that is no longer present.)"
  exit 1
}
[[ -b "$dev" ]] || die "$dev is not a block device."
ok "device: $dev"

# Removable and transport are properties of the DISK, not of the partition:
# asking for them on /dev/sda1 returns empty strings. Resolve the parent first.
disk="/dev/$(lsblk -no PKNAME "$dev" 2>/dev/null | head -1)"
[[ -b "$disk" ]] || die "Could not resolve the parent disk of $dev."
rm_flag=$(lsblk -ndo RM    "$disk" 2>/dev/null | tr -d ' ')
tran=$(   lsblk -ndo TRAN  "$disk" 2>/dev/null | tr -d ' ')
fstype=$(lsblk -ndo FSTYPE "$dev"  2>/dev/null | tr -d ' ')
model=$( lsblk -ndo MODEL  "$disk" 2>/dev/null | tr -d ' ')
[[ "$rm_flag" == "1"   ]] || die "$disk is not removable (RM=$rm_flag) — refusing."
[[ "$tran"    == "usb" ]] || die "$disk is not on the USB transport (TRAN=$tran) — refusing."
[[ "$fstype"  == "ext4" ]] || die "$dev is $fstype, expected ext4 — refusing."
ok "$disk: removable, usb, $fstype — $model"

# Mount if needed. udisks does this without a password for removable media owned
# by the seat user.
mnt=$(findmnt -n -o TARGET --source "$dev" 2>/dev/null | head -1)
if [[ -z "$mnt" ]]; then
  say "  not mounted — mounting it"
  command -v udisksctl >/dev/null 2>&1 || die "Not mounted and udisksctl is unavailable; mount it manually and re-run."
  udisksctl mount -b "$dev" >/dev/null 2>&1
  sleep 1
  mnt=$(findmnt -n -o TARGET --source "$dev" 2>/dev/null | head -1)
fi
[[ -n "$mnt" ]] || die "Could not mount $dev; mount it manually and re-run."
ok "mounted at $mnt"

# A freshly-formatted ext4 has its root directory owned by root (mkfs makes it
# that way and the mount cannot override it), so the ordinary user cannot write.
# Say so plainly here instead of failing later as a bare "mkdir: Permission denied".
if ! touch "$mnt/.phosphor-write-test" 2>/dev/null; then
  die "$mnt is not writable by $(id -un) — it is $(stat -c '%U:%G %a' "$mnt").
       Fix it once with:  sudo chown $(id -un): \"$mnt\""
fi
rm -f "$mnt/.phosphor-write-test"
ok "volume is writable"

# Sanity: the escrow passphrase should already be here, and it is the one thing
# this backup does NOT replace.
escrow=$(find "$mnt" -maxdepth 1 -name "$ESCROW_GLOB" 2>/dev/null | head -1)
if [[ -n "$escrow" ]]; then
  ok "escrow passphrase present: $(basename "$escrow") ($(stat -c%s "$escrow") bytes)"
else
  warn "'$ESCROW_GLOB' not found on the volume — the keys are useless without it."
fi

# ------------------------------------------------------------------ copy -----
DEST="$mnt/phosphor-keys-akita-$STAMP"
say ""
say "-- copying to $DEST"
mkdir -p "$DEST" || die "Could not create $DEST"
chmod 700 "$DEST"

copy_and_verify() {
  local src="$1" dst="$2" mode="$3" a b
  cp -p -- "$src" "$dst" || die "copy failed: $(basename "$src")"
  chmod "$mode" "$dst" 2>/dev/null
  a=$(sha256sum -- "$src" | awk '{print $1}')
  b=$(sha256sum -- "$dst" | awk '{print $1}')
  if [[ "$a" == "$b" ]]; then
    printf '  ok    %-28s %8s bytes  %s\n' "$(basename "$src")" "$(stat -c%s "$src")" "${a:0:16}…"
  else
    err   "HASH MISMATCH on $(basename "$src")"
    return 1
  fi
}

fail=0
for f in "$KEYDIR"/*.pk8 "$KEYDIR"/*.x509.pem "$KEYDIR"/avb.pem; do
  [[ -e "$f" ]] || continue
  copy_and_verify "$f" "$DEST/$(basename "$f")" 600 || fail=1
done
copy_and_verify "$KEYDIR/avb_pkmd.bin" "$DEST/avb_pkmd.bin" 644 || fail=1

say ""
say "-- copying custody metadata (contains no secrets)"
for f in "$SRC/yubikey.conf" "$SRC/piv-wrap-pub.pem" "$SRC/passphrase.sealed"; do
  [[ -e "$f" ]] || { warn "not present, skipped: $(basename "$f")"; continue; }
  copy_and_verify "$f" "$DEST/meta-$(basename "$f")" 600 || fail=1
done

if [[ "$fail" -ne 0 ]]; then
  rm -rf "$DEST"
  die "One or more files did not verify. The untrusted copy was deleted."
fi

# ---------------------------------------------------------------- manifest ---
say ""
say "-- writing MANIFEST.txt"
{
  say "Phosphor signing key set — offline backup"
  say ""
  say "Taken:      $STAMP (UTC)"
  say "Source:     $KEYDIR  on $(hostname)"
  say "Device:     $dev  (removable=$rm_flag, transport=$tran, fs=$fstype, model=$model)"
  say "avb_pkmd.bin sha256: $EXPECT_PKMD"
  say ""
  say "These files are ENCRYPTED AT REST (scrypt + AES-256). This backup is NOT"
  say "a substitute for the passphrase: without it these files are unreadable."
  say ""
  say "The passphrase is held in two independent places:"
  say "  1. $ESCROW_GLOB on this volume (if present), and"
  say "  2. a paper copy kept offline."
  say "Losing both means losing the ability to sign as Phosphor with this key set."
  say ""
  say "Note: 'meta-passphrase.sealed' is the passphrase encrypted to the YubiKey's"
  say "PIV public key. That is convenience, not recovery — it is useless without"
  say "that specific token. The paper copy is the real fallback."
  say ""
  say "Restore: copy these files back to ~/phosphor-keys/akita, then use"
  say "scripts/keys-sign-release.sh, which unseals the passphrase with the token."
  say ""
  say "Contents — only lines beginning 'F ' are machine-readable:"
  # Only 'F ' lines are parsed back. The prose above must never look like an
  # entry: an earlier version matched any indented line and tried to verify the
  # sentence "1. ESCROW-passphrase-*.txt on this volume" as a filename.
  # MANIFEST.txt is excluded because it cannot contain its own final hash.
  for f in "$DEST"/*; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == "MANIFEST.txt" ]] && continue
    printf 'F %s %s %s\n' "$(basename "$f")" "$(stat -c%s "$f")" "$(sha256sum -- "$f" | awk '{print $1}')"
  done
} > "$DEST/MANIFEST.txt"
chmod 600 "$DEST/MANIFEST.txt"

# Independent verification pass, driven from the manifest rather than from the
# copy loop, so it also catches a file that went missing afterwards.
say ""
say "-- independent verification pass (from the manifest)"
verify_fail=0
verified=0
while read -r tag fname fsize fhash; do
  [[ "$tag" == "F" ]] || continue
  [[ -n "$fname" && -n "$fhash" ]] || continue
  if [[ ! -f "$DEST/$fname" ]]; then
    err "missing after copy: $fname"; verify_fail=1; continue
  fi
  got=$(sha256sum -- "$DEST/$fname" | awk '{print $1}')
  if [[ "$got" == "$fhash" ]]; then
    verified=$((verified + 1))
  else
    err "hash mismatch: $fname"; verify_fail=1
  fi
done < <(grep '^F ' "$DEST/MANIFEST.txt")

if [[ "$verify_fail" -ne 0 ]]; then
  rm -rf "$DEST"
  die "Verification pass failed. The untrusted copy was deleted."
fi
ok "$verified files re-hashed from the manifest, all matching"

expected=$((9 + 9 + 1 + 1))   # .pk8, .x509.pem, avb.pem, avb_pkmd.bin
[[ "$verified" -ge "$expected" ]] || die "Only $verified files verified, expected at least $expected."
ok "file count complete ($verified >= $expected)"

sync

say ""
say "==> Done."
say ""
say "  Backed up to: $DEST"
say "  Files:        $(find "$DEST" -type f | wc -l)  ($(du -sh "$DEST" | cut -f1))"
say ""
say "  Eject the USB and return it to the safe. This volume now holds both the key"
say "  files and the escrow passphrase file — the paper copy is the only thing that"
say "  survives losing it, so a second medium is the real fix."
say ""
say "  Nothing here is plaintext, so it is safe to store alongside the escrow."
say "  Nothing was written to the host's disk."