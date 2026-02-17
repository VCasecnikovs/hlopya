"""
STT Pipeline for meeting recordings.
Primary: NVIDIA Parakeet-TDT-0.6B-v3 (SoTA bilingual EN+RU, 3-5.5% WER Russian, 6.3% English)
Fallback: faster-whisper (if NeMo unavailable)
Merges two channels into diarized transcript.
Echo cancellation: energy-gated mic suppression when system audio is active.
"""

import os
import json
import time
import tempfile
from pathlib import Path
from dataclasses import dataclass, asdict

import numpy as np
import soundfile as sf


@dataclass
class Segment:
    speaker: str  # "Me" or "Them"
    start: float  # seconds
    end: float
    text: str
    language: str = ""


class Transcriber:
    def __init__(self, config: dict):
        stt_cfg = config.get("stt", {})
        self.primary = stt_cfg.get("primary_model", "parakeet")
        self.parakeet_model = stt_cfg.get("parakeet_model", "nvidia/parakeet-tdt-0.6b-v3")
        self.whisper_model = stt_cfg.get("whisper_model", "large-v3")
        self.whisper_device = stt_cfg.get("whisper_device", "auto")
        self.whisper_compute = stt_cfg.get("whisper_compute_type", "float16")

        self._parakeet_model = None
        self._whisper_model = None

    def _load_parakeet(self):
        if self._parakeet_model is None:
            print("Loading Parakeet-TDT-0.6B-v3...")
            t0 = time.time()
            import nemo.collections.asr as nemo_asr
            self._parakeet_model = nemo_asr.models.ASRModel.from_pretrained(
                model_name=self.parakeet_model
            )
            # Enable local attention for long audio (up to 3 hours)
            self._parakeet_model.change_attention_model(
                self_attention_model="rel_pos_local_attn",
                att_context_size=[256, 256],
            )
            print(f"Parakeet loaded in {time.time() - t0:.1f}s")
        return self._parakeet_model

    def _load_whisper(self):
        if self._whisper_model is None:
            print("Loading Whisper model...")
            t0 = time.time()
            from faster_whisper import WhisperModel
            self._whisper_model = WhisperModel(
                self.whisper_model,
                device=self.whisper_device,
                compute_type=self.whisper_compute,
            )
            print(f"Whisper loaded in {time.time() - t0:.1f}s")
        return self._whisper_model

    def _transcribe_parakeet(self, audio_path: str) -> list[Segment]:
        """Transcribe with Parakeet. Returns segments with word-level timestamps."""
        model = self._load_parakeet()
        output = model.transcribe([audio_path], timestamps=True)

        segments = []
        if output and len(output) > 0:
            result = output[0]
            # Get segment-level timestamps (sentences/phrases)
            if hasattr(result, 'timestamp') and result.timestamp:
                seg_stamps = result.timestamp.get('segment', [])
                if seg_stamps:
                    for stamp in seg_stamps:
                        segments.append(Segment(
                            speaker="",
                            start=stamp.get("start", 0.0),
                            end=stamp.get("end", 0.0),
                            text=stamp.get("segment", "").strip(),
                        ))
                else:
                    # Fall back to word timestamps
                    word_stamps = result.timestamp.get('word', [])
                    if word_stamps:
                        # Group words into ~10 second chunks
                        chunk_segments = self._group_words_into_segments(word_stamps)
                        segments.extend(chunk_segments)

            # Fallback: just the full text
            if not segments and hasattr(result, 'text') and result.text:
                segments.append(Segment(
                    speaker="",
                    start=0.0,
                    end=0.0,
                    text=result.text.strip(),
                ))

        return segments

    def _group_words_into_segments(self, word_stamps: list, max_gap: float = 1.5) -> list[Segment]:
        """Group word timestamps into segments based on pauses."""
        if not word_stamps:
            return []

        segments = []
        current_words = []
        current_start = word_stamps[0].get("start", 0.0)

        for i, w in enumerate(word_stamps):
            current_words.append(w.get("word", ""))
            # Check if there's a significant pause before next word
            if i < len(word_stamps) - 1:
                gap = word_stamps[i + 1].get("start", 0) - w.get("end", 0)
                if gap > max_gap:
                    segments.append(Segment(
                        speaker="",
                        start=current_start,
                        end=w.get("end", 0.0),
                        text=" ".join(current_words).strip(),
                    ))
                    current_words = []
                    current_start = word_stamps[i + 1].get("start", 0.0)

        # Last segment
        if current_words:
            segments.append(Segment(
                speaker="",
                start=current_start,
                end=word_stamps[-1].get("end", 0.0),
                text=" ".join(current_words).strip(),
            ))

        return segments

    def _transcribe_whisper(self, audio_path: str) -> list[Segment]:
        """Transcribe with faster-whisper. Returns segments with timestamps."""
        model = self._load_whisper()
        segments_iter, info = model.transcribe(
            audio_path,
            language=None,  # Auto-detect
            beam_size=5,
            word_timestamps=True,
            vad_filter=True,
        )
        segments = []
        for seg in segments_iter:
            segments.append(Segment(
                speaker="",
                start=seg.start,
                end=seg.end,
                text=seg.text.strip(),
                language=info.language,
            ))
        return segments

    def _remove_echo(self, mic_path: str, sys_path: str) -> str:
        """
        Remove speaker bleed from mic using system audio as reference.
        Uses energy-gated suppression: when system audio is active,
        attenuate the mic signal to remove crosstalk from speakers.
        Returns path to cleaned mic WAV file.
        """
        mic_data, mic_sr = sf.read(mic_path, dtype='float32')
        sys_data, sys_sr = sf.read(sys_path, dtype='float32')

        # Ensure mono
        if mic_data.ndim > 1:
            mic_data = mic_data[:, 0]
        if sys_data.ndim > 1:
            sys_data = sys_data[:, 0]

        # Align lengths (pad shorter with zeros)
        min_len = min(len(mic_data), len(sys_data))
        mic_data = mic_data[:min_len]
        sys_data = sys_data[:min_len]

        # Window size: 30ms frames for smooth gating
        frame_size = int(mic_sr * 0.030)
        num_frames = len(mic_data) // frame_size

        # Compute per-frame RMS energy
        mic_rms = np.zeros(num_frames)
        sys_rms = np.zeros(num_frames)
        for i in range(num_frames):
            start = i * frame_size
            end = start + frame_size
            mic_rms[i] = np.sqrt(np.mean(mic_data[start:end] ** 2))
            sys_rms[i] = np.sqrt(np.mean(sys_data[start:end] ** 2))

        # Adaptive threshold: system audio is "active" when its RMS
        # exceeds 2x the median background noise level
        sys_median = np.median(sys_rms[sys_rms > 0]) if np.any(sys_rms > 0) else 0.001
        sys_threshold = max(sys_median * 0.5, 0.003)

        # Apply soft gate: when system is active and louder than mic,
        # suppress mic to reduce crosstalk
        cleaned = mic_data.copy()
        suppressed_frames = 0

        for i in range(num_frames):
            start = i * frame_size
            end = start + frame_size

            if sys_rms[i] > sys_threshold:
                # System audio is playing - check if mic signal is mostly echo
                # If system is significantly louder, mic content is likely echo
                ratio = sys_rms[i] / max(mic_rms[i], 1e-6)
                if ratio > 0.3:  # System contributes significantly
                    # Soft attenuation: stronger suppression when system is louder
                    attenuation = max(0.05, 1.0 - min(ratio * 0.8, 0.95))
                    cleaned[start:end] *= attenuation
                    suppressed_frames += 1

        # Save to temp file
        clean_path = tempfile.mktemp(suffix='_clean.wav', dir=str(Path(mic_path).parent))
        sf.write(clean_path, cleaned, mic_sr)

        pct = (suppressed_frames / max(num_frames, 1)) * 100
        print(f"  Echo removal: {suppressed_frames}/{num_frames} frames suppressed ({pct:.0f}%)")
        print(f"  System threshold: {sys_threshold:.4f}, median RMS: {sys_median:.4f}")

        return clean_path

    def transcribe_channel(self, audio_path: str, speaker: str) -> list[Segment]:
        """Transcribe a single audio channel."""
        print(f"Transcribing {speaker} channel: {audio_path}")
        t0 = time.time()

        if self.primary == "parakeet":
            try:
                segments = self._transcribe_parakeet(audio_path)
            except Exception as e:
                print(f"Parakeet failed: {e}. Falling back to Whisper...")
                segments = self._transcribe_whisper(audio_path)
        elif self.primary == "whisper":
            segments = self._transcribe_whisper(audio_path)
        else:
            segments = self._transcribe_whisper(audio_path)

        for seg in segments:
            seg.speaker = speaker

        elapsed = time.time() - t0
        total_text = " ".join(s.text for s in segments)
        print(f"  {speaker}: {len(segments)} segments, {len(total_text)} chars, {elapsed:.1f}s")
        return segments

    def merge_channels(self, mic_segments: list[Segment], sys_segments: list[Segment]) -> list[Segment]:
        """Merge two channels into a single timeline sorted by start time."""
        all_segments = mic_segments + sys_segments
        all_segments.sort(key=lambda s: s.start)

        # Remove empty segments
        all_segments = [s for s in all_segments if s.text.strip()]

        return all_segments

    def transcribe_meeting(self, mic_path: str, sys_path: str) -> dict:
        """
        Full meeting transcription pipeline.
        Returns dict with segments, full_text, and metadata.
        """
        print(f"\n{'='*60}")
        print("Meeting Transcription Pipeline")
        print(f"  Model: {self.primary}")
        print(f"{'='*60}")
        t0 = time.time()

        # Echo cancellation: clean mic audio using system audio as reference
        clean_mic_path = mic_path
        try:
            print("\nRemoving speaker echo from mic channel...")
            clean_mic_path = self._remove_echo(mic_path, sys_path)
        except Exception as e:
            print(f"  Warning: echo removal failed ({e}), using raw mic audio")

        mic_segments = self.transcribe_channel(clean_mic_path, "Me")
        sys_segments = self.transcribe_channel(sys_path, "Them")

        # Clean up temp file
        if clean_mic_path != mic_path:
            try:
                os.unlink(clean_mic_path)
            except OSError:
                pass

        merged = self.merge_channels(mic_segments, sys_segments)

        # Build formatted transcript
        lines = []
        for seg in merged:
            timestamp = f"[{seg.start:.1f}s]" if seg.start > 0 else ""
            lines.append(f"**{seg.speaker}** {timestamp}: {seg.text}")

        full_text = "\n".join(lines)
        elapsed = time.time() - t0

        result = {
            "segments": [asdict(s) for s in merged],
            "full_text": full_text,
            "plain_text": " ".join(s.text for s in merged),
            "me_text": " ".join(s.text for s in merged if s.speaker == "Me"),
            "them_text": " ".join(s.text for s in merged if s.speaker == "Them"),
            "num_segments": len(merged),
            "duration_seconds": max((s.end for s in merged), default=0),
            "processing_time": elapsed,
            "model_used": self.primary,
        }

        print(f"\nDone: {result['num_segments']} segments in {elapsed:.1f}s")
        print(f"Me: {len(mic_segments)} segments")
        print(f"Them: {len(sys_segments)} segments")

        return result

    def save_transcript(self, result: dict, output_path: str):
        """Save transcript to JSON and markdown."""
        output = Path(output_path)

        # JSON (full data)
        json_path = output.with_suffix(".json")
        with open(json_path, "w") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)

        # Markdown (readable)
        md_path = output.with_suffix(".md")
        with open(md_path, "w") as f:
            f.write("# Meeting Transcript\n\n")
            f.write(f"- Model: {result['model_used']}\n")
            f.write(f"- Segments: {result['num_segments']}\n")
            f.write(f"- Processing time: {result['processing_time']:.1f}s\n\n")
            f.write("---\n\n")
            f.write(result["full_text"])

        print(f"Saved: {json_path}")
        print(f"Saved: {md_path}")


def cli():
    """CLI: transcribe a recording session."""
    import sys
    import yaml

    if len(sys.argv) < 2:
        print("Usage: python transcriber.py <session_dir>")
        print("  session_dir should contain mic.wav and system.wav")
        sys.exit(1)

    session_dir = Path(sys.argv[1])
    mic_path = session_dir / "mic.wav"
    sys_path = session_dir / "system.wav"

    if not mic_path.exists() or not sys_path.exists():
        print(f"Error: need mic.wav and system.wav in {session_dir}")
        sys.exit(1)

    config_path = Path(__file__).parent / "config.yaml"
    if config_path.exists():
        with open(config_path) as f:
            config = yaml.safe_load(f)
    else:
        config = {}

    transcriber = Transcriber(config)
    result = transcriber.transcribe_meeting(str(mic_path), str(sys_path))
    transcriber.save_transcript(result, str(session_dir / "transcript"))


if __name__ == "__main__":
    cli()
