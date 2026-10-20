#!/bin/zsh
set -euo pipefail

required_variables=(APP_PATH MARKETING_VERSION BUILD_VERSION)
for variable in $required_variables; do
    if [[ -z "${(P)variable:-}" ]]; then
        print -u2 "Missing required environment variable: $variable"
        exit 1
    fi
done

WATCHDOG_PATH="$APP_PATH/Contents/Library/LoginItems/DockyDockWatchdog.app"
if [[ ! -d "$APP_PATH" || ! -d "$WATCHDOG_PATH" ]]; then
    print -u2 "Main app or embedded Watchdog is missing"
    exit 1
fi

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}

assert_equal() {
    local actual="$1"
    local expected="$2"
    local description="$3"
    if [[ "$actual" != "$expected" ]]; then
        print -u2 "$description: expected '$expected', got '$actual'"
        exit 1
    fi
}

verify_ad_hoc_signature() {
    local bundle="$1"
    codesign --verify --deep --strict --verbose=2 "$bundle"

    local details
    details="$(codesign -dv --verbose=4 "$bundle" 2>&1)"
    if [[ "$details" != *"Signature=adhoc"* ]]; then
        print -u2 "Expected an ad-hoc signature for $bundle"
        exit 1
    fi

    local entitlements
    entitlements="$(codesign -d --entitlements :- "$bundle" 2>/dev/null)"
    if [[ "$entitlements" == *"<key>com.apple.security.get-task-allow</key>"* ]]; then
        print -u2 "Preview bundle must not allow debugger attachment: $bundle"
        exit 1
    fi
    if spctl --assess --type execute --verbose=4 "$bundle"; then
        print -u2 "Preview bundle unexpectedly passed Gatekeeper assessment: $bundle"
        exit 1
    fi
}

verify_ad_hoc_signature "$APP_PATH"
verify_ad_hoc_signature "$WATCHDOG_PATH"

assert_equal "$(plist_value "$APP_PATH" CFBundleIdentifier)" "gt.quintero.Docky" "Main bundle identifier"
assert_equal "$(plist_value "$WATCHDOG_PATH" CFBundleIdentifier)" "gt.quintero.Docky.DockWatchdog" "Watchdog bundle identifier"
for bundle in "$APP_PATH" "$WATCHDOG_PATH"; do
    assert_equal "$(plist_value "$bundle" CFBundleShortVersionString)" "$MARKETING_VERSION" "Marketing version for $bundle"
    assert_equal "$(plist_value "$bundle" CFBundleVersion)" "$BUILD_VERSION" "Build version for $bundle"
done

assert_equal "$(plist_value "$APP_PATH" DockyUpdatesEnabled)" "NO" "Preview update gate"
assert_equal "$(plist_value "$APP_PATH" SUFeedURL)" "" "Preview update feed"
assert_equal "$(plist_value "$APP_PATH" SUPublicEDKey)" "" "Preview Sparkle public key"

if [[ -e "$APP_PATH/Contents/embedded.provisionprofile" ]]; then
    print -u2 "Preview bundle must not contain a provisioning profile"
    exit 1
fi

for architecture in arm64 x86_64; do
    lipo "$APP_PATH/Contents/MacOS/Docky" -verify_arch "$architecture"
    lipo "$WATCHDOG_PATH/Contents/MacOS/DockyDockWatchdog" -verify_arch "$architecture"
done

print "Unsigned preview bundle verification passed."
