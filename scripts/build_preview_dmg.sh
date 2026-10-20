#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/Docky.xcodeproj"
SCHEME="Docky"
CONFIGURATION="Release"
APP_NAME="Docky"

required_variables=(MARKETING_VERSION BUILD_VERSION PREVIEW_NUMBER PREVIEW_TAG)
for variable in $required_variables; do
    if [[ -z "${(P)variable:-}" ]]; then
        print -u2 "Missing required environment variable: $variable"
        exit 1
    fi
done

if [[ "$PREVIEW_NUMBER" != <1-> ]]; then
    print -u2 "PREVIEW_NUMBER must be a positive integer"
    exit 1
fi
if [[ "$BUILD_VERSION" != <-> ]]; then
    print -u2 "BUILD_VERSION must be numeric"
    exit 1
fi
if [[ "$PREVIEW_TAG" != "preview-v$MARKETING_VERSION.$PREVIEW_NUMBER" ]]; then
    print -u2 "PREVIEW_TAG must equal preview-v$MARKETING_VERSION.$PREVIEW_NUMBER"
    exit 1
fi

BUILD_ROOT="${PREVIEW_BUILD_ROOT:-$PROJECT_ROOT/build/preview}"
if [[ -z "$BUILD_ROOT" || "$BUILD_ROOT" == "/" ]]; then
    print -u2 "Unsafe preview build root: $BUILD_ROOT"
    exit 1
fi

DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
STAGING_PATH="$BUILD_ROOT/staging"
OUTPUT_PATH="$BUILD_ROOT/publication"
MOUNT_PATH="$BUILD_ROOT/mount"
DMG_NAME="$APP_NAME-$MARKETING_VERSION-preview.$PREVIEW_NUMBER-$BUILD_VERSION.dmg"
DMG_PATH="$OUTPUT_PATH/$DMG_NAME"
CHECKSUM_PATH="$OUTPUT_PATH/SHA256SUMS"
INSTALL_PATH="$PROJECT_ROOT/docs/preview-installation.md"

rm -rf "$DERIVED_DATA_PATH" "$STAGING_PATH" "$OUTPUT_PATH" "$MOUNT_PATH"
mkdir -p "$DERIVED_DATA_PATH" "$STAGING_PATH" "$OUTPUT_PATH" "$MOUNT_PATH"

xcodebuild build \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -destination 'generic/platform=macOS' \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$MARKETING_VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_VERSION" \
    DOCKY_UPDATES_ENABLED=NO \
    DOCKY_UPDATE_FEED_URL= \
    DOCKY_SPARKLE_PUBLIC_KEY= \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    DEVELOPMENT_TEAM=

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_PATH="$APP_PATH" \
MARKETING_VERSION="$MARKETING_VERSION" \
BUILD_VERSION="$BUILD_VERSION" \
    "$PROJECT_ROOT/scripts/verify_preview_bundle.sh"

if [[ ! -f "$INSTALL_PATH" ]]; then
    print -u2 "Preview installation guide is missing: $INSTALL_PATH"
    exit 1
fi

ditto "$APP_PATH" "$STAGING_PATH/$APP_NAME.app"
ln -s /Applications "$STAGING_PATH/Applications"
cp "$INSTALL_PATH" "$STAGING_PATH/INSTALL.md"

hdiutil create \
    -volname "$APP_NAME $MARKETING_VERSION Preview $PREVIEW_NUMBER" \
    -srcfolder "$STAGING_PATH" \
    -format UDZO \
    -ov \
    "$DMG_PATH"
hdiutil verify "$DMG_PATH"

mounted=false
cleanup_mount() {
    if [[ "$mounted" == true ]]; then
        hdiutil detach "$MOUNT_PATH" -quiet || true
    fi
}
trap cleanup_mount EXIT

hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_PATH" -quiet
mounted=true
MOUNTED_APP_PATH="$MOUNT_PATH/$APP_NAME.app"
APP_PATH="$MOUNTED_APP_PATH" \
MARKETING_VERSION="$MARKETING_VERSION" \
BUILD_VERSION="$BUILD_VERSION" \
    "$PROJECT_ROOT/scripts/verify_preview_bundle.sh"
[[ -L "$MOUNT_PATH/Applications" ]]
[[ "$(readlink "$MOUNT_PATH/Applications")" == "/Applications" ]]
cmp "$INSTALL_PATH" "$MOUNT_PATH/INSTALL.md"
hdiutil detach "$MOUNT_PATH" -quiet
mounted=false

(
    cd "$OUTPUT_PATH"
    shasum -a 256 "$DMG_NAME" > "$CHECKSUM_PATH"
)
cp "$INSTALL_PATH" "$OUTPUT_PATH/INSTALL.md"

print "Preview app: $APP_PATH"
print "Preview disk image: $DMG_PATH"
print "Preview checksums: $CHECKSUM_PATH"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    print "app_path=$APP_PATH" >> "$GITHUB_OUTPUT"
    print "dmg_path=$DMG_PATH" >> "$GITHUB_OUTPUT"
    print "dmg_name=$DMG_NAME" >> "$GITHUB_OUTPUT"
    print "checksum_path=$CHECKSUM_PATH" >> "$GITHUB_OUTPUT"
    print "publication_path=$OUTPUT_PATH" >> "$GITHUB_OUTPUT"
fi
