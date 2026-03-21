const sourceModeButtons = Array.from(document.querySelectorAll("[data-source-mode]"));
const deviceSelect = document.getElementById("monitor-device-select");
const videoSelect = document.getElementById("monitor-video-select");
const videoPathInput = document.getElementById("monitor-video-path");
const loopToggle = document.getElementById("monitor-loop-toggle");
const refreshButton = document.getElementById("monitor-refresh");
const browserFullscreenButton = document.getElementById("monitor-browser-fullscreen");
const preview = document.getElementById("monitor-preview");
const sourceSummary = document.getElementById("monitor-source-summary");
const sourceChip = document.getElementById("monitor-source-chip");
const stageTitle = document.getElementById("monitor-stage-title");
const statusLabel = document.getElementById("monitor-status");
const previewStatus = document.getElementById("monitor-preview-status");
const sessionFileLabel = document.getElementById("monitor-session-file");

const state = {
  session: null,
  media: { videos: [], cameras: [] },
  sessionFile: "",
};

let previewStream = null;
let browserCameraDevices = [];
let previewSyncToken = 0;
let pollTimer = null;
let lastSessionFingerprint = "";
let activePreviewSignature = "";

sourceModeButtons.forEach((button) => {
  button.addEventListener("click", async () => {
    await sendSessionPatch({ source: { mode: button.dataset.sourceMode } });
  });
});

deviceSelect.addEventListener("change", async () => {
  await sendSessionPatch({
    source: {
      mode: "camera",
      camera_index: Math.max(Number(deviceSelect.value || 0), 0),
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

videoPathInput.addEventListener("change", async () => {
  await sendSessionPatch({
    source: {
      mode: "video",
      video_file: videoPathInput.value.trim(),
    },
  });
});

loopToggle.addEventListener("click", async () => {
  const nextLoop = !Boolean(state.session?.source?.loop);
  await sendSessionPatch({ source: { loop: nextLoop } });
});

refreshButton.addEventListener("click", async () => {
  await loadSession();
});

browserFullscreenButton.addEventListener("click", async () => {
  if (!document.fullscreenElement) {
    await document.documentElement.requestFullscreen?.();
    return;
  }
  await document.exitFullscreen?.();
});

preview.addEventListener("error", () => {
  const message = preview.error?.message || "Unable to open preview stream";
  setPreviewStatus(`Preview error: ${message}`, "error");
});

window.addEventListener("beforeunload", () => {
  stopPreviewStream();
  if (pollTimer) {
    window.clearInterval(pollTimer);
  }
});

function setStatus(label) {
  statusLabel.textContent = label;
}

function setPreviewStatus(label, stateName = "warn") {
  previewStatus.textContent = label;
  previewStatus.dataset.state = stateName;
}

function stopPreviewStream() {
  if (!previewStream) {
    return;
  }
  previewStream.getTracks().forEach((track) => track.stop());
  previewStream = null;
  activePreviewSignature = "";
}

function clearPreviewVideoSource() {
  if (preview.srcObject) {
    preview.srcObject = null;
  }
  if (preview.hasAttribute("src")) {
    preview.pause();
    preview.removeAttribute("src");
    preview.load();
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

function populateVideoSelect(select, videos, currentPath) {
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
  if (currentPath && !videos.some((entry) => entry.path === currentPath)) {
    const option = document.createElement("option");
    option.value = currentPath;
    option.textContent = currentPath;
    select.appendChild(option);
  }
  select.value = currentPath;
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
  Array.from(deviceSelect.options).forEach((option) => {
    const index = Number(option.value);
    const browserDevice = browserCameraDevices[index];
    if (!browserDevice?.label) {
      return;
    }
    option.textContent = `${index}: ${browserDevice.label}`;
  });
}

async function syncPreview() {
  if (!state.session) {
    clearPreviewVideoSource();
    stopPreviewStream();
    sourceSummary.textContent = "Waiting";
    sourceChip.textContent = "No Source";
    stageTitle.textContent = "Waiting for source";
    setPreviewStatus("Waiting for session", "warn");
    return;
  }

  const token = ++previewSyncToken;
  const source = state.session.source || {};
  const isVideo = source.mode === "video";
  const sourceSignature = JSON.stringify({
    mode: source.mode || "camera",
    camera_index: Number(source.camera_index ?? 0),
    video_file: String(source.video_file || ""),
    loop: Boolean(source.loop),
  });

  if (isVideo) {
    const filePath = String(source.video_file || "").trim();
    if (!filePath) {
      clearPreviewVideoSource();
      stopPreviewStream();
      stageTitle.textContent = "Movie file is not set";
      sourceSummary.textContent = "Movie";
      sourceChip.textContent = "Movie";
      setPreviewStatus("Movie file is not set", "error");
      return;
    }

    const nextURL = buildVideoPreviewURL(filePath);
    if (
      activePreviewSignature === sourceSignature &&
      preview.dataset.previewMode === "video" &&
      preview.src === new URL(nextURL, window.location.href).href
    ) {
      const label = labelFromPath(filePath);
      sourceSummary.textContent = label;
      sourceChip.textContent = "Movie";
      stageTitle.textContent = label;
      setPreviewStatus(`Movie preview active: ${label}`, "ok");
      return;
    }

    stopPreviewStream();
    if (preview.srcObject) {
      preview.srcObject = null;
    }
    if (preview.dataset.previewMode !== "video" || preview.src !== new URL(nextURL, window.location.href).href) {
      clearPreviewVideoSource();
      preview.src = nextURL;
    }

    preview.dataset.previewMode = "video";
    preview.loop = Boolean(source.loop);
    try {
      await preview.play();
    } catch (error) {
      console.warn(error);
    }

    if (token !== previewSyncToken) {
      return;
    }

    const label = labelFromPath(filePath);
    activePreviewSignature = sourceSignature;
    sourceSummary.textContent = label;
    sourceChip.textContent = "Movie";
    stageTitle.textContent = label;
    setPreviewStatus(`Movie preview active: ${label}`, "ok");
    return;
  }

  clearPreviewVideoSource();
  sourceChip.textContent = "Device";
  stageTitle.textContent = `Device ${Number(source.camera_index ?? 0)}`;

  if (activePreviewSignature === sourceSignature && previewStream && previewStream.active) {
    const activeLabel = deviceSelect.selectedOptions[0]?.textContent || `Device ${Number(source.camera_index ?? 0)}`;
    sourceSummary.textContent = activeLabel;
    stageTitle.textContent = activeLabel;
    setPreviewStatus(`Camera preview active: ${activeLabel}`, "ok");
    return;
  }

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
    preview.srcObject = stream;
    preview.dataset.previewMode = "camera";
    try {
      await preview.play();
    } catch (error) {
      console.warn(error);
    }

    await refreshBrowserCameraDevices();
    if (token !== previewSyncToken) {
      return;
    }

    const activeLabel = chosenDevice?.label || `Device ${cameraIndex}`;
    activePreviewSignature = sourceSignature;
    sourceSummary.textContent = activeLabel;
    stageTitle.textContent = activeLabel;
    setPreviewStatus(`Camera preview active: ${activeLabel}`, "ok");
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    setPreviewStatus(`Camera preview failed: ${message}`, "error");
  }
}

function renderSession() {
  if (!state.session) {
    return;
  }

  const source = state.session.source || {};
  const currentCameraIndex = Number(source.camera_index ?? 0);
  const currentPath = source.video_file || "";

  sessionFileLabel.textContent = state.sessionFile ? state.sessionFile.split("/").pop() : "session";
  videoPathInput.value = currentPath;
  loopToggle.dataset.active = source.loop ? "true" : "false";
  loopToggle.textContent = source.loop ? "Loop ON" : "Loop OFF";

  populateOptionSelect(
    deviceSelect,
    Array.isArray(state.media?.cameras) ? state.media.cameras : [],
    currentCameraIndex,
    (entry) => String(entry.index),
    (entry) => entry.label || `Device ${entry.index}`,
  );
  populateVideoSelect(videoSelect, Array.isArray(state.media?.videos) ? state.media.videos : [], currentPath);

  sourceModeButtons.forEach((button) => {
    button.classList.toggle("is-active", button.dataset.sourceMode === source.mode);
  });

  const isVideo = source.mode === "video";
  deviceSelect.disabled = isVideo;
  videoSelect.disabled = !isVideo;
  videoPathInput.disabled = !isVideo;
  loopToggle.disabled = !isVideo;
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
  await syncPreview();
  setStatus("Live");
}

async function loadSession() {
  const response = await fetch("/api/session");
  if (!response.ok) {
    setStatus("Offline");
    setPreviewStatus("Session API is offline", "error");
    return;
  }

  const payload = await response.json();
  const fingerprint = JSON.stringify({
    session: payload.session || {},
    media: payload.media || {},
    session_file: payload.session_file || "",
  });
  if (fingerprint === lastSessionFingerprint) {
    setStatus("Live");
    return;
  }
  lastSessionFingerprint = fingerprint;
  state.session = payload.session;
  state.media = payload.media;
  state.sessionFile = payload.session_file || "";
  renderSession();
  await syncPreview();
  setStatus("Live");
}

async function boot() {
  await loadSession();
  pollTimer = window.setInterval(() => {
    void loadSession();
  }, 1000);
}

boot().catch((error) => {
  console.error(error);
  setStatus("Offline");
  setPreviewStatus("Monitor failed to initialize", "error");
});
