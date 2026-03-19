# SuperCollider Receiver Spec

## Runtime

- 受信ポート: `57120`
- 常時音用 body synth と、離散イベント用 trigger synth を分離する
- FX は専用バスで `delay -> chorus -> reverb -> master` の順に後段処理する
- `sclang supercollider/vrb_receiver.scd` でファイル全体を直接実行できる構造にする
- manual performance 用に WebUI bridge からの `/ui/*` OSC を受ける

## Server Options

```supercollider
s.options.numInputBusChannels = 0;
s.options.sampleRate = 44100;
```

## OSC Inputs

連続制御:

```text
/synth/body             [freq, v, amp, v, cutoff, v, pan, v]
/fx/reverb/mix          [v]
/fx/reverb/room         [v]
/fx/delay/time          [v]
/fx/delay/feedback      [v]
/ui/body                [mode, v, texture, v, noiseMix, v, subMix, v, motion, v, resonance, v]
/ui/fx/delay            [time, v, feedback, v, mix, v, tone, v]
/ui/fx/chorus           [mix, v, rate, v, depth, v]
/ui/fx/reverb           [mix, v, room, v, damp, v, tone, v]
/ui/master              [drive, v, width, v, tremRate, v, tremDepth, v, output, v]
/ui/trigger/onset       [mode, v, color, v]
/ui/trigger/impact      [mode, v, color, v]
/ui/trigger/enter       [mode, v, color, v]
/ui/trigger/exit        [mode, v, color, v]
/ui/trigger/flow        [mode, v, color, v]
/vrb/meta/detected      [0 or 1]
```

離散トリガー:

```text
/trigger/motion_onset   [amp, v, freq, v]
/trigger/person_enter   [amp, v, freq, v]
/trigger/person_exit    [amp, v]
/trigger/impact         [amp, v, freq, v]
/trigger/flow_burst     [amp, v, freq, v]
```

## SynthDefs

- `\vrb_body` 持続音。sub layer + torso harmonic layer + formant layer + breath/shimmer noise を `cutoff` と `amp` に追従させる
- `\vrb_body` は 4 mode を持つ。`Core / Pulse / Formant / PM` を `SelectX` で補間し、`texture / noiseMix / subMix / motion / resonance` を外部から操作する
- `\vrb_onset` モーション開始の短い strike。filtered noise + pitched body
- `\vrb_impact` 衝撃音。low thump + crack + short ring
- `\vrb_enter` 人物検出の上昇音。rising saw family + shimmer
- `\vrb_exit` 人物消失の下降音。falling pulse/body + dusty tail
- `\vrb_flow_burst` フロー急増のノイズバースト。band-pass noise cloud + resonant particles
- 各 trigger synth は `mode` と `color` を持ち、音色ファミリーを切り替えられる
- `\vrb_delay` `CombC` ベースのディレイ
- `\vrb_chorus` stereo delay modulation
- `\vrb_reverb` `FreeVerb2` を使う
- `\vrb_master` drive / width / tremolo / output trim

## Implementation Constraints

- `JPverb` は使わず `FreeVerb2` を使う
- `var` 宣言は各ブロックの先頭に置く
- `EnvGen` には `doneAction: 2` を付ける
- 出力は `Pan2.ar(...)` か `sig ! 2` でステレオ化する
- クリップ対策として最終出力は `.tanh` を通す
- `person_enter` / `person_exit` は `pan` を受け取った場合に空間位置へ反映する
- cleanup は自動実行せず、必要なら `~vrbCleanup.()` で呼べるようにする
- WebUI bridge は `/synth/body` と `/ui/*` を併用し、state mirror を保つ

## Named Pair Parsing

```supercollider
var args = msg[1..].asArray;
var ampIndex = args.indexOf(\amp);
var freqIndex = args.indexOf(\freq);
var amp = if(ampIndex.notNil) { args[ampIndex + 1] } { 0.5 };
var freq = if(freqIndex.notNil) { args[freqIndex + 1] } { 440 };
```

`?` と `->` を組み合わせた省略形は使わない。
