#!/bin/bash

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"

echo "Building Swift Metal test app..."

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Compile Swift files
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
    -o "$BUILD_DIR/SwiftMetalTest" \
    "${SWIFT_FILES[@]}" \
    -framework Foundation \
    -framework AppKit \
    -framework MetalKit \
    -framework Metal \
    -parse-as-library

echo "Build successful!"
echo "Running app..."

"$BUILD_DIR/SwiftMetalTest" &
APP_PID=$!

echo "App launched with PID: $APP_PID"
echo "Press Ctrl+C to stop..."

wait $APP_PID
