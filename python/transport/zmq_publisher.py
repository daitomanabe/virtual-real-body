from __future__ import annotations

from typing import Any

try:
    import msgpack
except ImportError:  # pragma: no cover
    msgpack = None

try:
    import zmq
except ImportError:  # pragma: no cover
    zmq = None


class ZMQPublisher:
    def __init__(self, bind_address: str) -> None:
        self.bind_address = bind_address
        self._context = None
        self._socket = None

    def connect(self) -> None:
        if zmq is None:
            return
        if self._socket is not None:
            return
        self._context = zmq.Context.instance()
        self._socket = self._context.socket(zmq.PUB)
        self._socket.bind(self.bind_address)

    def publish(self, topic: bytes, payload: dict[str, Any], analyzer_name: str | None = None) -> bytes:
        packet = topic + b" " + self._pack(payload, analyzer_name=analyzer_name)
        if self._socket is not None:
            self._socket.send(packet)
        return packet

    def _pack(self, payload: dict[str, Any], analyzer_name: str | None = None) -> bytes:
        enriched = dict(payload)
        if analyzer_name and "analyzer" not in enriched:
            enriched["analyzer"] = analyzer_name
        if msgpack is None:
            return repr(enriched).encode("utf-8")
        return msgpack.packb(self._serialize(enriched), use_bin_type=True)

    def _serialize(self, value: Any) -> Any:
        if isinstance(value, dict):
            return {key: self._serialize(item) for key, item in value.items()}
        if isinstance(value, (list, tuple)):
            return [self._serialize(item) for item in value]
        dtype = getattr(value, "dtype", None)
        shape = getattr(value, "shape", None)
        if dtype is not None and shape is not None and hasattr(value, "tobytes"):
            return {
                "__ndarray__": True,
                "dtype": str(dtype),
                "shape": list(shape),
                "data": value.tobytes(),
            }
        return value

    def close(self) -> None:
        if self._socket is not None:
            self._socket.close(linger=0)
            self._socket = None
