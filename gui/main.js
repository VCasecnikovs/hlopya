const { app, BrowserWindow, ipcMain, Tray, Menu, nativeImage, Notification } = require('electron');
const path = require('path');
const fs = require('fs');
const { spawn, execSync } = require('child_process');
const os = require('os');

// Paths - resolve differently when packaged vs dev
const IS_PACKAGED = app.isPackaged;
const RECORDINGS_DIR = path.join(os.homedir(), 'recordings');
const AUDIOCAP_PATH = IS_PACKAGED
  ? path.join(process.resourcesPath, 'audiocap', 'AudioCap.app', 'Contents', 'MacOS', 'audiocap')
  : path.join(__dirname, '..', 'audiocap', 'AudioCap.app', 'Contents', 'MacOS', 'audiocap');
const PYTHON_DIR = IS_PACKAGED
  ? path.join(process.resourcesPath, 'python')
  : path.join(__dirname, '..');

// Auto-detect Python binary
function findPython() {
  const candidates = [
    // Check pyenv first
    path.join(os.homedir(), '.pyenv', 'shims', 'python3'),
    // Homebrew
    '/opt/homebrew/bin/python3',
    '/usr/local/bin/python3',
    // System
    '/usr/bin/python3',
  ];

  // Check if specific version is set in config
  const configPath = IS_PACKAGED
    ? path.join(process.resourcesPath, 'python', 'config.yaml')
    : path.join(__dirname, '..', 'config.yaml');

  if (fs.existsSync(configPath)) {
    try {
      const yaml = fs.readFileSync(configPath, 'utf8');
      const match = yaml.match(/python_bin:\s*(.+)/);
      if (match && match[1].trim()) {
        const customBin = match[1].trim();
        if (fs.existsSync(customBin)) return customBin;
      }
    } catch (_) {}
  }

  for (const p of candidates) {
    try {
      if (fs.existsSync(p)) return p;
    } catch (_) {}
  }

  // Fallback: try which
  try {
    return execSync('which python3', { encoding: 'utf8' }).trim();
  } catch (_) {
    return 'python3';
  }
}

const PYTHON_BIN = findPython();

// Ensure Python toolchain is in PATH for child processes
const CHILD_ENV = {
  ...process.env,
  PATH: `${path.dirname(PYTHON_BIN)}:/opt/homebrew/bin:/usr/local/bin:${process.env.PATH || '/usr/bin:/bin'}`,
};

// Suppress EPIPE errors (happens when pipes close during shutdown)
process.stdout.on('error', () => {});
process.stderr.on('error', () => {});

let mainWindow = null;
let nubWindow = null;
let tray = null;
let audiocapProc = null;
let recording = false;
let currentSessionId = null;
let recStartTime = null;
let recTimer = null;

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Windows
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

function createMainWindow() {
  mainWindow = new BrowserWindow({
    width: 900,
    height: 650,
    minWidth: 700,
    minHeight: 500,
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 16, y: 16 },
    backgroundColor: '#1a1a2e',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, 'index.html'));
  mainWindow.on('closed', () => { mainWindow = null; });
}

function createNubWindow() {
  if (nubWindow) return;

  nubWindow = new BrowserWindow({
    width: 56,
    height: 56,
    alwaysOnTop: true,
    frame: false,
    transparent: true,
    resizable: false,
    hasShadow: false,
    skipTaskbar: true,
    focusable: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
    },
  });

  nubWindow.setAlwaysOnTop(true, 'floating');
  nubWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });

  // Position: right side, upper third
  const { screen } = require('electron');
  const display = screen.getPrimaryDisplay();
  const x = display.workArea.x + display.workArea.width - 72;
  const y = display.workArea.y + Math.floor(display.workArea.height * 0.3);
  nubWindow.setPosition(x, y);

  nubWindow.loadFile(path.join(__dirname, 'nub.html'));
  nubWindow.on('closed', () => { nubWindow = null; });
}

function destroyNub() {
  if (nubWindow) {
    nubWindow.close();
    nubWindow = null;
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Tray
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

function createTray() {
  // Simple circle icon
  const icon = nativeImage.createFromBuffer(
    Buffer.from(
      'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAIRJREFUWEft' +
      'lsEKACAIQ93/f7RaBBFq6nSIjrLnFBFUvFQcT6N4APYJ2BOIdQIL23YC9gJqC7ATsInIF7An' +
      'EOsEFrbtBOwF1BZgJ2ATkS9gTyDWCSxs2wnYC6gtwE7AJiJfwJ5ArBNY2LYTsBdQW4CdgE1E' +
      'voA9gVgnsLBtJ2AvoLcAG5wgICCR3v4AAAAASUVORK5CYII=',
      'base64'
    )
  );
  icon.setTemplateImage(true);

  tray = new Tray(icon.resize({ width: 18, height: 18 }));
  tray.setToolTip('Hlopya');

  const contextMenu = Menu.buildFromTemplate([
    {
      label: 'Open Hlopya',
      click: () => {
        if (mainWindow) mainWindow.show();
        else createMainWindow();
      },
    },
    { type: 'separator' },
    {
      label: 'Start Recording',
      id: 'toggle-rec',
      click: () => {
        if (!recording) startRecording();
        else stopRecording();
      },
    },
    { type: 'separator' },
    { label: 'Quit', click: () => app.quit() },
  ]);
  tray.setContextMenu(contextMenu);
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Recording
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

function startRecording() {
  if (recording) return;

  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  currentSessionId = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}_${pad(now.getHours())}-${pad(now.getMinutes())}-${pad(now.getSeconds())}`;

  const sessionDir = path.join(RECORDINGS_DIR, currentSessionId);
  fs.mkdirSync(sessionDir, { recursive: true });

  const sysPath = path.join(sessionDir, 'system.wav');

  audiocapProc = spawn(AUDIOCAP_PATH, [
    sysPath,
    '--sample-rate', '16000',
    '--mic',
  ]);

  audiocapProc.stderr.on('data', (data) => {
    try {
      console.log('[audiocap]', data.toString().trim());
    } catch (_) { /* ignore EPIPE */ }
  });

  audiocapProc.stderr.on('error', () => { /* ignore pipe errors */ });

  audiocapProc.on('error', (err) => {
    console.error('[audiocap] spawn error:', err.message);
  });

  audiocapProc.on('exit', (code) => {
    try {
      console.log('[audiocap] exited with code', code);
    } catch (_) { /* ignore */ }
  });

  recording = true;
  recStartTime = Date.now();

  // Show floating nub
  createNubWindow();

  // Update timer
  recTimer = setInterval(() => {
    const elapsed = Math.floor((Date.now() - recStartTime) / 1000);
    const m = String(Math.floor(elapsed / 60)).padStart(2, '0');
    const s = String(elapsed % 60).padStart(2, '0');
    try {
      if (nubWindow && !nubWindow.isDestroyed()) nubWindow.webContents.send('rec-time', `${m}:${s}`);
      if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('rec-status', { recording: true, time: `${m}:${s}`, sessionId: currentSessionId });
    } catch (_) { /* window may be destroyed */ }
  }, 1000);

  // Notify main window
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('rec-status', { recording: true, time: '00:00', sessionId: currentSessionId });
  }

  // Update tray
  if (tray) {
    const menu = Menu.buildFromTemplate([
      { label: `Recording: ${currentSessionId}`, enabled: false },
      { type: 'separator' },
      { label: 'Stop Recording', click: () => stopRecording() },
      { type: 'separator' },
      { label: 'Quit', click: () => app.quit() },
    ]);
    tray.setContextMenu(menu);
  }
}

function stopRecording() {
  if (!recording) return;

  clearInterval(recTimer);
  recTimer = null;

  if (audiocapProc) {
    try {
      audiocapProc.kill('SIGINT');
    } catch (_) { /* already dead */ }
    audiocapProc = null;
  }

  recording = false;
  destroyNub();

  const sessionId = currentSessionId;
  currentSessionId = null;
  recStartTime = null;

  // Notify
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('rec-status', { recording: false });
    mainWindow.webContents.send('session-saved', sessionId);
  }

  new Notification({
    title: 'Recording saved',
    body: `Session: ${sessionId}`,
  }).show();

  // Reset tray
  createTray();

  // Auto-process: transcribe + generate notes
  autoProcess(sessionId);

  return sessionId;
}

async function autoProcess(sessionId) {
  try {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('auto-process-status', { sessionId, stage: 'transcribing' });
    }

    await processSession(sessionId);

    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('auto-process-status', { sessionId, stage: 'done' });
    }

    new Notification({
      title: 'Meeting processed',
      body: `${sessionId}: transcript + notes ready`,
    }).show();
  } catch (err) {
    console.error('[auto-process] Error:', err.message);
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('auto-process-status', { sessionId, stage: 'error', error: err.message });
    }
    new Notification({
      title: 'Processing failed',
      body: err.message.slice(0, 100),
    }).show();
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Sessions
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

function loadMeta(sessionDir) {
  const metaPath = path.join(sessionDir, 'meta.json');
  if (fs.existsSync(metaPath)) {
    try {
      return JSON.parse(fs.readFileSync(metaPath, 'utf8'));
    } catch (_) {}
  }
  return {};
}

function saveMeta(sessionDir, meta) {
  const metaPath = path.join(sessionDir, 'meta.json');
  const existing = loadMeta(sessionDir);
  const merged = { ...existing, ...meta };
  fs.writeFileSync(metaPath, JSON.stringify(merged, null, 2));
  return merged;
}

function getSessions() {
  if (!fs.existsSync(RECORDINGS_DIR)) return [];

  const dirs = fs.readdirSync(RECORDINGS_DIR, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => d.name)
    .sort()
    .reverse();

  return dirs.map(id => {
    const dir = path.join(RECORDINGS_DIR, id);
    const hasMic = fs.existsSync(path.join(dir, 'mic.wav'));
    const hasSys = fs.existsSync(path.join(dir, 'system.wav'));
    const hasTranscript = fs.existsSync(path.join(dir, 'transcript.json'));
    const hasNotes = fs.existsSync(path.join(dir, 'notes.json'));
    const hasPersonalNotes = fs.existsSync(path.join(dir, 'personal_notes.md'));

    let title = '';
    let duration = 0;
    let participants = [];

    // Check meta.json first for custom title
    const meta = loadMeta(dir);
    if (meta.title) {
      title = meta.title;
    }

    // Read transcript/notes for metadata
    if (hasTranscript) {
      try {
        const t = JSON.parse(fs.readFileSync(path.join(dir, 'transcript.json'), 'utf8'));
        duration = t.duration_seconds || 0;
      } catch (_) {}
    }
    if (hasNotes) {
      try {
        const notes = JSON.parse(fs.readFileSync(path.join(dir, 'notes.json'), 'utf8'));
        if (!title) title = notes.title || '';
        participants = notes.participants || [];
      } catch (_) {}
    }

    let status = 'recorded';
    if (hasNotes) status = 'done';
    else if (hasTranscript) status = 'transcribed';

    return { id, hasMic, hasSys, hasTranscript, hasNotes, hasPersonalNotes, title, status, duration, participants };
  });
}

function getSessionDetail(sessionId) {
  const dir = path.join(RECORDINGS_DIR, sessionId);
  const result = { id: sessionId, transcript: null, notes: null, personalNotes: '', meta: {} };

  const transcriptPath = path.join(dir, 'transcript.md');
  if (fs.existsSync(transcriptPath)) {
    result.transcript = fs.readFileSync(transcriptPath, 'utf8');
  }

  const notesPath = path.join(dir, 'notes.json');
  if (fs.existsSync(notesPath)) {
    try {
      result.notes = JSON.parse(fs.readFileSync(notesPath, 'utf8'));
    } catch (_) {}
  }

  const personalPath = path.join(dir, 'personal_notes.md');
  if (fs.existsSync(personalPath)) {
    result.personalNotes = fs.readFileSync(personalPath, 'utf8');
  }

  result.meta = loadMeta(dir);

  return result;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Transcription
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

function processSession(sessionId) {
  const dir = path.join(RECORDINGS_DIR, sessionId);
  const appPy = path.join(PYTHON_DIR, 'app.py');

  return new Promise((resolve, reject) => {
    const proc = spawn(PYTHON_BIN, [appPy, 'process', dir], {
      cwd: PYTHON_DIR,
      env: CHILD_ENV,
    });

    let stdout = '';
    let stderr = '';

    proc.stdout.on('data', (data) => {
      stdout += data.toString();
      if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('process-log', data.toString());
    });

    proc.stderr.on('data', (data) => {
      stderr += data.toString();
      if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('process-log', data.toString());
    });

    proc.on('exit', (code) => {
      if (code === 0) {
        resolve({ success: true, stdout });
      } else {
        reject(new Error(`Process exited with code ${code}: ${stderr}`));
      }
    });

    proc.on('error', (err) => {
      reject(new Error(`Failed to start process: ${err.message}`));
    });
  });
}

function transcribeSession(sessionId) {
  const dir = path.join(RECORDINGS_DIR, sessionId);
  const appPy = path.join(PYTHON_DIR, 'app.py');

  return new Promise((resolve, reject) => {
    const proc = spawn(PYTHON_BIN, [appPy, 'transcribe', dir], {
      cwd: PYTHON_DIR,
      env: CHILD_ENV,
    });

    let stdout = '';
    let stderr = '';

    proc.stdout.on('data', (data) => {
      stdout += data.toString();
      if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('process-log', data.toString());
    });

    proc.stderr.on('data', (data) => {
      stderr += data.toString();
      if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('process-log', data.toString());
    });

    proc.on('exit', (code) => {
      if (code === 0) resolve({ success: true });
      else reject(new Error(`Transcription failed (code ${code}): ${stderr}`));
    });

    proc.on('error', (err) => {
      reject(new Error(`Failed to start transcription: ${err.message}`));
    });
  });
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// IPC
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ipcMain.handle('get-sessions', () => getSessions());
ipcMain.handle('get-session-detail', (_, id) => getSessionDetail(id));
ipcMain.handle('start-recording', () => { startRecording(); return currentSessionId; });
ipcMain.handle('stop-recording', () => { const id = stopRecording(); return id; });
ipcMain.handle('get-rec-status', () => ({ recording, sessionId: currentSessionId }));

ipcMain.handle('process-session', async (_, id) => {
  try {
    const result = await processSession(id);
    return { success: true };
  } catch (e) {
    return { success: false, error: e.message };
  }
});

ipcMain.handle('transcribe-session', async (_, id) => {
  try {
    const result = await transcribeSession(id);
    return { success: true };
  } catch (e) {
    return { success: false, error: e.message };
  }
});

ipcMain.handle('save-personal-notes', (_, sessionId, text) => {
  const dir = path.join(RECORDINGS_DIR, sessionId);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'personal_notes.md'), text);
  return true;
});

ipcMain.handle('save-enriched-notes', (_, sessionId, text) => {
  const dir = path.join(RECORDINGS_DIR, sessionId);
  const notesPath = path.join(dir, 'notes.json');
  if (!fs.existsSync(notesPath)) return false;
  try {
    const notes = JSON.parse(fs.readFileSync(notesPath, 'utf8'));
    notes.enriched_notes = text;
    fs.writeFileSync(notesPath, JSON.stringify(notes, null, 2));
    return true;
  } catch (_) { return false; }
});

ipcMain.handle('rename-participant', (_, sessionId, idx, oldName, newName) => {
  const dir = path.join(RECORDINGS_DIR, sessionId);
  if (!fs.existsSync(dir)) return false;

  const notesPath = path.join(dir, 'notes.json');
  if (fs.existsSync(notesPath)) {
    try {
      const notes = JSON.parse(fs.readFileSync(notesPath, 'utf8'));
      if (notes.participants) {
        notes.participants = notes.participants.map(p =>
          p === oldName ? newName : p
        );
      }
      if (notes.enriched_notes) {
        notes.enriched_notes = notes.enriched_notes.replace(new RegExp(oldName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g'), newName);
      }
      if (notes.action_items) {
        notes.action_items = notes.action_items.map(item => ({
          ...item,
          owner: item.owner === oldName ? newName : item.owner,
        }));
      }
      fs.writeFileSync(notesPath, JSON.stringify(notes, null, 2));
    } catch (_) {}
  }

  const meta = loadMeta(dir);
  const nameMap = meta.participant_names || {};
  if (oldName.match(/^Them/i) || nameMap['Them'] === oldName) {
    nameMap['Them'] = newName;
  } else if (oldName.match(/^Me/i) || nameMap['Me'] === oldName) {
    nameMap['Me'] = newName;
  }
  saveMeta(dir, { participant_names: nameMap });
  return true;
});

ipcMain.handle('rename-session', (_, sessionId, newTitle) => {
  const dir = path.join(RECORDINGS_DIR, sessionId);
  if (!fs.existsSync(dir)) return false;
  saveMeta(dir, { title: newTitle });
  return true;
});

ipcMain.on('show-main', () => {
  if (mainWindow) mainWindow.show();
  else createMainWindow();
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// App lifecycle
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

app.whenReady().then(() => {
  fs.mkdirSync(RECORDINGS_DIR, { recursive: true });
  createMainWindow();
  createTray();
});

app.on('window-all-closed', () => {
  // Keep running in tray on macOS
});

app.on('activate', () => {
  if (!mainWindow) createMainWindow();
});

app.on('before-quit', () => {
  if (recording) stopRecording();
});
