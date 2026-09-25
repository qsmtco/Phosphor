#!/usr/bin/env bash
#
# Phosphor Phase 3 — seal/unseal the signing-key passphrase with the YubiKey
#
#   bash scripts/keys-yubikey-seal.sh --seal   [-i IN] [-o OUT]   # stdin -> OUT
#   bash scripts/keys-yubikey-seal.sh --unseal [-o OUT]           # OUT <- token
#
# Reads the wrap-key configuration written by keys-yubikey-provision.sh
# (~/phosphor-keys/yubikey.conf) and uses the RSA-2048 key in PIV slot 9d.
#
# Sealing needs only the public key, so it works without the token.
# Unsealing needs the token AND its PIN — that is the whole point.
#
# SAFETY: --unseal writes the plaintext passphrase to a FILE, never to stdout.
# Printing it would put it in terminal scrollback, shell history, and any log
# that captures the caller's output. Callers read the file and delete it.
#
set -o errexit -o nounset -o pipefail

KEY_DIR_ROOT="${PHOSPHOR_KEY_DIR_ROOT:-$HOME/phosphor-keys}"
CONF="$KEY_DIR_ROOT/yubikey.conf"

# ------------------------------------------------------------------- config
[[ -f $CONF ]] || {
  echo "ERROR: no wrap-key config at $CONF" >&2
  echo "       Run scripts/keys-yubikey-provision.sh first." >&2
  exit 1
}

# shellcheck source=/dev/null
source "$CONF"

: "${PKCS11_MODULE:?config is missing PKCS11_MODULE}"
: "${PUBLIC_KEY:?config is missing PUBLIC_KEY}"
: "${PKCS11_OBJECT_ID:=}"

fail() { echo "ERROR: $*" >&2; exit 1; }

mode=""
infile=""
outfile=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --seal)   mode=seal;   shift ;;
    --unseal) mode=unseal; shift ;;
    -i)       infile="$2";  shift 2 ;;
    -o)       outfile="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -20
      exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n $mode ]] || fail "specify --seal or --unseal"

# --------------------------------------------------------------------- seal
if [[ $mode == seal ]]; then
  [[ -f $PUBLIC_KEY ]] || fail "public key not found at $PUBLIC_KEY"
  [[ -n $outfile ]] || outfile="$KEY_DIR_ROOT/passphrase.sealed"

  # Read plaintext from the file if given, otherwise stdin. Either way it is
  # fed through a pipe and never placed on a command line.
  src="/dev/stdin"
  [[ -n $infile ]] && src="$infile"
  tmp_plain="$(mktemp "$KEY_DIR_ROOT/.sealplain.XXXXXX")"
  chmod 600 "$tmp_plain"
  trap 'rm -f "$tmp_plain"' EXIT
  cat "$src" > "$tmp_plain"

  [[ -s $tmp_plain ]] || fail "refusing to seal an empty passphrase"

  # OAEP with SHA-256 for both the digest and MGF1. The decrypt side must match
  # exactly (see --unseal) — an OpenSSL default of SHA-1 on one side and SHA-256
  # on the other is the classic silent failure here.
  openssl pkeyutl -encrypt -pubin -inkey "$PUBLIC_KEY" \
    -pkeyopt rsa_padding_mode:oaep \
    -pkeyopt rsa_oaep_md:sha256 \
    -pkeyopt rsa_mgf1_md:sha256 \
    -in "$tmp_plain" -out "$outfile"

  chmod 600 "$outfile"
  printf '%s\n' "$outfile"
  exit 0
fi

# ------------------------------------------------------------------- unseal
if [[ $mode == unseal ]]; then
  [[ -n $outfile ]] || fail "--unseal requires -o FILE
       (the passphrase is never written to stdout by design)"

  sealed="${infile:-$KEY_DIR_ROOT/passphrase.sealed}"
  [[ -f $sealed ]] || fail "no sealed passphrase at $sealed"

  # Run directly, NOT in a command substitution: the PIN prompt needs the
  # terminal's stdin, and capturing output would consume it (pkcs11-tool then
  # fails with "util_getpass error").
  if [[ -n $PKCS11_OBJECT_ID ]]; then
    pkcs11-tool --module "$PKCS11_MODULE" --decrypt --mechanism RSA-PKCS-OAEP \
      --hash-algorithm SHA256 --mgf MGF1-SHA256 \
      --id "$PKCS11_OBJECT_ID" \
      --input-file "$sealed" --output-file "$outfile" --login
  else
    # No id recorded: relies on there being exactly one private key on the
    # token. Sound today (PIV slot 9d only), fragile if more keys are added.
    pkcs11-tool --module "$PKCS11_MODULE" --decrypt --mechanism RSA-PKCS-OAEP \
      --hash-algorithm SHA256 --mgf MGF1-SHA256 \
      --input-file "$sealed" --output-file "$outfile" --login
  fi

  chmod 600 "$outfile"
  [[ -s $outfile ]] || fail "unseal produced nothing — wrong token or PIN?"
  printf '%s\n' "$outfile"
  exit 0
fi
