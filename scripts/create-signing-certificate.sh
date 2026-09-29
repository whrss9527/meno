#!/usr/bin/env bash
#
# Creates a self-signed code signing certificate for Meno's releases.
#
# Ad hoc signatures differ with every build, so macOS treats each update as
# a new app and Accessibility has to be granted again. Releases signed with
# the same certificate keep one identity, and the permission carries over.
# This does not replace an Apple Developer ID: people still confirm the
# first launch, and the app cannot be notarized.
#
# Usage: scripts/create-signing-certificate.sh [name]
# Files go to ~/.meno-signing (MENO_SIGNING_DIR to change). Back the folder
# up: with a new certificate, the first update asks for Accessibility again.
set -euo pipefail

NAME="${1:-Meno Release Signing}"
DIR="${MENO_SIGNING_DIR:-$HOME/.meno-signing}"
OPENSSL="/usr/bin/openssl"
[[ -x "$OPENSSL" ]] || OPENSSL="openssl"

mkdir -p "$DIR"
chmod 700 "$DIR"
if [[ -e "$DIR/certificate.p12" ]]; then
  echo "$DIR already holds a certificate. Move the folder away to create a new one." >&2
  exit 1
fi

cat > "$DIR/openssl.cnf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = ${NAME}
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CONF

PASSWORD="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$DIR/openssl.cnf" \
  -keyout "$DIR/key.pem" -out "$DIR/certificate.pem" 2>/dev/null
# The macOS security tool only imports PKCS#12 files with these older algorithms.
"$OPENSSL" pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/certificate.pem" -name "$NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -out "$DIR/certificate.p12" -passout "pass:$PASSWORD"
rm -f "$DIR/key.pem" "$DIR/openssl.cnf"
printf '%s' "$PASSWORD" > "$DIR/password.txt"
base64 < "$DIR/certificate.p12" | tr -d '\n' > "$DIR/certificate.p12.base64"
chmod 600 "$DIR"/*

cat <<INFO

Created the code signing certificate "${NAME}" (valid for 10 years) in ${DIR}:
  certificate.p12          certificate and private key
  certificate.p12.base64   the same file, base64-encoded
  password.txt             password of the .p12 file

Add two secrets to the GitHub repository (Settings › Secrets and variables ›
Actions › New repository secret):
  MACOS_CERTIFICATE_P12        contents of certificate.p12.base64
                               (on macOS: pbcopy < ${DIR}/certificate.p12.base64)
  MACOS_CERTIFICATE_PASSWORD   contents of password.txt

Releases published by the Release workflow are then signed with it. Macs
running an ad hoc signed build grant Accessibility once more when they update
to the first signed release, and never again after that. Keep the private key
out of the repository and back up the folder.
INFO
