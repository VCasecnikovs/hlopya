# Hlopya for Even G2

Records a conversation through the Even Realities G2 microphones and sends it to
Hlopya on your Mac, the same way the Apple Watch app does (see
[`docs/watch-mvp.md`](../docs/watch-mvp.md)).

Flow:

1. The glasses stream 16 kHz mono PCM to this Even Hub web app on the phone.
2. On stop, the app wraps it in a WAV and POSTs it to Klava at
   `/api/hlopya/watch/upload` (`file`, `title`, `recorded_at`, `source=even-g2`).
3. Klava writes `~/recordings/<session>/mic.wav`; Hlopya on the Mac transcribes
   it and writes notes as usual.

Extra field: `speaker_roles` is a JSON list of `{role, start, end}` segments
(seconds) built from the Even app's per-frame `speakerRole` (`self` / `other`).
Klava can ignore it today; it is there so Me/Them diarization can use it later.

Recordings that fail to upload stay in IndexedDB on the phone and are retried
on next launch, after the next recording, or with **Send pending**.

## On the glasses

- Tap the temple (or R1 ring): start / stop. Stop sends immediately.
- Contextual menu: *Start / stop*, *Send pending*, *Discard recording*.
- Screen shows the timer and whether you or the other person is speaking.

## Develop

```bash
cd HlopyaG2
npm install
npm run dev        # Vite on :5173
npm run qr         # scan in the Even app (dev mode) to sideload
npm run pack       # builds dist/ and hlopya-g2.ehpk
```

Private install without store review: `npx evenhub login`, then
`npx evenhub create hlopya-g2.ehpk --name Hlopya --tagline "Meeting notes from your glasses"`
and put the build on the beta channel.

## Network

Even Hub only lets the app reach hosts listed in `app.json` →
`permissions[network].whitelist`. It is set to the Klava Tailscale address used
by the Watch app (`http://100.82.35.56:18788`). The phone must be on the tailnet.
If you change the server URL in the app's settings, add the new origin to the
whitelist and repack. If the Even app refuses plain `http`, expose Klava over
HTTPS with `tailscale serve` and use the `https://<mac>.<tailnet>.ts.net` URL.

## Limits

- Audio is held in memory until stop: about 115 MB per hour of recording.
- Only what the glasses hear is recorded (no phone call audio).
- Untested on hardware yet; `npm run build` and `evenhub pack` pass.
