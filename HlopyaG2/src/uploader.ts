import type { PendingRecording } from './store'

export type UploadSettings = { serverURL: string; token: string }

// Same contract as HlopyaWatch/KlavaUploader.swift: multipart POST with a
// `file` part plus title/source/recorded_at. Klava turns it into
// ~/recordings/<session>/mic.wav and the Mac app picks it up from there.
// `speaker_roles` is extra: the glasses' per-frame Me/Them guess, which Klava
// can ignore today and use later for diarization.
export async function upload(rec: PendingRecording, settings: UploadSettings): Promise<string> {
  const form = new FormData()
  form.append('title', rec.title || 'G2 Recording')
  form.append('source', 'even-g2')
  form.append('recorded_at', rec.recordedAt)
  form.append('speaker_roles', JSON.stringify(rec.segments))
  form.append('file', rec.wav, `${rec.id}.wav`)

  const headers: Record<string, string> = {}
  if (settings.token.trim()) headers.Authorization = `Bearer ${settings.token.trim()}`

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 120_000)
  try {
    const response = await fetch(settings.serverURL.trim(), {
      method: 'POST',
      body: form,
      headers,
      signal: controller.signal,
    })
    const text = await response.text()
    if (!response.ok) throw new Error(`Upload failed ${response.status}: ${text}`)
    return text || 'Uploaded'
  } finally {
    clearTimeout(timeout)
  }
}
