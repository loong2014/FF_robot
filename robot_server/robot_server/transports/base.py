from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Awaitable, Callable

from ..models import TransportEnvelope


EnvelopeHandler = Callable[[TransportEnvelope], Awaitable[None]]


class RuntimeTransport(ABC):
    name: str

    @abstractmethod
    async def start(self, handler: EnvelopeHandler) -> None:
        raise NotImplementedError

    @abstractmethod
    async def stop(self) -> None:
        raise NotImplementedError

    @abstractmethod
    async def send(self, session_id: str, payload: bytes) -> None:
        raise NotImplementedError

    @abstractmethod
    async def broadcast(self, payload: bytes) -> None:
        raise NotImplementedError

