import {
  AudioInputSource,
  OsEventTypeList,
  waitForEvenAppBridge,
  type EvenAppBridge,
} from '@evenrealities/even_hub_sdk'
import { createGlassesPage, isTap, MenuItem, updateGlasses, clock, type GlassesState } from './glasses'
import { encodeWav, PcmRecorder } from './recorder'
import { deletePending, listPending, savePending } from './store'
import { upload } from './uploader'

const DEFAULT_SERVER_URL = 'http://100.82.35.56:18788/api/hlopya/watch/upload'

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T
const serverInput = $<HTMLInputElement>('server')
const tokenInput = $<HTMLInputElement>('token')
const titleInput = $<HTMLInputElement>('title')
const toggleButton = $<HTMLButtonElement>('toggle')
const syncButton = $<HTMLButtonElement>('sync')
const statusLine = $<HTMLParagraphElement>('status')
const timerLine = $<HTMLParagraphElement>('timer')

const recorder = new PcmRecorder()
const state: GlassesState = { recording: false, seconds: 0, speaking: null, pending: 0, note: '' }
let bridge: EvenAppBridge | null = null
let syncing = false

async function main() {
  // Outside the Even app WebView the SDK still hands back a bridge whose calls
  // all fail, so check for the native handler directly.
  if (!('flutter_inappwebview' in window)) {
    setNote('Open this page from the Even app to use the glasses.')
    toggleButton.disabled = true
    return
  }
  bridge = await waitForEvenAppBridge()

  serverInput.value = (await bridge.getLocalStorage('serverURL')) || DEFAULT_SERVER_URL
  tokenInput.value = (await bridge.getLocalStorage('token')) || ''
  titleInput.value = (await bridge.getLocalStorage('title')) || 'G2 Recording'
  for (const [input, key] of [[serverInput, 'serverURL'], [tokenInput, 'token'], [titleInput, 'title']] as const) {
    input.addEventListener('change', () => bridge?.setLocalStorage(key, input.value))
  }

  bridge.onEvenHubEvent((event) => {
    const audio = event.audioEvent
    if (audio) {
      recorder.push(audio.audioPcm, audio.speakerRole)
      state.speaking = audio.speakerRole
      return
    }
    if (event.menuItemClickEvent) {
      const id = event.menuItemClickEvent.itemID
      if (id === MenuItem.Toggle) void toggle()
      if (id === MenuItem.Sync) void syncPending()
      if (id === MenuItem.Discard) void discard()
      return
    }
    const tap = event.textEvent ?? event.sysEvent
    if (tap) {
      const type = tap.eventType
      if (type === OsEventTypeList.ABNORMAL_EXIT_EVENT || type === OsEventTypeList.SYSTEM_EXIT_EVENT) {
        // Glasses app is going away: never lose what was captured so far.
        if (recorder.isRecording) void stop()
        return
      }
      if (isTap(type) && event.textEvent) void toggle()
    }
  })

  await refreshPending()
  if (!(await createGlassesPage(bridge, state))) setNote('Could not open the glasses screen.')

  toggleButton.addEventListener('click', () => void toggle())
  syncButton.addEventListener('click', () => void syncPending())
  setInterval(tick, 1000)
  void syncPending()
}

async function toggle() {
  if (recorder.isRecording) await stop()
  else await start()
}

async function start() {
  if (!bridge) return
  recorder.start()
  const ok = await bridge.audioControl(true, AudioInputSource.Glasses)
  if (!ok) {
    recorder.stop()
    setNote('Glasses mic did not start.')
    return
  }
  state.recording = true
  setNote('')
}

async function stop() {
  if (!bridge) return
  await bridge.audioControl(false)
  const captured = recorder.stop()
  state.recording = false
  state.speaking = null
  if (!captured || captured.pcm.length === 0) {
    setNote('Nothing was recorded.')
    return render()
  }
  const id = captured.startedAt.toISOString().replace(/[:.]/g, '-')
  await savePending({
    id,
    title: titleInput.value.trim(),
    recordedAt: captured.startedAt.toISOString(),
    seconds: captured.pcm.length / 2 / 16_000,
    wav: encodeWav(captured.pcm),
    segments: captured.segments,
  })
  await refreshPending()
  await syncPending()
}

async function discard() {
  if (!bridge || !recorder.isRecording) return
  await bridge.audioControl(false)
  recorder.stop()
  state.recording = false
  state.speaking = null
  setNote('Recording discarded.')
}

async function syncPending() {
  if (syncing) return
  const pending = await listPending()
  if (pending.length === 0) return
  syncing = true
  syncButton.disabled = true
  let sent = 0
  try {
    for (const rec of pending) {
      setNote(`Sending ${sent + 1}/${pending.length}…`)
      await upload(rec, { serverURL: serverInput.value, token: tokenInput.value })
      await deletePending(rec.id)
      sent++
    }
    setNote(sent === 1 ? 'Sent to Hlopya.' : `Sent ${sent} to Hlopya.`)
  } catch (error) {
    setNote(`Not sent, will retry. ${error instanceof Error ? error.message : error}`)
  } finally {
    syncing = false
    syncButton.disabled = false
    await refreshPending()
  }
}

async function refreshPending() {
  state.pending = (await listPending()).length
  render()
}

function tick() {
  state.seconds = recorder.seconds
  render()
}

function setNote(note: string) {
  state.note = note
  render()
}

function render() {
  toggleButton.textContent = state.recording ? 'Stop & send' : 'Start recording'
  toggleButton.classList.toggle('recording', state.recording)
  timerLine.textContent = state.recording ? `● ${clock(state.seconds)}` : `${state.pending} waiting to send`
  statusLine.textContent = state.note
  // Glasses text is limited, keep the note short there.
  if (bridge) void updateGlasses(bridge, { ...state, note: state.note.slice(0, 60) })
}

void main()
