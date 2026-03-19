const presetGrid = document.getElementById("preset-grid");
const actionGrid = document.getElementById("action-grid");
const triggerWall = document.getElementById("trigger-wall");
const bodyCoreGrid = document.getElementById("body-core-grid");
const bodyVoiceGrid = document.getElementById("body-voice-grid");
const fxColumn = document.getElementById("fx-column");
const triggerVoiceColumn = document.getElementById("trigger-voice-column");
const stateDump = document.getElementById("state-dump");
const serverStatus = document.getElementById("server-status");
const detectedToggle = document.getElementById("detected-toggle");

const MODE_OPTIONS = [
  ["0", "Core"],
  ["1", "Pulse"],
  ["2", "Formant"],
  ["3", "PM"],
];

const BODY_CORE_FIELDS = [
  { key: "freq", label: "Freq", min: 35, max: 2400, step: 1, format: (value) => `${value.toFixed(1)} Hz` },
  { key: "amp", label: "Amp", min: 0, max: 1, step: 0.01, format: (value) => value.toFixed(2) },
  { key: "cutoff", label: "Cutoff", min: 120, max: 10000, step: 10, format: (value) => `${value.toFixed(0)} Hz` },
  { key: "pan", label: "Pan", min: -1, max: 1, step: 0.01, format: (value) => value.toFixed(2) },
];

const BODY_VOICE_FIELDS = [
  { key: "mode", label: "Mode", type: "select", options: MODE_OPTIONS },
  { key: "texture", label: "Texture", min: 0, max: 1, step: 0.01, format: formatUnit },
  { key: "noiseMix", label: "Noise", min: 0, max: 1, step: 0.01, format: formatUnit },
  { key: "subMix", label: "Sub", min: 0, max: 1, step: 0.01, format: formatUnit },
  { key: "motion", label: "Motion", min: 0, max: 1, step: 0.01, format: formatUnit },
  { key: "resonance", label: "Resonance", min: 0.08, max: 0.95, step: 0.01, format: formatUnit },
];

const FX_FIELDS = {
  harshNoise: [
    { key: "enabled", label: "On", type: "toggle" },
    { key: "level", label: "Level", min: 0, max: 1, step: 0.01, format: formatUnit },
    { key: "tone", label: "Tone", min: 0, max: 1, step: 0.01, format: formatUnit },
    { key: "hp", label: "HP", min: 120, max: 12000, step: 1, format: (value) => `${value.toFixed(0)} Hz` },
    { key: "lp", label: "LP", min: 1200, max: 18000, step: 1, format: (value) => `${value.toFixed(0)} Hz` },
    { key: "duck", label: "Duck", min: 0, max: 1, step: 0.01, format: formatUnit },
  ],
  highpass: [
    { key: "enabled", label: "On", type: "toggle" },
    { key: "freq", label: "Freq", min: 20, max: 12000, step: 1, format: (value) => `${value.toFixed(0)} Hz` },
    { key: "resonance", label: "Resonance", min: 0.08, max: 0.95, step: 0.01, format: formatUnit },
    { key: "mix", label: "Mix", min: 0, max: 1, step: 0.01, format: formatUnit },
  ],
  lowpass: [
    { key: "enabled", label: "On", type: "toggle" },
    { key: "freq", label: "Freq", min: 120, max: 18000, step: 1, format: (value) => `${value.toFixed(0)} Hz` },
    { key: "resonance", label: "Resonance", min: 0.08, max: 0.95, step: 0.01, format: formatUnit },
    { key: "mix", label: "Mix", min: 0, max: 1, step: 0.01, format: formatUnit },
  ],
  distortion: [
    { key: "enabled", label: "On", type: "toggle" },
    { key: "drive", label: "Drive", min: 0, max: 1, step: 0.01, format: formatUnit },
    { key: "mix", label: "Mix", min: 0, max: 1, step: 0.01, format: formatUnit },
    { key: "fold", label: "Fold", min: 0, max: 1, step: 0.01, format: formatUnit },
    { key: "bias", label: "Bias", min: -1, max: 1, step: 0.01, format: formatUnit },
    { key: "tone", label: "Tone", min: 0, max: 1, step: 0.01, format: formatUnit },
  ],
  glitch: [
    { key: "enabled", label: "On", type: "toggle" },
    { key: "mix", label: "Mix", min: 0, max: 1, step: 0.01, format: formatUnit },
    { key: "rate", label: "Rate", min: 0.25, max: 40, step: 0.01, format: (value) => `${value.toFixed(2)} Hz` },
    { key: "depth", label: "Depth", min: 0, max: 1, step: 0.01, format: formatUnit },
    { key: "crush", label: "Crush", min: 0, max: 1, step: 0.01, format: formatUnit },
    { key: "gate", label: "Gate", min: 0, max: 1, step: 0.01, format: formatUnit },
  ],
  delay: [
    { key: "time", label: "Time", min: 0.01, max: 0.95, step: 0.01, format: (value) => `${value.toFixed(2)} s` },
    { key: "feedback", label: "Feedback", min: 0.01, max: 0.99, step: 0.01, format: formatUnit },
    { key: "mix", label: "Mix", min: 0, max: 1, step: 0.01, format: formatUnit },
    { key: "tone", label: "Tone", min: 0, max: 1, step: 0.01, format: formatUnit },
  ],
  chorus: [
    { key: "mix", label: "Mix", min: 0, max: 1, step: 0.01, format: formatUnit },
    { key: "rate", label: "Rate", min: 0.02, max: 8, step: 0.01, format: (value) => `${value.toFixed(2)} Hz` },
    { key: "depth", label: "Depth", min: 0.0001, max: 0.05, step: 0.0001, format: (value) => value.toFixed(4) },
  ],
  reverb: [
    { key: "mix", label: "Mix", min: 0, max: 1, step: 0.01, format: formatUnit },
    { key: "room", label: "Room", min: 0, max: 1, step: 0.01, format: formatUnit },
    { key: "damp", label: "Damp", min: 0, max: 1, step: 0.01, format: formatUnit },
    { key: "tone", label: "Tone", min: 0, max: 1, step: 0.01, format: formatUnit },
  ],
  master: [
    { key: "drive", label: "Drive", min: 0, max: 1, step: 0.01, format: formatUnit },
    { key: "width", label: "Width", min: 0, max: 1, step: 0.01, format: formatUnit },
    { key: "tremRate", label: "Trem Rate", min: 0, max: 12, step: 0.01, format: (value) => `${value.toFixed(2)} Hz` },
    { key: "tremDepth", label: "Trem Depth", min: 0, max: 1, step: 0.01, format: formatUnit },
    { key: "output", label: "Output", min: 0, max: 1, step: 0.01, format: formatUnit },
  ],
};

const TRIGGER_ORDER = ["onset", "impact", "enter", "exit", "flow"];

const TRIGGER_LABEL = {
  onset: "Motion Onset",
  impact: "Impact",
  enter: "Person Enter",
  exit: "Person Exit",
  flow: "Flow Burst",
};

const ACTION_LABEL = {
  reset: "Reset",
  mute: "Mute",
  dry: "Dry Rack",
  wide: "Wide",
  storm: "Storm",
  brutalize: "Brutalize",
  "filter-choke": "Filter Choke",
  "glitch-wall": "Glitch Wall",
  "random-soft": "Random Soft",
  "random-bold": "Random Bold",
};

const FX_SECTION_LABEL = {
  harshNoise: "Harsh Noise",
  highpass: "High-Pass",
  lowpass: "Low-Pass",
  distortion: "Distortion",
  glitch: "Glitch",
  delay: "Delay",
  chorus: "Chorus",
  reverb: "Reverb",
  master: "Master",
};

const state = {
  presets: [],
  actions: [],
  data: null,
};

let patchTimer = null;
let pendingPatch = {};

document.getElementById("refresh-state").addEventListener("click", async () => {
  await loadState();
});

detectedToggle.addEventListener("click", async () => {
  if (!state.data) return;
  const nextValue = !state.data.body.core.detected;
  await sendPatch({ body: { core: { detected: nextValue } } });
});

function formatUnit(value) {
  return Number(value).toFixed(2);
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

function queuePatch(patch) {
  mergePatch(pendingPatch, patch);
  clearTimeout(patchTimer);
  patchTimer = setTimeout(async () => {
    const nextPatch = pendingPatch;
    pendingPatch = {};
    await sendPatch(nextPatch);
  }, 80);
}

async function sendPatch(patch) {
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
  setStatus("Live");
  renderState();
}

async function recallPreset(name) {
  const response = await fetch(`/api/preset/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({}),
  });
  const payload = await response.json();
  state.data = payload.state;
  setStatus(`Preset ${name}`);
  window.setTimeout(() => setStatus("Live"), 900);
  renderState();
}

async function fireAction(name) {
  const response = await fetch(`/api/action/${name}`, {
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
  setStatus(`Action ${ACTION_LABEL[name] || name}`);
  window.setTimeout(() => setStatus("Live"), 900);
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
  window.setTimeout(() => {
    setStatus("Live");
  }, 1000);
}

async function loadState() {
  const [stateResponse, presetResponse, actionResponse] = await Promise.all([
    fetch("/api/state"),
    fetch("/api/presets"),
    fetch("/api/actions"),
  ]);
  const statePayload = await stateResponse.json();
  const presetPayload = await presetResponse.json();
  const actionPayload = await actionResponse.json();
  state.data = statePayload.state;
  state.presets = presetPayload.presets;
  state.actions = actionPayload.actions;
  setStatus("Live");
  renderStaticChrome();
  renderState();
}

function renderStaticChrome() {
  presetGrid.innerHTML = "";
  state.presets.forEach((presetName) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "preset-button";
    button.textContent = presetName;
    button.addEventListener("click", () => recallPreset(presetName));
    presetGrid.appendChild(button);
  });

  actionGrid.innerHTML = "";
  state.actions.forEach((actionName) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "action-button";
    button.textContent = ACTION_LABEL[actionName] || actionName;
    button.addEventListener("click", () => fireAction(actionName));
    actionGrid.appendChild(button);
  });

  triggerWall.innerHTML = "";
  TRIGGER_ORDER.forEach((name) => {
    const card = document.createElement("div");
    card.className = "trigger-card";
    card.innerHTML = `
      <div>
        <p class="trigger-label">${TRIGGER_LABEL[name]}</p>
        <p class="trigger-meta">mode + color + fire</p>
      </div>
    `;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "fire-button";
    button.textContent = "Fire";
    button.addEventListener("click", () => fireTrigger(name));
    card.appendChild(button);
    triggerWall.appendChild(card);
  });
}

function setStatus(label) {
  serverStatus.textContent = label;
}

function renderState() {
  if (!state.data) return;

  document.getElementById("freq-readout").textContent = `${state.data.body.core.freq.toFixed(1)} Hz`;
  document.getElementById("amp-readout").textContent = state.data.body.core.amp.toFixed(2);
  document.getElementById("cutoff-readout").textContent = `${state.data.body.core.cutoff.toFixed(0)} Hz`;
  document.getElementById("pan-readout").textContent = state.data.body.core.pan.toFixed(2);
  detectedToggle.textContent = state.data.body.core.detected ? "ON" : "OFF";
  detectedToggle.dataset.active = state.data.body.core.detected ? "true" : "false";
  stateDump.textContent = JSON.stringify(state.data, null, 2);

  renderFieldGrid(bodyCoreGrid, state.data.body.core, BODY_CORE_FIELDS, (key, value) => {
    queuePatch({ body: { core: { [key]: value } } });
  });

  renderFieldGrid(bodyVoiceGrid, state.data.body.voice, BODY_VOICE_FIELDS, (key, value) => {
    queuePatch({ body: { voice: { [key]: value } } });
  });

  fxColumn.innerHTML = "";
  Object.entries(FX_FIELDS).forEach(([section, fields]) => {
    const card = document.createElement("div");
    card.className = "fx-card";
    const heading = document.createElement("h3");
    heading.textContent = FX_SECTION_LABEL[section] || section;
    card.appendChild(heading);
    const grid = document.createElement("div");
    grid.className = "control-grid tight";
    card.appendChild(grid);
    renderFieldGrid(grid, state.data.fx[section], fields, (key, value) => {
      queuePatch({ fx: { [section]: { [key]: value } } });
    });
    fxColumn.appendChild(card);
  });

  triggerVoiceColumn.innerHTML = "";
  TRIGGER_ORDER.forEach((name) => {
    const card = document.createElement("div");
    card.className = "voice-card";
    const heading = document.createElement("h3");
    heading.textContent = TRIGGER_LABEL[name];
    card.appendChild(heading);
    const fields = [
      { key: "mode", label: "Mode", type: "select", options: MODE_OPTIONS },
      { key: "color", label: "Color", min: 0, max: 1, step: 0.01, format: formatUnit },
      { key: "amp", label: "Amp", min: 0, max: 1, step: 0.01, format: formatUnit },
      { key: "freq", label: "Freq", min: 40, max: 2400, step: 1, format: (value) => `${value.toFixed(0)} Hz` },
      { key: "pan", label: "Pan", min: -1, max: 1, step: 0.01, format: formatUnit },
    ];
    const grid = document.createElement("div");
    grid.className = "control-grid tight";
    card.appendChild(grid);
    renderFieldGrid(grid, state.data.triggers[name], fields, (key, value) => {
      queuePatch({ triggers: { [name]: { [key]: value } } });
    });
    const button = document.createElement("button");
    button.type = "button";
    button.className = "fire-button full-width";
    button.textContent = `Fire ${TRIGGER_LABEL[name]}`;
    button.addEventListener("click", () => fireTrigger(name));
    card.appendChild(button);
    triggerVoiceColumn.appendChild(card);
  });
}

function renderFieldGrid(container, values, fields, onChange) {
  container.innerHTML = "";
  fields.forEach((field) => {
    const wrap = document.createElement("label");
    wrap.className = "control-field";
    const head = document.createElement("div");
    head.className = "control-head";
    head.innerHTML = `<span>${field.label}</span><span>${formatFieldValue(field, values[field.key])}</span>`;
    wrap.appendChild(head);

    if (field.type === "toggle") {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "toggle-switch";
      const syncToggle = (active) => {
        button.dataset.active = active ? "true" : "false";
        button.textContent = active ? "ON" : "OFF";
        head.lastElementChild.textContent = active ? "ON" : "OFF";
      };
      syncToggle(Boolean(values[field.key]));
      button.addEventListener("click", () => {
        const nextValue = !Boolean(values[field.key]);
        values[field.key] = nextValue;
        syncToggle(nextValue);
        onChange(field.key, nextValue);
      });
      wrap.appendChild(button);
    } else if (field.type === "select") {
      const select = document.createElement("select");
      field.options.forEach(([value, label]) => {
        const option = document.createElement("option");
        option.value = value;
        option.textContent = label;
        select.appendChild(option);
      });
      select.value = String(values[field.key]);
      select.addEventListener("change", () => onChange(field.key, Number(select.value)));
      wrap.appendChild(select);
    } else {
      const input = document.createElement("input");
      input.type = "range";
      input.min = field.min;
      input.max = field.max;
      input.step = field.step;
      input.value = values[field.key];
      input.addEventListener("input", () => {
        head.lastElementChild.textContent = field.format(Number(input.value));
        onChange(field.key, Number(input.value));
      });
      wrap.appendChild(input);
    }

    container.appendChild(wrap);
  });
}

function formatFieldValue(field, value) {
  if (field.type === "toggle") {
    return value ? "ON" : "OFF";
  }
  if (field.format) {
    return field.format(Number(value));
  }
  return value;
}

loadState().catch((error) => {
  console.error(error);
  setStatus("Offline");
});
