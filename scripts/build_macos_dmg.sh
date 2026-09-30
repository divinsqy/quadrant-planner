#!/usr/bin/env bash
set -euo pipefail

mkdir -p dist/macos
APP_PATH="$(find build/macos/Build/Products/Release -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "No .app found" >&2
  exit 1
fi

KEYCHAIN_PATH="$RUNNER_TEMP/quadrant-signing.keychain-db"
SIGNED=0

if [[ -n "${APPLE_DEVELOPER_ID_P12_BASE64:-}" && -n "${APPLE_DEVELOPER_ID_P12_PASSWORD:-}" ]]; then
  CERT_PATH="$RUNNER_TEMP/developer-id.p12"
  echo "$APPLE_DEVELOPER_ID_P12_BASE64" | base64 --decode > "$CERT_PATH"
  security create-keychain -p ci "$KEYCHAIN_PATH"
  security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
  security unlock-keychain -p ci "$KEYCHAIN_PATH"
  security import "$CERT_PATH" -P "$APPLE_DEVELOPER_ID_P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
  security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db
  security set-key-partition-list -S apple-tool:,apple: -s -k ci "$KEYCHAIN_PATH"
  IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)"
  test -n "$IDENTITY"
  codesign --deep --force --options runtime --timestamp --sign "$IDENTITY" "$APP_PATH"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  SIGNED=1
else
  codesign --deep --force --sign - "$APP_PATH" || true
fi

STAGE="$RUNNER_TEMP/quadrant-dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="dist/macos/QuadrantPlanner-0.8.0-macos.dmg"
rm -f "$DMG"
hdiutil create -volname "象限计划" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

if [[ "$SIGNED" == "1" && -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  xcrun notarytool submit "$DMG"     --apple-id "$APPLE_ID"     --password "$APPLE_APP_PASSWORD"     --team-id "$APPLE_TEAM_ID"     --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

hdiutil verify "$DMG"
