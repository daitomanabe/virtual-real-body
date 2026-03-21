const presetGrid = document.getElementById("preset-grid");
const actionGrid = document.getElementById("action-grid");
const triggerWall = document.getElementById("trigger-wall");
const bodyCoreGrid = document.getElementById("body-core-grid");
const bodyVoiceGrid = document.getElementById("body-voice-grid");
const quickBodyGrid = document.getElementById("quick-body-grid");
const quickSpaceGrid = document.getElementById("quick-space-grid");
const fxColumn = document.getElementById("fx-column");
const triggerVoiceColumn = document.getElementById("trigger-voice-column");
const stateDump = document.getElementById("state-dump");
const serverStatus = document.getElementById("server-status");
const detectedToggle = document.getElementById("detected-toggle");
const activePresetLabel = document.getElementById("active-preset");
const activeActionLabel = document.getElementById("active-action");
const sessionFileLabel = document.getElementById("session-file-label");
const sourceSummary = document.getElementById("source-summary");
const displaySummary = document.getElementById("display-summary");
const inputPreview = document.getElementById("input-preview");
const inputPreviewStatus = document.getElementById("input-preview-status");
const previewSourceLabel = document.getElementById("preview-source-label");
const sourceModeButtons = Array.from(document.querySelectorAll("[data-source-mode]"));
const deviceSelect = document.getElementById("device-select");
const previewDeviceSelect = document.getElementById("preview-device-select");
const cameraIndexInput = document.getElementById("camera-index-input");
const videoSelect = document.getElementById("video-select");
const previewVideoSelect = document.getElementById("preview-video-select");
const videoPathInput = document.getElementById("video-path-input");
const videoLoopToggle = document.getElementById("video-loop-toggle");
const displayTargetSelect = document.getElementById("display-target-select");
const fullscreenToggle = document.getElementById("fullscreen-toggle");

const BODY_MODE_OPTIONS = [
  ["0", "Core"],
  ["1", "Pulse"],
  ["2", "Formant"],
  ["3", "PM"],
  ["4", "Glass"],
  ["5", "Sync"],
];

const TRIGGER_MODE_OPTIONS = [
  ["0", "Strike"],
  ["1", "Ring"],
  ["2", "PM"],
  ["3", "Shards"],
];

const TRIGGER_ORDER = ["onset", "impact", "enter", "exit", "flow"];

const TRIGGER_LABEL = {
  onset: "Motion Onset",
  impact: "Impact",
  enter: "Person Enter",
  exit: "Person Exit",
  flow: "Flow Burst",
};

const FX_SECTION_LABEL = {
  harshNoise: "Harsh Noise",
  highpass: "High-Pass",
  lowpass: "Low-Pass",
  distortion: "Distortion",
  glitch: "Glitch",
  resonator: "Resonator",
  delay: "Delay",
  chorus: "Chorus",
  reverb: "Reverb",
  shimmer: "Shimmer",
  master: "Master",
};

const BODY_CORE_FIELDS = [
  field("body.core", "freq", "Freq", { min: 35, max: 2400, step: 1, format: (value) => `${value.toFixed(1)} Hz` }),
  field("body.core", "amp", "Amp", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("body.core", "cutoff", "Cutoff", { min: 120, max: 10000, step: 10, format: (value) => `${value.toFixed(0)} Hz` }),
  field("body.core", "pan", "Pan", { min: -1, max: 1, step: 0.01, format: formatSignedUnit }),
];

const BODY_VOICE_FIELDS = [
  field("body.voice", "mode", "Mode", { type: "select", options: BODY_MODE_OPTIONS }),
  field("body.voice", "texture", "Texture", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("body.voice", "noiseMix", "Noise", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("body.voice", "subMix", "Sub", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("body.voice", "motion", "Motion", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("body.voice", "resonance", "Resonance", { min: 0.08, max: 0.95, step: 0.01, format: formatUnit }),
  field("body.voice", "airMix", "Air", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("body.voice", "ringMix", "Ring", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("body.voice", "grit", "Grit", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("body.voice", "drift", "Drift", { min: 0, max: 1, step: 0.01, format: formatUnit }),
];

const QUICK_BODY_FIELDS = [
  field("body.core", "amp", "Amp", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("body.core", "freq", "Freq", { min: 35, max: 2400, step: 1, format: (value) => `${value.toFixed(0)} Hz` }),
  field("body.core", "cutoff", "Cutoff", { min: 120, max: 10000, step: 10, format: (value) => `${value.toFixed(0)} Hz` }),
  field("body.voice", "mode", "Mode", { type: "select", options: BODY_MODE_OPTIONS }),
  field("body.voice", "texture", "Texture", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("body.voice", "motion", "Motion", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("body.voice", "airMix", "Air", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("body.voice", "ringMix", "Ring", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("body.voice", "grit", "Grit", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("body.voice", "drift", "Drift", { min: 0, max: 1, step: 0.01, format: formatUnit }),
];

const QUICK_SPACE_FIELDS = [
  field("fx.resonator", "mix", "Resonator", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("fx.delay", "mix", "Delay", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("fx.reverb", "mix", "Reverb", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("fx.shimmer", "mix", "Shimmer", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("fx.master", "width", "Width", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  field("fx.master", "output", "Output", { min: 0, max: 1, step: 0.01, format: formatUnit }),
];

const FX_FIELDS = {
  harshNoise: [
    field("fx.harshNoise", "enabled", "On", { type: "toggle" }),
    field("fx.harshNoise", "level", "Level", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.harshNoise", "tone", "Tone", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.harshNoise", "hp", "HP", { min: 120, max: 12000, step: 1, format: (value) => `${value.toFixed(0)} Hz` }),
    field("fx.harshNoise", "lp", "LP", { min: 1200, max: 18000, step: 1, format: (value) => `${value.toFixed(0)} Hz` }),
    field("fx.harshNoise", "duck", "Duck", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  ],
  highpass: [
    field("fx.highpass", "enabled", "On", { type: "toggle" }),
    field("fx.highpass", "freq", "Freq", { min: 20, max: 12000, step: 1, format: (value) => `${value.toFixed(0)} Hz` }),
    field("fx.highpass", "resonance", "Resonance", { min: 0.08, max: 0.95, step: 0.01, format: formatUnit }),
    field("fx.highpass", "mix", "Mix", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  ],
  lowpass: [
    field("fx.lowpass", "enabled", "On", { type: "toggle" }),
    field("fx.lowpass", "freq", "Freq", { min: 120, max: 18000, step: 1, format: (value) => `${value.toFixed(0)} Hz` }),
    field("fx.lowpass", "resonance", "Resonance", { min: 0.08, max: 0.95, step: 0.01, format: formatUnit }),
    field("fx.lowpass", "mix", "Mix", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  ],
  distortion: [
    field("fx.distortion", "enabled", "On", { type: "toggle" }),
    field("fx.distortion", "drive", "Drive", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.distortion", "mix", "Mix", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.distortion", "fold", "Fold", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.distortion", "bias", "Bias", { min: -1, max: 1, step: 0.01, format: formatSignedUnit }),
    field("fx.distortion", "tone", "Tone", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  ],
  glitch: [
    field("fx.glitch", "enabled", "On", { type: "toggle" }),
    field("fx.glitch", "mix", "Mix", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.glitch", "rate", "Rate", { min: 0.25, max: 40, step: 0.01, format: (value) => `${value.toFixed(2)} Hz` }),
    field("fx.glitch", "depth", "Depth", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.glitch", "crush", "Crush", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.glitch", "gate", "Gate", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  ],
  resonator: [
    field("fx.resonator", "mix", "Mix", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.resonator", "tune", "Tune", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.resonator", "decay", "Decay", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.resonator", "spread", "Spread", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  ],
  delay: [
    field("fx.delay", "time", "Time", { min: 0.01, max: 0.95, step: 0.01, format: (value) => `${value.toFixed(2)} s` }),
    field("fx.delay", "feedback", "Feedback", { min: 0.01, max: 0.99, step: 0.01, format: formatUnit }),
    field("fx.delay", "mix", "Mix", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.delay", "tone", "Tone", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  ],
  chorus: [
    field("fx.chorus", "mix", "Mix", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.chorus", "rate", "Rate", { min: 0.02, max: 8, step: 0.01, format: (value) => `${value.toFixed(2)} Hz` }),
    field("fx.chorus", "depth", "Depth", { min: 0.0001, max: 0.05, step: 0.0001, format: (value) => value.toFixed(4) }),
  ],
  reverb: [
    field("fx.reverb", "mix", "Mix", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.reverb", "room", "Room", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.reverb", "damp", "Damp", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.reverb", "tone", "Tone", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  ],
  shimmer: [
    field("fx.shimmer", "mix", "Mix", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.shimmer", "shift", "Shift", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.shimmer", "feedback", "Feedback", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.shimmer", "tone", "Tone", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  ],
  master: [
    field("fx.master", "drive", "Drive", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.master", "width", "Width", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.master", "tremRate", "Trem Rate", { min: 0, max: 12, step: 0.01, format: (value) => `${value.toFixed(2)} Hz` }),
    field("fx.master", "tremDepth", "Trem Depth", { min: 0, max: 1, step: 0.01, format: formatUnit }),
    field("fx.master", "output", "Output", { min: 0, max: 1, step: 0.01, format: formatUnit }),
  ],
};

const state = {
  presets: [],
  actions: [],
  data: null,
  session: null,
  sessionFile: null,
  media: { assets_dir: "", videos: [] },
  activePreset: null,
  activeAction: null,
};

let patchTimer = null;
let pendingPatch = {};
let previewStream = null;
let previewSyncToken = 0;
let browserCameraDevices = [];

document.getElementById("refresh-state").addEventListener("click", async () => {
  await loadState();
});

detectedToggle.addEventListener("click", async () => {
  if (!state.data) return;
  const nextValue = !state.data.body.core.detected;
  setScopedValue(state.data, "body.core", "detected", nextValue);
  renderReadouts();
  await sendPatch(buildPatch("body.core", "detected", nextValue), { clearSelections: false });
});

document.querySelectorAll(".nav-chip").forEach((button) => {
  button.addEventListener("click", () => {
    if (button.dataset.sourceMode) {
      return;
    }
    const target = document.getElementById(button.dataset.target);
    if (target) {
      scrollSectionIntoView(target);
    }
  });
});

sourceModeButtons.forEach((button) => {
  button.addEventListener("click", async () => {
    await sendSessionPatch({ source: { mode: button.dataset.sourceMode } });
  });
});

deviceSelect.addEventListener("change", async () => {
  const nextIndex = Math.max(Number(deviceSelect.value || 0), 0);
  cameraIndexInput.value = String(nextIndex);
  await sendSessionPatch({
    source: {
      mode: "camera",
      camera_index: nextIndex,
    },
  });
});

if (previewDeviceSelect) {
  previewDeviceSelect.addEventListener("change", async () => {
    const nextIndex = Math.max(Number(previewDeviceSelect.value || 0), 0);
    deviceSelect.value = String(nextIndex);
    cameraIndexInput.value = String(nextIndex);
    await sendSessionPatch({
      source: {
        mode: "camera",
        camera_index: nextIndex,
      },
    });
  });
}

cameraIndexInput.addEventListener("change", async () => {
  await sendSessionPatch({
    source: {
      mode: "camera",
      camera_index: Math.max(Number(cameraIndexInput.value || 0), 0),
    },
  });
});

videoSelect.addEventListener("change", async () => {
  const nextValue = videoSelect.value || "";
  videoPathInput.value = nextValue;
  await sendSessionPatch({
    source: {
      mode: "video",
      video_file: nextValue,
    },
  });
});

if (previewVideoSelect) {
  previewVideoSelect.addEventListener("change", async () => {
    const nextValue = previewVideoSelect.value || "";
    videoSelect.value = nextValue;
    videoPathInput.value = nextValue;
    await sendSessionPatch({
      source: {
        mode: "video",
        video_file: nextValue,
      },
    });
  });
}

videoPathInput.addEventListener("change", async () => {
  await sendSessionPatch({
    source: {
      mode: "video",
      video_file: videoPathInput.value.trim(),
    },
  });
});

videoLoopToggle.addEventListener("click", async () => {
  const nextLoop = !Boolean(state.session?.source?.loop);
  await sendSessionPatch({
    source: {
      loop: nextLoop,
    },
  });
});

displayTargetSelect.addEventListener("change", async () => {
  await sendSessionPatch({
    display: {
      target_screen: displayTargetSelect.value,
    },
  });
});

fullscreenToggle.addEventListener("click", async () => {
  const nextFullscreen = !Boolean(state.session?.display?.fullscreen);
  await sendSessionPatch({
    display: {
      fullscreen: nextFullscreen,
    },
  });
});

function field(scope, key, label, options = {}) {
  return { scope, key, label, ...options };
}

function formatUnit(value) {
  return Number(value).toFixed(2);
}

function formatSignedUnit(value) {
  return Number(value).toFixed(2);
}

function getOptionLabel(options, value) {
  const hit = options.find(([optionValue]) => Number(optionValue) === Number(value));
  return hit ? hit[1] : String(value);
}

function mergePatch(target, patch) {
  Object.entries(patch).forEach(([key, value]) => {
    if (value && typeof value === "object" && !Array.isArray(value)) {
      if (!target[key] || typeof target[key] !== "object" || Array.isArray(target[key])) {
        target[key] = {};
      }
      mergePatch(target[key], value);
      return;
    }
    target[key] = value;
  });
}

function buildPatch(scope, key, value) {
  const segments = scope.split(".");
  const patch = {};
  let cursor = patch;

  segments.forEach((segment, index) => {
    if (index === segments.length - 1) {
      cursor[segment] = { [key]: value };
      return;
    }
    cursor[segment] = {};
    cursor = cursor[segment];
  });

  return patch;
}

function getScopedValue(root, scope, key) {
  return scope.split(".").reduce((cursor, segment) => cursor?.[segment], root)?.[key];
}

function setScopedValue(root, scope, key, value) {
  const target = scope.split(".").reduce((cursor, segment) => cursor?.[segment], root);
  if (target) {
    target[key] = value;
  }
}

function queuePatch(patch) {
  mergePatch(pendingPatch, patch);
  clearTimeout(patchTimer);
  patchTimer = setTimeout(async () => {
    const nextPatch = pendingPatch;
    pendingPatch = {};
    await sendPatch(nextPatch, { clearSelections: true });
  }, 80);
}

async function sendPatch(patch, { clearSelections = true } = {}) {
  const response = await fetch("/api/state", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });

  if (!response.ok) {
    setStatus("Patch Error");
    return;
  }

  const payload = await response.json();
  state.data = payload.state;
  if (clearSelections) {
    state.activePreset = null;
    state.activeAction = null;
  }
  setStatus("Live");
  renderStaticChrome();
  renderState();
}

async function sendSessionPatch(patch) {
  const response = await fetch("/api/session", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });

  if (!response.ok) {
    setStatus("Session Error");
    return;
  }

  const payload = await response.json();
  state.session = payload.session;
  state.media = payload.media;
  renderSession();
  void syncInputPreview();
  setStatus("Live");
}

async function recallPreset(preset) {
  const response = await fetch(`/api/preset/${preset.name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({}),
  });

  if (!response.ok) {
    setStatus("Preset Error");
    return;
  }

  const payload = await response.json();
  state.data = payload.state;
  state.activePreset = preset.name;
  state.activeAction = null;
  setStatus(`Preset ${preset.label || preset.name}`);
  window.setTimeout(() => setStatus("Live"), 900);
  renderStaticChrome();
  renderState();
}

async function fireAction(action) {
  const response = await fetch(`/api/action/${action.name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({}),
  });

  if (!response.ok) {
    setStatus("Action Error");
    return;
  }

  const payload = await response.json();
  state.data = payload.state;
  state.activeAction = action.name;
  state.activePreset = null;
  setStatus(`Action ${action.label || action.name}`);
  window.setTimeout(() => setStatus("Live"), 900);
  renderStaticChrome();
  renderState();
}

async function fireTrigger(name) {
  const response = await fetch(`/api/trigger/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({}),
  });

  if (!response.ok) {
    setStatus("Trigger Error");
    return;
  }

  setStatus(`Fired ${TRIGGER_LABEL[name]}`);
  window.setTimeout(() => setStatus("Live"), 900);
}

async function loadState() {
  const [stateResponse, presetResponse, actionResponse, sessionResponse] = await Promise.all([
    fetch("/api/state"),
    fetch("/api/presets"),
    fetch("/api/actions"),
    fetch("/api/session"),
  ]);

  if (!stateResponse.ok || !presetResponse.ok || !actionResponse.ok || !sessionResponse.ok) {
    setStatus("Offline");
    return;
  }

  const statePayload = await stateResponse.json();
  const presetPayload = await presetResponse.json();
  const actionPayload = await actionResponse.json();
  const sessionPayload = await sessionResponse.json();

  state.data = statePayload.state;
  state.presets = presetPayload.presets;
  state.actions = actionPayload.actions;
  state.session = sessionPayload.session;
  state.media = sessionPayload.media;
  state.sessionFile = sessionPayload.session_file;
  setStatus("Live");
  renderStaticChrome();
  renderSession();
  await syncInputPreview();
  renderState();
}

function renderStaticChrome() {
  renderPresetCards();
  renderActionCards();
}

function renderSession() {
  if (!state.session) return;

  const session = state.session;
  const source = session.source || {};
  const display = session.display || {};

  sessionFileLabel.textContent = state.sessionFile ? state.sessionFile.split("/").pop() : "session";
  cameraIndexInput.value = String(source.camera_index ?? 0);
  videoPathInput.value = source.video_file || "";
  displayTargetSelect.value = display.target_screen || "external_preferred";
  fullscreenToggle.dataset.active = display.fullscreen ? "true" : "false";
  fullscreenToggle.textContent = display.fullscreen ? "ON" : "OFF";

  const cameras = Array.isArray(state.media?.cameras) ? state.media.cameras : [];
  const currentCameraIndex = Number(source.camera_index ?? 0);
  populateOptionSelect(deviceSelect, cameras, currentCameraIndex, (entry) => String(entry.index), (entry) => entry.label || `Device ${entry.index}`);
  if (previewDeviceSelect) {
    populateOptionSelect(previewDeviceSelect, cameras, currentCameraIndex, (entry) => String(entry.index), (entry) => entry.label || `Device ${entry.index}`);
  }

  sourceModeButtons.forEach((button) => {
    button.classList.toggle("is-active", button.dataset.sourceMode === source.mode);
  });

  videoLoopToggle.dataset.active = source.loop ? "true" : "false";
  videoLoopToggle.textContent = source.loop ? "ON" : "OFF";

  const videos = Array.isArray(state.media?.videos) ? state.media.videos : [];
  const currentPath = source.video_file || "";
  const hasCurrentPath = videos.some((entry) => entry.path === currentPath);
  populateVideoSelect(videoSelect, videos, currentPath, hasCurrentPath);
  if (previewVideoSelect) {
    populateVideoSelect(previewVideoSelect, videos, currentPath, hasCurrentPath);
  }

  const isVideo = source.mode === "video";
  deviceSelect.disabled = isVideo;
  if (previewDeviceSelect) {
    previewDeviceSelect.disabled = isVideo;
  }
  videoSelect.disabled = !isVideo;
  if (previewVideoSelect) {
    previewVideoSelect.disabled = !isVideo;
  }
  videoPathInput.disabled = !isVideo;
  videoLoopToggle.disabled = !isVideo;
  cameraIndexInput.disabled = isVideo;

  sourceSummary.textContent = isVideo
    ? currentPath || "Video file pending"
    : `Device ${Number(source.camera_index ?? 0)}`;
  displaySummary.textContent =
    display.target_screen === "main"
      ? (display.fullscreen ? "Main Display / Fullscreen" : "Main Display / Windowed")
      : (display.fullscreen ? "External Preferred / Fullscreen" : "External Preferred / Windowed");
}

function setPreviewStatus(label, stateName = "warn") {
  if (!inputPreviewStatus) {
    return;
  }
  inputPreviewStatus.textContent = label;
  inputPreviewStatus.dataset.state = stateName;
}

function stopPreviewStream() {
  if (!previewStream) {
    return;
  }
  previewStream.getTracks().forEach((track) => track.stop());
  previewStream = null;
}

function clearPreviewVideoSource() {
  if (!inputPreview) {
    return;
  }
  if (inputPreview.srcObject) {
    inputPreview.srcObject = null;
  }
  if (inputPreview.hasAttribute("src")) {
    inputPreview.pause();
    inputPreview.removeAttribute("src");
    inputPreview.load();
  }
}

function labelFromPath(filePath) {
  if (!filePath) {
    return "Movie";
  }
  const segments = String(filePath).split(/[\\/]/);
  return segments[segments.length - 1] || filePath;
}

function buildVideoPreviewURL(filePath) {
  return `/api/media/video?path=${encodeURIComponent(filePath)}`;
}

async function refreshBrowserCameraDevices() {
  if (!navigator.mediaDevices?.enumerateDevices) {
    browserCameraDevices = [];
    syncBrowserCameraLabels();
    return browserCameraDevices;
  }

  const devices = await navigator.mediaDevices.enumerateDevices();
  browserCameraDevices = devices.filter((entry) => entry.kind === "videoinput");
  syncBrowserCameraLabels();
  return browserCameraDevices;
}

function syncBrowserCameraLabels() {
  [deviceSelect, previewDeviceSelect].filter(Boolean).forEach((select) => {
    Array.from(select.options).forEach((option) => {
      const index = Number(option.value);
      const browserDevice = browserCameraDevices[index];
      if (!browserDevice?.label) {
        return;
      }
      option.textContent = `${index}: ${browserDevice.label}`;
    });
  });
}

async function syncInputPreview() {
  if (!inputPreview || !previewSourceLabel) {
    return;
  }
  if (!state.session) {
    clearPreviewVideoSource();
    stopPreviewStream();
    previewSourceLabel.textContent = "Waiting";
    setPreviewStatus("Waiting for session", "warn");
    return;
  }

  const token = ++previewSyncToken;
  const source = state.session.source || {};
  const isVideo = source.mode === "video";

  if (isVideo) {
    stopPreviewStream();
    previewSourceLabel.textContent = "Movie";

    const filePath = String(source.video_file || "").trim();
    if (!filePath) {
      clearPreviewVideoSource();
      setPreviewStatus("Movie file is not set", "error");
      return;
    }

    const nextURL = buildVideoPreviewURL(filePath);
    if (inputPreview.srcObject) {
      inputPreview.srcObject = null;
    }

    if (inputPreview.dataset.previewMode !== "video" || inputPreview.src !== new URL(nextURL, window.location.href).href) {
      clearPreviewVideoSource();
      inputPreview.src = nextURL;
    }

    inputPreview.dataset.previewMode = "video";
    inputPreview.loop = Boolean(source.loop);
    try {
      await inputPreview.play();
    } catch (error) {
      console.warn(error);
    }

    if (token !== previewSyncToken) {
      return;
    }

    previewSourceLabel.textContent = labelFromPath(filePath);
    setPreviewStatus(`Movie preview active: ${labelFromPath(filePath)}`, "ok");
    return;
  }

  clearPreviewVideoSource();
  previewSourceLabel.textContent = `Device ${Number(source.camera_index ?? 0)}`;

  if (!navigator.mediaDevices?.getUserMedia) {
    setPreviewStatus("Browser camera preview is not available in this environment", "error");
    return;
  }

  try {
    const cameraIndex = Math.max(Number(source.camera_index ?? 0), 0);
    const devices = await refreshBrowserCameraDevices();
    if (token !== previewSyncToken) {
      return;
    }

    const chosenDevice = devices[cameraIndex] || null;
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: chosenDevice?.deviceId ? { deviceId: { exact: chosenDevice.deviceId } } : true,
    });

    if (token !== previewSyncToken) {
      stream.getTracks().forEach((track) => track.stop());
      return;
    }

    stopPreviewStream();
    clearPreviewVideoSource();
    previewStream = stream;
    inputPreview.srcObject = stream;
    inputPreview.dataset.previewMode = "camera";
    inputPreview.muted = true;
    try {
      await inputPreview.play();
    } catch (error) {
      console.warn(error);
    }

    await refreshBrowserCameraDevices();
    if (token !== previewSyncToken) {
      return;
    }

    const activeLabel = chosenDevice?.label || `Device ${cameraIndex}`;
    previewSourceLabel.textContent = activeLabel;
    setPreviewStatus(`Camera preview active: ${activeLabel}`, "ok");
  } catch (error) {
    if (token !== previewSyncToken) {
      return;
    }
    const message = error instanceof Error ? error.message : String(error);
    setPreviewStatus(`Camera preview failed: ${message}`, "error");
  }
}

function scrollSectionIntoView(target) {
  target.scrollIntoView({ behavior: "smooth", block: "start" });
}

function populateOptionSelect(select, entries, currentValue, valueSelector, labelSelector) {
  select.innerHTML = "";
  entries.forEach((entry) => {
    const option = document.createElement("option");
    option.value = valueSelector(entry);
    option.textContent = labelSelector(entry);
    select.appendChild(option);
  });
  if (!entries.some((entry) => Number(valueSelector(entry)) === Number(currentValue))) {
    const option = document.createElement("option");
    option.value = String(currentValue);
    option.textContent = `Device ${currentValue}`;
    select.appendChild(option);
  }
  select.value = String(currentValue);
}

function populateVideoSelect(select, videos, currentPath, hasCurrentPath) {
  select.innerHTML = "";
  const placeholder = document.createElement("option");
  placeholder.value = "";
  placeholder.textContent = videos.length > 0 ? "Choose asset video" : "No asset videos found";
  select.appendChild(placeholder);
  videos.forEach((entry) => {
    const option = document.createElement("option");
    option.value = entry.path;
    option.textContent = entry.label || entry.path;
    select.appendChild(option);
  });
  if (currentPath && !hasCurrentPath) {
    const option = document.createElement("option");
    option.value = currentPath;
    option.textContent = currentPath;
    select.appendChild(option);
  }
  select.value = currentPath;
}

function renderPresetCards() {
  presetGrid.innerHTML = "";

  state.presets.forEach((preset) => {
    const card = document.createElement("button");
    card.type = "button";
    card.className = `scene-card preset-card${state.activePreset === preset.name ? " is-active" : ""}`;

    const title = document.createElement("span");
    title.className = "scene-title";
    title.textContent = preset.label || preset.name;
    card.appendChild(title);

    const description = document.createElement("span");
    description.className = "scene-description";
    description.textContent = preset.description || preset.name;
    card.appendChild(description);

    if (Array.isArray(preset.tags) && preset.tags.length > 0) {
      const tags = document.createElement("span");
      tags.className = "tag-row";
      preset.tags.forEach((tag) => {
        const chip = document.createElement("span");
        chip.className = "tag-chip";
        chip.textContent = tag;
        tags.appendChild(chip);
      });
      card.appendChild(tags);
    }

    card.addEventListener("click", () => recallPreset(preset));
    presetGrid.appendChild(card);
  });
}

function renderActionCards() {
  actionGrid.innerHTML = "";

  state.actions.forEach((action) => {
    const card = document.createElement("button");
    card.type = "button";
    card.className = `scene-card action-card${state.activeAction === action.name ? " is-active" : ""}`;

    const title = document.createElement("span");
    title.className = "scene-title";
    title.textContent = action.label || action.name;
    card.appendChild(title);

    const description = document.createElement("span");
    description.className = "scene-description";
    description.textContent = action.description || action.name;
    card.appendChild(description);

    card.addEventListener("click", () => fireAction(action));
    actionGrid.appendChild(card);
  });
}

function setStatus(label) {
  serverStatus.textContent = label;
}

function renderState() {
  if (!state.data) return;

  renderReadouts();
  stateDump.textContent = JSON.stringify(state.data, null, 2);

  renderControlGrid(bodyCoreGrid, BODY_CORE_FIELDS);
  renderControlGrid(bodyVoiceGrid, BODY_VOICE_FIELDS);
  renderControlGrid(quickBodyGrid, QUICK_BODY_FIELDS);
  renderControlGrid(quickSpaceGrid, QUICK_SPACE_FIELDS);
  renderFxColumn();
  renderTriggerPad();
  renderTriggerVoices();
}

function renderReadouts() {
  if (!state.data) return;

  document.getElementById("freq-readout").textContent = `${state.data.body.core.freq.toFixed(1)} Hz`;
  document.getElementById("amp-readout").textContent = state.data.body.core.amp.toFixed(2);
  document.getElementById("cutoff-readout").textContent = `${state.data.body.core.cutoff.toFixed(0)} Hz`;
  document.getElementById("pan-readout").textContent = state.data.body.core.pan.toFixed(2);
  detectedToggle.textContent = state.data.body.core.detected ? "ON" : "OFF";
  detectedToggle.dataset.active = state.data.body.core.detected ? "true" : "false";
  activePresetLabel.textContent = state.activePreset ? lookupLabel(state.presets, state.activePreset) : "Manual";
  activeActionLabel.textContent = state.activeAction ? lookupLabel(state.actions, state.activeAction) : "Idle";
}

function renderControlGrid(container, fields) {
  container.innerHTML = "";
  fields.forEach((fieldConfig) => {
    container.appendChild(renderField(fieldConfig));
  });
}

function renderField(fieldConfig) {
  const currentValue = getScopedValue(state.data, fieldConfig.scope, fieldConfig.key);
  const wrap = document.createElement("label");
  wrap.className = "control-field";

  const head = document.createElement("div");
  head.className = "control-head";
  head.innerHTML = `<span>${fieldConfig.label}</span><span>${formatFieldValue(fieldConfig, currentValue)}</span>`;
  wrap.appendChild(head);

  if (fieldConfig.type === "toggle") {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "toggle-switch";
    syncToggle(button, head, Boolean(currentValue));
    button.addEventListener("click", () => {
      const nextValue = !Boolean(getScopedValue(state.data, fieldConfig.scope, fieldConfig.key));
      setScopedValue(state.data, fieldConfig.scope, fieldConfig.key, nextValue);
      syncToggle(button, head, nextValue);
      queuePatch(buildPatch(fieldConfig.scope, fieldConfig.key, nextValue));
    });
    wrap.appendChild(button);
    return wrap;
  }

  if (fieldConfig.type === "select") {
    const select = document.createElement("select");
    fieldConfig.options.forEach(([value, label]) => {
      const option = document.createElement("option");
      option.value = value;
      option.textContent = label;
      select.appendChild(option);
    });
    select.value = String(currentValue);
    select.addEventListener("change", () => {
      const nextValue = Number(select.value);
      setScopedValue(state.data, fieldConfig.scope, fieldConfig.key, nextValue);
      head.lastElementChild.textContent = formatFieldValue(fieldConfig, nextValue);
      queuePatch(buildPatch(fieldConfig.scope, fieldConfig.key, nextValue));
      renderReadouts();
    });
    wrap.appendChild(select);
    return wrap;
  }

  const input = document.createElement("input");
  input.type = "range";
  input.min = fieldConfig.min;
  input.max = fieldConfig.max;
  input.step = fieldConfig.step;
  input.value = currentValue;
  input.addEventListener("input", () => {
    const nextValue = Number(input.value);
    setScopedValue(state.data, fieldConfig.scope, fieldConfig.key, nextValue);
    head.lastElementChild.textContent = formatFieldValue(fieldConfig, nextValue);
    queuePatch(buildPatch(fieldConfig.scope, fieldConfig.key, nextValue));
    renderReadouts();
  });
  wrap.appendChild(input);
  return wrap;
}

function renderFxColumn() {
  fxColumn.innerHTML = "";

  Object.entries(FX_FIELDS).forEach(([section, fields]) => {
    const card = document.createElement("div");
    card.className = "fx-card";

    const header = document.createElement("div");
    header.className = "panel-header compact";
    const title = document.createElement("h3");
    title.textContent = FX_SECTION_LABEL[section] || section;
    header.appendChild(title);

    const mixField = state.data.fx[section].mix;
    if (typeof mixField === "number") {
      const pill = document.createElement("span");
      pill.className = "data-pill";
      pill.textContent = `mix ${mixField.toFixed(2)}`;
      header.appendChild(pill);
    }

    card.appendChild(header);
    const grid = document.createElement("div");
    grid.className = "control-grid tight";
    card.appendChild(grid);
    renderControlGrid(grid, fields);
    fxColumn.appendChild(card);
  });
}

function renderTriggerPad() {
  triggerWall.innerHTML = "";

  TRIGGER_ORDER.forEach((name) => {
    const trigger = state.data.triggers[name];
    const card = document.createElement("div");
    card.className = "trigger-card";

    const copy = document.createElement("div");

    const label = document.createElement("p");
    label.className = "trigger-label";
    label.textContent = TRIGGER_LABEL[name];
    copy.appendChild(label);

    const meta = document.createElement("p");
    meta.className = "trigger-meta";
    meta.textContent = `${getOptionLabel(TRIGGER_MODE_OPTIONS, trigger.mode)}  |  ${trigger.freq.toFixed(0)} Hz  |  amp ${trigger.amp.toFixed(2)}`;
    copy.appendChild(meta);

    card.appendChild(copy);

    const button = document.createElement("button");
    button.type = "button";
    button.className = "fire-button";
    button.textContent = "Fire";
    button.addEventListener("click", () => fireTrigger(name));
    card.appendChild(button);

    triggerWall.appendChild(card);
  });
}

function renderTriggerVoices() {
  triggerVoiceColumn.innerHTML = "";

  TRIGGER_ORDER.forEach((name) => {
    const card = document.createElement("div");
    card.className = "voice-card";

    const header = document.createElement("div");
    header.className = "panel-header compact";
    const title = document.createElement("h3");
    title.textContent = TRIGGER_LABEL[name];
    header.appendChild(title);
    const pill = document.createElement("span");
    pill.className = "data-pill";
    pill.textContent = getOptionLabel(TRIGGER_MODE_OPTIONS, state.data.triggers[name].mode);
    header.appendChild(pill);
    card.appendChild(header);

    const grid = document.createElement("div");
    grid.className = "control-grid tight";
    card.appendChild(grid);

    renderControlGrid(grid, [
      field(`triggers.${name}`, "mode", "Mode", { type: "select", options: TRIGGER_MODE_OPTIONS }),
      field(`triggers.${name}`, "color", "Color", { min: 0, max: 1, step: 0.01, format: formatUnit }),
      field(`triggers.${name}`, "amp", "Amp", { min: 0, max: 1, step: 0.01, format: formatUnit }),
      field(`triggers.${name}`, "freq", "Freq", { min: 40, max: 2400, step: 1, format: (value) => `${value.toFixed(0)} Hz` }),
      field(`triggers.${name}`, "pan", "Pan", { min: -1, max: 1, step: 0.01, format: formatSignedUnit }),
    ]);

    const button = document.createElement("button");
    button.type = "button";
    button.className = "fire-button full-width";
    button.textContent = `Fire ${TRIGGER_LABEL[name]}`;
    button.addEventListener("click", () => fireTrigger(name));
    card.appendChild(button);

    triggerVoiceColumn.appendChild(card);
  });
}

function syncToggle(button, head, active) {
  button.dataset.active = active ? "true" : "false";
  button.textContent = active ? "ON" : "OFF";
  head.lastElementChild.textContent = active ? "ON" : "OFF";
}

function formatFieldValue(fieldConfig, value) {
  if (fieldConfig.type === "toggle") {
    return value ? "ON" : "OFF";
  }
  if (fieldConfig.type === "select") {
    return getOptionLabel(fieldConfig.options, value);
  }
  if (fieldConfig.format) {
    return fieldConfig.format(Number(value));
  }
  return value;
}

function lookupLabel(items, name) {
  const hit = items.find((item) => item.name === name);
  return hit ? hit.label || hit.name : name;
}

if (inputPreview) {
  inputPreview.addEventListener("error", () => {
    const message = inputPreview.error?.message || "Unable to open preview stream";
    setPreviewStatus(`Preview error: ${message}`, "error");
  });
}

window.addEventListener("beforeunload", () => {
  stopPreviewStream();
});

loadState().catch((error) => {
  console.error(error);
  setStatus("Offline");
  setPreviewStatus("Control surface is offline", "error");
});
