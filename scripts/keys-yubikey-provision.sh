#!/usr/bin/env bash
#
# Phosphor Phase 3 — provision the YubiKey as the signing-key passphrase gate
#
#   bash scripts/keys-yubikey-provision.sh
#
# Run as the NORMAL USER (not root). Your PIN and PUK are typed at ykman's own
# prompts; they are never passed as command-line arguments (which would expose
# them in the process list) and never written to disk by this script.
#
# What this does, per docs/PHASE-3-KEY-MANAGEMENT-DESIGN.md §5:
#
#   1. Requires the token's PIN and PUK to have been changed off their factory
#      defaults. This is the load-bearing step: the PIN is what gates the
#      passphrase unwrap, and the factory PIN is publicly known (123456), so
#      sealing to a default-PIN token would make the protection decorative.
#   2. Generates an RSA-2048 key in PIV slot 9d (Key Management). The private
#      key is generated on the token and never leaves it.
#   3. Self-signs a certificate for that slot, which is what makes the key
#      visible through PKCS#11 / OpenSC.
#   4. Round-trips a random test secret — seal with the public key, unseal via
#      the token — and only writes the "proven" marker if the secret survives
#      intact. keys-generate.sh refuses to run without that marker.
#
# The wrap key is RSA-2048 by choice (see §5.2): it wraps a 64-byte passphrase
# once per signing session, so 2048 bits is ample and it is the best-exercised
# path in OpenSC. This firmware supports RSA-4096 if more margin is ever wanted.
#
# Idempotent with respect to the PIN/PUK steps; refuses to overwrite an existing
# key in slot 9d without being told to.
#
set -o errexit -o nounset -o pipefail

KEY_DIR_ROOT="${PHOSPHOR_KEY_DIR_ROOT:-$HOME/phosphor-keys}"
CONF="$KEY_DIR_ROOT/yubikey.conf"
PUB="$KEY_DIR_ROOT/piv-wrap-pub.pem"
MARKER="$KEY_DIR_ROOT/.seal-tested"
SLOT=9d
# NOTE the format: ykman parses this as an RFC 4514 string, so it must be
# comma-separated with no leading slash. This is deliberately different from the
# subject passed to make_key in keys-generate.sh, which goes to `openssl req
# -subj` and therefore needs OpenSSL's /CN=x/O=y form. Passing the OpenSSL form
# here makes cryptography raise a ValueError with an EMPTY message, which ykman
# surfaces as a bare "ValueError" and no explanation.
SUBJECT="CN=Phosphor Key Wrap,O=Phosphor,C=US"
VALID_DAYS=3650
SELFTEST_PLAIN="$KEY_DIR_ROOT/.selftest.plain"
SELFTEST_SEALED="$KEY_DIR_ROOT/.selftest.sealed"
SELFTEST_OUT="$KEY_DIR_ROOT/.selftest.out"

# PKCS#11 module; the installer already located this, but keep it overridable.
PKCS11_MODULE="${PHOSPHOR_PKCS11_MODULE:-}"
if [[ -z $PKCS11_MODULE ]]; then
  for cand in /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so \
              /usr/lib/opensc-pkcs11.so \
              /usr/lib64/opensc-pkcs11.so; do
    [[ -f $cand ]] && PKCS11_MODULE="$cand" && break
  done
fi

fail() { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

cleanup() { rm -f "$SELFTEST_PLAIN" "$SELFTEST_SEALED" "$SELFTEST_OUT"; }
trap cleanup EXIT

echo "==> Phosphor Phase 3 — YubiKey provisioning"
echo "    config dir: $KEY_DIR_ROOT"
echo "    slot:       $SLOT"
echo

# ------------------------------------------------------------------- guards
[[ $EUID -ne 0 ]] || fail "run this as your normal user, not root"
have ykman        || fail "ykman not found — run scripts/host-setup-phase3-yubikey.sh first"
have pkcs11-tool  || fail "pkcs11-tool not found — run scripts/host-setup-phase3-yubikey.sh first"
have openssl      || fail "openssl not found"
[[ -n $PKCS11_MODULE ]] || fail "opensc-pkcs11.so not found — is opensc installed?"

mkdir -p "$KEY_DIR_ROOT"
chmod 700 "$KEY_DIR_ROOT"

echo "==> Checking the token and PIV"
pivinfo="$(ykman piv info 2>&1 || true)"
if ! grep -q 'PIV version' <<<"$pivinfo"; then
  echo "$pivinfo" | sed 's/^/    /'
  fail "PIV is not reachable.
       Usually a CCID permission problem — run:
           sudo bash scripts/host-fix-yubikey-ccid.sh"
fi
grep -E 'PIV version|PIN tries|PUK tries|Management key algorithm' <<<"$pivinfo" | sed 's/^/    /'
echo

# ---------------------------------------------------- PIN / PUK interlock
# The PIN is the whole point of the custody design. A factory PIN makes the
# token nearly useless as a gate, because 123456 is in every Yubico manual.
pin_is_default() { ykman piv info 2>&1 | grep -q 'Using default PIN!'; }
puk_is_default() { ykman piv info 2>&1 | grep -q 'Using default PUK!'; }

if pin_is_default || puk_is_default; then
  echo "==> The token is still on factory defaults"
  pin_is_default && echo "    PIN: default (publicly known — 123456 in every Yubico manual)"
  puk_is_default && echo "    PUK: default"
  echo
  echo "    Both must be changed before anything is sealed to this token."
  echo "    You will be prompted for the current value, then your new one."
  echo "    ykman requires 6-8 characters; numeric is recommended for"
  echo "    cross-platform compatibility."
  echo
  read -rp "    Change PIN and PUK now? [y/N] " ans
  [[ $ans == [yY]* ]] || fail "declined — nothing sealed. Re-run when ready."

  if pin_is_default; then
    echo
    echo "==> Changing the PIN (current PIN is 123456)"
    ykman piv access change-pin
  fi
  if puk_is_default; then
    echo
    echo "==> Changing the PUK (current PUK is 12345678)"
    ykman piv access change-puk
  fi

  echo
  echo "==> Re-checking"
  pivinfo="$(ykman piv info 2>&1 || true)"
  grep -E 'PIN tries|PUK tries' <<<"$pivinfo" | sed 's/^/    /'
  if pin_is_default || puk_is_default; then
    fail "the token still reports factory defaults — stopping before anything
       is sealed to it."
  fi
  echo "    PIN and PUK are no longer the defaults"
else
  echo "==> PIN and PUK are already non-default — good"
fi
echo

# ------------------------------------------------------- generate the key
# Resumable by design: an interrupted run leaves a good key in the slot, and
# regenerating it would be pointless churn that also invalidates the public key
# already written. Detect that state and continue to the certificate step.
if [[ -f $CONF && -f $MARKER ]]; then
  echo "==> This token already looks provisioned"
  printf '    config: %s\n' "$CONF"
  printf '    proven: %s\n' "$MARKER"
  echo
  read -rp "    Re-provision anyway (regenerating the wrap key)? [y/N] " ans
  [[ $ans == [yY]* ]] || { echo "    nothing to do"; exit 0; }
fi

skip_keygen=0
if ykman piv keys info "$SLOT" >/dev/null 2>&1; then
  echo "==> A key already exists in slot $SLOT"
  ykman piv keys info "$SLOT" 2>&1 | sed 's/^/    /' | head -8
  echo
  if [[ -f $PUB ]]; then
    echo "    The matching public key is already on disk: $PUB"
    read -rp "    Keep the key and resume from the certificate step? [Y/n] " ans
    [[ $ans == [nN]* ]] || skip_keygen=1
  fi
  if [[ $skip_keygen -eq 0 ]]; then
    read -rp "    Replace it? This invalidates anything sealed to the old key. [y/N] " ans
    [[ $ans == [yY]* ]] || fail "declined — keeping the existing key.
       If a passphrase is already sealed to it, use the existing public key at
       $PUB and re-run with nothing to do."
    echo "    deleting old key and certificate"
    ykman piv keys delete "$SLOT" 2>/dev/null || true
    ykman piv certificates delete "$SLOT" 2>/dev/null || true
  fi
fi

if [[ $skip_keygen -eq 1 ]]; then
  echo "==> Keeping the existing key in slot $SLOT; continuing to the certificate"
  [[ -f $PUB ]] || fail "the public key file $PUB is missing — cannot continue.
       Delete the key in slot $SLOT and re-run to regenerate both."
else
  echo "==> Generating an RSA-2048 key in slot $SLOT"
  echo "    The private key is generated on the token and never leaves it."
  echo "    ykman will prompt for the Management Key. The factory default is the"
  echo "    AES-192 value 010203040506070801020304050607080102030405060708 —"
  echo "    publicly known, and harmless here: it authorises key management only"
  echo "    and cannot decrypt anything. The PIN is what gates unsealing."
  # --pin-policy ONCE: one PIN entry per card session, which for an
  #   always-plugged-in build token means one per replug. ALWAYS would be
  #   stricter but re-prompts for every operation, which an unattended signing
  #   run cannot satisfy. --touch-policy NEVER is required for automation: a
  #   touch would stall a headless signing pass indefinitely.
  ykman piv keys generate \
    -a RSA2048 \
    --pin-policy ONCE \
    --touch-policy NEVER \
    "$SLOT" "$PUB"
  chmod 644 "$PUB"
  echo "    public key written: $PUB"
fi
echo

echo "==> Self-signing a certificate for slot $SLOT"
echo "    OpenSC exposes the key through PKCS#11 only once a certificate exists"
echo "    for it. You will be prompted for your PIN."
ykman piv certificates generate \
  -s "$SUBJECT" \
  -d "$VALID_DAYS" \
  "$SLOT" "$PUB"
echo

# ------------------------------------------------- discover the PKCS#11 id
echo "==> Locating the key through PKCS#11"
# Deliberately WITHOUT --login: the public key and certificate objects carry the
# same CKA_ID as the private key, and they are readable without a PIN. Using
# --login here would put an interactive PIN prompt inside a command
# substitution, where stdin is already consumed — pkcs11-tool then dies with
# "util_getpass error" and the id is lost. (The round-trip decrypt below runs
# directly, not in a substitution, so it prompts fine.)
objects="$(pkcs11-tool --module "$PKCS11_MODULE" --list-objects 2>&1 || true)"
echo "$objects" | sed 's/^/    /'

# Parse the ID from the public key (falling back to the certificate) object.
obj_id="$(awk '
  /Public Key Object/   { want=1; next }
  /Certificate Object/  { if (!want) want=1; next }
  want && /^[[:space:]]*ID:/ { gsub(/^[[:space:]]*ID:[[:space:]]*/, ""); print; exit }
' <<<"$objects" || true)"

if [[ -z $obj_id ]]; then
  echo
  echo "    Could not parse a private key ID from the listing above."
  echo "    The round-trip test below will try without an explicit id."
else
  echo
  echo "    private key id: $obj_id"
fi
echo

# ------------------------------------------------------ round-trip the seal
echo "==> Round-trip test: can this token unseal what its public key seals?"
testsecret="phosphor-seal-test-$(openssl rand -hex 16)"
printf '%s' "$testsecret" > "$SELFTEST_PLAIN"

if ! openssl pkeyutl -encrypt -pubin -inkey "$PUB" \
      -pkeyopt rsa_padding_mode:oaep \
      -pkeyopt rsa_oaep_md:sha256 \
      -pkeyopt rsa_mgf1_md:sha256 \
      -in "$SELFTEST_PLAIN" -out "$SELFTEST_SEALED" 2>/dev/null; then
  fail "could not seal the test secret with the PIV public key"
fi
echo "    sealed $(wc -c < "$SELFTEST_SEALED") bytes to the token's public key"

# SHA-256 for both the OAEP digest and MGF1, matching the encrypt side. Getting
# these out of step (OpenSSL defaulting to SHA-1 while the token uses something
# else) is the classic reason this fails.
decrypt_with_id() {
  local id="$1"
  if [[ -n $id ]]; then
    pkcs11-tool --module "$PKCS11_MODULE" --decrypt --mechanism RSA-PKCS-OAEP \
      --hash-algorithm SHA256 --mgf MGF1-SHA256 \
      --id "$id" --input-file "$SELFTEST_SEALED" --output-file "$SELFTEST_OUT" --login
  else
    pkcs11-tool --module "$PKCS11_MODULE" --decrypt --mechanism RSA-PKCS-OAEP \
      --hash-algorithm SHA256 --mgf MGF1-SHA256 \
      --input-file "$SELFTEST_SEALED" --output-file "$SELFTEST_OUT" --login
  fi
}

echo "    unsealing via the token — prompting for your PIN"
if ! decrypt_with_id "$obj_id"; then
  if [[ -n $obj_id ]]; then
    echo "    retrying without an explicit id"
    rm -f "$SELFTEST_OUT"
    decrypt_with_id "" || fail "the token could not unseal the test secret.
       Do not generate keys yet. The PKCS#11 parameters above need checking."
  else
    fail "the token could not unseal the test secret.
       Do not generate keys yet."
  fi
fi

got="$(cat "$SELFTEST_OUT" 2>/dev/null || true)"
if [[ $got != "$testsecret" ]]; then
  fail "the unsealed secret does not match what was sealed — the round trip is
       not sound. Do not seal a real passphrase to this token."
fi
echo "    round trip OK — the secret survived seal/unseal intact"
echo

# ------------------------------------------------------------- record it
cat > "$CONF" <<EOF
# Phosphor — YubiKey wrap-key configuration
# Written by scripts/keys-yubikey-provision.sh. Read by keys-yubikey-seal.sh.
#
# The key lives in PIV slot $SLOT and cannot be extracted from the token.
# Unsealing requires the token plus its PIN.
PKCS11_MODULE="$PKCS11_MODULE"
PIV_SLOT="$SLOT"
PKCS11_OBJECT_ID="${obj_id}"
PUBLIC_KEY="$PUB"
SEAL_PADDING="oaep-sha256"
EOF
chmod 600 "$CONF"

date -u '+%Y-%m-%dT%H:%M:%SZ' > "$MARKER"
chmod 600 "$MARKER"

echo "==> Summary"
printf '    config:    %s\n' "$CONF"
printf '    pub key:   %s\n' "$PUB"
printf '    pub sha256: %s\n' "$(sha256sum "$PUB" | cut -d' ' -f1)"
[[ -n $obj_id ]] && printf '    pkcs11 id: %s\n' "$obj_id"
printf '    proven:    %s\n' "$MARKER"
echo
cat <<EOF
==> Done. The token is provisioned and the seal/unseal path is proven.

Next: generate the signing key set, which will be encrypted and then sealed to
this token:

    bash ~/projects/Phosphor/scripts/keys-generate.sh

Do not skip the interlock — keys-generate.sh reads the marker written above and
refuses to run without it.
EOF
