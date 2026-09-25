#!/usr/bin/env bash
#
# Phosphor Phase 3 — generate the permanent signing key set
#
#   bash scripts/keys-generate.sh
#
# Run as the NORMAL USER, not root.
#
# Generates the ten-key set GrapheneOS signs with (nine APK signing keys plus
# avb.pem), extracts the AVB public key metadata, then encrypts the whole set
# with a single random passphrase and seals that passphrase to the YubiKey.
#
# This is a ONE-WAY operation. The key set cannot be changed later without
# flashing the device again and performing a factory reset. See
# docs/PHASE-3-KEY-MANAGEMENT-DESIGN.md (decision D1).
#
# Ordering matters: this refuses to run unless the token's seal/unseal path has
# already been proven, so the passphrase is never left unprotected.
#
set -o errexit -o nounset -o pipefail

TREE="${PHOSPHOR_TREE:-$HOME/projects/grapheneos-2026091900}"
KEYS_DIR="${PHOSPHOR_KEYS_DIR:-$HOME/phosphor-keys/akita}"
KEY_DIR_ROOT="$(dirname "$KEYS_DIR")"
CN="${PHOSPHOR_KEY_CN:-/CN=Phosphor/O=Phosphor/C=US}"
SEAL_TEST_MARKER="$KEY_DIR_ROOT/.seal-tested"

# From script/common.sh — the authoritative list, in GrapheneOS's own order.
SIGNING_KEYS=(bluetooth gmscompat_lib media networkstack nfc platform releasekey sdk_sandbox shared)

fail() { echo "ERROR: $*" >&2; exit 1; }

echo "==> Phosphor Phase 3 — signing key generation"
echo "    tree:     $TREE"
echo "    keys dir: $KEYS_DIR"
echo "    subject:  $CN"
echo

# ------------------------------------------------------------------- guards
[[ $EUID -ne 0 ]] || fail "do not run this as root; run it as your normal user"

[[ -d $TREE ]] || fail "source tree not found at $TREE (set PHOSPHOR_TREE)"

[[ -x $TREE/development/tools/make_key ]] \
  || fail "make_key not found at $TREE/development/tools/make_key"
[[ -f $TREE/script/encrypt-keys ]] \
  || fail "encrypt-keys not found at $TREE/script/encrypt-keys"
[[ -f $TREE/external/avb/avbtool.py ]] \
  || fail "avbtool.py not found at $TREE/external/avb/avbtool.py"

# The safety interlock: the token must already be provisioned and proven.
[[ -f $SEAL_TEST_MARKER ]] || fail "the YubiKey seal/unseal path has not been proven yet.
       Run scripts/keys-yubikey-provision.sh first, and do not skip it —
       generating keys before the passphrase can be sealed leaves it
       unprotected in memory and in the shell."

# Never silently replace an existing key set.
if [[ -d $KEYS_DIR ]] && compgen -G "$KEYS_DIR/*.pk8" > /dev/null; then
  fail "$KEYS_DIR already contains a key set.
       These keys are permanent: replacing them requires flashing the device
       again and a factory reset. Refusing to overwrite."
fi

echo "==> Generating a random passphrase for the key set"
# Hex avoids any shell-quoting hazards; 32 bytes = 256 bits of entropy.
PASSPHRASE="$(openssl rand -hex 32)"
[[ ${#PASSPHRASE} -eq 64 ]] || fail "passphrase generation failed"
echo "    generated (not displayed, not logged)"
echo

mkdir -p "$KEYS_DIR"
chmod 700 "$KEY_DIR_ROOT" "$KEYS_DIR"

# ------------------------------------------------------- generate the keys
cd "$KEYS_DIR"

echo "==> Generating nine APK signing keys (RSA 4096)"
# make_key reads its password from stdin: a blank line means "no password".
# The set is left unencrypted here and encrypted in one pass below, which is
# how GrapheneOS's own tooling expects to do it (encrypt-keys handles both the
# .pk8 files and avb.pem together, and needs one passphrase for all of them).
for key in "${SIGNING_KEYS[@]}"; do
  # make_key's own EXIT trap is `trap 'rm -rf ${tmpdir}; echo; exit 1' EXIT INT
  # QUIT`, so it returns 1 even when it has produced both files correctly.
  # Upstream never notices because nothing calls it under `set -e`. Tolerate the
  # status and verify the artifacts instead: the files are the ground truth.
  printf '\n' | "$TREE/development/tools/make_key" "$key" "$CN" rsa > /dev/null || true
  [[ -s "$key.pk8" && -s "$key.x509.pem" ]] \
    || fail "make_key did not produce $key.pk8 / $key.x509.pem"
  printf '    %s.pk8 + %s.x509.pem\n' "$key" "$key"
done
echo

echo "==> Generating the AVB (verified boot) key"
# Unencrypted at this point so avbtool can read it without a prompt.
openssl genrsa -out avb.pem 4096 2>/dev/null
chmod 600 avb.pem
echo "    avb.pem"
echo

echo "==> Extracting AVB public key metadata (avb_pkmd.bin)"
# This is the value that gets embedded in vbmeta and that the bootloader would
# verify against. Not needed to produce a signed release, but it is the record
# of which key this device trusts.
"$TREE/external/avb/avbtool.py" extract_public_key --key avb.pem --output avb_pkmd.bin
chmod 644 avb_pkmd.bin
printf '    avb_pkmd.bin  sha256=%s\n' "$(sha256sum avb_pkmd.bin | cut -d' ' -f1)"
echo

# ------------------------------------------------------------ encrypt them
echo "==> Encrypting the whole set (scrypt + AES256)"
# encrypt-keys reads three lines from stdin: old passphrase (blank — nothing is
# encrypted yet), then the new passphrase twice. Unlike decrypt-keys it has no
# env-var shortcut, so it must be driven this way.
printf '\n%s\n%s\n' "$PASSPHRASE" "$PASSPHRASE" | "$TREE/script/encrypt-keys" "$KEYS_DIR"
echo

# -------------------------------------------------------------- verify it
echo "==> Verifying the set is actually encrypted"
plain=0
for key in "${SIGNING_KEYS[@]}"; do
  # A wrong passphrase must fail on an encrypted PKCS#8 file. If it succeeds,
  # the key is still in the clear.
  if openssl pkcs8 -inform DER -in "$key.pk8" -passin pass:definitely-not-the-passphrase \
       -out /dev/null 2>/dev/null; then
    printf '    NOT ENCRYPTED: %s.pk8\n' "$key"
    plain=1
  fi
done
if openssl pkcs8 -in avb.pem -passin pass:definitely-not-the-passphrase -out /dev/null 2>/dev/null; then
  echo "    NOT ENCRYPTED: avb.pem"
  plain=1
fi
[[ $plain -eq 0 ]] || fail "encryption verification failed — do not proceed"
echo "    all ten keys reject a wrong passphrase (encrypted)"
echo

# ------------------------------------------------------------------- escrow
# Captured here, before the seal, because this is the only moment the passphrase
# exists outside the token. Writing it first also means a failure in the seal
# step still leaves the passphrase recoverable rather than stranded.
ESCROW="$KEY_DIR_ROOT/ESCROW-passphrase-$(date -u +%Y%m%dT%H%M%SZ).txt"
{
  echo "Phosphor — signing key set passphrase escrow"
  echo
  echo "  generated:  $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "  device:     Pixel 8a / akita (serial 3C121JEKB03922)"
  echo "  key set:    $KEYS_DIR"
  echo "  contents:   9 APK signing keys (RSA 4096) + avb.pem"
  [[ -f $KEYS_DIR/avb_pkmd.bin ]] && \
    echo "  avb_pkmd.bin sha256: $(sha256sum "$KEYS_DIR/avb_pkmd.bin" | cut -d' ' -f1)"
  echo
  echo "This passphrase decrypts the ten signing keys above. It is ALSO sealed to"
  echo "the YubiKey (PIV slot 9d), so normal signing uses the token plus its PIN"
  echo "and this file is not needed for day-to-day work."
  echo
  echo "It exists so that losing or destroying the token does not lose the key"
  echo "set. Store this OFFLINE — paper in a safe, or an encrypted volume on"
  echo "removable media — and then delete it from this host. While it sits on the"
  echo "build host it bypasses the token entirely, which is the exact property the"
  echo "token was chosen to provide."
  echo
  echo "Losing the token AND this passphrase means the device will not accept"
  echo "future updates without being unlocked again and factory reset."
  echo
  echo "passphrase:"
  echo "$PASSPHRASE"
} > "$ESCROW"
chmod 600 "$ESCROW"
echo "==> Escrow written"
echo "    $ESCROW"
echo

# ------------------------------------------------------------- seal to token
echo "==> Sealing the passphrase to the YubiKey"
sealer="$HOME/projects/Phosphor/scripts/keys-yubikey-seal.sh"
if [[ -x $sealer || -f $sealer ]]; then
  printf '%s' "$PASSPHRASE" | bash "$sealer" --seal
  echo "    sealed"
else
  fail "seal helper not found at $sealer
       The keys are encrypted and the escrow file exists at:
           $ESCROW
       but the passphrase is NOT yet sealed to the token. Do not discard that
       file. Run the seal step before closing this terminal."
fi
unset PASSPHRASE
echo

# ---------------------------------------------------------- escrow handling
# The escrow must not linger on the build host: sitting here it bypasses the
# token completely, so it is offered for removal once it has been stored.
echo "==> Escrow handling"
echo "    Store this offline now (paper in a safe, or encrypted removable media):"
echo "        $ESCROW"
echo
read -rp "    Delete the host copy now that it is stored offline? [y/N] " ans
if [[ $ans == [yY]* ]]; then
  shred -u "$ESCROW" 2>/dev/null || rm -f "$ESCROW"
  echo "    host copy removed"
else
  echo "    kept at $ESCROW"
  echo "    remove it yourself once stored:  shred -u \"$ESCROW\""
  echo "    (while it remains here, the token is not the only way in)"
fi
echo

echo "==> Summary"
ls -la "$KEYS_DIR" | sed 's/^/    /'
echo
cat <<EOF
==> Done. The key set is generated, encrypted, and sealed to the token.

Record these facts (they belong in docs/evidence/):

    keys dir            $KEYS_DIR
    avb_pkmd.bin sha256 $(sha256sum "$KEYS_DIR/avb_pkmd.bin" | cut -d' ' -f1)
    key count           $(ls "$KEYS_DIR"/*.pk8 2>/dev/null | wc -l) pk8 + $(ls "$KEYS_DIR"/avb.pem 2>/dev/null | wc -l) avb.pem

This key set is now PERMANENT for this device. Losing it means the device will
not accept future updates without another unlock and factory reset.

The passphrase escrow for this set was written by this run — store it offline as
described above, and that covers losing the token. Still outstanding is the wider
backup policy in PHASE-3-KEY-MANAGEMENT-DESIGN.md §7: an encrypted backup of the
keys themselves, and the trap it warns about — a backup you cannot unseal is
worthless.
EOF
