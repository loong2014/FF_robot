from __future__ import annotations

import struct
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
    SKILL_INVOKE = 0x20


class ServiceId(IntEnum):
    DO_ACTION = 0x01
    DO_DOG_BEHAVIOR = 0x02
    SET_FAN = 0x03
    ON_PATROL = 0x04
    PHONE_CALL = 0x05
    WATCH_DOG = 0x06
    SET_MOTION_PARAMS = 0x07
    SMART_ACTION = 0x08


class Operation(IntEnum):
    EXECUTE = 0x01
    START = 0x02
    STOP = 0x03
    SET = 0x04


class DogBehavior(IntEnum):
    CONFUSED = 0x01
    CONFUSED_AGAIN = 0x02
    RECOVERY_BALANCE_STAND_1 = 0x03
    RECOVERY_BALANCE_STAND = 0x04
    RECOVERY_BALANCE_STAND_HIGH = 0x05
    FORCE_RECOVERY_BALANCE_STAND = 0x06
    FORCE_RECOVERY_BALANCE_STAND_HIGH = 0x07
    RECOVERY_DANCE_STAND_AND_PARAMS = 0x08
    RECOVERY_DANCE_STAND = 0x09
    RECOVERY_DANCE_STAND_HIGH = 0x0A
    RECOVERY_DANCE_STAND_HIGH_AND_PARAMS = 0x0B
    RECOVERY_DANCE_STAND_POSE = 0x0C
    RECOVERY_DANCE_STAND_HIGH_POSE = 0x0D
    RECOVERY_STAND_POSE = 0x0E
    RECOVERY_STAND_HIGH_POSE = 0x0F
    WAIT = 0x10
    CUTE = 0x11
    CUTE_2 = 0x12
    ENJOY_TOUCH = 0x13
    VERY_ENJOY = 0x14
    EAGER = 0x15
    EXCITED_2 = 0x16
    EXCITED = 0x17
    CRAWL = 0x18
    STAND_AT_EASE = 0x19
    REST = 0x1A
    SHAKE_SELF = 0x1B
    BACK_FLIP = 0x1C
    FRONT_FLIP = 0x1D
    LEFT_FLIP = 0x1E
    RIGHT_FLIP = 0x1F
    EXPRESS_AFFECTION = 0x20
    YAWN = 0x21
    DANCE_IN_PLACE = 0x22
    SHAKE_HAND = 0x23
    WAVE_HAND = 0x24
    DRAW_HEART = 0x25
    PUSH_UP = 0x26
    BOW = 0x27


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
class SkillInvokeCommand:
    service_id: ServiceId
    operation: Operation
    args: bytes = b""
    require_ack: bool = True

    def __post_init__(self) -> None:
        if len(self.args) > 0xFF:
            raise ValueError("skill invoke args must fit in uint8 length field")

    @property
    def command_id(self) -> CommandId:
        return CommandId.SKILL_INVOKE

    @property
    def action_id(self) -> int:
        if self.service_id != ServiceId.DO_ACTION or self.operation != Operation.EXECUTE:
            raise ValueError("action_id is only available for do_action execute commands")
        if len(self.args) != 2:
            raise ValueError("do_action execute args must be 2 bytes")
        return struct.unpack("<H", self.args)[0]

    @property
    def behavior_id(self) -> DogBehavior:
        if self.service_id != ServiceId.DO_DOG_BEHAVIOR or self.operation != Operation.EXECUTE:
            raise ValueError("behavior_id is only available for do_dog_behavior execute commands")
        if len(self.args) != 1:
            raise ValueError("do_dog_behavior execute args must be 1 byte")
        return DogBehavior(self.args[0])

    @classmethod
    def do_action(cls, action_id: int, require_ack: bool = True) -> "SkillInvokeCommand":
        if not 0 <= action_id <= 0xFFFF:
            raise ValueError("action_id must fit in uint16")
        return cls(
            service_id=ServiceId.DO_ACTION,
            operation=Operation.EXECUTE,
            args=struct.pack("<H", action_id),
            require_ack=require_ack,
        )

    @classmethod
    def do_dog_behavior(
        cls,
        behavior_id: DogBehavior,
        require_ack: bool = True,
    ) -> "SkillInvokeCommand":
        return cls(
            service_id=ServiceId.DO_DOG_BEHAVIOR,
            operation=Operation.EXECUTE,
            args=bytes([int(behavior_id)]),
            require_ack=require_ack,
        )


@dataclass(frozen=True)
class RobotState:
    battery: int
    roll: float
    pitch: float
    yaw: float
