from __future__ import annotations

from typing import Iterable

from config import OSCClientTarget

try:
    from pythonosc.udp_client import SimpleUDPClient
except ImportError:  # pragma: no cover
    SimpleUDPClient = None


class OSCBroadcaster:
    def __init__(self, targets: Iterable[OSCClientTarget]) -> None:
        self.targets = list(targets)
        self._clients = self._build_clients()

    def _build_clients(self) -> list[object]:
        if SimpleUDPClient is None:
            return []
        return [SimpleUDPClient(target.host, target.port) for target in self.targets]

    def send(self, address: str, values: list[float | int]) -> None:
        for client in self._clients:
            client.send_message(address, values)

    def send_batch(self, messages: Iterable[tuple[str, list[float | int]]]) -> None:
        for address, values in messages:
            self.send(address, values)
