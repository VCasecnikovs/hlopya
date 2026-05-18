# Hlopya Watch MVP

This is a direct-to-Klava Apple Watch recorder.

Flow:

1. Watch records one AAC `.m4a` microphone track.
2. Watch uploads it as multipart form data to Klava:
   `POST /api/hlopya/watch/upload`
3. Klava converts it to `~/recordings/<session>/mic.wav`, creates a silent
   `system.wav`, and writes `meta.json`.
4. Mac Hlopya sees the session and can process it with the existing pipeline.

The default upload URL is a placeholder. On the watch, open `Server` and set:

```text
http://<mac-hostname-or-lan-ip>:18788/api/hlopya/watch/upload
```

If Klava auth is enabled for non-loopback requests, paste the webhook bearer
token into the Token field.

Limitations:

- This records ambient watch microphone audio, not internal iPhone call audio.
- The first MVP records in foreground. Long background recordings still need a
  dedicated extended-runtime pass.
- The Klava webhook server must be reachable from the watch. A default
  localhost-only Klava listener is not reachable from Apple Watch.
