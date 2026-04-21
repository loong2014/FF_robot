from __future__ import annotations

from collections import deque
from dataclasses import dataclass, replace
from typing import Deque, Optional


@dataclass(frozen=True)
class QueuedCommand:
    seq: int
    frame: bytes
    is_move: bool
    retries: int = 0
    last_sent_at: Optional[float] = None

    def mark_sent(self, sent_at: float) -> "QueuedCommand":
        return replace(self, last_sent_at=sent_at)

    def bump_retry(self, sent_at: float) -> "QueuedCommand":
        return replace(self, retries=self.retries + 1, last_sent_at=sent_at)


class CommandQueue:
    def __init__(self) -> None:
        self._discrete_queue: Deque[QueuedCommand] = deque()
        self._move_slot: Optional[QueuedCommand] = None
        self._inflight: Optional[QueuedCommand] = None

    @property
    def inflight(self) -> Optional[QueuedCommand]:
        return self._inflight

    @property
    def has_pending(self) -> bool:
        return self._inflight is not None or self._move_slot is not None or bool(self._discrete_queue)

    def enqueue(self, command: QueuedCommand) -> None:
        if command.is_move:
            self._move_slot = command
            return
        self._discrete_queue.append(command)

    def promote_next(self, sent_at: float) -> Optional[QueuedCommand]:
        if self._inflight is not None:
            return None

        next_command = self._discrete_queue.popleft() if self._discrete_queue else self._move_slot
        if next_command is None:
            return None

        if next_command is self._move_slot:
            self._move_slot = None

        self._inflight = next_command.mark_sent(sent_at)
        return self._inflight

    def ack(self, seq: int) -> bool:
        if self._inflight is None or self._inflight.seq != seq:
            return False
        self._inflight = None
        return True

    def retry_current(self, sent_at: float, max_retries: int) -> Optional[QueuedCommand]:
        if self._inflight is None:
            return None
        if self._inflight.retries >= max_retries:
            self._inflight = None
            return None
        self._inflight = self._inflight.bump_retry(sent_at)
        return self._inflight

    def drop_current(self) -> None:
        self._inflight = None
