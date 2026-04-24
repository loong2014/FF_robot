from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum


class FrameType(IntEnum):
    CMD = 0x01
    STATE = 0x02
    ACK = 0x03


class CommandId(IntEnum):
    MOVE = 0x01
    STAND = 0x10
    SIT = 0x11
    STOP = 0x12


@dataclass(frozen=True)
class Frame:
    frame_type: FrameType
    seq: int
    payload: bytes


@dataclass(frozen=True)
class MoveCommand:
    vx: float
    vy: float
    yaw: float

    @property
    def command_id(self) -> CommandId:
        return CommandId.MOVE


@dataclass(frozen=True)
class DiscreteCommand:
    command_id: CommandId


@dataclass(frozen=True)
class RobotState:
    battery: int
    roll: float
    pitch: float
    yaw: float

