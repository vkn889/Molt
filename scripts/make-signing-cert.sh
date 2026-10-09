#!/bin/bash
# Creates a local code-signing certificate, "Molt Local Signing", in your login keychain. Builds
# signed with it keep the same identity from version to version, so macOS keeps permissions such
# as Screen Recording across updates. Ad-hoc builds look like a new app to macOS every time.
# This is not Apple notarization. Run it once; macOS asks for your password to trust it.
set -euo pipefail
NAME="Molt Local Signing"
if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "$NAME is already set up."
  exit 0
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days 3650 -config "$WORK/cert.cnf" 2>/dev/null
PASS="$(openssl rand -hex 16)"
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/molt.p12" -passout "pass:$PASS"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
security import "$WORK/molt.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"
echo "Done. ./scripts/package.sh now signs Molt as \"$NAME\"."
