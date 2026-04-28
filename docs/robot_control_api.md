# 机器狗操控 API 与数据流说明

本文档面向 App 首页“完整动作控制页”的接口梳理，覆盖：

- `robot_skill/` 提供的 `do_action` / `do_dog_behavior` 能力清单
- 手机侧当前可用的协议与 SDK API
- `robot_server` 收到控制命令后的处理路径
- 机器人状态如何采集并回传给手机
- 当前缺口与推荐改造顺序

## 目标页面需求拆解

计划新增的首页入口大致需要三类数据：

| 数据 | 期望 | 当前是否可用 | 说明 |
| --- | --- | --- | --- |
| 机器人基础状态 | 电量、姿态、连接状态等 | 部分可用 | BLE/TCP/MQTT 都能收到 10Hz `STATE`，字段只有 `battery/roll/pitch/yaw` |
| 运动/配置状态 | 前进速度、角速度、控制配置、故障等 | 部分在服务端内部可用 | `StateStore` 有 odom extras，但协议 STATE 不下发；故障/低电量事件只走 MQTT event |
| 动作/行为清单 | 展示全部 `do_action` / `do_dog_behavior` | 本地资源可用，协议不可动态查询 | `robot_skill/` 有 JSON/YAML；手机协议没有“查询能力列表”API |

当前第一版页面已按“不扩协议，使用本地资源”的方式落地：

1. 状态区先展示 `RobotClient.stateStream` 已有的 `battery/roll/pitch/yaw` 和连接状态。
2. 动作区从 `robot_skill/do_action/ext_actions.json` 与 `robot_skill/do_dog_behavior/dog_behaviors.json` 打包成本地 App assets。
3. 点击动作时走 `RobotClient.doAction(actionId)`。
4. 点击行为时走 `RobotClient.doDogBehavior(...)`；但当前 SDK 只支持协议枚举里的 39 个行为，不能发送任意字符串行为名。
5. 若要展示速度、配置、动态能力列表，需要扩协议或新增事件/资源同步机制。

## `robot_skill/` 资源目录

当前能力清单放在 `robot_skill/`：

```text
robot_skill/
├── AlphaDog_功能清单.md
├── do_action/
│   ├── ext_actions.json
│   └── ext_actions.yaml
├── do_dog_behavior/
│   ├── dog_behaviors.json
│   └── dog_behaviors.yaml
├── push_ext_actions_to_server.sh
└── run_action_on_dog.sh
```

资源概况：

| 资源 | 数量 | 关键字段 | 当前用途 |
| --- | ---: | --- | --- |
| `AlphaDog_功能清单.md` | 文档 | action 表、behavior 表、ROS topic/service 示例 | 人读说明与真机能力记录 |
| `do_action/ext_actions.json` | 140 条，139 个唯一 `action_id` | `action_id`、`action_name`、`process` | 扩展动作资源，可打包给 App 展示 |
| `do_action/ext_actions.yaml` | 同 JSON | 同 JSON，带注释 | 便于维护和人工阅读 |
| `do_dog_behavior/dog_behaviors.json` | 39 条 | `behavior_name`、`tree` | 行为资源，可打包给 App 展示 |
| `do_dog_behavior/dog_behaviors.yaml` | 同 JSON | 同 JSON，带注释 | 便于维护和人工阅读 |

注意：

- `ext_actions.json` 中 `action_id=20589` 出现两次，分别是 `bored_half_sit` 和 `duck_walk`。如果 App 以 `action_id` 做唯一 key，需要额外处理重复 ID。
- `AlphaDog_功能清单.md` 写的是“扩展动作 134 个”，但当前 JSON 是 140 条；以后应以 JSON/YAML 资源为准，文档作为说明。
- `do_dog_behavior` 行为名共 39 个，当前协议枚举也正好覆盖这 39 个。

## 手机协议格式

控制和状态都走二进制帧：

```text
0xAA55 | Type | Seq | Len | Payload | CRC16
```

字段：

| 字段 | 长度 | 说明 |
| --- | ---: | --- |
| magic | 2 | 固定 `0xAA55` |
| type | 1 | `0x01 CMD` / `0x02 STATE` / `0x03 ACK` |
| seq | 1 | 0..255 循环序号 |
| len | 2 | little-endian payload 长度 |
| payload | N | 具体载荷 |
| crc16 | 2 | 对 `type + seq + len + payload` 计算 CRC16 |

最大 payload 长度当前是 512 bytes。

### CMD payload

| 命令 | command_id | Payload | 说明 |
| --- | ---: | --- | --- |
| MOVE | `0x01` | `cmd_id(1) + vx(int16) + vy(int16) + yaw(int16)` | `vx/vy/yaw` 乘以 100 后编码 |
| STAND | `0x10` | `cmd_id(1)` | 离散姿态命令 |
| SIT | `0x11` | `cmd_id(1)` | 离散姿态命令 |
| STOP | `0x12` | `cmd_id(1)` | 停止 |
| SKILL_INVOKE | `0x20` | 见下节 | 统一 skill 调用入口 |

### `0x20 skill_invoke`

Payload：

```text
cmd_id(0x20) | service_id | operation | flags | arg_len | args
```

| 字段 | 长度 | 说明 |
| --- | ---: | --- |
| `cmd_id` | 1 | 固定 `0x20` |
| `service_id` | 1 | 目标技能 |
| `operation` | 1 | 操作类型 |
| `flags` | 1 | bit0 表示 require_ack |
| `arg_len` | 1 | args 长度，最大 255 |
| `args` | N | 服务参数 |

已定义 `service_id`：

| service_id | 名称 | 当前链路是否完整 |
| ---: | --- | --- |
| `0x01` | `do_action` | 可用 |
| `0x02` | `do_dog_behavior` | 可用，但只能发送枚举内 39 个行为 |
| `0x03` | `set_fan` | 协议枚举保留，服务端未实现 |
| `0x04` | `on_patrol` | 协议枚举保留，服务端未实现 |
| `0x05` | `phone_call` | 协议枚举保留，服务端未实现 |
| `0x06` | `watch_dog` | 协议枚举保留，服务端未实现 |
| `0x07` | `set_motion_params` | 协议枚举保留，服务端未实现 |
| `0x08` | `smart_action` | 协议枚举保留，服务端未实现 |

已定义 `operation`：

| operation | 名称 |
| ---: | --- |
| `0x01` | `execute` |
| `0x02` | `start` |
| `0x03` | `stop` |
| `0x04` | `set` |

当前实际支持：

| API | args 编码 | ROS 目标 |
| --- | --- | --- |
| `do_action(actionId)` | `uint16 little-endian action_id` | `/agent_skill/do_action/execute` |
| `do_dog_behavior(behavior)` | `uint8 behavior_id` | `/agent_skill/do_dog_behavior/execute` |

### STATE payload

当前协议状态固定 7 bytes：

```text
battery(uint8) | roll(int16) | pitch(int16) | yaw(int16)
```

| 字段 | 单位/缩放 | 来源 |
| --- | --- | --- |
| `battery` | 0..100 | `StateStore`，可由 ROS battery topic 更新 |
| `roll` | `int16 / 100` | `StateStore`，可由 ROS IMU 更新 |
| `pitch` | `int16 / 100` | `StateStore`，可由 ROS IMU 更新 |
| `yaw` | `int16 / 100` | `StateStore`，可由 ROS IMU 更新 |

当前 STATE 不包含：

- 前进速度 `linear_vx`
- 横移速度 `linear_vy`
- 角速度 `angular_wz`
- odom 位置 `x/y/yaw`
- 机器人控制配置
- fault codes
- 当前正在执行的 action/behavior
- action 执行结果

这些扩展状态目前只能在服务端内部或 MQTT event 层部分表达，不能通过 BLE/TCP 的固定 STATE payload 到达 App。

### ACK payload

ACK payload 固定 1 byte：

```text
ack_seq(uint8)
```

ACK 语义：

- 表示 `robot_server` 成功解析命令，并成功进入本地处理链。
- 不表示动作执行完成。
- 如果需要动作完成/失败结果，需要新增 result/event 机制。

## SDK API

当前 `mobile_sdk` 对外入口是 `RobotClient`。

连接：

| API | 说明 |
| --- | --- |
| `connectBLE(options)` | BLE 连接 |
| `connectTCP(options)` | TCP 连接 |
| `connectMQTT(options)` | MQTT 连接 |
| `disconnect()` | 断开 |
| `scanBLE()` | BLE 扫描 |

状态：

| API | 说明 |
| --- | --- |
| `stateStream` | 解码后的 `RobotState(battery, roll, pitch, yaw)` |
| `frameStream` | 原始协议帧流 |
| `connectionState` | 连接状态 |
| `errors` | SDK 错误流 |

控制：

| API | 语义 | 适用场景 |
| --- | --- | --- |
| `move(vx, vy, yaw)` | last-wins | 手动摇杆/实时控制 |
| `stand()` | last-wins | 手动控制 |
| `sit()` | last-wins | 手动控制 |
| `stop()` | last-wins | 手动控制 |
| `emergencyStop()` | last-wins，映射 `do_action(0)` | 急停 |
| `enterMotionMode()` | last-wins，映射 `do_action(4)` | 进入运动模式 |
| `recover()` | last-wins，映射 `do_action(3)` | 恢复站立 |
| `doAction(actionId)` | last-wins | 单次动作按钮 |
| `doDogBehavior(behavior)` | last-wins | 单次行为按钮 |
| `*Queued()` | FIFO | 图形化编排 |

当前限制：

- `doDogBehavior` 参数类型是 `DogBehavior` 枚举，不支持从字符串直接发送任意 behavior name。
- `RobotClient` 没有暴露 MQTT `event` stream；虽然 `MqttTransport` 内部有 `events`，但 App 按架构不应直接依赖 transport。
- SDK 没有“查询机器人能力列表”的 API。

## 命令从手机到 ROS 的处理链路

整体链路：

```text
RobotClient
  -> encodeFrame(buildCommandFrame)
  -> BLE/TCP/MQTT transport
  -> robot_server RuntimeTransport
  -> RobotRuntime._handle_transport_chunk
  -> StreamDecoder
  -> RobotControlService.handle_frame
  -> RosControlBridge / RosSkillBridge
```

服务端关键文件：

| 文件 | 作用 |
| --- | --- |
| `robot_server/robot_server/runtime/robot_runtime.py` | transport 生命周期、收包、10Hz 状态广播 |
| `robot_server/robot_server/runtime/control_service.py` | 解析 CMD、去重、ACK、分发 |
| `robot_server/robot_server/ros/bridge.py` | MOVE -> ROS motion topic |
| `robot_server/robot_server/ros/skill_bridge.py` | STAND/SIT/STOP/skill_invoke -> agent skill |
| `robot_server/robot_server/ros/state_bridge.py` | ROS 状态订阅 -> StateStore |

### MOVE -> ROS 速度控制

`MOVE` 进入 `RosControlBridge.apply_command()`：

- 保存为 `_latest_move`
- 后台线程按 `ROBOT_ROS_HZ` 发布，默认 10Hz
- 默认 topic：`/alphadog_node/set_velocity`
- 如果 topic 以 `/set_velocity` 结尾，发布 `ros_alphadog/SetVelocity` 或 fallback message：

```text
vx = command.vx
vy = command.vy if ROBOT_ROS_ENABLE_LATERAL=true else 0
wz = command.yaw
```

如果不是 `set_velocity` topic，则退回 `geometry_msgs/Twist`：

```text
linear.x = vx
linear.y = vy if lateral enabled else 0
angular.z = yaw
```

`STOP` 同时会把 `_latest_move` 清零。

### STAND / SIT / STOP -> ROS skill

离散命令会同时进入 `RosControlBridge` 和 `RosSkillBridge`：

| 命令 | RosControlBridge | RosSkillBridge |
| --- | --- | --- |
| `STAND` | 无动作 | `do_action(ROBOT_ROS_STAND_ACTION_ID)`，默认 3 |
| `SIT` | 无动作 | `do_action(ROBOT_ROS_SIT_ACTION_ID)`，默认 5 |
| `STOP` | 清零速度 | `cancel_all()` 后 `do_action(ROBOT_ROS_STOP_ACTION_ID)`，默认 6 |

### `do_action` -> ROS skill

手机发送：

```dart
client.doAction(20593)
```

协议编码：

```text
cmd_id=0x20
service_id=0x01
operation=0x01
args=uint16_le(20593)
```

服务端执行：

```text
/agent_skill/do_action/execute
ExecuteGoal.args = {"action_id": 20593}
```

优先级和 hold time 来自环境变量：

| 环境变量 | 默认 |
| --- | --- |
| `ROBOT_ROS_ACTION_PRIORITY` | `30` |
| `ROBOT_ROS_ACTION_HOLD_SEC` | `5.0` |
| `ROBOT_ROS_SKILL_INVOKER` | `robot_server` |

### `do_dog_behavior` -> ROS skill

手机发送：

```dart
client.doDogBehavior(DogBehavior.waveHand)
```

协议编码：

```text
cmd_id=0x20
service_id=0x02
operation=0x01
args=uint8(0x24)
```

服务端执行：

```text
/agent_skill/do_dog_behavior/execute
ExecuteGoal.args = {"behavior": "wave_hand"}
```

当前 behavior ID 到名字的映射硬编码在：

```text
robot_server/robot_server/ros/skill_bridge.py
protocol/dart/lib/src/frame_types.dart
protocol/python/robot_protocol/models.py
```

这意味着如果 `robot_skill/do_dog_behavior/dog_behaviors.json` 新增行为，必须同步改 Dart/Python 协议枚举和服务端映射，除非后续把 `do_dog_behavior` 协议参数改为字符串。

## 状态从 ROS 到手机的处理链路

整体链路：

```text
ROS topics
  -> RosStateBridge
  -> StateStore
  -> RobotRuntime._state_loop
  -> build_state_frame
  -> transport.broadcast
  -> RobotClient.frameStream/stateStream
  -> App UI
```

服务端状态采集：

| ROSConfig 字段 | 默认 topic | 默认 msg | 写入 |
| --- | --- | --- | --- |
| `battery_topic` | `/battery_state` | `sensor_msgs/BatteryState` | `RobotState.battery` |
| `imu_topic` | `/imu/data` | `sensor_msgs/Imu` | `RobotState.roll/pitch/yaw` |
| `odom_topic` | `/odom` | `nav_msgs/Odometry` | `RobotStateExtras.odometry` |
| `diagnostics_topic` | `/diagnostics` | `diagnostic_msgs/DiagnosticArray` | `RobotStateExtras.fault_codes` + event |

真机 AlphaDog 文档中还列出这些状态 topic：

| topic | 内容 |
| --- | --- |
| `/alphadog_node/robot_ready` | 机器人就绪状态 |
| `/alphadog_node/boot_up_state` | 开机状态 |
| `/alphadog_node/body_status` | 身体状态 |
| `/alphadog_node/dog_ctrl_state` | 控制状态机 |
| `/alphadog_node/dog_ctrl_config` | 控制配置 |
| `/alphadog_node/robot_ctrl_status` | 机器人控制状态 |
| `/alphadog_node/joint_states` | 关节状态 |
| `/alphadog_node/imu` | IMU |
| `/alphadog_node/ground_status` | 地面接触状态 |
| `/alphadog_node/ext_force_status` | 外力检测 |
| `/alphadog_node/robot_system_info` | 系统信息 |
| `/alphadog_node/wifi` | WiFi 信息 |
| `/alphadog_aux/battery_state` | 电池状态 |
| `/alphago_slam/slam_pose` | SLAM 定位 |

当前 `RosStateBridge` 默认没有订阅这些 AlphaDog 专用 topic；可以通过环境变量改成真机 topic，例如：

```bash
ROBOT_ROS_STATE_ENABLED=true
ROBOT_ROS_BATTERY_TOPIC=/alphadog_aux/battery_state
ROBOT_ROS_IMU_TOPIC=/alphadog_node/imu
```

但即使服务端采集到 odom/fault，目前 BLE/TCP 固定 STATE 也只下发 4 个字段。

## 对新控制页的实现建议

### 第一阶段：不扩协议，先做本地资源控制页（已落地）

已实现范围：

- 首页新增“完整动作控制”入口。
- 页面顶部展示连接状态和 `stateStream` 的 `battery/roll/pitch/yaw`。
- 本地打包 `robot_skill/do_action/ext_actions.json` 和 `robot_skill/do_dog_behavior/dog_behaviors.json` 到 App assets。
- 动作列表展示 `action_id + action_name`，点击 `RobotClient.doAction(actionId)`。
- 行为列表展示 `behavior_name`，点击对应 `DogBehavior` 枚举。

需要处理：

- `action_id=20589` 重复，UI key 用 `action_id + action_name`。
- `do_dog_behavior` 只支持 39 个枚举行名，必须确认 JSON 与枚举一致。
- 资源文件已复制到 `apps/robot_app/assets/robot_skill/`；后续如 `robot_skill/` 源资源变化，需要同步更新 App assets。

### 第二阶段：补 SDK 状态/事件能力

如果页面要显示更多状态：

- 在 `RobotClient` 暴露 MQTT events，或新增统一 `eventStream`。
- 定义 `RobotStateExtended`，包含 odom/fault/config。
- 选择扩展路径：
  - 扩二进制协议新增 `STATE_EXT` 类型。
  - 或保留二进制 STATE，只用 MQTT JSON event 推扩展状态。
  - 或 BLE/TCP 也增加 JSON event frame。

推荐：如果 BLE 是主链路，优先扩二进制协议或增加统一 event frame，不要只依赖 MQTT。

### 第三阶段：动态获取能力列表

如果动作/行为列表必须来自机器狗而不是 App 本地资源，需要新增协议能力：

| 新能力 | 用途 |
| --- | --- |
| `CAPABILITY_QUERY` | 手机请求能力清单 |
| `CAPABILITY_STATE` 或 `CAPABILITY_CHUNK` | 服务端分片返回动作/行为列表 |
| 资源版本字段 | App 判断本地资源是否过期 |

服务端可选数据源：

- 读取 `robot_skill/do_action/ext_actions.json`
- 读取机器人端实际配置目录
- 调 ROS 服务 `/alphadog_node/get_actions`
- 订阅 `/agent_skill/do_action/ext_actions`、`/agent_skill/do_dog_behavior/dog_behaviors`，如果真机上 topic 稳定可用

## 当前明确缺口

| 缺口 | 影响 |
| --- | --- |
| 协议没有 capability/list 查询 | App 不能从机器人动态拉取全部动作/行为 |
| `do_dog_behavior` args 是 `uint8 behavior_id` | 不能直接发送任意 behavior name |
| STATE 固定 7 bytes | 不能展示速度、odom、配置、故障等扩展状态 |
| `RobotClient` 不暴露 MQTT events | App 不能通过 SDK 订阅 `battery_low/fault` JSON event |
| ACK 不表示动作完成 | UI 无法准确显示动作执行成功/失败 |
| `robot_skill` 源资源与 App assets 需要手动同步 | 源资源变化后，App 内列表可能过期 |

## 推荐下一步

1. 给 `RobotClient` 增加 `eventStream` 或 `extendedStateStream`，收口 MQTT event 与未来 BLE/TCP event。
2. 评估是否把 `do_dog_behavior` 协议参数从 `uint8 enum` 扩为字符串或字符串 ID，降低资源更新成本。
3. 如果必须显示前进速度，扩展状态协议，把 `StateStore.extras.odometry.linear_vx/angular_wz` 下发到 App。
4. 如需动作执行结果，新增 result event：`action_started/action_succeeded/action_failed`，不要复用 ACK 表达完成语义。
5. 为 `robot_skill/` 到 App assets 增加生成或同步脚本，避免资源手动复制后漂移。
