from __future__ import annotations

import struct
from typing import Union

from .constants import ANGLE_SCALE, MAGIC, MAX_PAYLOAD_LENGTH, MOVE_SCALE
from .crc import crc16_ccitt
from .models import CommandId, DiscreteCommand, Frame, FrameType, MoveCommand, RobotState


class ProtocolError(ValueError):
    pass


class CrcMismatchError(ProtocolError):
    pass


class PayloadError(ProtocolError):
    pass


RobotCommand = Union[MoveCommand, DiscreteCommand]


def _scale_to_i16(value: float, scale: int) -> int:
    scaled = int(round(value * scale))
    if not -32768 <= scaled <= 32767:
        raise PayloadError(f"scaled value out of int16 range: {value}")
    return scaled


def _unscale_from_i16(value: int, scale: int) -> float:
    return value / scale


def encode_frame(frame: Frame) -> bytes:
    if not 0 <= frame.seq <= 0xFF:
        raise ProtocolError(f"sequence out of range: {frame.seq}")
    if len(frame.payload) > MAX_PAYLOAD_LENGTH:
        raise ProtocolError(f"payload too large: {len(frame.payload)}")

    body = struct.pack("<BBH", int(frame.frame_type), frame.seq, len(frame.payload)) + frame.payload
    crc = crc16_ccitt(body)
    return MAGIC + body + struct.pack("<H", crc)


def decode_frame(data: bytes) -> Frame:
    if len(data) < 8:
        raise ProtocolError("frame too short")
    if data[:2] != MAGIC:
        raise ProtocolError("invalid magic header")

    frame_type_raw, seq, payload_len = struct.unpack("<BBH", data[2:6])
    total_length = 2 + 1 + 1 + 2 + payload_len + 2
    if len(data) != total_length:
        raise ProtocolError("frame length mismatch")

    payload = data[6 : 6 + payload_len]
    expected_crc = struct.unpack("<H", data[-2:])[0]
    actual_crc = crc16_ccitt(data[2:-2])
    if expected_crc != actual_crc:
        raise CrcMismatchError(f"crc mismatch: expected={expected_crc:#06x} actual={actual_crc:#06x}")

    try:
        frame_type = FrameType(frame_type_raw)
    except ValueError as exc:
        raise ProtocolError(f"unsupported frame type: {frame_type_raw:#04x}") from exc

    return Frame(frame_type=frame_type, seq=seq, payload=payload)


def build_command_frame(seq: int, command: RobotCommand) -> Frame:
    return Frame(frame_type=FrameType.CMD, seq=seq, payload=encode_command_payload(command))


def build_state_frame(seq: int, state: RobotState) -> Frame:
    payload = struct.pack(
        "<Bhhh",
        state.battery & 0xFF,
        _scale_to_i16(state.roll, ANGLE_SCALE),
        _scale_to_i16(state.pitch, ANGLE_SCALE),
        _scale_to_i16(state.yaw, ANGLE_SCALE),
    )
    return Frame(frame_type=FrameType.STATE, seq=seq, payload=payload)


def build_ack_frame(seq: int) -> Frame:
    ack_seq = seq & 0xFF
    return Frame(frame_type=FrameType.ACK, seq=ack_seq, payload=bytes([ack_seq]))


def encode_command_payload(command: RobotCommand) -> bytes:
    if isinstance(command, MoveCommand):
        return struct.pack(
            "<Bhhh",
            int(command.command_id),
            _scale_to_i16(command.vx, MOVE_SCALE),
            _scale_to_i16(command.vy, MOVE_SCALE),
            _scale_to_i16(command.yaw, ANGLE_SCALE),
        )
    return bytes([int(command.command_id)])


def parse_command_payload(payload: bytes) -> RobotCommand:
    if not payload:
        raise PayloadError("empty command payload")

    command_id = payload[0]
    if command_id == CommandId.MOVE:
        if len(payload) != 7:
            raise PayloadError("move command payload must be 7 bytes")
        _, vx, vy, yaw = struct.unpack("<Bhhh", payload)
        return MoveCommand(
            vx=_unscale_from_i16(vx, MOVE_SCALE),
            vy=_unscale_from_i16(vy, MOVE_SCALE),
            yaw=_unscale_from_i16(yaw, ANGLE_SCALE),
        )

    if command_id in (CommandId.STAND, CommandId.SIT, CommandId.STOP):
        if len(payload) != 1:
            raise PayloadError("discrete command payload must be 1 byte")
        return DiscreteCommand(command_id=CommandId(command_id))

    raise PayloadError(f"unsupported command id: {command_id:#04x}")


def parse_state_payload(payload: bytes) -> RobotState:
    if len(payload) != 7:
        raise PayloadError("state payload must be 7 bytes")
    battery, roll, pitch, yaw = struct.unpack("<Bhhh", payload)
    return RobotState(
        battery=battery,
        roll=_unscale_from_i16(roll, ANGLE_SCALE),
        pitch=_unscale_from_i16(pitch, ANGLE_SCALE),
        yaw=_unscale_from_i16(yaw, ANGLE_SCALE),
    )


def parse_ack_payload(payload: bytes) -> int:
    if len(payload) != 1:
        raise PayloadError("ack payload must be 1 byte")
    return payload[0]

