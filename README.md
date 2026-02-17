# Meeting Recorder

macOS app that records meetings, transcribes with AI (NVIDIA Parakeet / Whisper), and generates structured notes with Claude.

## Features

- **Dual-channel recording** - captures mic (you) and system audio (them) separately via ScreenCaptureKit
- **Echo cancellation** - energy-gated suppression removes speaker bleed from mic
- **Bilingual STT** - NVIDIA Parakeet-TDT-0.6B (EN + RU, 3-6% WER) with Whisper fallback
- **AI meeting notes** - Claude generates structured notes with decisions, action items, and follow-ups
- **Personal notes integration** - your notes become the backbone, AI enriches with transcript context
- **Electron GUI** - tray icon, floating recording indicator, session browser
- **CLI** - record, transcribe, and process from terminal

## Requirements

- macOS 14.2+ (ScreenCaptureKit for system audio capture)
- Python 3.11+
- [Claude CLI](https://github.com/anthropics/claude-code) (for note generation)
- Xcode Command Line Tools (for building audiocap)

## Install

```bash
git clone https://github.com/VCasecnikovs/meeting-recorder.git
cd meeting-recorder
bash install.sh
```

That's it. The script builds audiocap, installs deps, builds the Electron app, and copies it to `/Applications`.

On first run, macOS will ask for **Screen & System Audio Recording** permission. Grant it in System Settings > Privacy & Security.

### Manual install

If you prefer step-by-step:

```bash
cd audiocap && bash build.sh && cd ..      # Build audio capture binary
pip install -r requirements.txt             # Python deps (includes large STT models)
cd gui && npm install && npm run build      # Build Electron app
cp -R gui/dist/mac-arm64/Meeting\ Recorder.app /Applications/
```

## Usage

### GUI (Electron app)

Launch from `/Applications/Meeting Recorder.app` or Spotlight.

- Click **Record** to start - a floating red indicator shows recording time
- Take notes in the text area during the meeting
- Click **Stop** - auto-transcribes and generates AI notes
- Browse past sessions, edit notes, rename participants

### CLI

```bash
# Record (Ctrl+C to stop)
python app.py record

# List sessions
python app.py list

# Process a recording (transcribe + notes)
python app.py process ~/recordings/2026-02-17_14-30-45

# Transcribe only
python app.py transcribe ~/recordings/2026-02-17_14-30-45

# Export session as JSON (for integration with other tools)
python export.py ~/recordings/2026-02-17_14-30-45
python export.py ~/recordings/2026-02-17_14-30-45 --format json
python export.py --list --format json  # list all sessions as JSON
```

### Dev mode

```bash
cd gui && npm start
```

## Architecture

```
meeting-recorder/
├── gui/                    # Electron app
│   ├── main.js             # Main process (tray, recording, IPC)
│   ├── index.html          # UI (sidebar + detail view)
│   ├── preload.js          # IPC bridge
│   └── nub.html            # Floating recording indicator
├── audiocap/               # Swift binary for system audio capture
│   ├── Sources/main.swift  # ScreenCaptureKit + AVFoundation
│   ├── Package.swift
│   └── build.sh
├── recorder.py             # Audio recording orchestrator
├── transcriber.py          # STT pipeline (Parakeet/Whisper + echo cancellation)
├── noter.py                # AI note generation via Claude CLI
├── app.py                  # TUI app + CLI commands
├── export.py               # JSON/stdout export for external integrations
├── config.yaml             # Configuration
└── requirements.txt        # Python dependencies
```

### Pipeline

```
Record (audiocap) -> Echo Cancel -> Transcribe (Parakeet/Whisper) -> Notes (Claude) -> JSON
```

Recordings are saved to `~/recordings/{YYYY-MM-DD_HH-MM-SS}/` with:
- `mic.wav` - your voice
- `system.wav` - meeting audio
- `transcript.json` / `transcript.md` - diarized transcript
- `notes.json` - structured meeting notes
- `personal_notes.md` - your notes taken during recording
- `meta.json` - custom title, participant name mappings

## Integration

The `export.py` script outputs session data as JSON to stdout, making it easy to integrate with any external system:

```bash
# Get latest session as JSON
python export.py --latest --format json | jq .

# Pipe to your data pipeline
python export.py ~/recordings/SESSION_ID --format json | your-pipeline-tool ingest

# List all done sessions
python export.py --list --status done --format json
```

## Configuration

Edit `config.yaml`:

```yaml
audio:
  sample_rate: 16000
  output_dir: ~/recordings

stt:
  primary_model: parakeet       # or "whisper"
  parakeet_model: nvidia/parakeet-tdt-0.6b-v3
  whisper_model: large-v3

notes:
  model: claude-sonnet-4-5-20250929
  owner_name: Your Name        # filters action items assigned to you

app:
  auto_process: true
```

