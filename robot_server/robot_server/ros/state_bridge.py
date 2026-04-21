"""ROS1 state ingestion bridge.

Subscribes to the configured battery / IMU / odometry / diagnostics
topics and writes the latest samples into :class:`StateStore`. The
protocol-level STATE payload (``battery | roll | pitch | yaw``) is
unchanged; odometry and fault information are exposed as extras and may
be fanned out as JSON events via :meth:`RobotRuntime.publish_event`
(which only the MQTT transport consumes, per AGENTS.md).

Design goals:

- **Vendor neutral**: every topic name and message type can be
  overridden via :class:`ROSConfig` / environment variables. Empty
  topic strings disable the corresponding subscription.
- **Python 3.8 / Noetic compatible**: no PEP 604 / PEP 585 runtime
  usage, no walrus operator, no ``match`` statement.
- **Testable without rospy**: accepts a custom ``subscriber_factory``
  and ``message_registry`` so unit tests can inject fakes without
  importing ``rospy`` or the ``*_msgs`` wheels.
"""

from __future__ import annotations

import asyncio
import importlib
import logging
import math
import threading
import time
from typing import (
    Any,
    Awaitable,
    Callable,
    Dict,
    List,
    Optional,
    Tuple,
    Type,
)

from ..config import ROSConfig
from ..runtime.state_store import OdometrySample, StateStore

try:  # pragma: no cover - runtime dependency on target robot
    import rospy  # type: ignore[import-not-found]
except ImportError:  # pragma: no cover
    rospy = None  # type: ignore[assignment]


LOGGER = logging.getLogger(__name__)


SubscriberHandle = Any
SubscriberFactory = Callable[[str, Type[Any], Callable[[Any], None], int], SubscriberHandle]
EventEmitter = Callable[[Dict[str, Any]], Awaitable[None]]


def _default_subscriber_factory(
    topic: str,
    msg_type: Type[Any],
    callback: Callable[[Any], None],
    queue_size: int,
) -> SubscriberHandle:  # pragma: no cover - exercised on real robot
    if rospy is None:
        raise RuntimeError("rospy is not available; cannot create subscriber")
    return rospy.Subscriber(topic, msg_type, callback, queue_size=queue_size)


def _resolve_msg_type(spec: str) -> Type[Any]:
    """Resolve ``"pkg_name/MsgName"`` to the actual ROS message class.

    Import is deferred so tests never need ``sensor_msgs`` / ``nav_msgs``
    installed. Vendors with custom message packages just need to set
    ``ROBOT_ROS_*_MSG`` to e.g. ``"vendor_msgs/VendorBattery"``.
    """

    if "/" not in spec:
        raise ValueError(
            "invalid msg type {spec!r}; expected 'pkg/Msg' form".format(spec=spec)
        )
    pkg, name = spec.split("/", 1)
    module = importlib.import_module(pkg + ".msg")
    try:
        return getattr(module, name)
    except AttributeError as exc:
        raise ImportError(
            "message {name!r} not found in {pkg!r}".format(name=name, pkg=pkg)
        ) from exc


def _quaternion_to_rpy(x: float, y: float, z: float, w: float) -> Tuple[float, float, float]:
    """Standard ZYX (roll-pitch-yaw) extraction from a unit quaternion.

    Returns radians, matching the units used by ROS ``Imu.orientation``
    and the protocol ``RobotState`` (which multiplies by ANGLE_SCALE=100
    and fits into int16 because |roll|, |pitch|, |yaw| <= pi).
    """

    sinr_cosp = 2.0 * (w * x + y * z)
    cosr_cosp = 1.0 - 2.0 * (x * x + y * y)
    roll = math.atan2(sinr_cosp, cosr_cosp)

    sinp = 2.0 * (w * y - z * x)
    if sinp >= 1.0:
        pitch = math.pi / 2.0
    elif sinp <= -1.0:
        pitch = -math.pi / 2.0
    else:
        pitch = math.asin(sinp)

    siny_cosp = 2.0 * (w * z + x * y)
    cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
    yaw = math.atan2(siny_cosp, cosy_cosp)
    return roll, pitch, yaw


def _extract_battery_percentage(msg: Any) -> Optional[int]:
    """Normalize a ``sensor_msgs/BatteryState``-ish message to 0..100.

    Vendors either fill ``percentage`` in [0, 1] (ROS convention) or
    supply only ``voltage`` / ``charge`` / ``capacity``. We try those in
    that order. Returns ``None`` if nothing usable is present, so the
    StateStore keeps the previous value.
    """

    percentage = getattr(msg, "percentage", None)
    if percentage is not None and not (isinstance(percentage, float) and math.isnan(percentage)):
        value = float(percentage)
        if value <= 1.0:
            value = value * 100.0
        return int(round(max(0.0, min(100.0, value))))

    charge = getattr(msg, "charge", None)
    capacity = getattr(msg, "capacity", None)
    if (
        charge is not None
        and capacity is not None
        and isinstance(charge, (int, float))
        and isinstance(capacity, (int, float))
        and capacity > 0
    ):
        ratio = float(charge) / float(capacity)
        return int(round(max(0.0, min(1.0, ratio)) * 100.0))

    return None


class RosStateBridge:
    """Subscribes to configured ROS state topics and writes StateStore."""

    def __init__(
        self,
        config: ROSConfig,
        state_store: StateStore,
        event_emitter: Optional[EventEmitter] = None,
        *,
        subscriber_factory: Optional[SubscriberFactory] = None,
        message_registry: Optional[Dict[str, Type[Any]]] = None,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._config = config
        self._state_store = state_store
        self._event_emitter = event_emitter
        self._subscriber_factory = subscriber_factory or _default_subscriber_factory
        self._message_registry = message_registry or {}
        self._clock = clock

        self._subscribers: List[SubscriberHandle] = []
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._lock = threading.Lock()
        self._last_battery_event_at: Optional[float] = None
        self._last_fault_codes: Tuple[str, ...] = ()
        self._started = False

    @property
    def is_running(self) -> bool:
        return self._started

    def start(self, loop: Optional[asyncio.AbstractEventLoop] = None) -> None:
        if self._started:
            return
        if not (self._config.enabled and self._config.state_enabled):
            return

        self._loop = loop

        self._subscribe(
            self._config.battery_topic,
            self._config.battery_msg_type,
            self._on_battery,
        )
        self._subscribe(
            self._config.imu_topic,
            self._config.imu_msg_type,
            self._on_imu,
        )
        self._subscribe(
            self._config.odom_topic,
            self._config.odom_msg_type,
            self._on_odom,
        )
        self._subscribe(
            self._config.diagnostics_topic,
            self._config.diagnostics_msg_type,
            self._on_diagnostics,
        )
        self._started = True

    def stop(self) -> None:
        if not self._started:
            return
        for sub in self._subscribers:
            unregister = getattr(sub, "unregister", None)
            if callable(unregister):
                try:
                    unregister()
                except Exception:  # pragma: no cover - defensive
                    LOGGER.exception("ros-state-bridge: subscriber unregister failed")
        self._subscribers = []
        self._started = False

    def _subscribe(
        self,
        topic: str,
        msg_type_spec: str,
        callback: Callable[[Any], None],
    ) -> None:
        if not topic:
            LOGGER.info("ros-state-bridge: skipping %s (topic disabled)", msg_type_spec)
            return
        try:
            msg_type = self._message_registry.get(msg_type_spec) or _resolve_msg_type(msg_type_spec)
        except Exception as exc:  # pragma: no cover - env specific
            LOGGER.warning(
                "ros-state-bridge: cannot resolve %s for topic %s: %s",
                msg_type_spec,
                topic,
                exc,
            )
            return
        try:
            handle = self._subscriber_factory(topic, msg_type, callback, self._config.queue_size)
        except Exception as exc:  # pragma: no cover - env specific
            LOGGER.warning(
                "ros-state-bridge: subscribe(%s, %s) failed: %s", topic, msg_type_spec, exc
            )
            return
        self._subscribers.append(handle)
        LOGGER.info("ros-state-bridge: subscribed %s (%s)", topic, msg_type_spec)

    def _on_battery(self, msg: Any) -> None:
        level = _extract_battery_percentage(msg)
        if level is None:
            return
        self._state_store.set_battery(level)

        if level < self._config.battery_low_threshold:
            now = self._clock()
            with self._lock:
                last = self._last_battery_event_at
                debounce = self._config.battery_event_debounce_sec
                should_emit = last is None or (now - last) >= debounce
                if should_emit:
                    self._last_battery_event_at = now
            if should_emit:
                self._dispatch_event(
                    {
                        "type": "battery_low",
                        "level": level,
                        "threshold": self._config.battery_low_threshold,
                    }
                )

    def _on_imu(self, msg: Any) -> None:
        orientation = getattr(msg, "orientation", None)
        if orientation is None:
            return
        try:
            x = float(orientation.x)
            y = float(orientation.y)
            z = float(orientation.z)
            w = float(orientation.w)
        except (AttributeError, TypeError, ValueError):
            return
        roll, pitch, yaw = _quaternion_to_rpy(x, y, z, w)
        self._state_store.set_attitude(roll=roll, pitch=pitch, yaw=yaw)

    def _on_odom(self, msg: Any) -> None:
        pose = getattr(getattr(msg, "pose", None), "pose", None)
        twist = getattr(getattr(msg, "twist", None), "twist", None)
        if pose is None:
            return
        try:
            pos = pose.position
            ori = pose.orientation
            x = float(pos.x)
            y = float(pos.y)
            _, _, yaw = _quaternion_to_rpy(
                float(ori.x), float(ori.y), float(ori.z), float(ori.w)
            )
        except (AttributeError, TypeError, ValueError):
            return

        linear_vx = 0.0
        angular_wz = 0.0
        if twist is not None:
            try:
                linear_vx = float(twist.linear.x)
                angular_wz = float(twist.angular.z)
            except (AttributeError, TypeError, ValueError):
                pass

        self._state_store.set_odometry(
            OdometrySample(
                x=x,
                y=y,
                yaw=yaw,
                linear_vx=linear_vx,
                angular_wz=angular_wz,
            )
        )

    def _on_diagnostics(self, msg: Any) -> None:
        codes = self._extract_fault_codes(msg)
        with self._lock:
            previous = self._last_fault_codes
            self._last_fault_codes = codes

        if codes != previous:
            self._state_store.set_fault_codes(codes)
            if codes:
                self._dispatch_event({"type": "fault", "codes": list(codes)})
            else:
                self._dispatch_event({"type": "fault_cleared"})

    @staticmethod
    def _extract_fault_codes(msg: Any) -> Tuple[str, ...]:
        """Collect WARN/ERROR entries from ``diagnostic_msgs/DiagnosticArray``."""

        statuses = getattr(msg, "status", None) or []
        faults: List[str] = []
        for status in statuses:
            try:
                level = int(getattr(status, "level", 0))
            except (TypeError, ValueError):
                level = 0
            if level <= 0:
                continue
            name = str(getattr(status, "name", "")).strip() or "unknown"
            code = str(getattr(status, "message", "")).strip()
            token = "{name}:{code}".format(name=name, code=code) if code else name
            faults.append(token)
        return tuple(faults)

    def _dispatch_event(self, event: Dict[str, Any]) -> None:
        emitter = self._event_emitter
        if emitter is None:
            return
        loop = self._loop
        if loop is None:
            LOGGER.debug("ros-state-bridge: no event loop attached, dropping %s", event)
            return

        try:
            running = asyncio.get_running_loop()
        except RuntimeError:
            running = None

        try:
            if running is loop:
                loop.create_task(emitter(event))
            else:
                asyncio.run_coroutine_threadsafe(emitter(event), loop)
        except RuntimeError:  # pragma: no cover - loop already closed
            LOGGER.debug("ros-state-bridge: loop closed, dropping %s", event)
