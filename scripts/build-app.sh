#!/bin/bash
#
# ScreenBridge .app bundle 박는 script — v0.3 Notarized DMG path.
#
# 사용:
#   ./scripts/build-app.sh             — release build + .app 박음 (사인 안 함)
#   CODE_SIGN_ID="Developer ID Application: Your Name" ./scripts/build-app.sh
#                                       — sign + entitlements
#   CODE_SIGN_ID=... NOTARIZE=1 ./scripts/build-app.sh
#                                       — sign + notarytool submit + staple
#
# 결과: ./dist/ScreenBridge.app
#

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
DIST="$ROOT/dist"
APP="$DIST/ScreenBridge.app"

echo "[build-app] cleaning $DIST"
rm -rf "$DIST"
mkdir -p "$DIST"

echo "[build-app] swift build -c release"
swift build -c release --arch arm64

BINARY=".build/arm64-apple-macosx/release/ScreenBridge"
if [[ ! -x "$BINARY" ]]; then
    echo "[build-app] binary 박지 X: $BINARY" >&2
    exit 1
fi

echo "[build-app] .app structure 박음"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/ScreenBridge"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Future: cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Embed mlx-swift Metal libraries (MLXFastKernels.metallib 등).
if [[ -d ".build/arm64-apple-macosx/release/" ]]; then
    find .build/arm64-apple-macosx/release/ -name "*.metallib" -exec cp {} "$APP/Contents/Resources/" \;
fi

# Code sign (optional)
if [[ -n "${CODE_SIGN_ID:-}" ]]; then
    echo "[build-app] codesign with $CODE_SIGN_ID"
    codesign --force --deep --options runtime \
        --entitlements Resources/ScreenBridge.entitlements \
        --sign "$CODE_SIGN_ID" \
        "$APP"
    codesign --verify --strict --verbose=2 "$APP"
else
    echo "[build-app] CODE_SIGN_ID 박지 X — ad-hoc sign"
    codesign --force --deep --sign - "$APP"
fi

# Notarize (optional)
if [[ "${NOTARIZE:-0}" == "1" ]]; then
    echo "[build-app] notarytool submit"
    ZIP="$DIST/ScreenBridge.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" \
        --keychain-profile "${NOTARY_PROFILE:-ScreenBridge}" \
        --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
fi

echo "[build-app] ok — $APP"
ls -la "$APP/Contents/MacOS/" "$APP/Contents/Resources/" 2>&1 | head -20
