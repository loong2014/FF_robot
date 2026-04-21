from __future__ import annotations

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


class RosControlBridge:
    def __init__(self, config: ROSConfig) -> None:
        self._config = config
        self._lock = threading.Lock()
        self._latest_move = MoveCommand(vx=0.0, vy=0.0, yaw=0.0)
        self._publisher = None
        self._thread: Optional[threading.Thread] = None
        self._stop_event = threading.Event()

    def start(self) -> None:
        if not self._config.enabled or rospy is None or Twist is None:
            return

        if not rospy.core.is_initialized():
            rospy.init_node(self._config.node_name, anonymous=True, disable_signals=True)

        self._publisher = rospy.Publisher(self._config.topic, Twist, queue_size=10)
        self._stop_event.clear()
        self._thread = threading.Thread(target=self._publish_loop, name="ros-control-loop", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop_event.set()
        if self._thread is not None:
            self._thread.join(timeout=1.0)
            self._thread = None

    def apply_command(self, command: Union[MoveCommand, DiscreteCommand]) -> None:
        with self._lock:
            if isinstance(command, MoveCommand):
                self._latest_move = command
                return

            if command.command_id == CommandId.STOP:
                self._latest_move = MoveCommand(vx=0.0, vy=0.0, yaw=0.0)

    def _publish_loop(self) -> None:
        assert Twist is not None
        while not self._stop_event.is_set():
            with self._lock:
                move = self._latest_move

            twist = Twist()
            twist.linear.x = move.vx
            twist.linear.y = move.vy if self._config.enable_lateral else 0.0
            twist.angular.z = move.yaw

            if self._publisher is not None:
                self._publisher.publish(twist)

            if rospy is not None:
                time.sleep(1.0 / max(self._config.control_hz, 1.0))

