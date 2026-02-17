"""
Hlopya - Terminal UI App.
macOS app that records meetings, transcribes with AI, and generates structured notes.

Usage:
  python app.py                  # Launch TUI app
  python app.py record           # Quick record from CLI
  python app.py process <dir>    # Process existing recording
  python app.py list             # List sessions
"""

import json
import os
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

import yaml
from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Container, Horizontal, Vertical, VerticalScroll
from textual.widgets import (
    Button,
    DataTable,
    Footer,
    Header,
    Label,
    RichLog,
    Static,
)


def load_config() -> dict:
    config_path = Path(__file__).parent / "config.yaml"
    if config_path.exists():
        with open(config_path) as f:
            return yaml.safe_load(f)
    return {}


def get_sessions(config: dict) -> list[dict]:
    """Scan recordings directory for sessions."""
    output_dir = Path(os.path.expanduser(
        config.get("audio", {}).get("output_dir", "~/recordings")
    ))
    if not output_dir.exists():
        return []

    sessions = []
    for d in sorted(output_dir.iterdir(), reverse=True):
        if not d.is_dir():
            continue

        mic = d / "mic.wav"
        sys = d / "system.wav"
        transcript_md = d / "transcript.md"
        transcript_json = d / "transcript.json"
        notes_json = d / "notes.json"

        if not (mic.exists() or sys.exists()):
            continue

        # Get duration
        duration = 0
        for wav in [sys, mic]:
            if wav.exists():
                try:
                    import soundfile as sf
                    info = sf.info(str(wav))
                    duration = max(duration, info.duration)
                except Exception:
                    pass

        # Status
        has_transcript = transcript_json.exists() or transcript_md.exists()
        has_notes = notes_json.exists()

        if has_notes:
            status = "noted"
        elif has_transcript:
            status = "transcribed"
        else:
            status = "recorded"

        # Load title from notes if available
        title = ""
        if notes_json.exists():
            try:
                with open(notes_json) as f:
                    notes = json.load(f)
                    title = notes.get("title", "")
            except Exception:
                pass

        sessions.append({
            "id": d.name,
            "path": str(d),
            "duration": duration,
            "status": status,
            "has_transcript": has_transcript,
            "has_notes": has_notes,
            "title": title,
            "mic_path": str(mic),
            "sys_path": str(sys),
        })

    return sessions


def format_duration(seconds: float) -> str:
    if seconds <= 0:
        return "--:--"
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    if h > 0:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"


def format_status(status: str) -> str:
    icons = {"recorded": "[yellow]REC[/]", "transcribed": "[cyan]STT[/]", "noted": "[green]DONE[/]"}
    return icons.get(status, status)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# TUI App
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


STYLES = """
Screen {
    layout: grid;
    grid-size: 2 3;
    grid-columns: 1fr 2fr;
    grid-rows: auto 1fr auto;
}

#top-bar {
    column-span: 2;
    height: 3;
    background: $surface;
    padding: 0 1;
}

#status-label {
    width: 1fr;
    content-align: left middle;
    padding: 0 1;
}

#rec-time {
    width: auto;
    content-align: right middle;
    padding: 0 1;
    color: $error;
}

#session-list {
    height: 100%;
    border: solid $primary;
    border-title-color: $primary;
}

#detail-panel {
    height: 100%;
    border: solid $secondary;
    border-title-color: $secondary;
}

#bottom-bar {
    column-span: 2;
    height: 3;
    background: $surface;
    padding: 0 1;
}

Button {
    margin: 0 1;
    min-width: 12;
}

Button.recording {
    background: $error;
}

DataTable {
    height: 100%;
}

RichLog {
    height: 100%;
}
"""


class MeetingApp(App):
    CSS = STYLES
    TITLE = "Hlopya"
    BINDINGS = [
        Binding("r", "toggle_recording", "Record"),
        Binding("p", "process_selected", "Process"),
        Binding("t", "transcribe_selected", "Transcribe"),
        Binding("l", "refresh_list", "Refresh"),
        Binding("q", "quit", "Quit"),
    ]

    def __init__(self):
        super().__init__()
        self.config = load_config()
        self.recorder = None
        self.recording = False
        self.rec_start_time = None
        self.selected_session = None

    def compose(self) -> ComposeResult:
        yield Header()

        with Horizontal(id="top-bar"):
            yield Button("Record", id="btn-record", variant="success")
            yield Button("Process", id="btn-process", variant="primary")
            yield Button("Refresh", id="btn-refresh", variant="default")
            yield Label("Ready", id="status-label")
            yield Label("", id="rec-time")

        with Container(id="session-list"):
            table = DataTable(id="sessions-table")
            table.border_title = "Sessions"
            yield table

        with Container(id="detail-panel"):
            log = RichLog(id="detail-log", highlight=True, markup=True)
            log.border_title = "Details"
            yield log

        yield Footer()

    def on_mount(self) -> None:
        table = self.query_one("#sessions-table", DataTable)
        table.add_columns("Session", "Duration", "Status", "Title")
        table.cursor_type = "row"
        self.refresh_sessions()

    def refresh_sessions(self) -> None:
        table = self.query_one("#sessions-table", DataTable)
        table.clear()
        sessions = get_sessions(self.config)
        for s in sessions:
            table.add_row(
                s["id"],
                format_duration(s["duration"]),
                format_status(s["status"]),
                s["title"][:40] if s["title"] else "-",
                key=s["id"],
            )

    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        session_id = str(event.row_key.value)
        self.selected_session = session_id
        self.show_session_details(session_id)

    def show_session_details(self, session_id: str) -> None:
        log = self.query_one("#detail-log", RichLog)
        log.clear()

        output_dir = Path(os.path.expanduser(
            self.config.get("audio", {}).get("output_dir", "~/recordings")
        ))
        session_dir = output_dir / session_id

        log.write(f"[bold]Session:[/bold] {session_id}")
        log.write("")

        # Show files
        for f in ["mic.wav", "system.wav", "transcript.md", "transcript.json", "notes.json"]:
            fp = session_dir / f
            exists = "[green]exists[/green]" if fp.exists() else "[red]missing[/red]"
            log.write(f"  {f}: {exists}")

        # Show transcript if available
        transcript_md = session_dir / "transcript.md"
        if transcript_md.exists():
            log.write("")
            log.write("[bold cyan]--- Transcript ---[/bold cyan]")
            log.write("")
            content = transcript_md.read_text()
            for line in content.split("\n")[:100]:
                log.write(line)
            if content.count("\n") > 100:
                log.write(f"\n... ({content.count(chr(10)) - 100} more lines)")

        # Show notes if available
        notes_json = session_dir / "notes.json"
        if notes_json.exists():
            log.write("")
            log.write("[bold green]--- Notes ---[/bold green]")
            log.write("")
            try:
                with open(notes_json) as f:
                    notes = json.load(f)

                if notes.get("title"):
                    log.write(f"[bold]{notes['title']}[/bold]")
                if notes.get("summary"):
                    log.write(f"\n{notes['summary']}")
                if notes.get("decisions"):
                    log.write("\n[bold]Decisions:[/bold]")
                    for d in notes["decisions"]:
                        log.write(f"  - {d}")
                if notes.get("action_items"):
                    log.write("\n[bold]Action Items:[/bold]")
                    for item in notes["action_items"]:
                        deadline = f" (due: {item['deadline']})" if item.get("deadline") else ""
                        log.write(f"  - [{item.get('owner', '?')}] {item.get('task', '')}{deadline}")
            except Exception as e:
                log.write(f"Error reading notes: {e}")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-record":
            self.action_toggle_recording()
        elif event.button.id == "btn-process":
            self.action_process_selected()
        elif event.button.id == "btn-refresh":
            self.action_refresh_list()

    def action_toggle_recording(self) -> None:
        if not self.recording:
            self.start_recording()
        else:
            self.stop_recording()

    def start_recording(self) -> None:
        from recorder import MeetingRecorder

        status = self.query_one("#status-label", Label)
        btn = self.query_one("#btn-record", Button)
        rec_time = self.query_one("#rec-time", Label)

        try:
            self.recorder = MeetingRecorder(self.config)
            ready, msg = self.recorder.check_ready()
            if not ready:
                status.update(f"[red]{msg}[/red]")
                return

            session_id = self.recorder.start()
            self.recording = True
            self.rec_start_time = time.time()
            btn.label = "Stop"
            btn.variant = "error"
            status.update(f"[red bold]RECORDING[/red bold] - {session_id}")
            self.update_rec_timer()
        except Exception as e:
            status.update(f"[red]Error: {e}[/red]")

    def stop_recording(self) -> None:
        status = self.query_one("#status-label", Label)
        btn = self.query_one("#btn-record", Button)
        rec_time = self.query_one("#rec-time", Label)

        try:
            result = self.recorder.stop()
            self.recording = False
            self.rec_start_time = None
            btn.label = "Record"
            btn.variant = "success"
            rec_time.update("")
            status.update(f"Saved: {result['session_id']} ({result['duration']:.0f}s)")
            self.refresh_sessions()

            # Auto-process if enabled
            if self.config.get("app", {}).get("auto_process", True):
                self.process_session_async(result)

        except Exception as e:
            status.update(f"[red]Stop error: {e}[/red]")

    @work(thread=True)
    def update_rec_timer(self) -> None:
        while self.recording and self.rec_start_time:
            elapsed = time.time() - self.rec_start_time
            m, s = divmod(int(elapsed), 60)
            self.call_from_thread(
                self.query_one("#rec-time", Label).update,
                f"[red bold]{m:02d}:{s:02d}[/red bold]"
            )
            time.sleep(1)

    def action_process_selected(self) -> None:
        if not self.selected_session:
            self.query_one("#status-label", Label).update("[yellow]Select a session first[/yellow]")
            return

        output_dir = Path(os.path.expanduser(
            self.config.get("audio", {}).get("output_dir", "~/recordings")
        ))
        session_dir = output_dir / self.selected_session

        result = {
            "session_id": self.selected_session,
            "mic_path": str(session_dir / "mic.wav"),
            "sys_path": str(session_dir / "system.wav"),
            "duration": 0,
        }
        self.process_session_async(result)

    def action_transcribe_selected(self) -> None:
        if not self.selected_session:
            self.query_one("#status-label", Label).update("[yellow]Select a session first[/yellow]")
            return

        output_dir = Path(os.path.expanduser(
            self.config.get("audio", {}).get("output_dir", "~/recordings")
        ))
        session_dir = output_dir / self.selected_session

        result = {
            "session_id": self.selected_session,
            "mic_path": str(session_dir / "mic.wav"),
            "sys_path": str(session_dir / "system.wav"),
            "duration": 0,
        }
        self.transcribe_session_async(result)

    @work(thread=True)
    def process_session_async(self, result: dict) -> None:
        self.call_from_thread(
            self.query_one("#status-label", Label).update,
            f"[cyan]Processing {result['session_id']}...[/cyan]"
        )
        log = self.query_one("#detail-log", RichLog)
        self.call_from_thread(log.clear)

        try:
            self.call_from_thread(log.write, "[bold]Starting transcription...[/bold]")

            from transcriber import Transcriber
            from noter import MeetingNoter

            # Transcribe
            transcriber = Transcriber(self.config)
            self.call_from_thread(log.write, f"Model: {transcriber.primary}")
            self.call_from_thread(log.write, f"Mic: {result['mic_path']}")
            self.call_from_thread(log.write, f"System: {result['sys_path']}")
            self.call_from_thread(log.write, "")

            transcript = transcriber.transcribe_meeting(
                result["mic_path"],
                result["sys_path"],
            )
            session_dir = Path(result["mic_path"]).parent
            transcriber.save_transcript(transcript, str(session_dir / "transcript"))

            self.call_from_thread(log.write, f"\n[green]Transcription done: {transcript['num_segments']} segments[/green]")

            # Generate notes
            self.call_from_thread(log.write, "\n[bold]Generating notes with Claude...[/bold]")
            noter = MeetingNoter(self.config)
            notes = noter.generate_notes(transcript, session_dir=str(session_dir))

            notes_path = session_dir / "notes.json"
            with open(notes_path, "w") as f:
                json.dump(notes, f, ensure_ascii=False, indent=2)

            self.call_from_thread(log.write, f"\n[green bold]Done![/green bold]")
            self.call_from_thread(log.write, f"Title: {notes.get('title', '?')}")

            if notes.get("action_items"):
                self.call_from_thread(log.write, f"\nAction items ({len(notes['action_items'])}):")
                for item in notes["action_items"]:
                    self.call_from_thread(log.write, f"  - [{item.get('owner', '?')}] {item.get('task', '')}")

            self.call_from_thread(
                self.query_one("#status-label", Label).update,
                f"[green]Done: {notes.get('title', result['session_id'])}[/green]"
            )
            self.call_from_thread(self.refresh_sessions)

        except Exception as e:
            self.call_from_thread(log.write, f"\n[red bold]Error: {e}[/red bold]")
            self.call_from_thread(
                self.query_one("#status-label", Label).update,
                f"[red]Error: {str(e)[:60]}[/red]"
            )

    @work(thread=True)
    def transcribe_session_async(self, result: dict) -> None:
        self.call_from_thread(
            self.query_one("#status-label", Label).update,
            f"[cyan]Transcribing {result['session_id']}...[/cyan]"
        )
        log = self.query_one("#detail-log", RichLog)
        self.call_from_thread(log.clear)

        try:
            from transcriber import Transcriber

            transcriber = Transcriber(self.config)
            self.call_from_thread(log.write, f"[bold]Transcribing with {transcriber.primary}...[/bold]")

            transcript = transcriber.transcribe_meeting(
                result["mic_path"],
                result["sys_path"],
            )
            session_dir = Path(result["mic_path"]).parent
            transcriber.save_transcript(transcript, str(session_dir / "transcript"))

            self.call_from_thread(log.write, f"\n[green bold]Done! {transcript['num_segments']} segments[/green bold]")
            self.call_from_thread(
                self.query_one("#status-label", Label).update,
                f"[green]Transcribed: {result['session_id']}[/green]"
            )
            self.call_from_thread(self.refresh_sessions)

        except Exception as e:
            self.call_from_thread(log.write, f"\n[red bold]Error: {e}[/red bold]")
            self.call_from_thread(
                self.query_one("#status-label", Label).update,
                f"[red]Error: {str(e)[:60]}[/red]"
            )

    def action_refresh_list(self) -> None:
        self.refresh_sessions()
        self.query_one("#status-label", Label).update("Refreshed")

    def action_quit(self) -> None:
        if self.recording and self.recorder:
            self.recorder.stop()
        self.exit()


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CLI
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


def process_recording(session_result: dict, config: dict, meta: dict | None = None):
    """Full pipeline: transcribe + generate notes."""
    from transcriber import Transcriber
    from noter import MeetingNoter

    print(f"\n{'='*60}")
    print(f"Processing recording: {session_result['session_id']}")
    print(f"{'='*60}\n")

    transcriber = Transcriber(config)
    transcript = transcriber.transcribe_meeting(
        session_result["mic_path"],
        session_result["sys_path"],
    )
    session_dir = Path(session_result["mic_path"]).parent
    transcriber.save_transcript(transcript, str(session_dir / "transcript"))

    noter = MeetingNoter(config)
    notes = noter.generate_notes(transcript, meta, session_dir=str(session_dir))

    notes_path = session_dir / "notes.json"
    with open(notes_path, "w") as f:
        json.dump(notes, f, ensure_ascii=False, indent=2)

    tasks = noter.format_action_items_for_tasks(notes)

    print(f"\n{'='*60}")
    print("COMPLETE")
    print(f"  Transcript: {session_dir / 'transcript.md'}")
    print(f"  Notes: {notes_path}")
    print(f"  Action items: {len(tasks)}")
    for t in tasks:
        print(f"    - {t['title']}")
    print(f"{'='*60}\n")

    return {"transcript": transcript, "notes": notes, "tasks": tasks}


def run_cli():
    """CLI commands."""
    import argparse

    parser = argparse.ArgumentParser(description="Hlopya")
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("record", help="Record a meeting (Ctrl+C to stop)")

    sub.add_parser("list", help="List recording sessions")

    proc = sub.add_parser("process", help="Transcribe + generate notes")
    proc.add_argument("session_dir", help="Path to session directory")
    proc.add_argument("--title", help="Meeting title")
    proc.add_argument("--participants", help="Comma-separated names")

    tr = sub.add_parser("transcribe", help="Transcribe only")
    tr.add_argument("session_dir", help="Path to session directory")

    args = parser.parse_args()
    config = load_config()

    if args.command == "record":
        from recorder import MeetingRecorder
        recorder = MeetingRecorder(config)
        ready, msg = recorder.check_ready()
        if not ready:
            print(f"Error: {msg}")
            return

        try:
            session_id = recorder.start()
            print(f"Recording: {session_id}")
            print("Press Ctrl+C to stop.")
            while recorder.is_recording:
                time.sleep(0.5)
        except KeyboardInterrupt:
            print("\nStopping...")
        finally:
            if recorder.is_recording:
                result = recorder.stop()
                print(f"Duration: {result['duration']:.1f}s")
                print(f"To process: python app.py process {Path(result['mic_path']).parent}")

    elif args.command == "list":
        sessions = get_sessions(config)
        if not sessions:
            print("No recordings found.")
            return
        print(f"{'Session':<24} {'Duration':>8} {'Status':<12} {'Title'}")
        print("-" * 70)
        for s in sessions:
            status = {"recorded": "REC", "transcribed": "STT", "noted": "DONE"}.get(s["status"], "?")
            print(f"{s['id']:<24} {format_duration(s['duration']):>8} {status:<12} {s['title'][:30] or '-'}")

    elif args.command == "process":
        session_dir = Path(args.session_dir)
        meta = {}
        if hasattr(args, "title") and args.title:
            meta["title"] = args.title
        if hasattr(args, "participants") and args.participants:
            meta["participants"] = args.participants.split(",")

        result = {
            "session_id": session_dir.name,
            "mic_path": str(session_dir / "mic.wav"),
            "sys_path": str(session_dir / "system.wav"),
            "duration": 0,
        }
        process_recording(result, config, meta)

    elif args.command == "transcribe":
        from transcriber import Transcriber
        session_dir = Path(args.session_dir)
        transcriber = Transcriber(config)
        transcript = transcriber.transcribe_meeting(
            str(session_dir / "mic.wav"),
            str(session_dir / "system.wav"),
        )
        transcriber.save_transcript(transcript, str(session_dir / "transcript"))

    else:
        parser.print_help()


if __name__ == "__main__":
    if len(sys.argv) > 1:
        run_cli()
    else:
        app = MeetingApp()
        app.run()
