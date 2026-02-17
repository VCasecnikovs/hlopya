#!/bin/bash
# Hlopya - Setup Script
# Run: bash setup.sh

set -e

echo "=== Hlopya Setup ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. Build audiocap
echo ""
echo "Step 1: Build audiocap (Core Audio taps)"
if [ -f "$SCRIPT_DIR/audiocap/AudioCap.app/Contents/MacOS/audiocap" ]; then
    echo "  audiocap already built"
else
    echo "  Building audiocap..."
    cd "$SCRIPT_DIR/audiocap" && bash build.sh
fi

# 2. Python deps
echo ""
echo "Step 2: Install Python dependencies"
pip3 install -r "$SCRIPT_DIR/requirements.txt"

# 3. Create recordings dir
mkdir -p ~/recordings

# 4. Test
echo ""
echo "Step 3: Quick test"
cd "$SCRIPT_DIR"
python3 -c "
from recorder import MeetingRecorder
r = MeetingRecorder({})
ok, msg = r.check_ready()
print(f'  audiocap: {\"OK\" if ok else msg}')
print(f'  output: {r.output_dir}')
"

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Usage:"
echo "  python3 $SCRIPT_DIR/app.py           # TUI app (Record + view transcriptions)"
echo "  python3 $SCRIPT_DIR/app.py record    # Quick record from CLI"
echo "  python3 $SCRIPT_DIR/app.py list      # List sessions"
echo "  python3 $SCRIPT_DIR/app.py process DIR  # Process existing recording"
echo ""
echo "First recording: macOS will ask for Audio Recording permission."
echo "Grant it to AudioCap in System Settings > Privacy > Screen & System Audio Recording."
