# OSC / ZMQ Protocol Spec

## ZMQ

- Transport: `tcp://*:5555`
- Format: `topic_bytes + b" " + msgpack_payload`
- Payload schema:

```json
{
  "analyzer": "yolo.pose",
  "frame_id": 12345,
  "timestamp": 1234567890.123,
  "detected": true,
  "data": {}
}
```

## ZMQ Topics

| topic | data.keys | fps |
|---|---|---|
| yolo.detect | detections[{id,cls,name,conf,bbox,cx,cy}] | 60 |
| yolo.pose | persons[{id,keypoints(17,3),velocity(17,2),speed,com,bbox}] | 60 |
| yolo.seg | segments[{id,cls,conf,polygon}] | 30 |
| flow.dense | flow_f16(ndarray), energy, direction, quadrants | 30 |
| flow.sparse | vectors[{from,to,vel,speed}], trails, count | 30 |
| mp.pose | landmarks_norm(33,4), landmarks_world(33,3), velocity, speed_norm, energy, com | 60 |
| depth.map | depth_f16(ndarray), mean, com_depth, range | 10 |
| particle.state | spawn_points, attractors, emitters, field(ndarray) | 30 |
| event | events[str], pose_speed, flow_energy, com | 60 |
| meta.fps | fps{analyzer:hz} | 0.1 |

## ndarray Serialization

```python
{
  "__ndarray__": True,
  "dtype": "float32",
  "shape": [33, 3],
  "data": b"..."
}
```

## OSC Targets

- `127.0.0.1:9000` for Swift/Satin
- `127.0.0.1:57120` for SuperCollider

## OSC Address Map

Swift/Satin:

```text
/vrb/person/{id}/pos      x y
/vrb/person/{id}/speed    v
/vrb/person/{id}/bbox     x1 y1 x2 y2 conf
/vrb/person/{id}/joint/{name} x y conf
/vrb/person/mp/{name}     x y z vis
/vrb/flow/energy          v
/vrb/flow/direction       angle
/vrb/depth/com            d
/vrb/meta/detected        0 or 1
```

SuperCollider:

```text
/synth/body               [freq, v, amp, v, cutoff, v, pan, v]
/fx/reverb/mix            [v]
/fx/reverb/room           [v]
/fx/delay/time            [v]
/fx/delay/feedback        [v]
/trigger/motion_onset     [amp, v, freq, v]
/trigger/person_enter     [amp, v, freq, v]
/trigger/person_exit      [amp, v]
/trigger/impact           [amp, v, freq, v]
/trigger/flow_burst       [amp, v, freq, v]
/vrb/meta/detected        [0 or 1]
```
