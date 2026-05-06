#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="${APP_NAME:-MacOSUtilities}"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/MacOSUtilities.xcodeproj}"
SCHEME="${SCHEME:-MacOSUtilities}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_DIR/DerivedData}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_DIR/$APP_NAME.xcarchive}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT_DIR/artifacts}"
DMG_ROOT="$BUILD_DIR/dmg-root"

CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
BUNDLE_ID_PREFIX="${BUNDLE_ID_PREFIX:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-$DEVELOPMENT_TEAM}"
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"
NOTARIZE="${NOTARIZE:-auto}"

log() {
  printf '\n==> %s\n' "$1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command xcodebuild
require_command hdiutil
require_command codesign
require_command xcrun
require_command spctl

rm -rf "$BUILD_DIR" "$ARTIFACTS_DIR"
mkdir -p "$BUILD_DIR" "$ARTIFACTS_DIR"

SIGNING_ARGS=()
if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
  SIGNING_ARGS+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY"
    OTHER_CODE_SIGN_FLAGS="--timestamp"
  )

  if [[ -n "$DEVELOPMENT_TEAM" ]]; then
    SIGNING_ARGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
  fi
fi

if [[ -n "$BUNDLE_ID_PREFIX" ]]; then
  SIGNING_ARGS+=(BUNDLE_ID_PREFIX="$BUNDLE_ID_PREFIX")
fi

log "Archiving $APP_NAME"
xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  "${SIGNING_ARGS[@]}"

APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected archived app was not found at $APP_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0.0")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0")"
ARTIFACT_BASENAME="$APP_NAME-$VERSION"

log "Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dvvv --entitlements :- "$APP_PATH" >/dev/null

log "Creating DMG"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
ditto "$APP_PATH" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"

DMG_PATH="$ARTIFACTS_DIR/$ARTIFACT_BASENAME.dmg"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
  log "Signing DMG"
  codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

should_notarize=false
case "$NOTARIZE" in
  true|TRUE|1|yes|YES)
    should_notarize=true
    ;;
  false|FALSE|0|no|NO)
    should_notarize=false
    ;;
  auto)
    if [[ -n "$APPLE_ID" && -n "$APPLE_APP_SPECIFIC_PASSWORD" && -n "$APPLE_TEAM_ID" ]]; then
      should_notarize=true
    fi
    ;;
  *)
    echo "Unknown NOTARIZE value: $NOTARIZE" >&2
    exit 1
    ;;
esac

if [[ "$should_notarize" == true ]]; then
  if [[ -z "$APPLE_ID" || -z "$APPLE_APP_SPECIFIC_PASSWORD" || -z "$APPLE_TEAM_ID" ]]; then
    echo "Notarization requires APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, and APPLE_TEAM_ID or DEVELOPMENT_TEAM." >&2
    exit 1
  fi

  log "Submitting DMG for notarization"
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait

  log "Stapling notarization ticket"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"

  log "Assessing notarized DMG with Gatekeeper"
  spctl -a -vv -t open "$DMG_PATH"
fi

log "Writing checksums"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

if [[ -d "$ARCHIVE_PATH/dSYMs" ]]; then
  ditto -c -k --keepParent "$ARCHIVE_PATH/dSYMs" "$ARTIFACTS_DIR/$ARTIFACT_BASENAME-dSYMs.zip"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "app_name=$APP_NAME"
    echo "version=$VERSION"
    echo "build_number=$BUILD_NUMBER"
    echo "dmg_path=$DMG_PATH"
    echo "artifacts_dir=$ARTIFACTS_DIR"
  } >> "$GITHUB_OUTPUT"
fi

log "Release artifacts"
find "$ARTIFACTS_DIR" -maxdepth 1 -type f -print | sort
