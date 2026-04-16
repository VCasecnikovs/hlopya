#!/usr/bin/env bash
# Capture all README screenshots in one shot.
# Run from repo root: bash docs/capture-screenshots.sh
#
# Requires: Hlopya installed in /Applications, screen-recording permission
# granted to your terminal (System Settings → Privacy & Security → Screen Recording).

set -e

OUT="docs/images"
mkdir -p "$OUT"

say() { printf "\n\033[1;36m▸ %s\033[0m\n" "$1"; }
pause() { printf "   …press Enter when ready"; read -r _; }

# Make sure Hlopya is running
open -a Hlopya
sleep 2
osascript -e 'tell application "Hlopya" to activate'
sleep 1

say "1/5  HERO — main window with a session selected"
echo "   Resize the window to ~900×650, pick a session that has notes + transcript."
pause
/usr/sbin/screencapture -o -x -t png -W "$OUT/hero.png"
echo "   ✓ saved $OUT/hero.png"

say "2/5  MAIN — sessions list (sidebar focused)"
echo "   Click any session in the sidebar so the list is visible."
pause
/usr/sbin/screencapture -o -x -t png -W "$OUT/main.png"
echo "   ✓ saved $OUT/main.png"

say "3/5  TRANSCRIPT view"
echo "   Open a session → switch to the Transcript tab."
pause
/usr/sbin/screencapture -o -x -t png -W "$OUT/transcript.png"
echo "   ✓ saved $OUT/transcript.png"

say "4/5  NOTES view"
echo "   Same session → switch to the Notes tab (must have AI notes generated)."
pause
/usr/sbin/screencapture -o -x -t png -W "$OUT/notes.png"
echo "   ✓ saved $OUT/notes.png"

say "5/5  RECORDING NUB"
echo "   Start a recording (⌘R) — the floating nub will appear. Position cursor over it."
pause
/usr/sbin/screencapture -o -x -t png -W "$OUT/nub.png"
echo "   ✓ saved $OUT/nub.png"

say "BONUS  MENU BAR"
echo "   Click the mic icon in the menu bar to open the dropdown."
pause
/usr/sbin/screencapture -o -x -t png "$OUT/menubar.png"
echo "   ✓ saved $OUT/menubar.png"

echo
echo "Done. Commit:"
echo "   git add docs/images && git commit -m 'docs: add README screenshots'"
