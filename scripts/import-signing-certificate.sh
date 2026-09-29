#!/usr/bin/env bash
#
# Imports a code signing certificate (.p12, base64-encoded) into a temporary
# keychain for codesign. Used by the Release workflow:
#
#   CERTIFICATE_P12_BASE64=… CERTIFICATE_PASSWORD=… scripts/import-signing-certificate.sh
#
# The certificate can be a Developer ID Application certificate or one made
# by scripts/create-signing-certificate.sh. The identity and keychain are
# written to $GITHUB_ENV as SIGN_IDENTITY and SIGN_KEYCHAIN (printed when
# not running on GitHub Actions); scripts/build-app.sh signs with them.
set -euo pipefail

: "${CERTIFICATE_P12_BASE64:?CERTIFICATE_P12_BASE64 is not set}"
: "${CERTIFICATE_PASSWORD:?CERTIFICATE_PASSWORD is not set}"

work="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/meno-signing"
rm -rf "$work" && mkdir -p "$work"
keychain="$work/signing.keychain-db"
keychain_password="$(/usr/bin/openssl rand -hex 24)"
p12="$work/certificate.p12"

# Pasted secrets can carry line breaks or spaces.
printf '%s' "$CERTIFICATE_P12_BASE64" | tr -d ' \r\n\t' | base64 --decode > "$p12"
[[ -s "$p12" ]] || { echo "CERTIFICATE_P12_BASE64 does not decode to a file" >&2; exit 1; }

security create-keychain -p "$keychain_password" "$keychain"
# Keep the keychain unlocked for the whole build (the default is 5 minutes).
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
if ! security import "$p12" -k "$keychain" -P "$CERTIFICATE_PASSWORD" -f pkcs12 -T /usr/bin/codesign >/dev/null; then
  rm -f "$p12"
  echo "Could not import the certificate: wrong password, or the .p12 has no private key" >&2
  exit 1
fi
rm -f "$p12"
# Let codesign use the key without a confirmation dialog, which would hang CI.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
# Add the keychain to the search list, keeping the existing ones.
# shellcheck disable=SC2046
security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')

# A self-signed certificate is not trusted, so -v would hide it: take the
# first identity that can sign code.
identities="$(security find-identity -p codesigning "$keychain")"
identity="$(printf '%s\n' "$identities" | awk '/^ *1\)/ { print $2; exit }')"
name="$(printf '%s\n' "$identities" | awk -F'"' '/^ *1\)/ { print $2; exit }')"
if [[ -z "$identity" ]]; then
  printf '%s\n' "$identities"
  echo "The keychain holds no identity that can sign code" >&2
  exit 1
fi
echo "Signing with: ${name} (${identity})"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "SIGN_IDENTITY=$identity"
    echo "SIGN_KEYCHAIN=$keychain"
  } >> "$GITHUB_ENV"
else
  echo "SIGN_IDENTITY=$identity"
  echo "SIGN_KEYCHAIN=$keychain"
fi
