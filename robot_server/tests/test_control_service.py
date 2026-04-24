from __future__ import annotations

import unittest
from typing import List, Optional

from robot_protocol import (
    Frame,
    FrameType,
    DogBehavior,
    MoveCommand,
    PayloadError,
    SkillInvokeCommand,
    build_command_frame,
    decode_frame,
    parse_ack_payload,
)

from robot_server.runtime import RobotControlService, StateStore


class _FakeBridge:
    def __init__(self, error: Optional[Exception] = None) -> None:
        self.error = error
        self.commands: List[object] = []

    def apply_command(self, command: object) -> None:
        if self.error is not None:
            raise self.error
        self.commands.append(command)


class _FakeSkillBridge(_FakeBridge):
    pass


class RobotControlServiceTests(unittest.IsolatedAsyncioTestCase):
    async def test_ack_sent_after_successful_local_acceptance(self) -> None:
        bridge = _FakeBridge()
        service = RobotControlService(ros_bridge=bridge, state_store=StateStore())
        replies = []

        async def reply(payload: bytes) -> None:
            replies.append(payload)

        await service.handle_frame(
            "tcp:client#1",
            build_command_frame(seq=7, command=MoveCommand(vx=0.3, vy=0.0, yaw=0.1)),
            reply,
        )

        self.assertEqual(len(bridge.commands), 1)
        self.assertEqual(len(replies), 1)
        ack_frame = decode_frame(replies[0])
        self.assertEqual(ack_frame.frame_type, FrameType.ACK)
        self.assertEqual(ack_frame.seq, 7)
        self.assertEqual(parse_ack_payload(ack_frame.payload), 7)

    async def test_duplicate_seq_and_payload_is_only_acked_once_per_execution(self) -> None:
        bridge = _FakeBridge()
        service = RobotControlService(ros_bridge=bridge, state_store=StateStore())
        frame = build_command_frame(seq=11, command=MoveCommand(vx=0.4, vy=0.0, yaw=0.2))
        replies = []

        async def reply(payload: bytes) -> None:
            replies.append(payload)

        await service.handle_frame("ble:central", frame, reply)
        await service.handle_frame("ble:central", frame, reply)

        self.assertEqual(len(bridge.commands), 1)
        self.assertEqual(len(replies), 2)
        self.assertTrue(all(decode_frame(payload).frame_type == FrameType.ACK for payload in replies))

    async def test_same_seq_with_different_payload_is_treated_as_new_command(self) -> None:
        bridge = _FakeBridge()
        service = RobotControlService(ros_bridge=bridge, state_store=StateStore())
        replies = []

        async def reply(payload: bytes) -> None:
            replies.append(payload)

        await service.handle_frame(
            "mqtt:robot-1",
            build_command_frame(seq=5, command=MoveCommand(vx=0.1, vy=0.0, yaw=0.0)),
            reply,
        )
        await service.handle_frame(
            "mqtt:robot-1",
            build_command_frame(seq=5, command=MoveCommand(vx=0.2, vy=0.0, yaw=0.0)),
            reply,
        )

        self.assertEqual(len(bridge.commands), 2)
        self.assertEqual(len(replies), 2)

    async def test_skill_invoke_command_is_routed_to_skill_bridge(self) -> None:
        bridge = _FakeBridge()
        skill_bridge = _FakeSkillBridge()
        service = RobotControlService(
            ros_bridge=bridge,
            ros_skill_bridge=skill_bridge,
            state_store=StateStore(),
        )
        replies = []

        async def reply(payload: bytes) -> None:
            replies.append(payload)

        await service.handle_frame(
            "ble:central",
            build_command_frame(
                seq=13,
                command=SkillInvokeCommand.do_dog_behavior(DogBehavior.WAVE_HAND),
            ),
            reply,
        )

        self.assertEqual(bridge.commands, [])
        self.assertEqual(len(skill_bridge.commands), 1)
        self.assertEqual(len(replies), 1)
        self.assertEqual(decode_frame(replies[0]).frame_type, FrameType.ACK)

    async def test_parse_failure_does_not_ack(self) -> None:
        bridge = _FakeBridge()
        service = RobotControlService(ros_bridge=bridge, state_store=StateStore())
        replies = []

        async def reply(payload: bytes) -> None:
            replies.append(payload)

        with self.assertRaises(PayloadError):
            await service.handle_frame(
                "tcp:client#2",
                Frame(frame_type=FrameType.CMD, seq=3, payload=b"\x99"),
                reply,
            )

        self.assertEqual(bridge.commands, [])
        self.assertEqual(replies, [])

    async def test_bridge_failure_does_not_ack_and_retry_is_not_marked_duplicate(self) -> None:
        bridge = _FakeBridge(error=RuntimeError("bridge exploded"))
        service = RobotControlService(ros_bridge=bridge, state_store=StateStore())
        frame = build_command_frame(seq=9, command=MoveCommand(vx=0.2, vy=0.0, yaw=0.0))
        replies = []

        async def reply(payload: bytes) -> None:
            replies.append(payload)

        with self.assertRaises(RuntimeError):
            await service.handle_frame("tcp:client#3", frame, reply)

        self.assertEqual(replies, [])
        self.assertEqual(bridge.commands, [])

        bridge.error = None
        await service.handle_frame("tcp:client#3", frame, reply)

        self.assertEqual(len(bridge.commands), 1)
        self.assertEqual(len(replies), 1)


if __name__ == "__main__":
    unittest.main()
