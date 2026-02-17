"""
Audio recorder for meetings.
Records mic (you) and system audio (them) as separate WAV files.
Uses audiocap (Core Audio taps) - no BlackHole or ScreenCaptureKit needed.
Works with any audio output (speakers, AirPods, etc.)
"""

import os
import signal
import subprocess
import time
from datetime import datetime
from pathlib import Path

import soundfile as sf


class MeetingRecorder:
    def __init__(self, config: dict):
        audio_cfg = config.get("audio", {})
        self.sample_rate = audio_cfg.get("sample_rate", 16000)
        self.output_dir = Path(os.path.expanduser(audio_cfg.get("output_dir", "~/recordings")))
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # audiocap binary path (Core Audio taps)
        self.audiocap_path = Path(__file__).parent / "audiocap" / "AudioCap.app" / "Contents" / "MacOS" / "audiocap"

        self._recording = False
        self._session_id = None
        self._audiocap_proc = None

    def check_ready(self) -> tuple[bool, str]:
        """Check if audiocap is built and ready."""
        if not self.audiocap_path.exists():
            return False, (
                f"audiocap binary not found at {self.audiocap_path}. "
                "Build it: cd audiocap && bash build.sh"
            )
        return True, "Ready"

    def start(self) -> str:
        """Start recording both channels. Returns session ID."""
        if self._recording:
            raise RuntimeError("Already recording")

        ready, msg = self.check_ready()
        if not ready:
            raise RuntimeError(msg)

        self._session_id = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        session_dir = self.output_dir / self._session_id
        session_dir.mkdir(parents=True, exist_ok=True)

        sys_path = session_dir / "system.wav"
        cmd = [
            str(self.audiocap_path),
            str(sys_path),
            "--sample-rate", str(self.sample_rate),
            "--mic",  # Also capture microphone
        ]

        self._audiocap_proc = subprocess.Popen(
            cmd,
            stderr=subprocess.PIPE,
            text=True,
        )
        # Give it a moment to start
        time.sleep(1.5)
        if self._audiocap_proc.poll() is not None:
            stderr = self._audiocap_proc.stderr.read()
            raise RuntimeError(f"audiocap failed to start: {stderr}")

        self._recording = True
        return self._session_id

    def stop(self) -> dict:
        """Stop recording and save WAV files. Returns file paths."""
        if not self._recording:
            raise RuntimeError("Not recording")

        session_dir = self.output_dir / self._session_id

        if self._audiocap_proc and self._audiocap_proc.poll() is None:
            self._audiocap_proc.send_signal(signal.SIGINT)
            try:
                self._audiocap_proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self._audiocap_proc.kill()

        mic_path = session_dir / "mic.wav"
        sys_path = session_dir / "system.wav"

        # Get duration from file
        duration = 0
        for path in [sys_path, mic_path]:
            if path.exists():
                try:
                    info = sf.info(str(path))
                    duration = max(duration, info.duration)
                except Exception:
                    pass

        self._recording = False

        return {
            "session_id": self._session_id,
            "mic_path": str(mic_path),
            "sys_path": str(sys_path),
            "duration": duration,
            "sample_rate": self.sample_rate,
        }

    @property
    def is_recording(self) -> bool:
        return self._recording

    @property
    def session_id(self) -> str | None:
        return self._session_id


def cli():
    """Quick CLI test: record until Ctrl+C."""
    import yaml

    config_path = Path(__file__).parent / "config.yaml"
    if config_path.exists():
        with open(config_path) as f:
            config = yaml.safe_load(f)
    else:
        config = {}

    recorder = MeetingRecorder(config)
    ready, msg = recorder.check_ready()
    if not ready:
        print(f"Error: {msg}")
        return

    print(f"Output: {recorder.output_dir}")
    print(f"Sample rate: {recorder.sample_rate}")
    print()

    try:
        session_id = recorder.start()
        print(f"Recording session: {session_id}")
        print("Press Ctrl+C to stop.")
        while recorder.is_recording:
            time.sleep(0.5)
    except KeyboardInterrupt:
        print("\nStopping...")
    finally:
        if recorder.is_recording:
            result = recorder.stop()
            print(f"Duration: {result['duration']:.1f}s")
            print(f"Mic: {result['mic_path']}")
            print(f"System: {result['sys_path']}")


if __name__ == "__main__":
    cli()
