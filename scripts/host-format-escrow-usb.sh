#!/usr/bin/env bash
#
# Phosphor Phase 3 — format the escrow USB drive and copy the escrow onto it
#
#   sudo bash scripts/host-format-escrow-usb.sh [DEVICE]
#
# DESTRUCTIVE. This erases the target device completely.
#
# The guards below all have to pass before anything is written. They exist because
# a wrong device node here costs real data, and a typo is indistinguishable from a
# correct answer at the moment it matters:
#
#   1. must be run as root
#   2. the device must be REMOVABLE (a USB stick, not an internal disk)
#   3. its sysfs vendor/model must match the expected drive (Netac OnlyDisk)
#   4. it must not be the device backing / or /boot/efi
#   5. any mounted filesystem on it must be under /run/media or /media — i.e. a
#      desktop auto-mount of removable media, never something structural
#
# Then it: unmounts its partitions, wipes the old signatures, writes a fresh GPT
# with one Linux partition, makes ext4 (which, unlike FAT/exFAT, enforces file
# permissions — the escrow must stay 0600), copies the escrow passphrase over,
# and verifies the copy by sha256 before claiming success.
#
set -o errexit -o nounset -o pipefail

DEV="${1:-/dev/sda}"
EXPECT_VENDOR="${PHOSPHOR_USB_VENDOR:-Netac}"
EXPECT_MODEL="${PHOSPHOR_USB_MODEL:-OnlyDisk}"
LABEL="${PHOSPHOR_USB_LABEL:-PHOSPHOR-ESCROW}"

# Under sudo, $HOME is /root — so resolve the invoking user's home explicitly, or
# this would look for the keys in /root/phosphor-keys and find nothing.
REAL_USER="${SUDO_USER:-$(id -un)}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
KEY_DIR_ROOT="${PHOSPHOR_KEY_DIR_ROOT:-$USER_HOME/phosphor-keys}"

say() { printf '%s\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

# ------------------------------------------------------------------- guards
[[ $EUID -eq 0 ]] || fail "run this with sudo:
       sudo bash $0 $DEV"

say "==> Phosphor — format the escrow USB"
say "    device:   $DEV"
say "    user:     $REAL_USER (home $USER_HOME)"
say

[[ -b $DEV ]] || fail "$DEV is not a block device"
DEV="$(readlink -f "$DEV")"
BASE="$(basename "$DEV")"
SYS="/sys/block/$BASE"
[[ -d $SYS ]] || fail "no sysfs entry for $DEV (is it really a whole disk?)"

# guard 2: removable
removable="$(cat "$SYS/removable" 2>/dev/null || echo 0)"
[[ $removable == 1 ]] || fail "$DEV is not removable — refusing to format an internal disk"
say "    removable: yes"

# guard 3: identity
VENDOR="$(tr -d ' ' < "$SYS/device/vendor" 2>/dev/null || true)"
MODEL="$(tr -d ' ' < "$SYS/device/model" 2>/dev/null || true)"
SIZE="$(lsblk -dno SIZE "$DEV")"
say "    identity:  vendor='$VENDOR' model='$MODEL' size=$SIZE"
[[ $VENDOR == "$EXPECT_VENDOR" && $MODEL == "$EXPECT_MODEL" ]] \
  || fail "expected $EXPECT_VENDOR/$EXPECT_MODEL, found '$VENDOR'/'$MODEL' — refusing.
       Override only if you are certain: PHOSPHOR_USB_VENDOR=... PHOSPHOR_USB_MODEL=..."

# guard 4 + 5: nothing structural may live on this device
ROOT_SRC="$(findmnt -no SOURCE / )"
ROOT_DISK="$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | head -1 || true)"
[[ $BASE == "$ROOT_DISK" ]] && fail "$DEV is the disk holding / — refusing"

while read -r src target; do
  [[ -n $src && -n $target ]] || continue
  parent="$(lsblk -no PKNAME "$src" 2>/dev/null | head -1 || true)"
  [[ $parent == "$BASE" ]] || continue
  case "$target" in
    /run/media/*|/media/*) : ;;   # a desktop auto-mount: ours, we unmount it below
    *) fail "$src is mounted at $target, which is not removable-media — refusing" ;;
  esac
done < <(findmnt -rno SOURCE,TARGET)
say "    mounts:    only removable-media mounts (or none)"
say

# ------------------------------------------------------------- what is here
say "==> Current contents (about to be erased)"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$DEV" | sed 's/^/    /'
say

# ---------------------------------------------------------------- unmount
say "==> Unmounting its partitions"
# A desktop auto-mount is often pinned by the file manager having the directory
# open, which makes umount fail with EBUSY ("target is busy"). Releasing that
# handle is the only correct fix. Deliberately NOT umount -l: a lazy unmount
# leaves a detached filesystem whose cached pages could be written back over the
# freshly-created ext4 and corrupt it.
release_holders() {
  local pdev="$1"
  local who
  who="$(fuser -vm "$pdev" 2>&1 | grep -v '^ *USER' | grep -v 'kernel mount' || true)"
  [[ -n $who ]] || return 0
  printf '%s\n' "$who" | sed 's/^/    holder: /'
  if printf '%s' "$who" | grep -q nautilus && command -v runuser >/dev/null 2>&1; then
    say "    nautilus is holding it — asking it to quit (it restarts when needed)"
    runuser -u "$REAL_USER" -- env \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$REAL_USER")/bus" \
      nautilus -q >/dev/null 2>&1 || true
    sleep 2
  fi
}

for part in $(lsblk -rno NAME "$DEV" | tail -n +2); do
  pdev="/dev/$part"
  mnt="$(findmnt -no TARGET "$pdev" 2>/dev/null | head -1 || true)"
  [[ -n $mnt ]] || continue
  if ! umount "$pdev" 2>/dev/null; then
    release_holders "$pdev"
    if ! umount "$pdev" 2>/dev/null; then
      fail "could not unmount $pdev from $mnt.
       Something still holds it. See what with:
           sudo fuser -vm $pdev
       Close whatever is holding it (a file manager window showing the drive is
       the usual cause) and run this script again. Nothing has been erased."
    fi
  fi
  say "    unmounted $pdev from $mnt"
done
say "    done"
say

# ------------------------------------------------------------------- format
say "==> Wiping old signatures"
wipefs -a "$DEV" 2>&1 | sed 's/^/    /'
sgdisk --zap-all "$DEV" > /dev/null 2>&1 || true
say "    cleared"
say

say "==> Writing a fresh GPT with one Linux partition"
sgdisk --clear \
       --new=1:0:0 \
       --typecode=1:8300 \
       --change-name=1:"$LABEL" \
       "$DEV" > /dev/null
partprobe "$DEV"
udevadm settle 2>/dev/null || sleep 2

if [[ $BASE =~ [0-9]$ ]]; then PART="${DEV}p1"; else PART="${DEV}1"; fi
[[ -b $PART ]] || fail "partition $PART did not appear"
say "    $PART created"
say

say "==> Making ext4 (label $LABEL)"
mkfs.ext4 -F -L "$LABEL" -m 1 "$PART" 2>&1 | tail -4 | sed 's/^/    /'
say

# mkfs.ext4 creates the filesystem ROOT DIRECTORY owned by root, and an ext4 mount
# cannot be told otherwise (uid=/gid= are vfat/NTFS options only). Left alone, the
# ordinary user cannot write to the freshly-formatted drive and only discovers it
# much later as a bare "mkdir: Permission denied". Fix the ownership now, while we
# are still root.
TMPMNT="$(mktemp -d)"
if mount "$PART" "$TMPMNT" 2>/dev/null; then
  chown "$REAL_USER:" "$TMPMNT" && say "    root directory now owned by $REAL_USER"
  umount "$TMPMNT" 2>/dev/null || fail "could not unmount $TMPMNT"
else
  say "    WARNING: could not mount $PART to set ownership."
  say "    After mounting it, run: sudo chown $REAL_USER: <mountpoint>"
fi
rmdir "$TMPMNT" 2>/dev/null || true
say

# --------------------------------------------------------------- copy it
ESCROW="$(ls -1 "$KEY_DIR_ROOT"/ESCROW-passphrase-*.txt 2>/dev/null | head -1 || true)"
[[ -n $ESCROW ]] || fail "no escrow file found in $KEY_DIR_ROOT"
[[ -f $ESCROW ]] || fail "escrow file vanished: $ESCROW"

say "==> Copying the escrow onto the drive"
MNT="$(mktemp -d /run/format-escrow.XXXXXX)"
mount "$PART" "$MNT"
trap 'umount "$MNT" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true' EXIT

install -m 600 -o "$REAL_USER" -g "$REAL_USER" "$ESCROW" "$MNT/"
sync
say "    copied $(basename "$ESCROW") (mode 600, owner $REAL_USER)"
say

# ------------------------------------------------------------- verify it
say "==> Verifying the copy by sha256"
want="$(sha256sum "$ESCROW" | cut -d' ' -f1)"
got="$(sha256sum "$MNT/$(basename "$ESCROW")" | cut -d' ' -f1)"
say "    source: $want"
say "    on USB: $got"
[[ $want == "$got" ]] || fail "the copy on the USB does not match the source — do NOT trust it"
say "    match"
say
say "    contents now on the drive:"
ls -la "$MNT" | sed 's/^/      /'
say

umount "$MNT"
rmdir "$MNT"
trap - EXIT
sync

say "==> Done. The drive is formatted and the escrow is on it, verified."
say
say "    Label:  $LABEL"
say "    Device: $PART"
say
say "Next:"
say "  1. Unplug the drive and plug it back in — the desktop will auto-mount it so"
say "     you can confirm it reads back."
say "  2. MAKE A PAPER COPY TOO. Flash memory leaks charge when unpowered; a USB"
say "     stick in a safe can quietly lose data over a few years. The passphrase is"
say "     64 hex characters — one line on paper is immune to that, and immune to"
say "     being stolen digitally. Treat the stick as a convenience copy."
say "  3. Only once BOTH are stored, remove the host copy:"
say "       shred -u \"$ESCROW\""
say
say "The escrow file is plaintext on that drive. The safe is its only protection."
