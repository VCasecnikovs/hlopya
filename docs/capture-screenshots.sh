#!/usr/bin/env bash
# Capture README screenshots non-interactively (no clicking required).
# Run from repo root: bash docs/capture-screenshots.sh
#
# Requires:
#   - Hlopya installed in /Applications
#   - jq (brew install jq)
#   - Screen Recording permission for your terminal
#     (System Settings → Privacy & Security → Screen Recording)

set -e

OUT="docs/images"
mkdir -p "$OUT"

say() { printf "\n\033[1;36m▸ %s\033[0m\n" "$1"; }
pause() { printf "   …press Enter when ready"; read -r _; }

# --- helpers ---------------------------------------------------------------

focus_hlopya() {
  osascript -e 'tell application "Hlopya" to activate' >/dev/null 2>&1
  sleep 0.6
}

hlopya_window_id() {
  # Largest on-screen window owned by Hlopya, by area
  osascript <<'OSA' 2>/dev/null
    use framework "Foundation"
    use framework "AppKit"
    use framework "CoreGraphics"
    set windowList to (current application's CGWindowListCopyWindowInfo(((current application's kCGWindowListOptionOnScreenOnly) as integer) + ((current application's kCGWindowListExcludeDesktopElements) as integer), 0)) as list
    set bestId to 0
    set bestArea to 0
    repeat with w in windowList
      try
        set ownerName to (w's valueForKey:"kCGWindowOwnerName") as text
        if ownerName is "Hlopya" then
          set wid to (w's valueForKey:"kCGWindowNumber") as integer
          set bounds to (w's valueForKey:"kCGWindowBounds")
          set wWidth to (bounds's valueForKey:"Width") as real
          set wHeight to (bounds's valueForKey:"Height") as real
          set area to wWidth * wHeight
          if area > bestArea and wWidth > 200 and wHeight > 200 then
            set bestArea to area
            set bestId to wid
          end if
        end if
      end try
    end repeat
    return bestId
OSA
}

shoot() {
  local outfile="$1"
  focus_hlopya
  local wid
  wid=$(hlopya_window_id | tr -d '[:space:]')
  if [[ -z "$wid" || "$wid" == "0" ]]; then
    echo "   ✗ no Hlopya window found — open the main window (⌘O from menu bar)"
    return 1
  fi
  /usr/sbin/screencapture -o -x -l "$wid" -t png "$outfile"
  echo "   ✓ saved $outfile (window id $wid)"
}

# --- run -------------------------------------------------------------------

# Make sure Hlopya is running with its main window open
open -a Hlopya
sleep 2
focus_hlopya

say "1/3  HERO — main window with a session that has notes + transcript"
echo "   In Hlopya: pick a session that has both AI notes AND transcript visible."
echo "   Resize window to ~900×650 if you can. Don't switch back to Terminal."
pause
shoot "$OUT/hero.png"

say "2/3  NOTES — same window, switch to the My Notes / Enhanced tab"
echo "   Click on the 'My Notes' or 'Enhanced' tab so the AI notes are visible."
pause
shoot "$OUT/notes.png"

say "3/3  TRANSCRIPT — same window, scroll the transcript into view"
echo "   Scroll down so the diarized transcript section is centered."
pause
shoot "$OUT/transcript.png"

echo
echo "Done. Commit:"
echo "   git add docs/images && git commit -m 'docs: refresh README screenshots' && git push"
