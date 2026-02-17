#!/bin/bash
# Build audiocap and package into .app bundle
set -e

cd "$(dirname "$0")"

echo "Building audiocap..."
swift build -c release

echo "Packaging into AudioCap.app..."
mkdir -p AudioCap.app/Contents/MacOS
cp .build/release/audiocap AudioCap.app/Contents/MacOS/audiocap

echo "Code signing..."
codesign --force --sign - AudioCap.app

echo ""
echo "Done! AudioCap.app is ready."
echo ""
echo "First run: macOS will ask for Audio Recording permission."
echo "Grant it to 'AudioCap' in System Settings > Privacy > Screen & System Audio Recording."
echo ""
echo "Test: AudioCap.app/Contents/MacOS/audiocap /tmp/test.wav --mic"
