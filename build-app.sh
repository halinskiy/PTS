#!/bin/bash
set -euo pipefail

APP_NAME="PTS"
DISPLAY_NAME="Pet in The System"
BUNDLE_ID="com.pts.app"
VERSION="2.5.2"
BUILD_DIR=".build/release"
APP_DIR="$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "Building $DISPLAY_NAME release..."
swift build -c release 2>&1

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"

# Copy Sparkle framework and set rpath
mkdir -p "$CONTENTS/Frameworks"
if [ -d "$BUILD_DIR/Sparkle.framework" ]; then
    cp -R "$BUILD_DIR/Sparkle.framework" "$CONTENTS/Frameworks/Sparkle.framework"
    # Add rpath so binary finds the framework
    install_name_tool -add_rpath @executable_path/../Frameworks "$CONTENTS/MacOS/$APP_NAME" 2>/dev/null || true
fi

# Copy resource bundle
RESOURCE_BUNDLE="${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$BUILD_DIR/$RESOURCE_BUNDLE" ]; then
    cp -R "$BUILD_DIR/$RESOURCE_BUNDLE" "$CONTENTS/Resources/$RESOURCE_BUNDLE"
fi

# Create Info.plist
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/halinskiy/PTS/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>2Ne7z6Ps8wOBB0xFredP5la4nQbr61Gpn0vh8f3YOyo=</string>
</dict>
</plist>
PLIST

# Generate .icns from PNG if available
ICON_SRC="Assets/AppIcon/appicon.png"
if [ -f "$ICON_SRC" ]; then
    echo "Creating app icon..."
    ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET_DIR"

    sips -z 16 16     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null 2>&1
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null 2>&1
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null 2>&1
    sips -z 64 64     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null 2>&1
    sips -z 128 128   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null 2>&1
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null 2>&1
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null 2>&1
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null 2>&1
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null 2>&1
    sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null 2>&1

    iconutil -c icns "$ICONSET_DIR" -o "$CONTENTS/Resources/AppIcon.icns" 2>/dev/null || {
        echo "Warning: iconutil failed, copying PNG as fallback"
        cp "$ICON_SRC" "$CONTENTS/Resources/AppIcon.png"
    }
    rm -rf "$(dirname "$ICONSET_DIR")"
else
    echo "Warning: No icon source at $ICON_SRC"
fi

echo ""
echo "Installing to /Applications/..."
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.4
rm -rf "/Applications/$APP_DIR"
cp -R "$APP_DIR" "/Applications/$APP_DIR"

# Strip quarantine before signing
xattr -cr "/Applications/$APP_DIR" 2>/dev/null || true

# ─── Local code signing ───────────────────────────────────────────────────────
# Signs with a stable local cert so macOS TCC tracks by bundle ID + cert,
# not by binary hash — Accessibility permission survives rebuilds.
# Uses first available valid code-signing identity in the keychain.
set +e
SIGN_ID=$(security find-identity -p codesigning -v 2>/dev/null | grep -o '"[^"]*"' | head -1 | tr -d '"')
if [ -n "$SIGN_ID" ]; then
    if codesign --force --deep --sign "$SIGN_ID" "/Applications/$APP_DIR" 2>/dev/null; then
        echo "Signed with \"$SIGN_ID\"."
    else
        echo "Warning: signing failed — accessibility may need re-granting after each build."
    fi
else
    echo "Warning: no code-signing cert found."
    echo "  → To fix: open Keychain Access → Certificate Assistant → Create a Certificate"
    echo "    (name: anything, type: Code Signing). Then rebuild."
fi
set -e
# ─────────────────────────────────────────────────────────────────────────────

echo "Launching from /Applications/..."
open "/Applications/$APP_DIR"
echo "Done."
