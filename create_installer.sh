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

# 7. Create DMG
echo "💿 Creating DMG..."
rm -f "$DMG_NAME"
mkdir -p dmg_content
cp -r "$APP_BUNDLE" dmg_content/
ln -s /Applications dmg_content/Applications

hdiutil create -volname "$APP_NAME" -srcfolder dmg_content -ov -format UDZO "$DMG_NAME"

# 8. Cleanup
echo "🧹 Cleaning up..."
rm -rf dmg_content
# Optional: keep the .app for testing
# rm -rf "$APP_BUNDLE"

echo "✅ Installer created successfully: $DMG_NAME"
