#!/usr/bin/env bash
# Build a shareable (unsigned / non-notarized) Vani.dmg.
# Recipients drag Vani.app to Applications and bypass Gatekeeper once.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${ROOT}/Vani.app"
DIST="${ROOT}/dist"
DMG="${DIST}/Vani.dmg"
VOL="Vani"

echo "==> Building release app..."
"${ROOT}/scripts/bundle.sh" release

echo "==> Staging disk image..."
STAGE="$(mktemp -d)"
cp -R "${APP}" "${STAGE}/Vani.app"
ln -s /Applications "${STAGE}/Applications"

cat > "${STAGE}/READ ME FIRST.txt" <<'TXT'
Vani - bring-your-own-key voice dictation for macOS (unsigned build)

INSTALL
  1. Drag Vani.app onto the Applications folder shown in this window.

FIRST LAUNCH (one time - this build is not notarized by Apple)
  macOS will say the developer "cannot be verified". To open it:

  Easiest (Terminal):
      xattr -dr com.apple.quarantine /Applications/Vani.app
      then open Vani from Applications.

  Without Terminal:
      Right-click Vani.app -> Open -> Open.
      If still blocked: System Settings -> Privacy & Security ->
      scroll down -> "Open Anyway".

PERMISSIONS (Vani prompts; approve in System Settings -> Privacy & Security)
  - Microphone        hear you while you hold the talk key
  - Accessibility     type the cleaned text into any app
  - Screen Recording  only if you turn on AI vision context

USING IT
  Vani lives in the menu bar (no Dock icon). Open Settings, paste your own
  API key (OpenRouter / OpenAI / Anthropic / Groq / or run a local model),
  then hold Right Option anywhere and talk. Your audio and text go straight
  to your chosen provider - never through our servers.
TXT

mkdir -p "${DIST}"
rm -f "${DMG}"
echo "==> Creating DMG..."
hdiutil create -volname "${VOL}" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}" >/dev/null
rm -rf "${STAGE}"

echo ""
echo "Built: ${DMG}"
du -h "${DMG}" | awk '{print "Size:  "$1}'
echo ""
echo "Share that .dmg. Tell recipients: open the dmg, drag Vani to Applications,"
echo "then run:  xattr -dr com.apple.quarantine /Applications/Vani.app"
