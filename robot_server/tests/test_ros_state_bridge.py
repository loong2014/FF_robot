from __future__ import annotations

import asyncio
import math
import unittest
from types import SimpleNamespace
from typing import Any, Callable, Dict, List, Tuple

from robot_server.config import ROSConfig
from robot_server.ros.state_bridge import (
    RosStateBridge,
    _extract_battery_percentage,
    _quaternion_to_rpy,
)
from robot_server.runtime.state_store import StateStore


# ---- Test doubles ----------------------------------------------------------


class _FakeSubscriber:
    def __init__(self, topic: str, msg_type: type, callback: Callable[[Any], None]) -> None:
        self.topic = topic
        self.msg_type = msg_type
        self.callback = callback
        self.unregistered = False

    def unregister(self) -> None:
        self.unregistered = True


class _FakeRosBackend:
    """Records every subscribe() call and lets tests fire messages later."""

    def __init__(self) -> None:
        self.subscribers: List[_FakeSubscriber] = []

    def factory(
        self,
        topic: str,
        msg_type: type,
        callback: Callable[[Any], None],
        queue_size: int,
    ) -> _FakeSubscriber:
        sub = _FakeSubscriber(topic, msg_type, callback)
        self.subscribers.append(sub)
        return sub

    def deliver(self, topic: str, message: Any) -> None:
        for sub in self.subscribers:
            if sub.topic == topic:
                sub.callback(message)


class _FakeBatteryMsg:
    pass


class _FakeImuMsg:
    pass


class _FakeOdomMsg:
    pass


class _FakeDiagMsg:
    pass


_FAKE_MSG_REGISTRY: Dict[str, type] = {
    "sensor_msgs/BatteryState": _FakeBatteryMsg,
    "sensor_msgs/Imu": _FakeImuMsg,
    "nav_msgs/Odometry": _FakeOdomMsg,
    "diagnostic_msgs/DiagnosticArray": _FakeDiagMsg,
}


def _enabled_config(**overrides: Any) -> ROSConfig:
    kwargs: Dict[str, Any] = {
        "enabled": True,
        "state_enabled": True,
        "battery_low_threshold": 20,
        "battery_event_debounce_sec": 60.0,
    }
    kwargs.update(overrides)
    return ROSConfig(**kwargs)


# ---- Helpers ---------------------------------------------------------------


def _make_battery(percentage: float) -> _FakeBatteryMsg:
    msg = _FakeBatteryMsg()
    msg.percentage = percentage  # type: ignore[attr-defined]
    return msg


def _make_imu(roll: float, pitch: float, yaw: float) -> _FakeImuMsg:
    cr = math.cos(roll / 2.0)
    sr = math.sin(roll / 2.0)
    cp = math.cos(pitch / 2.0)
    sp = math.sin(pitch / 2.0)
    cy = math.cos(yaw / 2.0)
    sy = math.sin(yaw / 2.0)
    qx = sr * cp * cy - cr * sp * sy
    qy = cr * sp * cy + sr * cp * sy
    qz = cr * cp * sy - sr * sp * cy
    qw = cr * cp * cy + sr * sp * sy
    msg = _FakeImuMsg()
    msg.orientation = SimpleNamespace(x=qx, y=qy, z=qz, w=qw)  # type: ignore[attr-defined]
    return msg


def _make_odom(
    x: float,
    y: float,
    yaw: float,
    linear_vx: float = 0.0,
    angular_wz: float = 0.0,
) -> _FakeOdomMsg:
    qz = math.sin(yaw / 2.0)
    qw = math.cos(yaw / 2.0)
    pose = SimpleNamespace(
        pose=SimpleNamespace(
            position=SimpleNamespace(x=x, y=y, z=0.0),
            orientation=SimpleNamespace(x=0.0, y=0.0, z=qz, w=qw),
        )
    )
    twist = SimpleNamespace(
        twist=SimpleNamespace(
            linear=SimpleNamespace(x=linear_vx, y=0.0, z=0.0),
            angular=SimpleNamespace(x=0.0, y=0.0, z=angular_wz),
        )
    )
    msg = _FakeOdomMsg()
    msg.pose = pose  # type: ignore[attr-defined]
    msg.twist = twist  # type: ignore[attr-defined]
    return msg


def _make_diag(*statuses: Tuple[int, str, str]) -> _FakeDiagMsg:
    msg = _FakeDiagMsg()
    msg.status = [  # type: ignore[attr-defined]
        SimpleNamespace(level=level, name=name, message=message)
        for level, name, message in statuses
    ]
    return msg


# ---- Tests -----------------------------------------------------------------


class QuaternionMathTests(unittest.TestCase):
    def test_identity_quaternion_is_zero_rpy(self) -> None:
        roll, pitch, yaw = _quaternion_to_rpy(0.0, 0.0, 0.0, 1.0)
        self.assertAlmostEqual(roll, 0.0)
        self.assertAlmostEqual(pitch, 0.0)
        self.assertAlmostEqual(yaw, 0.0)

    def test_yaw_only_quaternion_round_trips(self) -> None:
        target_yaw = 0.5
        qz = math.sin(target_yaw / 2.0)
        qw = math.cos(target_yaw / 2.0)
        roll, pitch, yaw = _quaternion_to_rpy(0.0, 0.0, qz, qw)
        self.assertAlmostEqual(roll, 0.0)
        self.assertAlmostEqual(pitch, 0.0)
        self.assertAlmostEqual(yaw, target_yaw)


class BatteryExtractionTests(unittest.TestCase):
    def test_percentage_as_ratio(self) -> None:
        self.assertEqual(_extract_battery_percentage(_make_battery(0.42)), 42)

    def test_percentage_as_zero_to_hundred_scale(self) -> None:
        msg = _FakeBatteryMsg()
        msg.percentage = 75.0  # type: ignore[attr-defined]
        self.assertEqual(_extract_battery_percentage(msg), 75)

    def test_fallback_to_charge_capacity(self) -> None:
        msg = _FakeBatteryMsg()
        msg.percentage = float("nan")  # type: ignore[attr-defined]
        msg.charge = 3.0  # type: ignore[attr-defined]
        msg.capacity = 10.0  # type: ignore[attr-defined]
        self.assertEqual(_extract_battery_percentage(msg), 30)

    def test_returns_none_when_no_signal(self) -> None:
        msg = _FakeBatteryMsg()
        msg.percentage = float("nan")  # type: ignore[attr-defined]
        self.assertIsNone(_extract_battery_percentage(msg))


class RosStateBridgeSubscriptionTests(unittest.TestCase):
    def _build_bridge(
        self,
        config: ROSConfig,
        backend: _FakeRosBackend,
        *,
        event_emitter: Any = None,
        clock: Callable[[], float] = lambda: 0.0,
    ) -> RosStateBridge:
        return RosStateBridge(
            config=config,
            state_store=StateStore(),
            event_emitter=event_emitter,
            subscriber_factory=backend.factory,
            message_registry=_FAKE_MSG_REGISTRY,
            clock=clock,
        )

    def test_noop_when_ros_disabled(self) -> None:
        backend = _FakeRosBackend()
        bridge = self._build_bridge(ROSConfig(enabled=False, state_enabled=True), backend)
        bridge.start()
        self.assertFalse(bridge.is_running)
        self.assertEqual(backend.subscribers, [])

    def test_noop_when_state_disabled(self) -> None:
        backend = _FakeRosBackend()
        bridge = self._build_bridge(ROSConfig(enabled=True, state_enabled=False), backend)
        bridge.start()
        self.assertFalse(bridge.is_running)
        self.assertEqual(backend.subscribers, [])

    def test_subscribes_all_default_topics(self) -> None:
        backend = _FakeRosBackend()
        bridge = self._build_bridge(_enabled_config(), backend)
        bridge.start()
        topics = sorted(sub.topic for sub in backend.subscribers)
        self.assertEqual(
            topics, ["/battery_state", "/diagnostics", "/imu/data", "/odom"]
        )
        self.assertTrue(bridge.is_running)

    def test_empty_topic_disables_single_subscription(self) -> None:
        backend = _FakeRosBackend()
        bridge = self._build_bridge(_enabled_config(imu_topic=""), backend)
        bridge.start()
        topics = sorted(sub.topic for sub in backend.subscribers)
        self.assertEqual(topics, ["/battery_state", "/diagnostics", "/odom"])

    def test_custom_topic_names_are_used(self) -> None:
        backend = _FakeRosBackend()
        config = _enabled_config(
            battery_topic="/vendor/battery",
            imu_topic="/vendor/imu",
            odom_topic="/vendor/odom",
            diagnostics_topic="/vendor/diag",
        )
        bridge = self._build_bridge(config, backend)
        bridge.start()
        topics = sorted(sub.topic for sub in backend.subscribers)
        self.assertEqual(
            topics,
            ["/vendor/battery", "/vendor/diag", "/vendor/imu", "/vendor/odom"],
        )

    def test_stop_unregisters_subscribers_and_is_idempotent(self) -> None:
        backend = _FakeRosBackend()
        bridge = self._build_bridge(_enabled_config(), backend)
        bridge.start()
        bridge.stop()
        for sub in backend.subscribers:
            self.assertTrue(sub.unregistered)
        bridge.stop()
        self.assertFalse(bridge.is_running)


class RosStateBridgeCallbackTests(unittest.TestCase):
    def _start(
        self,
        *,
        config: ROSConfig,
        event_emitter: Any = None,
        clock: Callable[[], float] = lambda: 0.0,
    ) -> Tuple[RosStateBridge, StateStore, _FakeRosBackend]:
        backend = _FakeRosBackend()
        store = StateStore()
        bridge = RosStateBridge(
            config=config,
            state_store=store,
            event_emitter=event_emitter,
            subscriber_factory=backend.factory,
            message_registry=_FAKE_MSG_REGISTRY,
            clock=clock,
        )
        bridge.start()
        return bridge, store, backend

    def test_battery_updates_state_store(self) -> None:
        _, store, backend = self._start(config=_enabled_config())
        backend.deliver("/battery_state", _make_battery(0.87))
        self.assertEqual(store.snapshot().battery, 87)

    def test_imu_sets_attitude(self) -> None:
        _, store, backend = self._start(config=_enabled_config())
        backend.deliver("/imu/data", _make_imu(0.1, -0.2, 0.3))
        snap = store.snapshot()
        self.assertAlmostEqual(snap.roll, 0.1, places=5)
        self.assertAlmostEqual(snap.pitch, -0.2, places=5)
        self.assertAlmostEqual(snap.yaw, 0.3, places=5)

    def test_odom_updates_extras(self) -> None:
        _, store, backend = self._start(config=_enabled_config())
        backend.deliver(
            "/odom",
            _make_odom(x=1.5, y=-0.4, yaw=0.25, linear_vx=0.8, angular_wz=0.1),
        )
        extras = store.snapshot_extras()
        self.assertAlmostEqual(extras.odometry.x, 1.5)
        self.assertAlmostEqual(extras.odometry.y, -0.4)
        self.assertAlmostEqual(extras.odometry.yaw, 0.25, places=5)
        self.assertAlmostEqual(extras.odometry.linear_vx, 0.8)
        self.assertAlmostEqual(extras.odometry.angular_wz, 0.1)

    def test_diagnostics_only_keeps_warn_and_error(self) -> None:
        _, store, backend = self._start(config=_enabled_config())
        backend.deliver(
            "/diagnostics",
            _make_diag((0, "imu", "ok"), (1, "battery", "low"), (2, "motor", "fault")),
        )
        self.assertEqual(
            store.snapshot_extras().fault_codes,
            ("battery:low", "motor:fault"),
        )


class RosStateBridgeEventTests(unittest.IsolatedAsyncioTestCase):
    async def test_battery_low_event_is_debounced(self) -> None:
        backend = _FakeRosBackend()
        events: List[Dict[str, Any]] = []

        async def emitter(event: Dict[str, Any]) -> None:
            events.append(event)

        now = {"t": 0.0}
        bridge = RosStateBridge(
            config=_enabled_config(battery_low_threshold=25, battery_event_debounce_sec=60.0),
            state_store=StateStore(),
            event_emitter=emitter,
            subscriber_factory=backend.factory,
            message_registry=_FAKE_MSG_REGISTRY,
            clock=lambda: now["t"],
        )
        bridge.start(loop=asyncio.get_running_loop())

        backend.deliver("/battery_state", _make_battery(0.10))
        backend.deliver("/battery_state", _make_battery(0.08))
        now["t"] = 59.0
        backend.deliver("/battery_state", _make_battery(0.07))
        await asyncio.sleep(0.01)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["type"], "battery_low")
        self.assertEqual(events[0]["level"], 10)

        now["t"] = 61.0
        backend.deliver("/battery_state", _make_battery(0.05))
        await asyncio.sleep(0.01)
        self.assertEqual(len(events), 2)
        self.assertEqual(events[1]["level"], 5)

    async def test_fault_event_only_fires_on_change(self) -> None:
        backend = _FakeRosBackend()
        events: List[Dict[str, Any]] = []

        async def emitter(event: Dict[str, Any]) -> None:
            events.append(event)

        bridge = RosStateBridge(
            config=_enabled_config(),
            state_store=StateStore(),
            event_emitter=emitter,
            subscriber_factory=backend.factory,
            message_registry=_FAKE_MSG_REGISTRY,
        )
        bridge.start(loop=asyncio.get_running_loop())

        backend.deliver("/diagnostics", _make_diag((2, "motor", "overheat")))
        backend.deliver("/diagnostics", _make_diag((2, "motor", "overheat")))
        await asyncio.sleep(0.01)
        fault_events = [e for e in events if e["type"] == "fault"]
        self.assertEqual(len(fault_events), 1)
        self.assertEqual(fault_events[0]["codes"], ["motor:overheat"])

        backend.deliver("/diagnostics", _make_diag((0, "motor", "nominal")))
        await asyncio.sleep(0.01)
        cleared = [e for e in events if e["type"] == "fault_cleared"]
        self.assertEqual(len(cleared), 1)


if __name__ == "__main__":
    unittest.main()
