#!/usr/bin/env bash
# Build Vani and assemble a minimal .app bundle so menu-bar behavior and
# macOS permission prompts (Microphone, Accessibility) work correctly.
set -euo pipefail

CONFIG="${1:-debug}"   # debug | release
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${ROOT}/Vani.app"

echo "Building (${CONFIG})..."
swift build -c "${CONFIG}"
BIN="${ROOT}/.build/${CONFIG}/Vani"

echo "Assembling ${APP} ..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
cp "${BIN}" "${APP}/Contents/MacOS/Vani"

cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Vani</string>
    <key>CFBundleDisplayName</key>     <string>Vani</string>
    <key>CFBundleIdentifier</key>      <string>network.playai.vani</string>
    <key>CFBundleExecutable</key>      <string>Vani</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Vani records your voice to transcribe it into text.</string>
</dict>
</plist>
PLIST

# Prefer the stable self-signed identity (TCC grants persist across rebuilds).
# No -v: a self-signed cert is untrusted (hidden by -v) but codesign can use it.
IDENTITY_NAME="Vani Dev"
SIGNED_WITH=""
if security find-identity -p codesigning 2>/dev/null | grep -q "${IDENTITY_NAME}"; then
    if codesign --force --deep --sign "${IDENTITY_NAME}" "${APP}" 2>/tmp/vani-codesign.err; then
        SIGNED_WITH="${IDENTITY_NAME}"
    else
        echo "NOTE: signing with '${IDENTITY_NAME}' failed:"
        cat /tmp/vani-codesign.err 2>/dev/null || true
    fi
fi

if [ -z "${SIGNED_WITH}" ]; then
    if codesign --force --deep --sign - "${APP}" >/dev/null 2>&1; then
        SIGNED_WITH="ad-hoc"
    fi
fi

case "${SIGNED_WITH}" in
    "${IDENTITY_NAME}") echo "Codesigned with '${IDENTITY_NAME}' (Accessibility/Mic grants will persist).";;
    "ad-hoc")           echo "Codesigned (ad-hoc). Run ./scripts/setup-signing.sh once so grants persist across rebuilds.";;
    *)                  echo "WARNING: codesign failed entirely.";;
esac

echo "Built ${APP}"
echo "Run with: open \"${APP}\"   (or ./scripts/run.sh)"
