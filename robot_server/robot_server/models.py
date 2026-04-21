from __future__ import annotations

from dataclasses import dataclass
from typing import Awaitable, Callable


ReplyFn = Callable[[bytes], Awaitable[None]]


@dataclass
class TransportEnvelope:
    transport_name: str
    session_id: str
    payload: bytes
    reply: ReplyFn

    @property
    def peer_key(self) -> str:
        return f"{self.transport_name}:{self.session_id}"

