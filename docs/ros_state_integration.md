# ROS1 状态采集集成（Milestone 6）

> 适用范围：`robot_server` 在 Ubuntu 20.04 + ROS1 Noetic + Python 3.8 下的真机部署。
>
> 本文档所有带「🖧 真机配置」标记的部分都是**运行在真正的机器狗上**才需要改动的；仅做桌面仿真/联调可以保持默认值。

---

## 1. 设计要点

- 控制下行（`/cmd_vel`，10Hz）由 `RosControlBridge` 负责，**本轮完全不改动**，继续由 `RobotRuntime.start()` 启动。
- 状态上行新增 `RosStateBridge`，独立订阅 **电池 / IMU / 里程 / 诊断** 四个来源，并写入 `StateStore`。
- 协议 `STATE` 帧载荷（`battery | roll(int16) | pitch | yaw`，固定 7 字节）**保持不变**，由 `RobotRuntime._state_loop` 以 `state_hz` 向 **BLE / TCP / MQTT 三条路径**统一广播。
- 里程 / 故障码等**放不进协议 STATE 帧**的字段，进入 `RobotStateExtras`；需要下发到 App 时通过 `RobotRuntime.publish_event()` 作为 JSON event 发到 `robot/{id}/event`（仅 MQTT 消费，遵循 AGENTS.md §4）。
- **topic 名称与消息类型都可配置**，默认使用 ROS 通用消息（`sensor_msgs/BatteryState`、`sensor_msgs/Imu`、`nav_msgs/Odometry`、`diagnostic_msgs/DiagnosticArray`），**不绑定单一机器狗厂商**。

```
┌──────────────┐  ROS topic (subscribe)     ┌────────────────────┐
│ /battery_state│ ──────────────────────────▶│ RosStateBridge     │
│ /imu/data    │                             │  _on_battery       │──▶ StateStore.set_battery(int)
│ /odom        │                             │  _on_imu           │──▶ StateStore.set_attitude(rad)
│ /diagnostics │                             │  _on_odom          │──▶ StateStore.set_odometry(...)
└──────────────┘                             │  _on_diagnostics   │──▶ StateStore.set_fault_codes(...)
                                             └─────────┬──────────┘
                                                       │ publish_event()（可选）
                                                       ▼
                                             RobotRuntime.publish_event
                                                       │
                                             ┌─────────┴─────────┐
                                             ▼                   ▼
                                      robot/{id}/event      (BLE/TCP 忽略)
```

控制路径不变：

```
App → mobile_sdk → (BLE/TCP/MQTT) → RobotRuntime → RosControlBridge → /cmd_vel @10Hz
```

---

## 2. 可配置项 🖧 真机配置

所有字段集中在 [`robot_server/robot_server/config.py`](../robot_server/robot_server/config.py) 的 `ROSConfig`。可以在部署机器狗时通过**环境变量**覆盖，也可以在自建 bootstrap 里直接构造 `ServerConfig`。

| 字段 | 环境变量 | 默认 | 说明 |
|---|---|---|---|
| `enabled` | `ROBOT_ROS_ENABLED` | `false` | ROS1 控制桥（`/cmd_vel`）是否启用 |
| `topic` | `ROBOT_ROS_TOPIC` | `/cmd_vel` | 控制话题 |
| `control_hz` | `ROBOT_ROS_HZ` | `10.0` | 控制发布频率（保持 10Hz） |
| `enable_lateral` | `ROBOT_ROS_ENABLE_LATERAL` | `false` | 是否开放横向速度（四足通常关闭） |
| `node_name` | `ROBOT_ROS_NODE` | `robot_os_lite` | `rospy.init_node` 节点名 |
| `state_enabled` | `ROBOT_ROS_STATE_ENABLED` | `false` | **状态采集开关**；关闭时 `StateStore` 保持默认值（battery=100、姿态=0） |
| `battery_topic` | `ROBOT_ROS_BATTERY_TOPIC` | `/battery_state` | 电池话题；置空字符串禁用该订阅 |
| `battery_msg_type` | `ROBOT_ROS_BATTERY_MSG` | `sensor_msgs/BatteryState` | 电池消息类型；厂商自定义 msg 可改为 `vendor_msgs/VendorBattery` |
| `imu_topic` | `ROBOT_ROS_IMU_TOPIC` | `/imu/data` | IMU 话题；置空禁用 |
| `imu_msg_type` | `ROBOT_ROS_IMU_MSG` | `sensor_msgs/Imu` | IMU 消息类型（取 `orientation`，按 ZYX 提取弧度制 RPY） |
| `odom_topic` | `ROBOT_ROS_ODOM_TOPIC` | `/odom` | 里程计话题；置空禁用 |
| `odom_msg_type` | `ROBOT_ROS_ODOM_MSG` | `nav_msgs/Odometry` | 里程消息类型（读 `pose.pose` + `twist.twist`） |
| `diagnostics_topic` | `ROBOT_ROS_DIAG_TOPIC` | `/diagnostics` | 诊断话题；置空禁用 |
| `diagnostics_msg_type` | `ROBOT_ROS_DIAG_MSG` | `diagnostic_msgs/DiagnosticArray` | 诊断消息类型（WARN/ERROR 级记录为 `fault_codes`） |
| `battery_low_threshold` | `ROBOT_ROS_BATTERY_LOW_PCT` | `20` | 低电量阈值（百分比），低于时推 `battery_low` event |
| `battery_event_debounce_sec` | `ROBOT_ROS_BATTERY_EVENT_DEBOUNCE_SEC` | `60.0` | 低电量 event 去抖间隔 |
| `queue_size` | `ROBOT_ROS_QUEUE_SIZE` | `10` | 每个订阅的 `queue_size` |

> 置空禁用的语义：`ROBOT_ROS_BATTERY_TOPIC=""`、或在 Python 里 `ROSConfig(battery_topic="")`。
>
> 没有安装对应消息包（比如机器狗没有 `/diagnostics`）时，即便 `state_enabled=True`，`RosStateBridge` 也只会跳过该订阅（打 WARN 日志），不会阻塞启动。

---

## 3. 真机部署步骤

### 3.1 依赖

**系统**（Ubuntu 20.04 + ROS1 Noetic，Python 3.8）：

```
# Noetic 基础话题的消息包
sudo apt install ros-noetic-sensor-msgs ros-noetic-nav-msgs ros-noetic-diagnostic-msgs
# 如果厂家用 vendor_msgs，自行 apt / catkin 安装
```

**Python**：`rospy` 由 `source /opt/ros/noetic/setup.bash` 提供，不需要 pip 安装。

### 3.2 启动

```bash
source /opt/ros/noetic/setup.bash

# 最小 — TCP only + ROS 状态采集开启，BLE/MQTT 关
ROBOT_BLE_ENABLED=false \
ROBOT_MQTT_ENABLED=false \
ROBOT_ROS_ENABLED=true \
ROBOT_ROS_STATE_ENABLED=true \
PYTHONPATH=protocol/python:robot_server \
python3 scripts/run_robot_server.py
```

完整部署（MQTT + ROS 控制 + ROS 状态 + 低电量事件）示例：

```bash
ROBOT_MQTT_ENABLED=true \
ROBOT_MQTT_HOST=<broker-host> \
ROBOT_ID=dog-prod-42 \
ROBOT_ROS_ENABLED=true \
ROBOT_ROS_STATE_ENABLED=true \
ROBOT_ROS_BATTERY_LOW_PCT=15 \
PYTHONPATH=protocol/python:robot_server \
python3 scripts/run_robot_server.py
```

### 3.3 验证 🖧 真机配置

1. **协议 STATE 实时携带真实姿态**（@10Hz）：

 ```bash
 rostopic pub /imu/data sensor_msgs/Imu '{ orientation: { x: 0, y: 0, z: 0.3827, w: 0.9239 } }' -r 10
 # 同时 mobile_sdk / mqttx 观察 state 帧，yaw 应该 ≈ 0.785 rad
 ```

2. **电池上报 + 低电量 event**（需 MQTT 开启）：

 ```bash
 rostopic pub /battery_state sensor_msgs/BatteryState '{ percentage: 0.05 }' -1
 # 订阅 robot/<id>/event 应收到 {"type": "battery_low", "level": 5, "threshold": 20}
 ```

3. **诊断故障 event**：

 ```bash
 rostopic pub /diagnostics diagnostic_msgs/DiagnosticArray \
 '{ status: [ { level: 2, name: "motor/front_left", message: "overheat" } ] }' -1
 # event 应收到 {"type": "fault", "codes": ["motor/front_left:overheat"]}
 ```

4. **切换厂商消息类型**：

 ```bash
 ROBOT_ROS_BATTERY_MSG=vendor_msgs/VendorBattery \
 ROBOT_ROS_BATTERY_TOPIC=/vendor/battery \
 ... python3 scripts/run_robot_server.py
 ```

---

## 4. 事件协议（MQTT `robot/{id}/event`）

| `type` | 字段 | 触发条件 |
|---|---|---|
| `battery_low` | `level: int`（0-100）、`threshold: int` | 电量 < `battery_low_threshold`，按 `battery_event_debounce_sec` 去抖 |
| `fault` | `codes: List[str]`（形如 `name:message`） | `DiagnosticArray` 出现 WARN/ERROR，并与上次 fault 集合不同 |
| `fault_cleared` | — | 所有 WARN/ERROR 消失（由有故障回到无故障） |

后续如果要增加 `odom_tick` / `heartbeat` 等事件，沿用相同约定追加即可。

---

## 5. 测试

- 单元测试：[`robot_server/tests/test_ros_state_bridge.py`](../robot_server/tests/test_ros_state_bridge.py)，覆盖
  - quaternion → RPY 数学
  - 电池 percentage / charge+capacity 两种来源 & 非法值退化
  - 四种订阅可独立启停、topic / 消息类型可覆盖
  - callback 写 StateStore（battery / 姿态 / odom / fault）
  - `battery_low` event 去抖、`fault` event 仅在变化时触发
- 跑法：

 ```bash
 PYTHONPATH=protocol/python:robot_server \
 python3 -m unittest discover -s robot_server/tests
 ```

---

## 6. 剩余风险 / 限制

- **依赖运行时 rospy**：没有 ROS1 环境时（如 macOS 开发机），`RosStateBridge._default_subscriber_factory` 直接 raise，这正是期望行为；测试通过注入 `subscriber_factory` 绕开。
- **厂商消息 schema 差异**：若 vendor 的电池消息字段既不是 `percentage`、也没有 `charge/capacity`，`_extract_battery_percentage` 会返回 `None`，`battery` 保持上次值。遇到这种厂商需要在 `RosStateBridge` 上加一层 adapter（后续 backlog）。
- **BLE/TCP 上的 event**：当前 AGENTS.md 明确 event 只走 MQTT；如果未来需要 BLE/TCP 也携带结构化事件，需要扩协议（新的 frame type），不是本轮范围。
- **`diagnostics` 高频刷屏**：当前实现按「fault_codes 集合是否变化」触发 event，不会每帧都发；但如果厂商在 DiagnosticArray 里频繁增删 transient WARN 会抖动，必要时在 bridge 层再加一层去抖。
- **smoke 测试**：本地 macOS 无法 `apt install ros-noetic-*`，端到端仅能在真机或 docker (`osrf/ros:noetic-desktop`) 里跑；建议在部署清单里加一条 rostopic pub 验证步骤。
