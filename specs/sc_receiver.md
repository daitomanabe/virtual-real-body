# SuperCollider Receiver Spec

## Runtime

- 受信ポート: `57120`
- 常時音用 body synth と、離散イベント用 trigger synth を分離する
- FX は専用バスで後段処理する

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

- `\vrb_body` 持続音。`SinOsc` 複数 + `BrownNoise` + `RLPF`
- `\vrb_onset` モーション開始の打撃音
- `\vrb_impact` 衝撃音
- `\vrb_enter` 人物検出の上昇音
- `\vrb_exit` 人物消失の下降音
- `\vrb_flow_burst` フロー急増のノイズバースト
- `\vrb_reverb` `FreeVerb2` を使う
- `\vrb_delay` `CombC` ベースのディレイ

## Implementation Constraints

- `JPverb` は使わず `FreeVerb2` を使う
- `var` 宣言は各ブロックの先頭に置く
- `EnvGen` には `doneAction: 2` を付ける
- 出力は `Pan2.ar(...)` か `sig ! 2` でステレオ化する
- クリップ対策として最終出力は `.tanh` を通す

## Named Pair Parsing

```supercollider
var args = msg[1..].asArray;
var ampIndex = args.indexOf(\amp);
var freqIndex = args.indexOf(\freq);
var amp = if(ampIndex.notNil) { args[ampIndex + 1] } { 0.5 };
var freq = if(freqIndex.notNil) { args[freqIndex + 1] } { 440 };
```

`?` と `->` を組み合わせた省略形は使わない。
