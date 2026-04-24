from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Optional

from robot_protocol import DEFAULT_STATE_HZ


def _env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


@dataclass
class BLEConfig:
    # BLE is again the primary robot link, but the implementation now ports
    # the proven peripheral server that already runs on the robot dog.
    enabled: bool = True
    adapter: str = "hci0"
    app_path: str = "/com/robotfactory/robotoslite"
    device_name: str = "RobotOSLite"
    service_uuid: str = "12345678-1234-5678-1234-56789abc0000"
    cmd_char_uuid: str = "12345678-1234-5678-1234-56789abc0001"
    state_char_uuid: str = "12345678-1234-5678-1234-56789abc0002"
    advertise_enabled: bool = True
    mtu_default: int = 23
    mtu_max: int = 517
    # "auto" (默认，真机优先 glib/dbus-python；不可用时回退 dbus_next asyncio)、
    # "glib"、"dbus_next"。详见 transports/ble/__init__.py。
    backend: str = "auto"
    # 启动前等待 bluetoothd / hci 适配器就绪的超时。厂商机器狗冷启动时
    # `bluetooth.service` 常处于 `activating` 状态十几秒，期间
    # `Set(Powered=true)` 会阻塞直到硬件拉起。把默认给到 60s，真机首次开机也够用。
    ready_timeout_sec: float = 60.0


@dataclass
class TCPConfig:
    # Disabled by default: BLE is the primary link for the robot dog.
    enabled: bool = False
    host: str = "0.0.0.0"
    port: int = 9000


@dataclass
class MQTTConfig:
    enabled: bool = False
    host: str = "127.0.0.1"
    port: int = 1883
    robot_id: str = "dog-001"
    qos: int = 1
    client_id: str = ""
    username: Optional[str] = None
    password: Optional[str] = None
    keepalive: int = 60
    tls: bool = False
    reconnect_min_delay: float = 1.0
    reconnect_max_delay: float = 30.0

    def __post_init__(self) -> None:
        if not self.robot_id or "/" in self.robot_id or "+" in self.robot_id or "#" in self.robot_id:
            raise ValueError(
                f"invalid robot_id={self.robot_id!r}: must be non-empty and free of MQTT wildcards / slashes"
            )
        if self.qos not in (0, 1, 2):
            raise ValueError(f"invalid qos={self.qos}: must be 0, 1 or 2")
        if not self.client_id:
            self.client_id = f"robot-server-{self.robot_id}"

    @property
    def control_topic(self) -> str:
        return f"robot/{self.robot_id}/control"

    @property
    def state_topic(self) -> str:
        return f"robot/{self.robot_id}/state"

    @property
    def event_topic(self) -> str:
        return f"robot/{self.robot_id}/event"


@dataclass
class ROSConfig:
    """Configuration for the ROS1 bridge.

    Two independent paths:

    - Control (always on when ``enabled``): publishes ``MoveCommand`` to
      :attr:`topic` at :attr:`control_hz` via :class:`RosControlBridge`.
    - State ingestion (opt-in via ``state_enabled``): subscribes the topics
      below and writes into :class:`StateStore`. Every topic is
      individually disableable by setting it to an empty string, so this
      stays portable across robot-dog vendors.
    """

    enabled: bool = False
    topic: str = "/cmd_vel"
    control_hz: float = 10.0
    enable_lateral: bool = False
    node_name: str = "robot_os_lite"

    skill_enabled: bool = True
    action_skill_name: str = "do_action"
    behavior_skill_name: str = "do_dog_behavior"
    skill_invoker: str = "robot_server"
    skill_server_wait_sec: float = 3.0
    action_priority: int = 30
    stop_priority: int = 50
    behavior_priority: int = 50
    action_hold_time_sec: float = 5.0
    stop_hold_time_sec: float = 2.0
    behavior_hold_time_sec: float = 5.0
    stand_action_id: int = 3
    sit_action_id: int = 5
    stop_action_id: int = 6

    state_enabled: bool = False
    battery_topic: str = "/battery_state"
    battery_msg_type: str = "sensor_msgs/BatteryState"
    imu_topic: str = "/imu/data"
    imu_msg_type: str = "sensor_msgs/Imu"
    odom_topic: str = "/odom"
    odom_msg_type: str = "nav_msgs/Odometry"
    diagnostics_topic: str = "/diagnostics"
    diagnostics_msg_type: str = "diagnostic_msgs/DiagnosticArray"

    battery_low_threshold: int = 20
    battery_event_debounce_sec: float = 60.0
    queue_size: int = 10


@dataclass
class DebugStateTickConfig:
    enabled: bool = False
    interval_sec: float = 1.0

    def __post_init__(self) -> None:
        if self.interval_sec <= 0:
            raise ValueError(
                "invalid debug state tick interval: must be > 0"
            )


@dataclass
class ServerConfig:
    ble: BLEConfig = field(default_factory=BLEConfig)
    tcp: TCPConfig = field(default_factory=TCPConfig)
    mqtt: MQTTConfig = field(default_factory=MQTTConfig)
    ros: ROSConfig = field(default_factory=ROSConfig)
    debug_state_tick: DebugStateTickConfig = field(
        default_factory=DebugStateTickConfig
    )
    state_hz: int = DEFAULT_STATE_HZ


def load_config_from_env() -> ServerConfig:
    return ServerConfig(
        ble=BLEConfig(
            enabled=_env_bool("ROBOT_BLE_ENABLED", True),
            adapter=os.getenv("ROBOT_BLE_ADAPTER", "hci0"),
            app_path=os.getenv("ROBOT_BLE_APP_PATH", "/com/robotfactory/robotoslite"),
            device_name=os.getenv("ROBOT_BLE_DEVICE_NAME", "RobotOSLite"),
            service_uuid=os.getenv("ROBOT_BLE_SERVICE_UUID", "12345678-1234-5678-1234-56789abc0000"),
            cmd_char_uuid=os.getenv("ROBOT_BLE_CMD_UUID", "12345678-1234-5678-1234-56789abc0001"),
            state_char_uuid=os.getenv("ROBOT_BLE_STATE_UUID", "12345678-1234-5678-1234-56789abc0002"),
            advertise_enabled=_env_bool("ROBOT_BLE_ADVERTISE_ENABLED", True),
            mtu_default=int(os.getenv("ROBOT_BLE_MTU_DEFAULT", "23")),
            mtu_max=int(os.getenv("ROBOT_BLE_MTU_MAX", "517")),
            backend=os.getenv("ROBOT_BLE_BACKEND", "auto"),
            ready_timeout_sec=float(
                os.getenv("ROBOT_BLE_READY_TIMEOUT_SEC", "60.0")
            ),
        ),
        tcp=TCPConfig(
            enabled=_env_bool("ROBOT_TCP_ENABLED", False),
            host=os.getenv("ROBOT_TCP_HOST", "0.0.0.0"),
            port=int(os.getenv("ROBOT_TCP_PORT", "9000")),
        ),
        mqtt=MQTTConfig(
            enabled=_env_bool("ROBOT_MQTT_ENABLED", False),
            host=os.getenv("ROBOT_MQTT_HOST", "127.0.0.1"),
            port=int(os.getenv("ROBOT_MQTT_PORT", "1883")),
            robot_id=os.getenv("ROBOT_ID", "dog-001"),
            qos=int(os.getenv("ROBOT_MQTT_QOS", "1")),
            client_id=os.getenv("ROBOT_MQTT_CLIENT_ID", ""),
            username=os.getenv("ROBOT_MQTT_USERNAME"),
            password=os.getenv("ROBOT_MQTT_PASSWORD"),
            keepalive=int(os.getenv("ROBOT_MQTT_KEEPALIVE", "60")),
            tls=_env_bool("ROBOT_MQTT_TLS", False),
            reconnect_min_delay=float(os.getenv("ROBOT_MQTT_RECONNECT_MIN", "1.0")),
            reconnect_max_delay=float(os.getenv("ROBOT_MQTT_RECONNECT_MAX", "30.0")),
        ),
        ros=ROSConfig(
            enabled=_env_bool("ROBOT_ROS_ENABLED", False),
            topic=os.getenv("ROBOT_ROS_TOPIC", "/cmd_vel"),
            control_hz=float(os.getenv("ROBOT_ROS_HZ", "10.0")),
            enable_lateral=_env_bool("ROBOT_ROS_ENABLE_LATERAL", False),
            node_name=os.getenv("ROBOT_ROS_NODE", "robot_os_lite"),
            skill_enabled=_env_bool("ROBOT_ROS_SKILL_ENABLED", True),
            action_skill_name=os.getenv("ROBOT_ROS_ACTION_SKILL", "do_action"),
            behavior_skill_name=os.getenv(
                "ROBOT_ROS_BEHAVIOR_SKILL", "do_dog_behavior"
            ),
            skill_invoker=os.getenv("ROBOT_ROS_SKILL_INVOKER", "robot_server"),
            skill_server_wait_sec=float(
                os.getenv("ROBOT_ROS_SKILL_WAIT_SEC", "3.0")
            ),
            action_priority=int(os.getenv("ROBOT_ROS_ACTION_PRIORITY", "30")),
            stop_priority=int(os.getenv("ROBOT_ROS_STOP_PRIORITY", "50")),
            behavior_priority=int(os.getenv("ROBOT_ROS_BEHAVIOR_PRIORITY", "50")),
            action_hold_time_sec=float(
                os.getenv("ROBOT_ROS_ACTION_HOLD_SEC", "5.0")
            ),
            stop_hold_time_sec=float(
                os.getenv("ROBOT_ROS_STOP_HOLD_SEC", "2.0")
            ),
            behavior_hold_time_sec=float(
                os.getenv("ROBOT_ROS_BEHAVIOR_HOLD_SEC", "5.0")
            ),
            stand_action_id=int(os.getenv("ROBOT_ROS_STAND_ACTION_ID", "3")),
            sit_action_id=int(os.getenv("ROBOT_ROS_SIT_ACTION_ID", "5")),
            stop_action_id=int(os.getenv("ROBOT_ROS_STOP_ACTION_ID", "6")),
            state_enabled=_env_bool("ROBOT_ROS_STATE_ENABLED", False),
            battery_topic=os.getenv("ROBOT_ROS_BATTERY_TOPIC", "/battery_state"),
            battery_msg_type=os.getenv("ROBOT_ROS_BATTERY_MSG", "sensor_msgs/BatteryState"),
            imu_topic=os.getenv("ROBOT_ROS_IMU_TOPIC", "/imu/data"),
            imu_msg_type=os.getenv("ROBOT_ROS_IMU_MSG", "sensor_msgs/Imu"),
            odom_topic=os.getenv("ROBOT_ROS_ODOM_TOPIC", "/odom"),
            odom_msg_type=os.getenv("ROBOT_ROS_ODOM_MSG", "nav_msgs/Odometry"),
            diagnostics_topic=os.getenv("ROBOT_ROS_DIAG_TOPIC", "/diagnostics"),
            diagnostics_msg_type=os.getenv(
                "ROBOT_ROS_DIAG_MSG", "diagnostic_msgs/DiagnosticArray"
            ),
            battery_low_threshold=int(os.getenv("ROBOT_ROS_BATTERY_LOW_PCT", "20")),
            battery_event_debounce_sec=float(
                os.getenv("ROBOT_ROS_BATTERY_EVENT_DEBOUNCE_SEC", "60.0")
            ),
            queue_size=int(os.getenv("ROBOT_ROS_QUEUE_SIZE", "10")),
        ),
        debug_state_tick=DebugStateTickConfig(
            enabled=_env_bool("ROBOT_DEBUG_STATE_TICK_ENABLED", False),
            interval_sec=float(os.getenv("ROBOT_DEBUG_STATE_TICK_SEC", "1.0")),
        ),
        state_hz=int(os.getenv("ROBOT_STATE_HZ", str(DEFAULT_STATE_HZ))),
    )
