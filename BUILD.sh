#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
PRODUCT="AuthMyMac"
CONFIGURATION="${1:-debug}"
OPEN_AFTER_BUILD="${OPEN_AFTER_BUILD:-1}"
MARKETING_VERSION="${MARKETING_VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
    print -u2 "Usage: ./BUILD.sh [debug|release]"
    exit 64
fi

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

APP_PATH="$ROOT_DIR/dist/$PRODUCT.app"
CONTENTS_PATH="$APP_PATH/Contents"
EXECUTABLE_PATH="$ROOT_DIR/.build/$CONFIGURATION/$PRODUCT"
ICON_SOURCE_PATH="$ROOT_DIR/Configuration/AppIcon.png"
ICONSET_PATH="$ROOT_DIR/dist/AppIcon.appiconset"
ASSET_CATALOG_PATH="$ROOT_DIR/dist/AppIcon.xcassets"

mkdir -p "$CONTENTS_PATH/MacOS" "$CONTENTS_PATH/Resources"
cp "$EXECUTABLE_PATH" "$CONTENTS_PATH/MacOS/$PRODUCT"
cp "$ROOT_DIR/Configuration/Info.plist" "$CONTENTS_PATH/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $PRODUCT" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $PRODUCT" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier dev.geeky.AuthMyMac" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $PRODUCT" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$CONTENTS_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_PATH/Info.plist"

if [[ -f "$ICON_SOURCE_PATH" ]]; then
    rm -rf "$ICONSET_PATH" "$ASSET_CATALOG_PATH"
    mkdir -p "$ICONSET_PATH"
    cp "$ROOT_DIR/Configuration/AppIcon.appiconset/Contents.json" "$ICONSET_PATH/Contents.json"

    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$ICON_SOURCE_PATH" --out "$ICONSET_PATH/icon_${size}x${size}.png" >/dev/null
        sips -z "$((size * 2))" "$((size * 2))" "$ICON_SOURCE_PATH" --out "$ICONSET_PATH/icon_${size}x${size}@2x.png" >/dev/null
    done

    mkdir -p "$ASSET_CATALOG_PATH"
    mv "$ICONSET_PATH" "$ASSET_CATALOG_PATH/AppIcon.appiconset"
    xcrun actool --compile "$CONTENTS_PATH/Resources" --platform macosx --minimum-deployment-target 26.0 --app-icon AppIcon --output-partial-info-plist "$ASSET_CATALOG_PATH/Info.plist" "$ASSET_CATALOG_PATH"
    /usr/libexec/PlistBuddy -c "Merge $ASSET_CATALOG_PATH/Info.plist" "$CONTENTS_PATH/Info.plist"
fi

# Ad-hoc signing makes this development bundle eligible for macOS privacy prompts.
codesign --force --sign - --entitlements "$ROOT_DIR/Configuration/AuthMyMac.entitlements" "$APP_PATH"

print "Built $APP_PATH"
if [[ "$OPEN_AFTER_BUILD" == "1" ]]; then
    open "$APP_PATH"
fi
