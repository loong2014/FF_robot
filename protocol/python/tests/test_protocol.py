from __future__ import annotations

import unittest

from robot_protocol import (
    CommandId,
    CrcMismatchError,
    DiscreteCommand,
    DogBehavior,
    MoveCommand,
    RobotState,
    SkillInvokeCommand,
    StreamDecoder,
    build_ack_frame,
    build_command_frame,
    build_state_frame,
    decode_frame,
    encode_frame,
    parse_ack_payload,
    parse_command_payload,
    parse_state_payload,
)


class ProtocolTests(unittest.TestCase):
    def test_move_round_trip(self) -> None:
        command = MoveCommand(vx=0.55, vy=-0.2, yaw=1.25)
        frame = build_command_frame(seq=7, command=command)
        decoded = decode_frame(encode_frame(frame))

        self.assertEqual(decoded.seq, 7)
        parsed = parse_command_payload(decoded.payload)
        self.assertIsInstance(parsed, MoveCommand)
        assert isinstance(parsed, MoveCommand)
        self.assertAlmostEqual(parsed.vx, 0.55, places=2)
        self.assertAlmostEqual(parsed.vy, -0.2, places=2)
        self.assertAlmostEqual(parsed.yaw, 1.25, places=2)

    def test_state_round_trip(self) -> None:
        state = RobotState(battery=87, roll=1.2, pitch=-0.5, yaw=35.66)
        frame = build_state_frame(seq=9, state=state)
        decoded = decode_frame(encode_frame(frame))
        parsed = parse_state_payload(decoded.payload)

        self.assertEqual(parsed.battery, 87)
        self.assertAlmostEqual(parsed.roll, 1.2, places=2)
        self.assertAlmostEqual(parsed.pitch, -0.5, places=2)
        self.assertAlmostEqual(parsed.yaw, 35.66, places=2)

    def test_ack_payload_round_trip(self) -> None:
        frame = build_ack_frame(42)
        decoded = decode_frame(encode_frame(frame))
        self.assertEqual(parse_ack_payload(decoded.payload), 42)

    def test_skill_invoke_do_action_round_trip(self) -> None:
        command = SkillInvokeCommand.do_action(action_id=20524)
        frame = build_command_frame(seq=8, command=command)
        decoded = decode_frame(encode_frame(frame))
        parsed = parse_command_payload(decoded.payload)

        self.assertIsInstance(parsed, SkillInvokeCommand)
        assert isinstance(parsed, SkillInvokeCommand)
        self.assertEqual(parsed.action_id, 20524)
        self.assertTrue(parsed.require_ack)

    def test_skill_invoke_do_dog_behavior_round_trip(self) -> None:
        command = SkillInvokeCommand.do_dog_behavior(
            behavior_id=DogBehavior.WAVE_HAND,
            require_ack=False,
        )
        frame = build_command_frame(seq=9, command=command)
        decoded = decode_frame(encode_frame(frame))
        parsed = parse_command_payload(decoded.payload)

        self.assertIsInstance(parsed, SkillInvokeCommand)
        assert isinstance(parsed, SkillInvokeCommand)
        self.assertEqual(parsed.behavior_id, DogBehavior.WAVE_HAND)
        self.assertFalse(parsed.require_ack)

    def test_decoder_handles_partial_and_sticky_frames(self) -> None:
        move = encode_frame(build_command_frame(seq=1, command=MoveCommand(vx=0.1, vy=0.0, yaw=0.2)))
        stop = encode_frame(build_command_frame(seq=2, command=DiscreteCommand(command_id=CommandId.STOP)))
        blob = move + stop

        decoder = StreamDecoder()
        first = decoder.feed(blob[:5])
        second = decoder.feed(blob[5:])

        self.assertEqual(first, [])
        self.assertEqual(len(second), 2)
        self.assertEqual(second[0].seq, 1)
        self.assertEqual(second[1].seq, 2)

    def test_crc_error_raises(self) -> None:
        data = bytearray(encode_frame(build_command_frame(seq=3, command=MoveCommand(vx=0.0, vy=0.0, yaw=0.0))))
        data[-1] ^= 0xFF

        with self.assertRaises(CrcMismatchError):
            decode_frame(bytes(data))


if __name__ == "__main__":
    unittest.main()
