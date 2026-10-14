#!/bin/bash
# Package the iPhone/iPad build as an IPA for SideStore, AltStore, Sideloadly or
# TrollStore. The app is signed ad hoc *with its entitlements*, because sideloading
# tools copy the entitlements from the existing signature when they re-sign:
# that is how the App Group (widgets) and get-task-allow (StikDebug JIT) survive.
#
#   apple/scripts/package-ipa.sh <Release-iphoneos dir> <output.ipa>
set -euo pipefail

PRODUCTS="${1:?products dir}"
OUTPUT="${2:?output ipa}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${HERE}/build/package-ipa"

APP="$(find "${PRODUCTS}" -maxdepth 1 -name '*.app' | head -1)"
[ -n "${APP}" ] || { echo "no .app in ${PRODUCTS}"; exit 1; }

# Resolve $(APP_GROUP) the same way Xcode would.
APP_GROUP="$(cd "${HERE}" && xcodebuild -project Halcyon.xcodeproj -target HalcyonIOS -configuration Release \
    -sdk iphoneos -showBuildSettings 2>/dev/null | awk -F' = ' '$1 ~ / APP_GROUP$/ {print $2; exit}')"
echo "App Group: ${APP_GROUP}"

rm -rf "${WORK}"
mkdir -p "${WORK}/Payload"
sed "s/\$(APP_GROUP)/${APP_GROUP}/g" "${HERE}/iOS/Halcyon.entitlements" > "${WORK}/app.entitlements"
sed "s/\$(APP_GROUP)/${APP_GROUP}/g" "${HERE}/Widgets/HalcyonWidgets.entitlements" > "${WORK}/widgets.entitlements"

cp -R "${APP}" "${WORK}/Payload/"
STAGED="${WORK}/Payload/$(basename "${APP}")"

for appex in "${STAGED}"/PlugIns/*.appex; do
    [ -d "${appex}" ] || continue
    codesign --force --sign - --entitlements "${WORK}/widgets.entitlements" "${appex}"
done
codesign --force --sign - --entitlements "${WORK}/app.entitlements" "${STAGED}"
codesign -d --entitlements - "${STAGED}" 2>/dev/null | head -20 || true

rm -f "${OUTPUT}"
(cd "${WORK}" && zip -qry "${OUTPUT}" Payload)
echo "Wrote ${OUTPUT}"
