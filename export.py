#!/usr/bin/env python3
"""
Export meeting recorder sessions as JSON to stdout.
Designed for integration with external tools and data pipelines.

Usage:
  python export.py <session_dir>                    # Export single session
  python export.py --latest                         # Export latest session
  python export.py --list                           # List all sessions
  python export.py --list --status done             # List sessions with notes
  python export.py --list --since 2026-02-01        # Sessions after date
  python export.py <session_dir> --format json      # JSON output (default)
"""

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path

import yaml


def load_config() -> dict:
    config_path = Path(__file__).parent / "config.yaml"
    if config_path.exists():
        with open(config_path) as f:
            return yaml.safe_load(f)
    return {}


def get_recordings_dir(config: dict) -> Path:
    return Path(os.path.expanduser(
        config.get("audio", {}).get("output_dir", "~/recordings")
    ))


def export_session(session_dir: Path) -> dict:
    """Export a single session as a structured dict."""
    session_id = session_dir.name

    result = {
        "id": session_id,
        "path": str(session_dir),
        "status": "recorded",
        "title": None,
        "date": None,
        "duration_seconds": 0,
        "participants": [],
        "transcript": None,
        "notes": None,
        "personal_notes": None,
        "action_items": [],
        "decisions": [],
        "summary": None,
        "enriched_notes": None,
        "meta": {},
    }

    # Parse date from session ID
    try:
        dt = datetime.strptime(session_id[:19], "%Y-%m-%d_%H-%M-%S")
        result["date"] = dt.isoformat()
    except ValueError:
        pass

    # Read meta.json
    meta_path = session_dir / "meta.json"
    if meta_path.exists():
        try:
            result["meta"] = json.loads(meta_path.read_text())
            if result["meta"].get("title"):
                result["title"] = result["meta"]["title"]
        except Exception:
            pass

    # Read transcript
    transcript_json = session_dir / "transcript.json"
    transcript_md = session_dir / "transcript.md"
    if transcript_json.exists():
        try:
            t = json.loads(transcript_json.read_text())
            result["transcript"] = t.get("full_text", "")
            result["duration_seconds"] = t.get("duration_seconds", 0)
            result["status"] = "transcribed"
        except Exception:
            pass
    elif transcript_md.exists():
        result["transcript"] = transcript_md.read_text()
        result["status"] = "transcribed"

    # Read notes
    notes_path = session_dir / "notes.json"
    if notes_path.exists():
        try:
            notes = json.loads(notes_path.read_text())
            result["notes"] = notes
            result["status"] = "done"
            if not result["title"]:
                result["title"] = notes.get("title")
            result["participants"] = notes.get("participants", [])
            result["action_items"] = notes.get("action_items", [])
            result["decisions"] = notes.get("decisions", [])
            result["summary"] = notes.get("summary")
            result["enriched_notes"] = notes.get("enriched_notes")
        except Exception:
            pass

    # Read personal notes
    pn_path = session_dir / "personal_notes.md"
    if pn_path.exists():
        result["personal_notes"] = pn_path.read_text()

    return result


def list_sessions(config: dict, status_filter: str | None = None, since: str | None = None) -> list[dict]:
    """List all sessions with basic metadata."""
    recordings_dir = get_recordings_dir(config)
    if not recordings_dir.exists():
        return []

    sessions = []
    for d in sorted(recordings_dir.iterdir(), reverse=True):
        if not d.is_dir():
            continue

        # Check if it looks like a session
        has_audio = (d / "mic.wav").exists() or (d / "system.wav").exists()
        if not has_audio:
            continue

        # Quick status check
        has_notes = (d / "notes.json").exists()
        has_transcript = (d / "transcript.json").exists() or (d / "transcript.md").exists()

        status = "recorded"
        if has_notes:
            status = "done"
        elif has_transcript:
            status = "transcribed"

        if status_filter and status != status_filter:
            continue

        # Date filter
        if since:
            try:
                since_dt = datetime.strptime(since, "%Y-%m-%d")
                session_dt = datetime.strptime(d.name[:10], "%Y-%m-%d")
                if session_dt < since_dt:
                    continue
            except ValueError:
                pass

        # Get title from meta or notes
        title = None
        meta_path = d / "meta.json"
        if meta_path.exists():
            try:
                meta = json.loads(meta_path.read_text())
                title = meta.get("title")
            except Exception:
                pass

        if not title and has_notes:
            try:
                notes = json.loads((d / "notes.json").read_text())
                title = notes.get("title")
            except Exception:
                pass

        sessions.append({
            "id": d.name,
            "status": status,
            "title": title,
            "path": str(d),
        })

    return sessions


def main():
    parser = argparse.ArgumentParser(
        description="Export meeting recorder sessions as JSON"
    )
    parser.add_argument("session_dir", nargs="?", help="Path to session directory")
    parser.add_argument("--latest", action="store_true", help="Export the latest session")
    parser.add_argument("--list", action="store_true", help="List all sessions")
    parser.add_argument("--status", choices=["recorded", "transcribed", "done"], help="Filter by status")
    parser.add_argument("--since", help="Filter sessions after date (YYYY-MM-DD)")
    parser.add_argument("--format", choices=["json", "jsonl"], default="json", help="Output format")
    parser.add_argument("--full", action="store_true", help="Include full transcript and notes in list mode")

    args = parser.parse_args()
    config = load_config()

    if args.list:
        sessions = list_sessions(config, args.status, args.since)
        if args.full:
            sessions = [export_session(Path(s["path"])) for s in sessions]

        if args.format == "jsonl":
            for s in sessions:
                print(json.dumps(s, ensure_ascii=False))
        else:
            print(json.dumps(sessions, ensure_ascii=False, indent=2))
        return

    if args.latest:
        recordings_dir = get_recordings_dir(config)
        sessions = list_sessions(config)
        if not sessions:
            print(json.dumps({"error": "No sessions found"}))
            sys.exit(1)
        session_dir = Path(sessions[0]["path"])
    elif args.session_dir:
        session_dir = Path(args.session_dir)
    else:
        parser.print_help()
        sys.exit(1)

    if not session_dir.exists():
        print(json.dumps({"error": f"Session not found: {session_dir}"}))
        sys.exit(1)

    result = export_session(session_dir)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
