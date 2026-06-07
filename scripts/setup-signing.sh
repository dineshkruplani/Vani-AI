#!/usr/bin/env bash
# One-time: create a stable self-signed code-signing identity so macOS TCC grants
# (Accessibility, Microphone) persist across rebuilds. Works with macOS LibreSSL.
set -euo pipefail

IDENTITY_NAME="Vani Dev"

# Note: no -v — a self-signed cert is untrusted, which -v hides, but codesign can
# still sign with it.
if security find-identity -p codesigning 2>/dev/null | grep -q "${IDENTITY_NAME}"; then
    echo "Signing identity '${IDENTITY_NAME}' already exists. Nothing to do."
    security find-identity -p codesigning | grep "${IDENTITY_NAME}"
    exit 0
fi

echo "Creating self-signed code-signing identity '${IDENTITY_NAME}'..."
TMP="$(mktemp -d)"
KEY="${TMP}/key.pem"; CRT="${TMP}/cert.pem"; P12="${TMP}/id.p12"; CFG="${TMP}/openssl.cnf"

# Extensions via a config file (portable across OpenSSL and macOS LibreSSL; no -addext).
cat > "${CFG}" <<'CNF'
[ req ]
distinguished_name = dn
prompt = no
[ dn ]
CN = Vani Dev
[ codesign ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -keyout "${KEY}" -out "${CRT}" -days 3650 -nodes \
    -config "${CFG}" -extensions codesign

# OpenSSL 3.x writes a PKCS#12 MAC that macOS `security` can't verify ("wrong
# password"). Add -legacy when the openssl build supports it (LibreSSL doesn't
# need it and doesn't have the flag).
P12_ARGS=(-export -inkey "${KEY}" -in "${CRT}" -out "${P12}" -passout pass:vani -name "${IDENTITY_NAME}")
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    P12_ARGS+=(-legacy)
fi
openssl pkcs12 "${P12_ARGS[@]}"

# -A lets codesign use the key without a per-sign Keychain prompt.
security import "${P12}" -k "${HOME}/Library/Keychains/login.keychain-db" \
    -P vani -A -T /usr/bin/codesign

rm -rf "${TMP}"

echo ""
if security find-identity -p codesigning | grep -q "${IDENTITY_NAME}"; then
    echo "SUCCESS - identity created:"
    security find-identity -p codesigning | grep "${IDENTITY_NAME}"
    echo "Now run ./scripts/run.sh - it will sign with this identity."
else
    echo "ERROR: identity was not created. Paste this whole output to debug."
    exit 1
fi
