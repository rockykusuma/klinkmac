#!/usr/bin/env bash
# Release script: build Release, sign, create DMG, notarize, staple.
# Requirements:
#   - Apple Developer Program membership
#   - "Developer ID Application" certificate in Keychain
#   - Xcode command line tools
#   - create-dmg: brew install create-dmg
#   - App-specific password at NOTARYTOOL_PASSWORD (or use --keychain-profile)
#
# Usage:
#   TEAM_ID=YOUR_TEAM_ID APP_BUNDLE_ID=com.klinkmac.KlinkMac ./release.sh

set -euo pipefail

TEAM_ID="${TEAM_ID:-}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.klinkmac.KlinkMac}"
SCHEME="KlinkMac"
PROJECT="KlinkMac/KlinkMac.xcodeproj"
BUILD_DIR="$(pwd)/build"
APP_NAME="KlinkMac"
DMG_NAME="${APP_NAME}.dmg"
APPLE_ID="${APPLE_ID:-}"                   # Your Apple ID email
NOTARYTOOL_PASSWORD="${NOTARYTOOL_PASSWORD:-}" # App-specific password (NOT your Apple ID password)

# ---- Validate ---------------------------------------------------------------

if [[ -z "$TEAM_ID" ]]; then
  echo "Error: set TEAM_ID to your Apple Developer team ID." >&2
  exit 1
fi
if [[ -z "$APPLE_ID" || -z "$NOTARYTOOL_PASSWORD" ]]; then
  echo "Error: set APPLE_ID and NOTARYTOOL_PASSWORD for notarization." >&2
  exit 1
fi

# ---- Build ------------------------------------------------------------------

echo "==> Building $SCHEME (Release)"
rm -rf "$BUILD_DIR"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  ARCHS="arm64 x86_64" \
  BUILD_DIR="$BUILD_DIR" \
  clean build

APP_PATH="$BUILD_DIR/Release/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: app not found at $APP_PATH after build." >&2
  exit 1
fi

# ---- Sign -------------------------------------------------------------------

echo "==> Signing $APP_NAME.app"
codesign \
  --sign "Developer ID Application" \
  --options runtime \
  --entitlements "KlinkMac/KlinkMac.entitlements" \
  --timestamp \
  --deep \
  --force \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "  Signature verified."

# ---- Create DMG -------------------------------------------------------------

echo "==> Creating $DMG_NAME"
TMP_DMG="$BUILD_DIR/${APP_NAME}-unsigned.dmg"

# Stage only the .app into an isolated dir so create-dmg doesn't pick up
# build intermediates (SPM .o files, .swiftmodule, .dSYM) that live alongside
# the .app in Release/ and fail notarization as "unsigned binaries".
STAGING_DIR="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"

if command -v create-dmg &>/dev/null; then
  create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 200 190 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 400 185 \
    "$TMP_DMG" \
    "$STAGING_DIR"
else
  # Fallback: plain hdiutil DMG (no pretty background)
  hdiutil create -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR/$APP_NAME.app" \
    -ov -format UDZO \
    "$TMP_DMG"
fi

# Sign the DMG too.
codesign --sign "Developer ID Application" --timestamp "$TMP_DMG"

FINAL_DMG="$BUILD_DIR/$DMG_NAME"
cp "$TMP_DMG" "$FINAL_DMG"

# ---- Notarize ---------------------------------------------------------------

echo "==> Submitting $DMG_NAME for notarization"
xcrun notarytool submit "$FINAL_DMG" \
  --apple-id "$APPLE_ID" \
  --password "$NOTARYTOOL_PASSWORD" \
  --team-id "$TEAM_ID" \
  --wait

# ---- Staple -----------------------------------------------------------------

echo "==> Stapling notarization ticket"
xcrun stapler staple "$FINAL_DMG"
xcrun stapler validate "$FINAL_DMG"

echo ""
echo "Done!  $FINAL_DMG is signed and notarized."
echo "Upload this file to your website for distribution."
