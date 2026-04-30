from __future__ import annotations

import asyncio
import logging
from typing import TYPE_CHECKING, Any, Dict, List, Optional

from robot_protocol import RobotState, StreamDecoder, build_state_frame, encode_frame

from ..config import DebugStateTickConfig
from ..models import TransportEnvelope
from ..ros.bridge import RosControlBridge
from ..ros.skill_bridge import RosSkillBridge
from ..transports.base import RuntimeTransport
from .control_service import RobotControlService
from .state_store import StateStore

if TYPE_CHECKING:  # pragma: no cover - typing only
    from ..ros.state_bridge import RosStateBridge


LOGGER = logging.getLogger(__name__)


class RobotRuntime:
    def __init__(
        self,
        transports: List[RuntimeTransport],
        ros_bridge: RosControlBridge,
        ros_skill_bridge: Optional[RosSkillBridge] = None,
        state_store: Optional[StateStore] = None,
        debug_state_tick: Optional[DebugStateTickConfig] = None,
        state_hz: int = 10,
        ros_state_bridge: Optional["RosStateBridge"] = None,
    ) -> None:
        self._transports = transports
        self._state_store = state_store or StateStore()
        self._ros_bridge = ros_bridge
        self._ros_skill_bridge = ros_skill_bridge
        self._ros_state_bridge = ros_state_bridge
        self._debug_state_tick = debug_state_tick or DebugStateTickConfig()
        self._control_service = RobotControlService(
            ros_bridge=self._ros_bridge,
            ros_skill_bridge=self._ros_skill_bridge,
            state_store=self._state_store,
        )
        self._decoders: Dict[str, StreamDecoder] = {}
        self._state_hz = state_hz
        self._state_task: Optional["asyncio.Task[None]"] = None
        self._debug_state_task: Optional["asyncio.Task[None]"] = None

    @property
    def state_store(self) -> StateStore:
        return self._state_store

    def attach_ros_state_bridge(self, bridge: "RosStateBridge") -> None:
        """Install a state-ingestion bridge after construction.

        This keeps ``build_runtime`` simple: it first constructs the
        runtime so that ``publish_event`` is available, then attaches
        the bridge with that callback wired in.
        """

        self._ros_state_bridge = bridge

    async def start(self) -> None:
        self._ros_bridge.start()
        if self._ros_skill_bridge is not None:
            self._ros_skill_bridge.start()
        if self._ros_state_bridge is not None:
            try:
                loop = asyncio.get_running_loop()
            except RuntimeError:
                loop = None
            self._ros_state_bridge.start(loop=loop)
        for transport in self._transports:
            register_disconnect = getattr(transport, "set_disconnect_handler", None)
            if register_disconnect is not None:
                register_disconnect(self._handle_transport_disconnect)
            await transport.start(self._handle_transport_chunk)
        self._state_task = asyncio.create_task(self._state_loop(), name="robot-state-loop")
        if self._debug_state_tick.enabled:
            LOGGER.info(
                "debug state ticker enabled interval=%.2fs",
                self._debug_state_tick.interval_sec,
            )
            self._debug_state_task = asyncio.create_task(
                self._debug_state_tick_loop(),
                name="robot-debug-state-tick",
            )

    async def stop(self) -> None:
        if self._debug_state_task is not None:
            self._debug_state_task.cancel()
            try:
                await self._debug_state_task
            except asyncio.CancelledError:
                pass
            self._debug_state_task = None

        if self._state_task is not None:
            self._state_task.cancel()
            try:
                await self._state_task
            except asyncio.CancelledError:
                pass
            self._state_task = None

        for transport in reversed(self._transports):
            await transport.stop()

        if self._ros_state_bridge is not None:
            self._ros_state_bridge.stop()
        if self._ros_skill_bridge is not None:
            self._ros_skill_bridge.stop()
        self._ros_bridge.stop()

    async def publish_event(self, event: Dict[str, Any]) -> None:
        """Fan out a JSON event on every transport that supports it (MQTT)."""

        tasks = []
        for transport in self._transports:
            publish = getattr(transport, "publish_event", None)
            if publish is None:
                continue
            tasks.append(publish(event))
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def _handle_transport_chunk(self, envelope: TransportEnvelope) -> None:
        decoder = self._decoders.setdefault(envelope.peer_key, StreamDecoder())
        for frame in decoder.feed(envelope.payload):
            if LOGGER.isEnabledFor(logging.DEBUG):
                LOGGER.debug(
                    "recv frame peer=%s type=0x%02x seq=%d payload_len=%d",
                    envelope.peer_key,
                    int(frame.frame_type),
                    frame.seq,
                    len(frame.payload),
                )
            try:
                await self._control_service.handle_frame(
                    envelope.peer_key,
                    frame,
                    envelope.reply,
                )
            except Exception:
                LOGGER.exception(
                    "command handling failed peer=%s type=0x%02x seq=%d",
                    envelope.peer_key,
                    int(frame.frame_type),
                    frame.seq,
                )

    async def _handle_transport_disconnect(
        self,
        transport_name: str,
        session_id: str,
    ) -> None:
        if transport_name != "ble":
            return
        peer_key = "%s:%s" % (transport_name, session_id)
        LOGGER.warning("BLE peer disconnected; forcing motion stop peer=%s", peer_key)
        try:
            self._ros_bridge.stop_motion("BLE peer disconnected")
        except Exception:
            LOGGER.exception("failed to force zero velocity after BLE disconnect")
        if self._ros_skill_bridge is not None:
            try:
                self._ros_skill_bridge.cancel_all()
            except Exception:
                LOGGER.exception("failed to cancel skill goals after BLE disconnect")

    async def _state_loop(self) -> None:
        seq = 0
        interval = 1.0 / max(self._state_hz, 1)

        try:
            while True:
                state_frame = encode_frame(build_state_frame(seq=seq, state=self._state_store.snapshot()))
                await asyncio.gather(
                    *(transport.broadcast(state_frame) for transport in self._transports),
                    return_exceptions=True,
                )
                seq = (seq + 1) & 0xFF
                await asyncio.sleep(interval)
        except asyncio.CancelledError:
            raise

    async def _debug_state_tick_loop(self) -> None:
        step = 0
        interval = self._debug_state_tick.interval_sec
        roll_values = (-0.12, -0.06, 0.0, 0.06, 0.12, 0.06, 0.0, -0.06)
        pitch_values = (0.08, 0.04, 0.0, -0.04, -0.08, -0.04, 0.0, 0.04)
        yaw_values = (-0.30, -0.15, 0.0, 0.15, 0.30, 0.15, 0.0, -0.15)

        try:
            while True:
                state = RobotState(
                    battery=100 - (step % 10),
                    roll=roll_values[step % len(roll_values)],
                    pitch=pitch_values[step % len(pitch_values)],
                    yaw=yaw_values[step % len(yaw_values)],
                )
                self._state_store.replace(state)
                if LOGGER.isEnabledFor(logging.DEBUG):
                    LOGGER.debug(
                        "debug state tick battery=%d roll=%.2f pitch=%.2f yaw=%.2f",
                        state.battery,
                        state.roll,
                        state.pitch,
                        state.yaw,
                    )
                step += 1
                await asyncio.sleep(interval)
        except asyncio.CancelledError:
            raise
