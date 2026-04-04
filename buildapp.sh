#!/bin/bash

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Minecraft"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"

echo "Building $APP_NAME.app..."

# Clean and setup directory structure
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS"

# Compile Swift files directly into the .app bundle
SWIFT_FILES=(
    "$PROJECT_DIR/main.swift"
    "$PROJECT_DIR/AppDelegate.swift"
    "$PROJECT_DIR/ShaderLibrary.swift"
    "$PROJECT_DIR/SimpleTriangle.swift"
    "$PROJECT_DIR/TriangleRenderer.swift"
    "$PROJECT_DIR/CubeMesh.swift"
    "$PROJECT_DIR/BlockTextures.swift"
    "$PROJECT_DIR/MetalRenderer.swift"
    "$PROJECT_DIR/MetalViewContainer.swift"
)

swiftc \
    -target arm64-apple-macosx14.0 \
    -o "$MACOS/$APP_NAME" \
    "${SWIFT_FILES[@]}" \
    -framework Foundation \
    -framework AppKit \
    -framework MetalKit \
    -framework Metal \
    -parse-as-library

# Create the Info.plist (This is what makes it an "App")
cat <<EOF > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://apple.com">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.user.minecraftswift</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
EOF

echo "Build successful! Created $APP_BUNDLE"

# Launch the bundle instead of the raw binary
open "$APP_BUNDLE"