# Hlopya Watch MVP

Direct-to-Klava Apple Watch recorder.

Flow:

1. Watch records one AAC `.m4a` microphone track.
2. When recording stops, Watch uploads it as multipart form data to Klava:
   `POST /api/hlopya/watch/upload`
3. Klava converts it to `~/recordings/<session>/mic.wav`, creates a silent
   `system.wav`, and writes `meta.json`.
4. Mac Hlopya sees the session and can process it with the existing pipeline.

Default upload URL uses this Mac's Tailscale IPv4:

```text
http://100.82.35.56:18788/api/hlopya/watch/upload
```

The Klava watch upload endpoint is exempted from dashboard bearer auth, so leave
the Token field empty for this MVP.

Limitations:

- This records ambient watch microphone audio, not internal iPhone call audio.
- The MVP records in the foreground. Long background recordings need a dedicated
  extended-runtime pass.
- Apple Watch does not run this Mac's Tailscale node. This works only when
  watchOS can route the request through a path that reaches the tailnet endpoint,
  typically via the paired iPhone with Tailscale/VPN active.
- If direct watch upload cannot reach `100.82.35.56`, add an iPhone relay with
  WatchConnectivity.
