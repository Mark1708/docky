#!/bin/zsh
set -euo pipefail
setopt null_glob

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
required_variables=(
    RELEASE_TAG
    MARKETING_VERSION
    BUILD_VERSION
    RELEASE_ZIP
    SPARKLE_BIN_DIR
    SPARKLE_PRIVATE_KEY
)
for variable in $required_variables; do
    if [[ -z "${(P)variable:-}" ]]; then
        print -u2 "Missing required environment variable: $variable"
        exit 1
    fi
done

PUBLIC_KEY_FILE="${SPARKLE_PUBLIC_KEY_FILE:-$PROJECT_ROOT/Config/SparklePublicKey.txt}"
GENERATE_KEYS="$SPARKLE_BIN_DIR/generate_keys"
GENERATE_APPCAST="$SPARKLE_BIN_DIR/generate_appcast"
SIGN_UPDATE="$SPARKLE_BIN_DIR/sign_update"
for tool in "$GENERATE_KEYS" "$GENERATE_APPCAST" "$SIGN_UPDATE"; do
    if [[ ! -x "$tool" ]]; then
        print -u2 "Required Sparkle tool is unavailable: $tool"
        exit 1
    fi
done
if [[ ! -f "$PUBLIC_KEY_FILE" || ! -f "$RELEASE_ZIP" ]]; then
    print -u2 "Public key or release archive is missing"
    exit 1
fi

WORK_ROOT="${RUNNER_TEMP:-$PROJECT_ROOT/build}/docky-appcast-$$"
KEYCHAIN_PATH="$WORK_ROOT/Sparkle.keychain-db"
PRIVATE_KEY_FILE="$WORK_ROOT/private-key"
APPCAST_DIR="$WORK_ROOT/appcast"
OUTPUT_DIR="${APPCAST_OUTPUT_DIR:-$PROJECT_ROOT/build/updates}"
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
previous_default="$(security default-keychain -d user | tr -d '"')"
previous_default="${previous_default#"${previous_default%%[![:space:]]*}"}"
previous_default="${previous_default%"${previous_default##*[![:space:]]}"}"
search_lines=("${(@f)$(security list-keychains -d user)}")
previous_search=()
for line in $search_lines; do
    line="${line//\"/}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$line" ]] && previous_search+=("$line")
done
cleanup() {
    local exit_status=$?
    rm -f "$PRIVATE_KEY_FILE"
    if (( ${#previous_search[@]} > 0 )); then
        security list-keychains -d user -s "${previous_search[@]}" >/dev/null 2>&1 || true
    fi
    if [[ -n "$previous_default" ]]; then
        security default-keychain -d user -s "$previous_default" >/dev/null 2>&1 || true
    fi
    security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
    rm -rf "$WORK_ROOT"
    return $exit_status
}
trap cleanup EXIT

mkdir -p "$APPCAST_DIR" "$OUTPUT_DIR"
chmod 700 "$WORK_ROOT"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security default-keychain -d user -s "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH" "${previous_search[@]}"

umask 077
print -rn -- "$SPARKLE_PRIVATE_KEY" > "$PRIVATE_KEY_FILE"
"$GENERATE_KEYS" --account Mark1708.docky -f "$PRIVATE_KEY_FILE" >/dev/null
rm -f "$PRIVATE_KEY_FILE"

expected_public_key="$(tr -d '[:space:]' < "$PUBLIC_KEY_FILE")"
actual_public_key="$("$GENERATE_KEYS" --account Mark1708.docky -p | tr -d '[:space:]')"
if [[ -z "$expected_public_key" || "$actual_public_key" != "$expected_public_key" ]]; then
    print -u2 "Imported Sparkle private key does not match Config/SparklePublicKey.txt"
    exit 1
fi

archive_name="${RELEASE_ZIP:t}"
cp "$RELEASE_ZIP" "$APPCAST_DIR/$archive_name"
print -rn -- "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" \
    --ed-key-file - \
    --download-url-prefix "https://github.com/Mark1708/docky/releases/download/$RELEASE_TAG/" \
    "$APPCAST_DIR"

APPCAST_PATH="$APPCAST_DIR/appcast.xml"
if [[ ! -f "$APPCAST_PATH" ]]; then
    print -u2 "Sparkle did not generate appcast.xml"
    exit 1
fi
signature="$(python3 "$PROJECT_ROOT/scripts/verify_release_artifacts.py" \
    --release-tag "$RELEASE_TAG" \
    --marketing-version "$MARKETING_VERSION" \
    --build-version "$BUILD_VERSION" \
    --archive "$RELEASE_ZIP" \
    --appcast "$APPCAST_PATH" \
    --print-signature)"
"$SIGN_UPDATE" --account Mark1708.docky --verify "$RELEASE_ZIP" "$signature"

cp "$APPCAST_PATH" "$OUTPUT_DIR/appcast.xml"
print "Appcast: $OUTPUT_DIR/appcast.xml"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    print "appcast=$OUTPUT_DIR/appcast.xml" >> "$GITHUB_OUTPUT"
fi
