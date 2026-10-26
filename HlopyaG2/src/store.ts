import type { RoleSegment } from './recorder'

// Finished recordings wait here until Klava accepts them, so a dead tailnet
// or a closed phone app never loses a meeting. Mirrors the Watch's
// "pending / Sync" behaviour.
export type PendingRecording = {
  id: string
  title: string
  recordedAt: string
  seconds: number
  wav: Blob
  segments: RoleSegment[]
}

const DB_NAME = 'hlopya-g2'
const STORE = 'pending'

function open(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1)
    request.onupgradeneeded = () => request.result.createObjectStore(STORE, { keyPath: 'id' })
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}

async function run<T>(mode: IDBTransactionMode, body: (store: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const db = await open()
  return new Promise((resolve, reject) => {
    const request = body(db.transaction(STORE, mode).objectStore(STORE))
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}

export const savePending = (rec: PendingRecording) => run('readwrite', (s) => s.put(rec))
export const deletePending = (id: string) => run('readwrite', (s) => s.delete(id))
export const listPending = () => run<PendingRecording[]>('readonly', (s) => s.getAll())
