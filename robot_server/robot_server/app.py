"""Runtime bootstrap helpers.

Provides a small factory that assembles a :class:`RobotRuntime` from a
:class:`ServerConfig`. This is intentionally transport-pluggable so that
smoke scripts / integration tests can spin up a TCP-only stack without
needing BLE / MQTT / ROS dependencies.
"""

from __future__ import annotations

from typing import List, Optional

from .config import ServerConfig
from .ros.bridge import RosControlBridge
from .ros.skill_bridge import RosSkillBridge
from .ros.state_bridge import RosStateBridge
from .runtime import RobotRuntime, StateStore
from .transports import MqttRouterTransport, TcpTransport
from .transports.base import RuntimeTransport


def build_transports(config: ServerConfig) -> List[RuntimeTransport]:
    transports: List[RuntimeTransport] = []
    if config.tcp.enabled:
        transports.append(TcpTransport(host=config.tcp.host, port=config.tcp.port))
    if config.ble.enabled:
        # Keep BlueZ isolated from the core runtime unless explicitly enabled.
        from .transports.ble import create_ble_transport

        transports.append(create_ble_transport(config.ble))
    if config.mqtt.enabled:
        transports.append(MqttRouterTransport(config.mqtt))
    return transports


def build_runtime(
    config: ServerConfig,
    state_store: Optional[StateStore] = None,
) -> RobotRuntime:
    transports = build_transports(config)
    ros_bridge = RosControlBridge(config.ros)
    ros_skill_bridge = RosSkillBridge(config.ros)
    runtime = RobotRuntime(
        transports=transports,
        ros_bridge=ros_bridge,
        ros_skill_bridge=ros_skill_bridge,
        state_store=state_store,
        debug_state_tick=config.debug_state_tick,
        state_hz=config.state_hz,
    )

    if config.ros.enabled and config.ros.state_enabled:
        runtime.attach_ros_state_bridge(
            RosStateBridge(
                config=config.ros,
                state_store=runtime.state_store,
                event_emitter=runtime.publish_event,
            )
        )

    return runtime
