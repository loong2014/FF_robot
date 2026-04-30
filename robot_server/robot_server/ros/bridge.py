from __future__ import annotations

import logging
import struct
import threading
import time
from typing import Optional, Union

from robot_protocol import CommandId, DiscreteCommand, MoveCommand

from ..config import ROSConfig

try:
    import rospy
    from geometry_msgs.msg import Twist
except ImportError:  # pragma: no cover - runtime dependency on target robot
    rospy = None
    Twist = None

try:
    from ros_alphadog.msg import SetVelocity as RosSetVelocity  # type: ignore[import-not-found]
except ImportError:  # pragma: no cover - runtime dependency on target robot
    RosSetVelocity = None


LOGGER = logging.getLogger(__name__)


class _FallbackSetVelocity(object):
    """Minimal ROS message compatible with ``ros_alphadog/SetVelocity``.

    The robot dog's installed package does not expose a Python message
    module in the current environment, but the binary clearly advertises
    the message definition and MD5 sum. This fallback is sufficient for
    ``rospy.Publisher`` because it provides the generated-message
    attributes and serialization methods.
    """

    __slots__ = ("vx", "vy", "wz")
    _type = "ros_alphadog/SetVelocity"
    _md5sum = "b2020d2d07e276a9930049ea7b96eb7a"
    _has_header = False
    _full_text = "float32 vx\nfloat32 vy\nfloat32 wz\n"
    _slot_types = ("float32", "float32", "float32")

    def __init__(self, vx: float = 0.0, vy: float = 0.0, wz: float = 0.0) -> None:
        self.vx = vx
        self.vy = vy
        self.wz = wz

    def serialize(self, buff: object) -> None:
        if hasattr(buff, "write"):
            buff.write(struct.pack("<fff", float(self.vx), float(self.vy), float(self.wz)))
            return
        raise TypeError("message buffer must provide write()")

    def deserialize(self, data: bytes) -> "_FallbackSetVelocity":
        self.vx, self.vy, self.wz = struct.unpack("<fff", data[:12])
        return self


def _motion_topic_type(topic: str):
    if topic.endswith("/set_velocity"):
        return RosSetVelocity or _FallbackSetVelocity
    return Twist


def _build_motion_message(topic: str, move: MoveCommand, enable_lateral: bool):
    if topic.endswith("/set_velocity"):
        message_type = _motion_topic_type(topic)
        msg = message_type()
        msg.vx = move.vx
        msg.vy = move.vy if enable_lateral else 0.0
        msg.wz = move.yaw
        return msg

    message_type = _motion_topic_type(topic)
    if message_type is None:
        raise RuntimeError("geometry_msgs/Twist is unavailable")
    msg = message_type()
    msg.linear.x = move.vx
    msg.linear.y = move.vy if enable_lateral else 0.0
    msg.angular.z = move.yaw
    return msg


class RosControlBridge:
    def __init__(self, config: ROSConfig) -> None:
        self._config = config
        self._lock = threading.Lock()
        self._latest_move = MoveCommand(vx=0.0, vy=0.0, yaw=0.0)
        self._publisher = None
        self._thread: Optional[threading.Thread] = None
        self._stop_event = threading.Event()

    def start(self) -> None:
        if not self._config.enabled:
            LOGGER.info(
                "ROS control bridge disabled; MOVE commands will be ACKed but not published to %s",
                self._config.topic,
            )
            return
        message_type = _motion_topic_type(self._config.topic)
        if rospy is None or message_type is None:
            LOGGER.info(
                "ROS control bridge unavailable (rospy/Twist missing); MOVE commands will be ACKed but not published to %s",
                self._config.topic,
            )
            return

        if not rospy.core.is_initialized():
            rospy.init_node(self._config.node_name, anonymous=True, disable_signals=True)

        self._publisher = rospy.Publisher(self._config.topic, message_type, queue_size=10)
        LOGGER.info(
            "ROS control bridge started topic=%s type=%s hz=%.1f enable_lateral=%s",
            self._config.topic,
            getattr(message_type, "_type", message_type.__name__),
            self._config.control_hz,
            self._config.enable_lateral,
        )
        self._stop_event.clear()
        self._thread = threading.Thread(target=self._publish_loop, name="ros-control-loop", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop_event.set()
        if self._thread is not None:
            self._thread.join(timeout=1.0)
            self._thread = None

    def stop_motion(self, reason: str = "") -> None:
        with self._lock:
            self._latest_move = MoveCommand(vx=0.0, vy=0.0, yaw=0.0)
        if reason:
            LOGGER.warning("ros control forced zero velocity: %s", reason)
        else:
            LOGGER.info("ros control forced zero velocity")

    def apply_command(self, command: Union[MoveCommand, DiscreteCommand]) -> None:
        with self._lock:
            if isinstance(command, MoveCommand):
                self._latest_move = command
                LOGGER.info(
                    "ros control move vx=%.2f vy=%.2f yaw=%.2f lateral=%s",
                    command.vx,
                    command.vy,
                    command.yaw,
                    self._config.enable_lateral,
                )
                return

            if command.command_id == CommandId.STOP:
                self._latest_move = MoveCommand(vx=0.0, vy=0.0, yaw=0.0)
                LOGGER.info("ros control stop -> zero velocity")

    def _publish_loop(self) -> None:
        message_type = _motion_topic_type(self._config.topic)
        assert message_type is not None
        while not self._stop_event.is_set():
            with self._lock:
                move = self._latest_move

            twist = _build_motion_message(
                self._config.topic,
                move,
                self._config.enable_lateral,
            )

            if self._publisher is not None:
                self._publisher.publish(twist)

            if rospy is not None:
                time.sleep(1.0 / max(self._config.control_hz, 1.0))
