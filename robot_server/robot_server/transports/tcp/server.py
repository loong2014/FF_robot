from __future__ import annotations

import asyncio
import logging
from typing import Dict, Optional

from ...models import TransportEnvelope
from ..base import EnvelopeHandler, RuntimeTransport

_logger = logging.getLogger(__name__)

_READ_CHUNK_SIZE = 4096


class TcpTransport(RuntimeTransport):
    """Asyncio TCP transport.

    Responsibilities (aligned with BLE path):
    - Accept one active controller at a time. New connections are
      rejected while an active session exists.
    - Forward raw bytes to RobotRuntime via EnvelopeHandler; StreamDecoder
      lives in RobotRuntime so we just pass the chunk through.
    - Provide per-session `send` and broadcast for 10Hz state push.
    - Clean up writer on disconnect to avoid stale broadcasts.
    """

    name = "tcp"

    def __init__(self, host: str, port: int) -> None:
        self._host = host
        self._port = port
        self._handler: Optional[EnvelopeHandler] = None
        self._server: Optional[asyncio.base_events.Server] = None
        self._clients: Dict[str, asyncio.StreamWriter] = {}
        self._session_counter = 0
        self._active_session_id: Optional[str] = None

    @property
    def host(self) -> str:
        return self._host

    @property
    def port(self) -> int:
        return self._port

    async def start(self, handler: EnvelopeHandler) -> None:
        self._handler = handler
        self._server = await asyncio.start_server(
            self._handle_client, self._host, self._port
        )
        sockets = self._server.sockets or ()
        addresses = ", ".join(str(sock.getsockname()) for sock in sockets)
        _logger.info("TCP transport listening on %s", addresses or f"{self._host}:{self._port}")

    async def stop(self) -> None:
        for session_id, writer in list(self._clients.items()):
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:  # pragma: no cover - best-effort shutdown
                _logger.debug("TCP writer close failed for %s", session_id, exc_info=True)
        self._clients.clear()

        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
            self._server = None
            _logger.info("TCP transport stopped")

    async def send(self, session_id: str, payload: bytes) -> None:
        if session_id != self._active_session_id:
            return
        writer = self._clients.get(session_id)
        if writer is None or writer.is_closing():
            return
        try:
            writer.write(payload)
            await writer.drain()
        except (ConnectionError, OSError) as exc:
            _logger.debug("TCP send failed for %s: %s", session_id, exc)
            self._drop_client(session_id)

    async def broadcast(self, payload: bytes) -> None:
        if self._active_session_id is None:
            return
        await self.send(self._active_session_id, payload)

    def _next_session_id(self, peer: object) -> str:
        self._session_counter += 1
        peer_repr = str(peer) if peer is not None else "anon"
        return f"{peer_repr}#{self._session_counter}"

    def _drop_client(self, session_id: str) -> None:
        writer = self._clients.pop(session_id, None)
        if writer is None:
            return
        try:
            if not writer.is_closing():
                writer.close()
        except Exception:  # pragma: no cover - defensive
            pass

    async def _handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        peer = writer.get_extra_info("peername")
        session_id = self._next_session_id(peer)
        if self._active_session_id is not None:
            _logger.warning(
                "TCP client rejected session=%s peer=%s active_session=%s",
                session_id,
                peer,
                self._active_session_id,
            )
            try:
                if not writer.is_closing():
                    writer.close()
                await writer.wait_closed()
            except Exception:  # pragma: no cover - best-effort cleanup
                pass
            return

        self._clients[session_id] = writer
        self._active_session_id = session_id
        _logger.info("TCP client connected session=%s peer=%s", session_id, peer)

        async def reply(payload: bytes, sid: str = session_id) -> None:
            await self.send(sid, payload)

        try:
            while True:
                try:
                    data = await reader.read(_READ_CHUNK_SIZE)
                except (ConnectionError, OSError) as exc:
                    _logger.debug("TCP read failed session=%s: %s", session_id, exc)
                    break
                if not data:
                    break
                if self._handler is None:
                    continue

                envelope = TransportEnvelope(
                    transport_name=self.name,
                    session_id=session_id,
                    payload=data,
                    reply=reply,
                )
                await self._handler(envelope)
        finally:
            self._drop_client(session_id)
            if self._active_session_id == session_id:
                self._active_session_id = None
            try:
                if not writer.is_closing():
                    writer.close()
                await writer.wait_closed()
            except Exception:  # pragma: no cover - best-effort cleanup
                pass
            _logger.info("TCP client disconnected session=%s", session_id)
