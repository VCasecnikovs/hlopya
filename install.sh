#!/bin/bash
# Meeting Recorder - One-step install
# Usage: bash install.sh
set -e

echo "=== Meeting Recorder Install ==="
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. Build audiocap
echo "Step 1/4: Building audiocap (system audio capture)..."
if [ -f "$SCRIPT_DIR/audiocap/AudioCap.app/Contents/MacOS/audiocap" ]; then
    echo "  Already built, skipping"
else
    cd "$SCRIPT_DIR/audiocap" && bash build.sh
fi

# 2. Python deps
echo ""
echo "Step 2/4: Installing Python dependencies..."
pip3 install -q sounddevice soundfile numpy pyyaml 2>/dev/null || pip3 install sounddevice soundfile numpy pyyaml
echo "  Core deps installed"
echo "  Note: STT models (torch, nemo, faster-whisper) are large (~2GB)."
echo "  Install them separately: pip3 install -r requirements.txt"

# 3. Electron build
echo ""
echo "Step 3/4: Building Electron app..."
cd "$SCRIPT_DIR/gui"
npm install --silent 2>/dev/null || npm install
npm run build

# 4. Install to Applications
echo ""
echo "Step 4/4: Installing to /Applications..."
if [ -d "/Applications/Meeting Recorder.app" ]; then
    echo "  Removing old version..."
    rm -rf "/Applications/Meeting Recorder.app"
fi
cp -R "$SCRIPT_DIR/gui/dist/mac-arm64/Meeting Recorder.app" /Applications/
echo "  Installed!"

# Create recordings dir
mkdir -p ~/recordings

echo ""
echo "=== Install complete! ==="
echo ""
echo "Launch: open '/Applications/Meeting Recorder.app'"
echo "   or: search 'Meeting Recorder' in Spotlight"
echo ""
echo "First run: macOS will ask for Screen & System Audio Recording permission."
echo "Grant it in System Settings > Privacy & Security."
echo ""
echo "For full STT (transcription), install heavy deps:"
echo "  pip3 install torch torchaudio nemo_toolkit[asr] faster-whisper"
