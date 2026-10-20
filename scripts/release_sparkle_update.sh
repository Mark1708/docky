#!/bin/zsh
set -euo pipefail
setopt null_glob

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/Docky.xcodeproj"
SCHEME="Docky"
CONFIGURATION="Release"
APP_NAME="Docky"
FEED_URL="https://github.com/Mark1708/docky/releases/latest/download/appcast.xml"

required_variables=(
    MARKETING_VERSION
    BUILD_VERSION
    RELEASE_TAG
    APPLE_TEAM_ID
    SPARKLE_PUBLIC_KEY
    NOTARYTOOL_PROFILE
    RELEASE_KEYCHAIN
)
for variable in $required_variables; do
    if [[ -z "${(P)variable:-}" ]]; then
        print -u2 "Missing required environment variable: $variable"
        exit 1
    fi
done

if [[ "$RELEASE_TAG" != "v$MARKETING_VERSION" ]]; then
    print -u2 "RELEASE_TAG must equal v$MARKETING_VERSION"
    exit 1
fi
if [[ "$BUILD_VERSION" != <-> ]]; then
    print -u2 "BUILD_VERSION must be numeric"
    exit 1
fi
if [[ ! -f "$RELEASE_KEYCHAIN" ]]; then
    print -u2 "Release keychain not found: $RELEASE_KEYCHAIN"
    exit 1
fi

BUILD_ROOT="$PROJECT_ROOT/build"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
ARCHIVE_PATH="$BUILD_ROOT/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_ROOT/export"
UPDATES_PATH="$BUILD_ROOT/updates"
EXPORT_OPTIONS_PATH="$BUILD_ROOT/ExportOptions-DeveloperID.plist"
NOTARY_ZIP_PATH="$BUILD_ROOT/$APP_NAME-notarization.zip"
ZIP_NAME="$APP_NAME-$MARKETING_VERSION-$BUILD_VERSION.zip"
ZIP_PATH="$UPDATES_PATH/$ZIP_NAME"

identity_lines=("${(@f)$(security find-identity -v -p codesigning "$RELEASE_KEYCHAIN")}")
matching_identities=()
for line in $identity_lines; do
    if [[ "$line" == *"Developer ID Application:"*"($APPLE_TEAM_ID)"* ]]; then
        matching_identities+=("$line")
    fi
done
if (( ${#matching_identities[@]} != 1 )); then
    print -u2 "Expected exactly one Developer ID Application identity for team $APPLE_TEAM_ID in $RELEASE_KEYCHAIN; found ${#matching_identities[@]}"
    exit 1
fi

mkdir -p "$BUILD_ROOT" "$DERIVED_DATA_PATH" "$UPDATES_PATH"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
rm -f "$EXPORT_OPTIONS_PATH" "$NOTARY_ZIP_PATH" "$ZIP_PATH"

cat > "$EXPORT_OPTIONS_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>teamID</key>
    <string>$APPLE_TEAM_ID</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF

common_build_settings=(
    "MARKETING_VERSION=$MARKETING_VERSION"
    "CURRENT_PROJECT_VERSION=$BUILD_VERSION"
    "DOCKY_UPDATES_ENABLED=YES"
    "DOCKY_UPDATE_FEED_URL=$FEED_URL"
    "DOCKY_SPARKLE_PUBLIC_KEY=$SPARKLE_PUBLIC_KEY"
    "DEVELOPMENT_TEAM=$APPLE_TEAM_ID"
    "CODE_SIGN_STYLE=Manual"
    "CODE_SIGN_IDENTITY=Developer ID Application"
    "OTHER_CODE_SIGN_FLAGS=--keychain $RELEASE_KEYCHAIN"
)

xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -archivePath "$ARCHIVE_PATH" \
    "${common_build_settings[@]}"

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PATH" \
    "OTHER_CODE_SIGN_FLAGS=--keychain $RELEASE_KEYCHAIN"

exported_apps=("$EXPORT_PATH"/*.app(N))
if (( ${#exported_apps[@]} != 1 )); then
    print -u2 "Expected exactly one exported app in $EXPORT_PATH; found ${#exported_apps[@]}"
    exit 1
fi
APP_PATH="$exported_apps[1]"
if [[ "${APP_PATH:t}" != "$APP_NAME.app" ]]; then
    print -u2 "Unexpected exported app: $APP_PATH"
    exit 1
fi

# Notarization consumes a temporary archive. The final update archive is created
# only after the exported app is accepted and stapled.
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$NOTARY_ZIP_PATH"
notary_result="$(xcrun notarytool submit "$NOTARY_ZIP_PATH" \
    --keychain "$RELEASE_KEYCHAIN" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait \
    --output-format json)"
NOTARY_RESULT="$notary_result" python3 - <<'PY'
import json
import os
import sys

result = json.loads(os.environ["NOTARY_RESULT"])
if result.get("status") != "Accepted":
    print(f"Notarization did not succeed: {result.get('status', 'unknown')}", file=sys.stderr)
    raise SystemExit(1)
PY
rm -f "$NOTARY_ZIP_PATH"

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

print "Release app: $APP_PATH"
print "Release archive: $ZIP_PATH"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    print "app_path=$APP_PATH" >> "$GITHUB_OUTPUT"
    print "release_zip=$ZIP_PATH" >> "$GITHUB_OUTPUT"
    print "zip_name=$ZIP_NAME" >> "$GITHUB_OUTPUT"
fi
