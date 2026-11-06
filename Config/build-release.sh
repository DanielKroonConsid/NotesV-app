#!/bin/bash
# Builds a release .dmg of NotesV with its SHA-256 checksum in build/release.
#
#   Config/build-release.sh <version> [build number]
#
# Without Apple credentials the app is signed ad hoc, so macOS warns on first launch.
# Set these to sign with Developer ID and notarize:
#   DEVELOPER_ID_IDENTITY  e.g. "Developer ID Application: Name (TEAMID)"
#   NOTARY_KEY_PATH        path to an App Store Connect API key (.p8)
#   NOTARY_KEY_ID          the key's id
#   NOTARY_ISSUER_ID       the issuer's id
set -euo pipefail

version="${1:?Usage: build-release.sh <version> [build number]}"
build_number="${2:-1}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "The version must look like 1.2.3." >&2; exit 1; }
[[ "$build_number" =~ ^[0-9]+$ ]] || { echo "The build number must be a number." >&2; exit 1; }

root="$(cd "$(dirname "$0")/.." && pwd)"
output="$root/build/release"
archive="$output/NotesV.xcarchive"
app="$archive/Products/Applications/NotesV.app"
dmg="$output/NotesV-$version.dmg"
staging="$output/dmg"

rm -rf "$output"
mkdir -p "$output"

# Signing is done below, so that both kinds of release are built the same way.
xcodebuild archive \
    -project "$root/NotesV.xcodeproj" \
    -scheme NotesV \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive" \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    CODE_SIGNING_ALLOWED=NO \
    -quiet

identity="${DEVELOPER_ID_IDENTITY:--}"
sign_options=(--force --options runtime --entitlements "$root/Config/NotesV-Release.entitlements" --sign "$identity")
if [[ "$identity" != "-" ]]; then
    sign_options+=(--timestamp)
fi
codesign "${sign_options[@]}" "$app"
codesign --verify --strict "$app"

mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "NotesV $version" -srcfolder "$staging" -format UDZO -ov -quiet "$dmg"
rm -rf "$staging"

if [[ "$identity" != "-" ]]; then
    codesign --force --timestamp --sign "$identity" "$dmg"
    xcrun notarytool submit "$dmg" \
        --key "${NOTARY_KEY_PATH:?Set NOTARY_KEY_PATH to notarize}" \
        --key-id "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID to notarize}" \
        --issuer "${NOTARY_ISSUER_ID:?Set NOTARY_ISSUER_ID to notarize}" \
        --wait
    xcrun stapler staple "$dmg"
fi

(cd "$output" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
echo "$dmg"
