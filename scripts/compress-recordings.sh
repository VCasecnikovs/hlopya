#!/usr/bin/env bash
# Transcode session WAVs to AAC/.m4a in place.
#
# Live capture writes raw WAV (crash-recoverable). This reclaims the space
# afterwards: 16kHz mono speech goes from 256kbps PCM to 32kbps AAC (~8x).
# AVAudioFile decodes .m4a natively, so Hlopya reads either form via SessionAudio.
#
# The source WAV is only replaced after the encode is verified: the .m4a must
# open through CoreAudio and its duration must match within DUR_TOL seconds.
set -uo pipefail

ROOT="${1:-$HOME/recordings}"
JOBS="${JOBS:-6}"
DUR_TOL="${DUR_TOL:-0.25}"
DRY="${DRY:-0}"
MIN_AGE_MIN="${MIN_AGE_MIN:-60}"
LOG="${LOG:-/tmp/hlopya-compress.log}"

command -v ffmpeg >/dev/null || { echo "ffmpeg required"; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe required"; exit 1; }

dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null; }

convert_one() {
  local wav="$1" tol="$2" dry="$3" minage="$4"
  local m4a="${wav%.wav}.m4a"

  [ -f "$m4a" ] && { echo "SKIP-EXISTS $wav"; return 0; }

  # Never touch a file the recorder may still be appending to: a live capture
  # would be truncated mid-meeting and the WAV removed.
  local mtime now age
  mtime=$(stat -f%m "$wav" 2>/dev/null) || { echo "FAIL-UNREADABLE $wav"; return 1; }
  now=$(date +%s); age=$(( (now - mtime) / 60 ))
  [ "$age" -lt "$minage" ] && { echo "SKIP-ACTIVE $wav (${age}m old)"; return 0; }

  local ch sd
  ch=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$wav" 2>/dev/null)
  [ -z "$ch" ] && { echo "FAIL-UNREADABLE $wav"; return 1; }
  sd=$(dur "$wav"); [ -z "$sd" ] && { echo "FAIL-NODUR $wav"; return 1; }

  # 32kbps is transparent enough for 16kHz speech re-transcription; scale for stereo.
  local br=$((32 * ch))

  if [ "$dry" = "1" ]; then echo "DRY $wav (${ch}ch ${br}k)"; return 0; fi

  local tmp="${m4a}.partial"
  # -f ipod: the temp name ends in .partial, so the muxer cannot be inferred.
  if ! ffmpeg -y -loglevel error -i "$wav" -c:a aac -b:a "${br}k" -ar 16000 -ac "$ch" -f ipod "$tmp" 2>/dev/null; then
    rm -f "$tmp"; echo "FAIL-ENCODE $wav"; return 1
  fi

  # Verify: CoreAudio must decode it (the same stack AVAudioFile uses).
  if ! afinfo "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"; echo "FAIL-COREAUDIO $wav"; return 1
  fi

  local md delta
  md=$(dur "$tmp")
  [ -z "$md" ] && { rm -f "$tmp"; echo "FAIL-NOOUTDUR $wav"; return 1; }
  delta=$(awk -v a="$sd" -v b="$md" 'BEGIN{d=a-b; if(d<0)d=-d; print d}')
  if awk -v d="$delta" -v t="$tol" 'BEGIN{exit !(d>t)}'; then
    rm -f "$tmp"; echo "FAIL-DURATION $wav (delta ${delta}s)"; return 1
  fi

  mv "$tmp" "$m4a"
  local ws ms
  ws=$(stat -f%z "$wav"); ms=$(stat -f%z "$m4a")
  rm -f "$wav"
  echo "OK $wav ${ws} -> ${ms}"
}
export -f convert_one dur

echo "=== hlopya compress: root=$ROOT jobs=$JOBS dry=$DRY min_age=${MIN_AGE_MIN}m ===" | tee "$LOG"
find "$ROOT" -name '*.wav' -print0 \
  | xargs -0 -P "$JOBS" -I{} bash -c 'convert_one "$@"' _ {} "$DUR_TOL" "$DRY" "$MIN_AGE_MIN" \
  | tee -a "$LOG"

echo "--- summary ---" | tee -a "$LOG"
for k in OK SKIP-EXISTS SKIP-ACTIVE DRY FAIL-ENCODE FAIL-COREAUDIO FAIL-DURATION FAIL-UNREADABLE FAIL-NODUR FAIL-NOOUTDUR; do
  n=$(grep -c "^$k " "$LOG" 2>/dev/null) || n=0
  [ "$n" -gt 0 ] && echo "$k: $n" | tee -a "$LOG"
done
awk '/^OK /{w+=$(NF-2); m+=$NF} END{if(w)printf "reclaimed: %.2f GB (%.2f -> %.2f GB, %.1fx)\n",(w-m)/1073741824,w/1073741824,m/1073741824,w/m}' "$LOG" | tee -a "$LOG"
