"""
Meeting notes generator using Claude CLI (claude -p).
Takes transcript and produces structured meeting notes.
"""

import os
import json
import subprocess
from pathlib import Path
from datetime import datetime


SYSTEM_PROMPT = """You are a meeting notes assistant. You receive a diarized transcript and the user's personal notes taken during the meeting.

Your job: produce structured meeting notes that INTEGRATE the user's personal notes as the backbone. The user's original notes should be preserved verbatim and highlighted, with AI-generated context enriching around them.

## Output Format (JSON)

Return ONLY a valid JSON object (no markdown fences, no extra text) with these fields:

{
  "title": "Short meeting title",
  "date": "YYYY-MM-DD",
  "participants": ["Name 1", "Name 2"],
  "summary": "2-3 sentence summary of what was discussed and decided",
  "enriched_notes": "Markdown string - see rules below",
  "topics": [
    {"topic": "Topic name", "details": "Key points discussed"}
  ],
  "decisions": ["Decision 1", "Decision 2"],
  "action_items": [
    {
      "owner": "Person name",
      "task": "What needs to be done",
      "deadline": "YYYY-MM-DD or null",
      "context": "Why this matters, full context for the task"
    }
  ],
  "insights": ["Key insight 1", "Key insight 2"],
  "follow_ups": ["Suggested follow-up 1", "Suggested follow-up 2"]
}

## enriched_notes Rules (CRITICAL - this is the main output)

The enriched_notes field is a markdown string that merges the user's notes with transcript context:

1. Each line from the user's personal notes becomes a **bold** line (wrapped in **)
2. Below each user note, add 1-3 lines of AI context from the transcript - details, numbers, quotes, who said what
3. If the user wrote nothing, create the enriched notes purely from the transcript
4. Group related notes under topic headers (## headers)
5. Add topics from the transcript that the user DIDN'T note (mark these sections without bold)
6. Preserve the user's note ordering - don't rearrange

Example enriched_notes format:
"## Product Discussion\\n\\n**Need to decide on pricing by Friday**\\nDuring the call, Alex proposed $50/month for the basic tier. Maria pushed back suggesting $35 to match competitor X. Team agreed to finalize by EOW.\\n\\n**Check competitor pricing**\\nAlex mentioned that competitor X just launched at $35/mo. Maria confirmed she saw their announcement.\\n\\n## Timeline\\n\\nThe team discussed launching in Q2. No specific date was set but Alex suggested April 15 as a target."

## Other Rules
- Extract EVERY actionable commitment from the meeting
- Make action items self-contained (enough context to act without re-reading transcript)
- Note numbers: pricing, volumes, timelines, team sizes
- Note relationship dynamics and who knows whom
- Flag any deadlines or time-sensitive items
- Language: Use the same language as the meeting transcript
- Return ONLY the JSON object, nothing else
"""


class MeetingNoter:
    def __init__(self, config: dict):
        notes_cfg = config.get("notes", {})
        self.model = notes_cfg.get("model", "claude-sonnet-4-5-20250929")
        self.output_dir = Path(os.path.expanduser(
            notes_cfg.get("output_dir", "~/meeting-notes")
        ))
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.owner_name = notes_cfg.get("owner_name", "me")

    def generate_notes(self, transcript: dict, meeting_meta: dict | None = None, session_dir: str | None = None) -> dict:
        """
        Generate structured notes from transcript using claude -p.
        transcript: output from Transcriber.transcribe_meeting()
        meeting_meta: optional dict with title, participants, date overrides
        session_dir: path to session directory (to read personal_notes.md)
        """
        meta = meeting_meta or {}

        # Load personal notes if available
        personal_notes = ""
        if session_dir:
            pn_path = Path(session_dir) / "personal_notes.md"
            if pn_path.exists():
                personal_notes = pn_path.read_text().strip()

        personal_section = ""
        if personal_notes:
            personal_section = f"""
## User's Personal Notes (CRITICAL - these form the backbone of enriched_notes)

Each line below was written by the user during the meeting. Preserve ALL of them as **bold** lines in enriched_notes, in order. Enrich each with context from the transcript.

```
{personal_notes}
```
"""
        else:
            personal_section = """
## User's Personal Notes

(No personal notes were taken. Generate enriched_notes purely from the transcript.)
"""

        prompt = f"""{SYSTEM_PROMPT}

## Meeting Info

Date: {meta.get('date', datetime.now().strftime('%Y-%m-%d'))}
Title: {meta.get('title', 'Meeting')}
Known participants: {', '.join(meta.get('participants', ['Me', 'Them']))}
{personal_section}
## Transcript

{transcript['full_text']}
"""
        print(f"Generating notes with claude -p (model: {self.model})...")

        # Remove CLAUDECODE env var to avoid nested session error
        env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}

        result = subprocess.run(
            ["claude", "-p", "--model", self.model, "--output-format", "text"],
            input=prompt,
            capture_output=True,
            text=True,
            timeout=300,
            env=env,
        )

        if result.returncode != 0:
            raise RuntimeError(f"claude -p failed (code {result.returncode}): {result.stderr}")

        text = result.stdout.strip()

        # Try to extract JSON from markdown code block if present
        if "```json" in text:
            text = text.split("```json")[1].split("```")[0]
        elif "```" in text:
            text = text.split("```")[1].split("```")[0]

        try:
            notes = json.loads(text)
        except json.JSONDecodeError:
            print(f"Warning: Could not parse JSON response. Raw text saved.")
            notes = {"raw_text": text, "parse_error": True}

        notes["model_used"] = self.model
        notes["transcript_stats"] = {
            "segments": transcript.get("num_segments", 0),
            "duration": transcript.get("duration_seconds", 0),
            "stt_model": transcript.get("model_used", "unknown"),
        }

        return notes

    def format_action_items_for_tasks(self, notes: dict) -> list[dict]:
        """Format action items owned by the user."""
        items = notes.get("action_items", [])
        title = notes.get("title", "Meeting")
        owner = self.owner_name.lower()
        tasks = []
        for item in items:
            item_owner = (item.get("owner") or "").lower()
            if item_owner in (owner, "me", "i"):
                tasks.append({
                    "title": f"{title}: {item['task'][:80]}",
                    "notes": item.get("context", item["task"]),
                    "due": item.get("deadline"),
                })
        return tasks


def cli():
    """CLI: generate notes from transcript JSON."""
    import sys
    import yaml

    if len(sys.argv) < 2:
        print("Usage: python noter.py <transcript.json> [--title 'Meeting Title'] [--participants 'A,B']")
        sys.exit(1)

    transcript_path = Path(sys.argv[1])
    with open(transcript_path) as f:
        transcript = json.load(f)

    config_path = Path(__file__).parent / "config.yaml"
    if config_path.exists():
        with open(config_path) as f:
            config = yaml.safe_load(f)
    else:
        config = {}

    # Parse optional args
    meta = {}
    args = sys.argv[2:]
    for i, arg in enumerate(args):
        if arg == "--title" and i + 1 < len(args):
            meta["title"] = args[i + 1]
        elif arg == "--participants" and i + 1 < len(args):
            meta["participants"] = args[i + 1].split(",")

    noter = MeetingNoter(config)
    notes = noter.generate_notes(transcript, meta)

    # Show action items
    tasks = noter.format_action_items_for_tasks(notes)
    if tasks:
        print(f"\nAction items ({len(tasks)}):")
        for t in tasks:
            print(f"  - {t['title']}")

    # Save notes JSON
    notes_json = transcript_path.parent / "notes.json"
    with open(notes_json, "w") as f:
        json.dump(notes, f, ensure_ascii=False, indent=2)
    print(f"Notes JSON: {notes_json}")


if __name__ == "__main__":
    cli()
