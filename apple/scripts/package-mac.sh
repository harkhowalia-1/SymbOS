#!/bin/bash
# Sign the Mac app and wrap it in a DMG.
#
#   apple/scripts/package-mac.sh <path/to/Halcyon.app> <output.dmg>
#
# Without secrets the app is signed ad hoc (users right-click › Open the first time).
# With these environment variables it is signed with Developer ID and notarized,
# so it opens with a normal double-click:
#   MAC_SIGN_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID1234)"
#   NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD (an app-specific password)
set -euo pipefail

APP="${1:?app path}"
OUTPUT="${2:?output dmg}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
NAME="$(basename "${APP}" .app)"
IDENTITY="${MAC_SIGN_IDENTITY:--}"
ENTITLEMENTS="${HERE}/macOS/Halcyon.entitlements"

TIMESTAMP=()
if [ "${IDENTITY}" != "-" ]; then
    TIMESTAMP=(--timestamp)
    echo "Signing with ${IDENTITY}"
else
    echo "Signing ad hoc (no MAC_SIGN_IDENTITY)"
fi

# Inside out: embedded frameworks first, then the app with the Hardened Runtime.
if [ -d "${APP}/Contents/Frameworks" ]; then
    find "${APP}/Contents/Frameworks" -maxdepth 1 -name '*.framework' -print0 |
        while IFS= read -r -d '' framework; do
            codesign --force --sign "${IDENTITY}" ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} --options runtime "${framework}"
        done
fi
codesign --force --sign "${IDENTITY}" ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} --options runtime \
    --entitlements "${ENTITLEMENTS}" "${APP}"
codesign --verify --deep --strict "${APP}"

# Disk image: styled when create-dmg is available, plain otherwise.
rm -rf "${HERE}/build/dmg" "${OUTPUT}"
mkdir -p "${HERE}/build/dmg"
cp -R "${APP}" "${HERE}/build/dmg/"
if command -v create-dmg >/dev/null && create-dmg \
        --volname "${NAME}" \
        --background "${HERE}/dmg/background.png" \
        --window-pos 200 120 --window-size 600 400 --icon-size 112 \
        --icon "${NAME}.app" 165 200 --hide-extension "${NAME}.app" \
        --app-drop-link 435 200 \
        "${OUTPUT}" "${HERE}/build/dmg/"; then
    echo "Styled disk image created"
else
    rm -f "${OUTPUT}"
    ln -s /Applications "${HERE}/build/dmg/Applications"
    hdiutil create -volname "${NAME}" -srcfolder "${HERE}/build/dmg" -ov -format UDZO "${OUTPUT}"
fi

if [ "${IDENTITY}" != "-" ]; then
    codesign --force --sign "${IDENTITY}" --timestamp "${OUTPUT}"
    if [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
        xcrun notarytool submit "${OUTPUT}" --apple-id "${NOTARY_APPLE_ID}" --team-id "${NOTARY_TEAM_ID}" \
            --password "${NOTARY_PASSWORD}" --wait
        xcrun stapler staple "${OUTPUT}"
    fi
fi
echo "Wrote ${OUTPUT}"
