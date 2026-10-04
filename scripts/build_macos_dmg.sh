#!/usr/bin/env bash
set -euo pipefail

APP_PATH="$(find build/macos/Build/Products/Release -maxdepth 1 -name '*.app' -print -quit)"
[[ -d "$APP_PATH" ]] || { echo 'No release .app found' >&2; exit 1; }
read -r APP_VERSION APP_BUILD EXECUTABLE < <(python3 - "$APP_PATH/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'rb') as f: info=plistlib.load(f)
print(info['CFBundleShortVersionString'],info['CFBundleVersion'],info['CFBundleExecutable'])
PY
)
[[ "$APP_VERSION" == '1.0.0' && "$APP_BUILD" == '9' ]] || { echo 'Unexpected app version/build' >&2; exit 1; }
BINARY="$APP_PATH/Contents/MacOS/$EXECUTABLE"
[[ -f "$BINARY" ]] || { echo 'App executable missing' >&2; exit 1; }
ARCHES="$(lipo -archs "$BINARY")"
case "$ARCHES" in
  arm64) ARCHITECTURE=arm64 ;;
  x86_64) ARCHITECTURE=x86_64 ;;
  'arm64 x86_64'|'x86_64 arm64') ARCHITECTURE=universal ;;
  *) echo "Unsupported app architecture: $ARCHES" >&2; exit 1 ;;
esac
# Every packaged Mach-O dependency must support the advertised architectures.
while IFS= read -r -d '' dependency; do
  if file -b "$dependency" | grep -q 'Mach-O'; then
    DEPENDENCY_ARCHES="$(lipo -archs "$dependency")"
    for architecture in $ARCHES; do
      case " $DEPENDENCY_ARCHES " in *" $architecture "*) ;; *) echo "Missing $architecture in packaged dependency: $dependency" >&2; exit 1 ;; esac
    done
  fi
done < <(find "$APP_PATH" -type f -print0)
mkdir -p dist/macos
TEMP_ROOT="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/quadrant-package.XXXXXX")"
KEYCHAIN_PATH="$TEMP_ROOT/signing.keychain-db"
cleanup() { if [[ -f "$KEYCHAIN_PATH" ]]; then security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true; fi; rm -rf "$TEMP_ROOT"; }
trap cleanup EXIT
SIGNING=ad-hoc
NOTARIZED=false
ENTITLEMENTS=macos/Runner/Release.entitlements
SIGN_ARGS=(--deep --force)
if [[ -f "$ENTITLEMENTS" ]]; then SIGN_ARGS+=(--entitlements "$ENTITLEMENTS"); fi
if [[ -n "${APPLE_DEVELOPER_ID_P12_BASE64:-}" && -n "${APPLE_DEVELOPER_ID_P12_PASSWORD:-}" ]]; then
  CERT_PATH="$TEMP_ROOT/developer-id.p12"
  printf '%s' "$APPLE_DEVELOPER_ID_P12_BASE64" | base64 --decode > "$CERT_PATH"
  KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  security import "$CERT_PATH" -P "$APPLE_DEVELOPER_ID_P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
  security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db
  security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
  IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)"
  [[ -n "$IDENTITY" ]] || { echo 'Developer ID identity missing' >&2; exit 1; }
  codesign --options runtime --timestamp "${SIGN_ARGS[@]}" --sign "$IDENTITY" "$APP_PATH"
  SIGNING=developer-id
else
  codesign "${SIGN_ARGS[@]}" --sign - "$APP_PATH"
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
STAGE="$TEMP_ROOT/stage"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="dist/macos/QuadrantPlanner-${APP_VERSION}-macos-${ARCHITECTURE}-not-notarized.dmg"
hdiutil create -volname '象限计划' -srcfolder "$STAGE" -ov -format UDZO "$DMG"
if [[ "$SIGNING" == developer-id && -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  xcrun notarytool submit "$DMG" --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  FINAL_DMG="dist/macos/QuadrantPlanner-${APP_VERSION}-macos-${ARCHITECTURE}-notarized.dmg"
  mv "$DMG" "$FINAL_DMG"
  DMG="$FINAL_DMG"
  NOTARIZED=true
fi
hdiutil verify "$DMG"
python3 - "$DMG" "$ARCHITECTURE" "$ARCHES" "$SIGNING" "$NOTARIZED" <<'PY'
import hashlib,json,pathlib,sys
file=pathlib.Path(sys.argv[1])
metadata={'filename':file.name,'version':'1.0.0+9','architecture':sys.argv[2],'binary_architectures':sys.argv[3].split(),'signing':sys.argv[4],'notarized':sys.argv[5]=='true','sha256':hashlib.sha256(file.read_bytes()).hexdigest()}
(file.parent/'metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
print(json.dumps(metadata))
PY
