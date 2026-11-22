#!/usr/bin/env bash
# Builds a Developer ID–signed, notarized, stapled Macros.app and DMG into dist/apps/mac/release.
#
# Notary credentials, in order of preference:
#   NOTARY_KEY + NOTARY_KEY_ID + NOTARY_ISSUER   App Store Connect API key (.p8 path) — for CI
#   NOTARY_PROFILE                               notarytool keychain profile (default: macros-notary)
#
# VERSION (X.Y.Z) and BUILD_NUMBER override MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml.
# SIGN_IDENTITY overrides the signing identity used for the DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APP_DIR="$ROOT/apps/mac"
OUT="$ROOT/dist/apps/mac/release"
TEAM_ID="7C3LJCLXTY"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Bo Bramer ($TEAM_ID)}"

if [[ -n "${NOTARY_KEY:-}" ]]; then
    NOTARY_AUTH=(--key "$NOTARY_KEY" --key-id "${NOTARY_KEY_ID:?}" --issuer "${NOTARY_ISSUER:?}")
else
    NOTARY_AUTH=(--keychain-profile "${NOTARY_PROFILE:-macros-notary}")
fi

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# Submits a file for notarization, waits, and fails with Apple's log unless it was accepted.
notarize() {
    local file="$1" result="$OUT/notary-$(basename "$1").json"
    xcrun notarytool submit "$file" "${NOTARY_AUTH[@]}" --wait --output-format json >"$result" || true
    local status id
    status="$(plutil -extract status raw -o - "$result" 2>/dev/null || echo unknown)"
    id="$(plutil -extract id raw -o - "$result" 2>/dev/null || echo)"
    echo "Notarization of $(basename "$file"): $status ${id:+(id $id)}"
    if [[ "$status" != "Accepted" ]]; then
        cat "$result"
        [[ -n "$id" ]] && xcrun notarytool log "$id" "${NOTARY_AUTH[@]}"
        exit 1
    fi
}

rm -rf "$OUT"
mkdir -p "$OUT"

step "Generating Xcode project"
(cd "$APP_DIR" && xcodegen generate --quiet)
PROJECT="$APP_DIR/Macros.xcodeproj"

VERSION="${VERSION:-$(xcodebuild -project "$PROJECT" -scheme Macros -configuration Release -showBuildSettings \
    2>/dev/null | awk '$1 == "MARKETING_VERSION" { print $3; exit }')}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must be X.Y.Z, got '$VERSION'" >&2
    exit 1
fi
VERSION_SETTINGS=("MARKETING_VERSION=$VERSION")
[[ -n "${BUILD_NUMBER:-}" ]] && VERSION_SETTINGS+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
echo "Version $VERSION (build ${BUILD_NUMBER:-from project.yml})"

step "Archiving"
xcodebuild archive \
    -project "$PROJECT" -scheme Macros -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$OUT/Macros.xcarchive" -quiet \
    "${VERSION_SETTINGS[@]}"

step "Exporting with Developer ID"
xcodebuild -exportArchive \
    -archivePath "$OUT/Macros.xcarchive" \
    -exportOptionsPlist "$APP_DIR/ExportOptions.plist" \
    -exportPath "$OUT/export" -quiet
APP="$OUT/export/Macros.app"
codesign --verify --strict --deep "$APP"

step "Notarizing app"
ditto -c -k --keepParent "$APP" "$OUT/Macros-notarize.zip"
notarize "$OUT/Macros-notarize.zip"
xcrun stapler staple -q "$APP"
rm "$OUT/Macros-notarize.zip"

step "Building DMG"
DMG="$OUT/Macros-$VERSION.dmg"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Macros.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Macros $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"

step "Notarizing DMG"
notarize "$DMG"
xcrun stapler staple -q "$DMG"

step "Zipping stapled app"
ZIP="$OUT/Macros-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

step "Verifying"
spctl --assess --type exec -vv "$APP"
spctl --assess --type open --context context:primary-signature -vv "$DMG"
xcrun stapler validate -q "$APP"
xcrun stapler validate -q "$DMG"

step "Done"
ls -lh "$DMG" "$ZIP"
