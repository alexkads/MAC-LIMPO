#!/bin/bash

# Configuration
APP_NAME="MAC-LIMPO"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"

echo "🚀 Starting installer creation for $APP_NAME..."

# 1. Build release version
echo "📦 Building release version..."
swift build -c release -Xswiftc -O

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

# 2. Create App Bundle Structure
echo "📂 Creating App Bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 3. Copy Executable
echo "COPYING executable..."
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 4. Copy Info.plist
echo "CREATING Info.plist..."
# Always overwrite with correct values, do not copy existing broken one
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.alexkads.$APP_NAME</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
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
    xcrun actool Assets.xcassets --compile "$APP_BUNDLE/Contents/Resources" --platform macosx --minimum-deployment-target 13.0 --app-icon AppIcon --output-partial-info-plist /tmp/assetcatalog_generated_info.plist
else
    echo "⚠️ Assets.xcassets not found. Skipping icon compilation."
fi

# 6. Code Signing (Ad-hoc)
echo "🔐 Signing application..."
# Remove quarantine attributes
xattr -cr "$APP_BUNDLE"

codesign --force --deep --sign - "$APP_BUNDLE"

# 8. Create Customized DMG
echo "💿 Creating Customized DMG..."
rm -f "$DMG_NAME"
rm -f "pack.temp.dmg"
rm -rf "dmg_staging"

# Prepare staging directory
echo "📂 Preparing staging area..."
mkdir -p "dmg_staging"
mkdir -p "dmg_staging/.background"

# Copy App
cp -r "$APP_BUNDLE" "dmg_staging/"

# Copy Background
BACKGROUND_FILE="Design/Installer/dmg-background.png"
if [ -f "$BACKGROUND_FILE" ]; then
    echo "🖼️  Adding background image..."
    cp "$BACKGROUND_FILE" "dmg_staging/.background/background.png"
else
    echo "⚠️ Background image not found at $BACKGROUND_FILE"
fi

# Link Applications
ln -s /Applications "dmg_staging/Applications"

# Create temporary writable DMG from staging
echo "📀 Creating temporary DMG..."
hdiutil create -srcfolder "dmg_staging" -volname "$APP_NAME" -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW -size 200m pack.temp.dmg

# Mount it
echo "Mounting DMG..."
device=$(hdiutil attach -readwrite -noverify -noautoopen "pack.temp.dmg" | grep -E '^/dev/' | sed 1q | awk '{print $1}')
sleep 2

# Run AppleScript to style the window
echo "🎨 Styling DMG window..."
osascript <<EOF
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
        on error
            display dialog "Could not set background" buttons {"OK"} default button 1
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
hdiutil detach "$device"

# Convert to compressed DMG
echo "📦 Compressing DMG..."
hdiutil convert "pack.temp.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG_NAME"
rm -f "pack.temp.dmg"
rm -rf "dmg_staging"

echo "✅ Installer created successfully: $DMG_NAME"
