# WebUI Control Surface Spec

## Purpose

- SuperCollider receiver を手動演奏できる browser control surface を提供する
- Python analysis engine を止めた状態でも、SC 音色と FX を単独で audition できるようにする
- 現在の runtime state を HTTP と OSC の両方で mirror する

## Runtime

- Bridge server: `python/sc_control_server.py`
- Default bind: `127.0.0.1:8080`
- SC target: `127.0.0.1:57120`
- Static assets: `webui/index.html`, `webui/app.js`, `webui/styles.css`

## API

### Read endpoints

```text
GET /api/state
GET /api/presets
GET /api/actions
```

### Write endpoints

```text
POST /api/state
POST /api/preset/{name}
POST /api/action/{name}
POST /api/trigger/{name}
```

## Presets

- `ember-choir`
- `glass-cavern`
- `machine-ritual`
- `shattered-lattice`
- `submerged-brass`
- `tidal-halo`

## Macro Actions

- `reset`
- `mute`
- `dry`
- `wide`
- `storm`
- `random-soft`
- `random-bold`

## UI Layout

- fixed top hero: status, detected toggle, preset lane, macro lane
- fixed left viewport: performance meters, trigger wall, raw state dump
- right control column with internal scroll only
- body core, body voice, FX rack, trigger voices を section 分割する

## Interaction Model

- sliders は `input` event で 80ms debounce patch を送る
- preset / macro / trigger は即時 POST
- detected toggle は `/vrb/meta/detected` と body amp gate の mirror として扱う
- UI の state dump は server snapshot をそのまま表示する

## OSC Emission

- body core は `/synth/body`
- detected は `/vrb/meta/detected`
- body voice は `/ui/body`
- FX は `/ui/fx/delay`, `/ui/fx/chorus`, `/ui/fx/reverb`, `/ui/master`
- trigger timbre は `/ui/trigger/*`
- trigger fire は `/trigger/*`
