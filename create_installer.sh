#!/bin/bash
set -euo pipefail

# Configuration
APP_NAME="MAC-LIMPO"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
BUNDLE_ID="com.alexkads.$APP_NAME"

# Version — single source of truth is the VERSION file (SemVer). BUILD_NUMBER is
# the monotonic CFBundleVersion; override via env when cutting a build, e.g.
# BUILD_NUMBER=3 ./create_installer.sh
VERSION="$(tr -d ' \n' < VERSION 2>/dev/null || echo '1.1.0')"
BUILD_NUMBER="${BUILD_NUMBER:-2}"

echo "🚀 Starting installer creation for $APP_NAME v$VERSION ($BUILD_NUMBER)..."

# 1. Build release version
echo "📦 Building release version..."
if ! swift build -c release -Xswiftc -O; then
    echo "❌ Build failed"
    exit 1
fi

if [ ! -f "$BUILD_DIR/$APP_NAME" ]; then
    echo "❌ Built executable not found at $BUILD_DIR/$APP_NAME"
    exit 1
fi

# 2. Create App Bundle Structure
echo "📂 Creating App Bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 3. Copy Executable
echo "📎 Copying executable..."
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 4. Write Info.plist
# Always overwrite with correct values, do not copy an existing (possibly stale) one.
echo "📝 Writing Info.plist..."
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 alexkads. All rights reserved.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>MAC-LIMPO needs permission to execute shell commands for cleaning operations.</string>
</dict>
</plist>
EOF

# Create PkgInfo
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 5. Compile Assets (Icon)
echo "🎨 Compiling assets..."
if [ -d "Assets.xcassets" ]; then
    xcrun actool Assets.xcassets \
        --compile "$APP_BUNDLE/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 13.0 \
        --app-icon AppIcon \
        --output-partial-info-plist /tmp/assetcatalog_generated_info.plist > /dev/null || \
        echo "⚠️ Icon compilation reported issues (continuing without a custom icon)."
else
    echo "⚠️ Assets.xcassets not found. Skipping icon compilation."
fi

# 6. Code Signing (Ad-hoc)
echo "🔐 Signing application (ad-hoc)..."
# Remove quarantine attributes before signing
xattr -cr "$APP_BUNDLE"

if ! codesign --force --deep --sign - "$APP_BUNDLE"; then
    echo "❌ Code signing failed"
    exit 1
fi

# Verify the signature
if ! codesign --verify --deep --strict "$APP_BUNDLE" 2>/dev/null; then
    echo "⚠️ Signature verification reported issues (ad-hoc signatures are expected to be unverified by notarization)."
fi

# 7. Create Customized DMG
echo "💿 Creating customized DMG..."
rm -f "$DMG_NAME"
rm -f "pack.temp.dmg"
rm -rf "dmg_staging"

# Prepare staging directory
echo "📂 Preparing staging area..."
mkdir -p "dmg_staging/.background"

# Copy App
cp -r "$APP_BUNDLE" "dmg_staging/"

# Copy Background
BACKGROUND_FILE="Design/Installer/dmg-background.png"
if [ -f "$BACKGROUND_FILE" ]; then
    echo "🖼️  Adding background image..."
    cp "$BACKGROUND_FILE" "dmg_staging/.background/background.png"
else
    echo "⚠️ Background image not found at $BACKGROUND_FILE (DMG will use the default background)."
fi

# Link Applications
ln -s /Applications "dmg_staging/Applications"

# Create temporary writable DMG from staging
echo "📀 Creating temporary DMG..."
hdiutil create -srcfolder "dmg_staging" -volname "$APP_NAME" \
    -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW -size 200m pack.temp.dmg

# Mount it
echo "🔗 Mounting DMG..."
device=$(hdiutil attach -readwrite -noverify -noautoopen "pack.temp.dmg" | grep -E '^/dev/' | sed 1q | awk '{print $1}')
if [ -z "$device" ]; then
    echo "❌ Failed to mount temporary DMG"
    exit 1
fi
sleep 2

# Run AppleScript to style the window (cosmetic — never fail the build over it)
echo "🎨 Styling DMG window..."
osascript <<EOF || echo "⚠️ DMG window styling failed (cosmetic, continuing)."
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 940, 500}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100

        -- Set background
        try
            set background picture of theViewOptions to file "background.png" of folder ".background"
        end try

        -- Position items
        set position of item "$APP_NAME" of container window to {160, 200}
        set position of item "Applications" of container window to {400, 200}

        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

# Sync and Detach
sync
hdiutil detach "$device" || hdiutil detach "$device" -force

# Convert to compressed DMG
echo "📦 Compressing DMG..."
hdiutil convert "pack.temp.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG_NAME"

# Cleanup
rm -f "pack.temp.dmg"
rm -rf "dmg_staging"

echo "✅ Installer created successfully: $DMG_NAME (v$VERSION build $BUILD_NUMBER)"
