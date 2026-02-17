const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  getSessions: () => ipcRenderer.invoke('get-sessions'),
  getSessionDetail: (id) => ipcRenderer.invoke('get-session-detail', id),
  startRecording: () => ipcRenderer.invoke('start-recording'),
  stopRecording: () => ipcRenderer.invoke('stop-recording'),
  getRecStatus: () => ipcRenderer.invoke('get-rec-status'),
  processSession: (id) => ipcRenderer.invoke('process-session', id),
  transcribeSession: (id) => ipcRenderer.invoke('transcribe-session', id),
  savePersonalNotes: (id, text) => ipcRenderer.invoke('save-personal-notes', id, text),
  saveEnrichedNotes: (id, text) => ipcRenderer.invoke('save-enriched-notes', id, text),
  renameParticipant: (id, idx, oldName, newName) => ipcRenderer.invoke('rename-participant', id, idx, oldName, newName),
  renameSession: (id, title) => ipcRenderer.invoke('rename-session', id, title),

  onRecStatus: (cb) => ipcRenderer.on('rec-status', (_, data) => cb(data)),
  onSessionSaved: (cb) => ipcRenderer.on('session-saved', (_, id) => cb(id)),
  onProcessLog: (cb) => ipcRenderer.on('process-log', (_, msg) => cb(msg)),
  onRecTime: (cb) => ipcRenderer.on('rec-time', (_, time) => cb(time)),
  onAutoProcessStatus: (cb) => ipcRenderer.on('auto-process-status', (_, data) => cb(data)),

  showMain: () => ipcRenderer.send('show-main'),
});
