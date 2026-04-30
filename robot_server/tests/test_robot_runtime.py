from __future__ import annotations

import unittest
from typing import List

from robot_protocol import CommandId, DiscreteCommand, Frame, FrameType, encode_frame

from robot_server.models import TransportEnvelope
from robot_server.runtime import RobotRuntime, StateStore


class _FakeRosBridge:
    def __init__(self) -> None:
        self.commands: List[object] = []
        self.stop_reasons: List[str] = []

    def start(self) -> None:
        pass

    def stop(self) -> None:
        pass

    def apply_command(self, command: object) -> None:
        self.commands.append(command)

    def stop_motion(self, reason: str = "") -> None:
        self.stop_reasons.append(reason)


class _FakeSkillBridge:
    def __init__(self) -> None:
        self.cancel_count = 0

    def start(self) -> None:
        pass

    def stop(self) -> None:
        pass

    def apply_command(self, command: object) -> None:
        pass

    def cancel_all(self) -> None:
        self.cancel_count += 1


class RobotRuntimeTests(unittest.IsolatedAsyncioTestCase):
    async def test_ble_disconnect_forces_motion_stop(self) -> None:
        ros_bridge = _FakeRosBridge()
        skill_bridge = _FakeSkillBridge()
        runtime = RobotRuntime(
            transports=[],
            ros_bridge=ros_bridge,  # type: ignore[arg-type]
            ros_skill_bridge=skill_bridge,  # type: ignore[arg-type]
            state_store=StateStore(),
        )

        await runtime._handle_transport_disconnect("ble", "central")  # noqa: SLF001

        self.assertEqual(ros_bridge.stop_reasons, ["BLE peer disconnected"])
        self.assertEqual(skill_bridge.cancel_count, 1)

    async def test_command_processing_error_does_not_escape_transport_handler(self) -> None:
        ros_bridge = _FakeRosBridge()
        runtime = RobotRuntime(
            transports=[],
            ros_bridge=ros_bridge,  # type: ignore[arg-type]
            state_store=StateStore(),
        )
        replies: List[bytes] = []

        async def reply(payload: bytes) -> None:
            replies.append(payload)

        envelope = TransportEnvelope(
            transport_name="ble",
            session_id="central",
            payload=encode_frame(
                Frame(frame_type=FrameType.CMD, seq=3, payload=b"\x99")
            ),
            reply=reply,
        )

        await runtime._handle_transport_chunk(envelope)  # noqa: SLF001

        self.assertEqual(ros_bridge.commands, [])
        self.assertEqual(replies, [])

    async def test_valid_command_still_acknowledges_after_error_isolation(self) -> None:
        ros_bridge = _FakeRosBridge()
        runtime = RobotRuntime(
            transports=[],
            ros_bridge=ros_bridge,  # type: ignore[arg-type]
            state_store=StateStore(),
        )
        replies: List[bytes] = []

        async def reply(payload: bytes) -> None:
            replies.append(payload)

        envelope = TransportEnvelope(
            transport_name="ble",
            session_id="central",
            payload=encode_frame(
                Frame(
                    frame_type=FrameType.CMD,
                    seq=4,
                    payload=bytes([CommandId.STOP]),
                )
            ),
            reply=reply,
        )

        await runtime._handle_transport_chunk(envelope)  # noqa: SLF001

        self.assertEqual(len(replies), 1)
        self.assertIsInstance(ros_bridge.commands[0], DiscreteCommand)


if __name__ == "__main__":
    unittest.main()
