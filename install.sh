#!/bin/bash
# Hlopya - One-step install
# Usage: bash install.sh
set -e

echo "=== Hlopya Install ==="
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Pre-flight checks
fail=0

if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 not found. Install Python 3.11+ from python.org or: brew install python"
    fail=1
fi

if ! command -v npm &>/dev/null; then
    echo "ERROR: npm not found. Install Node.js from nodejs.org or: brew install node"
    fail=1
fi

if ! xcode-select -p &>/dev/null; then
    echo "ERROR: Xcode Command Line Tools not found. Install: xcode-select --install"
    fail=1
fi

if [ "$fail" -eq 1 ]; then
    echo ""
    echo "Fix the above and re-run: bash install.sh"
    exit 1
fi

# 1. Build audiocap
echo "Step 1/4: Building audiocap (system audio capture)..."
if [ -f "$SCRIPT_DIR/audiocap/AudioCap.app/Contents/MacOS/audiocap" ]; then
    echo "  Already built, skipping"
else
    cd "$SCRIPT_DIR/audiocap" && bash build.sh
fi

# 2. Python deps (core only - lightweight)
echo ""
echo "Step 2/4: Installing Python dependencies..."
pip3 install --break-system-packages -q sounddevice soundfile numpy pyyaml 2>/dev/null \
    || pip3 install -q sounddevice soundfile numpy pyyaml 2>/dev/null \
    || pip3 install sounddevice soundfile numpy pyyaml
echo "  Core deps installed"

# 3. Electron build
echo ""
echo "Step 3/4: Building Electron app..."
cd "$SCRIPT_DIR/gui"
npm install --silent 2>/dev/null || npm install
npm run build

# 4. Install to Applications
echo ""
echo "Step 4/4: Installing to /Applications..."
if [ -d "/Applications/Hlopya.app" ]; then
    echo "  Removing old version..."
    rm -rf "/Applications/Hlopya.app"
fi
cp -R "$SCRIPT_DIR/gui/dist/mac-arm64/Hlopya.app" /Applications/
echo "  Installed!"

# Create recordings dir
mkdir -p ~/recordings

echo ""
echo "=== Install complete! ==="
echo ""
echo "Launch: open '/Applications/Hlopya.app'"
echo "   or: search 'Hlopya' in Spotlight"
echo ""
echo "First run: macOS will ask for Screen & System Audio Recording permission."
echo "Grant it in System Settings > Privacy & Security."
echo ""
echo "For full STT (transcription), install heavy deps:"
echo "  pip3 install torch torchaudio nemo_toolkit[asr] faster-whisper"
