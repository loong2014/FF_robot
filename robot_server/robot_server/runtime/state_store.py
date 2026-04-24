from __future__ import annotations

from dataclasses import dataclass, field
from threading import Lock
from typing import Tuple, Union

from robot_protocol import CommandId, DiscreteCommand, MoveCommand, RobotState, SkillInvokeCommand


@dataclass(frozen=True)
class OdometrySample:
    """Latest odometry sample captured from ROS (or a mock source).

    Units intentionally match typical ROS conventions:
    - ``x`` / ``y`` in meters
    - ``yaw`` in radians
    - ``linear_vx`` in m/s, ``angular_wz`` in rad/s
    """

    x: float = 0.0
    y: float = 0.0
    yaw: float = 0.0
    linear_vx: float = 0.0
    angular_wz: float = 0.0


@dataclass(frozen=True)
class RobotStateExtras:
    """Non-protocol state fields.

    These do not fit the fixed 7-byte STATE payload but are useful for
    event broadcasting (MQTT ``robot/{id}/event``) and debugging.
    """

    odometry: OdometrySample = field(default_factory=OdometrySample)
    fault_codes: Tuple[str, ...] = ()


class StateStore:
    def __init__(self) -> None:
        self._lock = Lock()
        self._state = RobotState(battery=100, roll=0.0, pitch=0.0, yaw=0.0)
        self._extras = RobotStateExtras()

    def snapshot(self) -> RobotState:
        with self._lock:
            return self._state

    def snapshot_extras(self) -> RobotStateExtras:
        with self._lock:
            return self._extras

    def replace(self, state: RobotState) -> None:
        with self._lock:
            self._state = state

    def set_battery(self, battery: int) -> None:
        with self._lock:
            self._state = RobotState(
                battery=max(0, min(100, battery)),
                roll=self._state.roll,
                pitch=self._state.pitch,
                yaw=self._state.yaw,
            )

    def set_attitude(self, roll: float, pitch: float, yaw: float) -> None:
        with self._lock:
            self._state = RobotState(
                battery=self._state.battery,
                roll=roll,
                pitch=pitch,
                yaw=yaw,
            )

    def set_odometry(self, odom: OdometrySample) -> None:
        with self._lock:
            self._extras = RobotStateExtras(
                odometry=odom,
                fault_codes=self._extras.fault_codes,
            )

    def set_fault_codes(self, codes: Tuple[str, ...]) -> None:
        with self._lock:
            self._extras = RobotStateExtras(
                odometry=self._extras.odometry,
                fault_codes=tuple(codes),
            )

    def observe_command(
        self,
        command: Union[MoveCommand, DiscreteCommand, SkillInvokeCommand],
    ) -> None:
        if isinstance(command, DiscreteCommand) and command.command_id == CommandId.STOP:
            self.set_attitude(roll=self._state.roll, pitch=self._state.pitch, yaw=self._state.yaw)
