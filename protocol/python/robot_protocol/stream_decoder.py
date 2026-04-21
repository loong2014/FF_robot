from __future__ import annotations

from typing import List

from .codec import ProtocolError, decode_frame
from .constants import FRAME_OVERHEAD, MAGIC, MAX_PAYLOAD_LENGTH
from .models import Frame


class StreamDecoder:
    def __init__(self) -> None:
        self._buffer = bytearray()

    def feed(self, chunk: bytes) -> List[Frame]:
        if not chunk:
            return []

        self._buffer.extend(chunk)
        frames: List[Frame] = []

        while True:
            start = self._buffer.find(MAGIC)
            if start < 0:
                self._buffer[:] = self._buffer[-1:] if self._buffer[-1:] == MAGIC[:1] else b""
                break

            if start > 0:
                del self._buffer[:start]

            if len(self._buffer) < FRAME_OVERHEAD:
                break

            payload_len = int.from_bytes(self._buffer[4:6], "little", signed=False)
            if payload_len > MAX_PAYLOAD_LENGTH:
                del self._buffer[0]
                continue

            total_length = FRAME_OVERHEAD + payload_len
            if len(self._buffer) < total_length:
                break

            candidate = bytes(self._buffer[:total_length])
            try:
                frame = decode_frame(candidate)
            except ProtocolError:
                del self._buffer[0]
                continue

            frames.append(frame)
            del self._buffer[:total_length]

        return frames

