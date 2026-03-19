# Python Engine Spec

## Analyzer 抽象クラス

```python
class Analyzer(ABC):
    name:      str   # "yolo.pose"
    zmq_topic: bytes # b"yolo.pose"

    @abstractmethod
    def process(self, frame_bgr: np.ndarray, frame_id: int) -> AnalysisResult: ...
    def osc_messages(self, result: AnalysisResult) -> list[tuple[str, list]]: return []
    def close(self) -> None: pass
```

## AnalysisEngine スレッドモデル

```
MainThread:
  cap.read() → frame_bgr
  for inline analyzers: process() → _on_result()
  for threaded analyzers: worker.enqueue(frame, frame_id)

WorkerThread(per analyzer):
  queue.get() → analyzer.process() → _on_result()
  queue maxsize=2 → drop oldest on full (prioritise latency)

_on_result():
  zmq.publish(topic, result)
  osc.send_batch(analyzer.osc_messages(result))
  meta-analyzer hooks: event_a.update_*(result), particle_a.update_*(result)
```

## EventAnalyzer (meta)

連続値 → 離散SCイベントの検出ロジック:

```python
# motion_onset: speed が threshold を下から上に超えたとき
if speed > THRESHOLD and prev_speed <= THRESHOLD and cooldown == 0:
    emit /trigger/motion_onset [amp, speed*0.85, freq, exp_map(com_y)]

# impact: acceleration spike
if accel > ACCEL_THRESHOLD and cooldown == 0:
    emit /trigger/impact [amp, ..., freq, ...]

# person enter/exit: detected state change
if detected and not prev_detected: emit /trigger/person_enter
if not detected and prev_detected: emit /trigger/person_exit

# flow burst: flow energy spike
if flow_energy > FLOW_THRESHOLD and cooldown == 0:
    emit /trigger/flow_burst
```

継続制御 (毎フレーム):

```python
# pose CoM y → SC synth freq (exponential, inverted)
freq = SC_FREQ_HIGH * (SC_FREQ_LOW/SC_FREQ_HIGH) ** com_y  # top=high
emit /synth/body [freq, f, amp, a, cutoff, c, pan, p]

# flow energy → reverb
emit /fx/reverb/mix [flow_energy * 0.75]
```
