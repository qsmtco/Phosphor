#!/usr/bin/env bash
#
# Phosphor Phase 3 — grant pcscd access to the YubiKey's CCID interface
#
#   sudo bash scripts/host-fix-yubikey-ccid.sh
#
# Symptom:
#
#   ykman piv info    ->  ERROR: Failed to connect to YubiKey
#   opensc-tool -l    ->  No smart card readers found
#   journalctl -u pcscd:
#       ccid_usb.c: OpenUSBByName() Can't libusb_open(1/N): LIBUSB_ERROR_ACCESS
#
# What should already handle this:
#
#   /usr/lib/udev/rules.d/60-fido-id.rules:10
#       SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device",
#       ENV{ID_USB_INTERFACES}=="*:0b????:*", ENV{ID_SMARTCARD_READER}="1"
#   /usr/lib/udev/rules.d/92-libccid.rules:12
#       ENV{ID_USB_INTERFACES}=="*:0b0000:*", GROUP="pcscd"
#
# The token's value really is ":030101:030000:0b0000:" and the pcscd group
# exists, so both rules ought to match. Observed on this host: they do not take
# effect and the node stays root:root, so pcscd — running as its own user — is
# denied and PIV is unreachable. Note also that 69-yubikey.rules tags the device
# "uaccess", which keeps working for the seat user over the HID/OTP path; that
# asymmetry is why `ykman info` succeeds while `ykman piv info` fails.
#
# This script therefore records what udev actually decides (`udevadm test`, which
# it can run because it is root), and installs a targeted rule to guarantee the
# outcome rather than relying on the stock rule that is demonstrably not working.
#
# Idempotent.
#
set -o errexit -o nounset -o pipefail

RULE=/etc/udev/rules.d/99-yubikey-pcscd.rules

echo "==> Phosphor — YubiKey CCID access"
echo

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root:  sudo bash $0" >&2
  exit 1
fi

find_node() {
  local d
  for d in /dev/bus/usb/*/*; do
    [[ -c $d ]] || continue
    if udevadm info -q property -n "$d" 2>/dev/null | grep -q '^ID_VENDOR_ID=1050$'; then
      printf '%s' "$d"
      return 0
    fi
  done
  return 1
}

node="$(find_node || true)"
if [[ -z $node ]]; then
  echo "==> No Yubico device on USB — plug the token in and re-run."
  exit 1
fi

echo "==> Current state"
printf '    %s  %s\n' "$(ls -l "$node" | awk '{print $1, $3, $4}')" "$node"

# ------------------------------------------------------------------ diagnose
# Capture udev's own decision, so the cause is evidence rather than theory.
echo
echo "==> udev's own view"
syspath="$(udevadm info -q path -n "$node" 2>/dev/null || true)"
if [[ -n $syspath ]]; then
  testout="$(udevadm test "$syspath" 2>&1 || true)"
  echo "    device: $syspath"
  if grep -q '92-libccid.rules' <<<"$testout"; then
    echo "    92-libccid.rules parsed: yes"
  else
    echo "    92-libccid.rules parsed: no"
  fi
  echo "    ID_SMARTCARD_READER: $(udevadm info -q property -n "$node" 2>/dev/null | sed -n 's/^ID_SMARTCARD_READER=//p')"
  echo "    ID_USB_INTERFACES:   $(udevadm info -q property -n "$node" 2>/dev/null | sed -n 's/^ID_USB_INTERFACES=//p')"
  # Anything udev said about groups/permissions on the way through.
  if grep -qi 'group' <<<"$testout"; then
    grep -i 'group' <<<"$testout" | tail -6 | sed 's/^/    | /'
  fi
  grep -i -E 'node (created|applied)|MODE=|permissions|Running' <<<"$testout" \
    | tail -3 | sed 's/^/    | /'
else
  echo "    could not resolve a sysfs path"
fi

# --------------------------------------------------------------------- fix
echo
if [[ "$(ls -l "$node" | awk '{print $4}')" == pcscd ]]; then
  echo "==> Node group is already 'pcscd' — stock rules are working; nothing to add."
else
  echo "==> Installing targeted rule: $RULE"
  cat > "$RULE" <<'EOF'
# Phosphor — let pcscd open the YubiKey's CCID interface.
#
# Rationale: the stock /usr/lib/udev/rules.d/92-libccid.rules assigns
# GROUP="pcscd" to devices whose ID_USB_INTERFACES matches *:0b0000:*, and
# 60-fido-id.rules flags smartcard readers with ID_SMARTCARD_READER=1. On this
# host the stock rule did not take effect and the device node stayed root:root,
# leaving pcscd unable to open it (LIBUSB_ERROR_ACCESS), which made PIV
# unreachable ("ykman piv info: Failed to connect to YubiKey"). This rule pins
# the same outcome using the property 60-fido-id.rules sets, and is numbered 99
# so it is evaluated last.
#
# The node's uaccess ACL (from 70-uaccess.rules) is unaffected, so the logged-in
# seat user keeps its access; this only adds the group that pcscd needs.
ACTION!="add|change", GOTO="phosphor_yubikey_end"
SUBSYSTEM!="usb", GOTO="phosphor_yubikey_end"
ENV{DEVTYPE}!="usb_device", GOTO="phosphor_yubikey_end"
ENV{ID_SMARTCARD_READER}=="1", GROUP="pcscd", MODE="0660"
LABEL="phosphor_yubikey_end"
EOF
  echo "    written"

  udevadm control --reload-rules
  udevadm trigger --subsystem-match=usb --action=add
  sleep 2

  node="$(find_node || true)"
  if [[ -n $node ]]; then
    printf '    now: %s  %s\n' "$(ls -l "$node" | awk '{print $1, $3, $4}')" "$node"
  fi
fi

# ------------------------------------------------------------------- verify
echo
if [[ -n $node && "$(ls -l "$node" | awk '{print $4}')" == pcscd ]]; then
  echo "==> Group is 'pcscd' — correct"
else
  echo "==> Group is still not 'pcscd'."
  echo "    Unplug the token and plug it back in (udev applies rules on device"
  echo "    arrival), then re-run this script."
  exit 1
fi

echo "==> Restarting pcscd so it re-scans for readers"
systemctl restart pcscd.service 2>/dev/null || systemctl start pcscd.service 2>/dev/null || true
sleep 2

echo "==> Reader check"
readers="$(timeout 15 opensc-tool --list-readers 2>&1 || true)"
echo "$readers" | sed 's/^/    /'
if grep -qi 'yubikey' <<<"$readers"; then
  echo
  echo "==> Done — the PIV applet is reachable."
else
  echo
  echo "==> Still no reader. Unplug/replug the token and re-run."
  exit 1
fi
