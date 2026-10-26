import { AudioSpeakerRole } from '@evenrealities/even_hub_sdk'

export const SAMPLE_RATE = 16_000
const BYTES_PER_SAMPLE = 2

export type RoleSegment = { role: 'self' | 'other' | 'unknown'; start: number; end: number }

// Collects the glasses' 16 kHz mono s16le frames and remembers which frames the
// Even app classified as the wearer ("self") vs everyone else ("other"), so the
// Mac side can later split Me/Them the way it does with mic.wav/system.wav.
export class PcmRecorder {
  private chunks: Uint8Array[] = []
  private byteCount = 0
  private segments: RoleSegment[] = []
  startedAt: Date | null = null

  get isRecording(): boolean {
    return this.startedAt !== null
  }

  get seconds(): number {
    return this.byteCount / BYTES_PER_SAMPLE / SAMPLE_RATE
  }

  start(): void {
    this.chunks = []
    this.byteCount = 0
    this.segments = []
    this.startedAt = new Date()
  }

  push(pcm: Uint8Array, role: AudioSpeakerRole): void {
    if (!this.isRecording || pcm.length === 0) return
    const start = this.seconds
    this.chunks.push(pcm.slice())
    this.byteCount += pcm.length
    this.addSegment(role, start, this.seconds)
  }

  stop(): { pcm: Uint8Array; segments: RoleSegment[]; startedAt: Date } | null {
    if (!this.startedAt) return null
    const pcm = new Uint8Array(this.byteCount)
    let offset = 0
    for (const chunk of this.chunks) {
      pcm.set(chunk, offset)
      offset += chunk.length
    }
    const result = { pcm, segments: this.segments, startedAt: this.startedAt }
    this.chunks = []
    this.byteCount = 0
    this.segments = []
    this.startedAt = null
    return result
  }

  private addSegment(role: AudioSpeakerRole, start: number, end: number): void {
    const name = role === AudioSpeakerRole.Self ? 'self' : role === AudioSpeakerRole.Other ? 'other' : 'unknown'
    const last = this.segments[this.segments.length - 1]
    if (last && last.role === name) {
      last.end = end
    } else {
      this.segments.push({ role: name, start, end })
    }
  }
}

export function encodeWav(pcm: Uint8Array, sampleRate = SAMPLE_RATE): Blob {
  const header = new DataView(new ArrayBuffer(44))
  const writeAscii = (offset: number, text: string) => {
    for (let i = 0; i < text.length; i++) header.setUint8(offset + i, text.charCodeAt(i))
  }
  writeAscii(0, 'RIFF')
  header.setUint32(4, 36 + pcm.length, true)
  writeAscii(8, 'WAVE')
  writeAscii(12, 'fmt ')
  header.setUint32(16, 16, true)
  header.setUint16(20, 1, true) // PCM
  header.setUint16(22, 1, true) // mono
  header.setUint32(24, sampleRate, true)
  header.setUint32(28, sampleRate * BYTES_PER_SAMPLE, true)
  header.setUint16(32, BYTES_PER_SAMPLE, true)
  header.setUint16(34, 16, true)
  writeAscii(36, 'data')
  header.setUint32(40, pcm.length, true)
  return new Blob([header.buffer, pcm as Uint8Array<ArrayBuffer>], { type: 'audio/wav' })
}
