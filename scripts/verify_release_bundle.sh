#!/bin/zsh
set -euo pipefail

required_variables=(APP_PATH APPLE_TEAM_ID MARKETING_VERSION BUILD_VERSION SPARKLE_PUBLIC_KEY)
for variable in $required_variables; do
    if [[ -z "${(P)variable:-}" ]]; then
        print -u2 "Missing required environment variable: $variable"
        exit 1
    fi
done

FEED_URL="https://github.com/Mark1708/docky/releases/latest/download/appcast.xml"
WATCHDOG_PATH="$APP_PATH/Contents/Library/LoginItems/DockyDockWatchdog.app"
if [[ ! -d "$APP_PATH" || ! -d "$WATCHDOG_PATH" ]]; then
    print -u2 "Main app or embedded Watchdog is missing"
    exit 1
fi

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}

verify_signature() {
    local bundle="$1"
    codesign --verify --deep --strict --verbose=2 "$bundle"
    local details
    details="$(codesign -dv --verbose=4 "$bundle" 2>&1)"
    if [[ "$details" != *"TeamIdentifier=$APPLE_TEAM_ID"* ]]; then
        print -u2 "Unexpected TeamIdentifier for $bundle"
        exit 1
    fi
    spctl --assess --type execute --verbose=4 "$bundle"
}

verify_signature "$APP_PATH"
verify_signature "$WATCHDOG_PATH"
xcrun stapler validate "$APP_PATH"

[[ "$(plist_value "$APP_PATH" CFBundleIdentifier)" == "gt.quintero.Docky" ]]
[[ "$(plist_value "$WATCHDOG_PATH" CFBundleIdentifier)" == "gt.quintero.Docky.DockWatchdog" ]]
for bundle in "$APP_PATH" "$WATCHDOG_PATH"; do
    [[ "$(plist_value "$bundle" CFBundleShortVersionString)" == "$MARKETING_VERSION" ]]
    [[ "$(plist_value "$bundle" CFBundleVersion)" == "$BUILD_VERSION" ]]
done
[[ "$(plist_value "$APP_PATH" DockyUpdatesEnabled)" == "YES" ]]
[[ "$(plist_value "$APP_PATH" SUFeedURL)" == "$FEED_URL" ]]
[[ "$(plist_value "$APP_PATH" SUPublicEDKey)" == "$SPARKLE_PUBLIC_KEY" ]]

print "Signed release bundle verification passed."
