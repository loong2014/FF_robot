# robot_factory Backlog（现状盘点 + 优先级）

> 生成时间：2026-04-21  
> 依据：`prd.md`、`brd.md`、`docs/cursor_opus_development_roadmap.md`，以及对 `protocol/` / `robot_server/` / `mobile_sdk/` / `apps/robot_app/` 的并行 explore 盘点。  
> 规则：本文档是所有后续里程碑的上下文锚点；每个里程碑结束时需要回写完成度与剩余风险。
> 2026-04-23 更新：根据用户反馈，BLE 已完成客户端真实搜索 / 连接 / 数据交互验证；以下与 BLE 基础连通性相关的结论已同步收敛，本轮未做新的真机复测。
> 2026-04-25 更新：长期规划现已明确为“互联、动作控制、教育、视觉、SKILL 平台”。当前 MVP 只覆盖“互联 + 动作控制 + 教育中的简单图形化编程”，不包含视觉和 SKILL 平台。

---

## TL;DR（一眼看结论）

- **协议层（`protocol`）**：帧格式 / CRC / stream decoder / Python ↔ Dart 对齐 **基本到位**。~~主要风险在 **Python 3.8 兼容性**（`@dataclass(slots=True)`、`pyproject.toml requires-python = ">=3.11"`）~~ ✅ 2026-04-21 完成 Python 3.8 兼容性对齐（见 P0-1）；Dart 侧测试覆盖不足的风险仍在。
- **机器人端（`robot_server`）**：主链可运行（BLE/TCP/MQTT/ROS/StateStore/部署脚手架均已落地）；ACK 语义已收口为“成功接受 `CMD` 进入本地处理链后回 ACK”，重复包按 `seq + payload` 去重，server 侧未接入的 `CommandQueue` 已删除。
- **SDK（`mobile_sdk`）**：`RobotClient` API + 命令队列 + ACK/重试 + BLE/TCP/MQTT transport + 连接状态已经可用，其中 BLE 已完成客户端真实搜索 / 连接 / 数据交互验证；主要缺口是**没有 BLE > TCP > MQTT 自动切换**，且 export 边界仍偏宽。
- **App（`apps/robot_app`）**：已具备 **BLE 扫描 / 连接**、TCP/MQTT 参数配置、状态看板、首页快捷动作直控与动作编排；并已完成一条真实主链联调：App 通过 BLE 向机器狗发命令，机器人端转成 ROS 控制机器狗。当前仍是演示级控制台，缺设备绑定、配置持久化与正式运动控制 UI。

**最高优先级的三件事**（建议按顺序推进，与路线图 Milestone 1/2 对齐）：

1. **P0/P1 — 把 App 从演示控制台推进到可交付控制产品**：补设备管理、配置持久化、手动控制 UI 与更完整的错误恢复。
2. **P1/P2 — 把已验证的 BLE 基础链路沉淀为稳定性回归能力**：补长时压测、多终端回归和 smoke / CI，而不是重复证明能扫到和连上。
3. **P0/P1 — 收敛 SDK / 协议契约**：补 `mobile_sdk` export 边界、Python ↔ Dart golden vectors 与更多 runtime 回归，减少后续多 transport 漂移。
4. **新增 P0 Gate — 收敛两周 K12 MVP 范围**：当前关键不再是“能不能做”，而是“两周内只交付简单图形化编程”，避免把参数化动作编辑器、视觉和 SKILL 平台一并塞进首版。

---

## 1. 模块完成度矩阵

对照 `prd.md` Phase 2 各子能力：

| 子能力 | `robot_server` | `mobile_sdk` | `apps/robot_app` | `protocol` | 备注 |
|---|---|---|---|---|---|
| 统一二进制协议（帧 + CRC + stream decoder） | ✅（`robot_protocol` 接入） | ✅（`robot_protocol` 接入） | 无需关心 | ✅ | Python ↔ Dart 对齐度高 |
| BLE 传输 | ✅（BlueZ GATT + GLib backend 已落地） | ✅（`flutter_blue_plus` 真实 transport） | ✅（已完成客户端真实扫描 / 连接 / 数据交互验证） | — | 基础链路已闭环，剩余是稳定性压测与多终端回归 |
| TCP 传输 | 🟡（asyncio server + 广播 OK，断连语义简） | 🟡（`Socket` + stream decoder，无超时 / 无统一断开事件） | 🟡（有"Connect TCP"按钮，无参数配置 UI） | — | 跑得起来，但未产品化 |
| MQTT 传输 | 🟡（Router、鉴权、TLS、事件分流已实现） | 🟡（真实 transport 已实现） | 🟡（已接入参数配置与连接入口） | — | 仍依赖真实 broker 与 smoke / CI 回归 |
| ROS1 运动控制（10Hz） | 🟡（`RosControlBridge` 有，独立线程；AlphaDog 默认 `/alphadog_node/set_velocity`） | 无需关心 | 无需关心 | — | 无 mock 节点 / rostest |
| ROS1 状态采集（电池 / IMU / odom / 诊断） | ✅（`RosStateBridge`，topic + msg_type 可配置；默认 sensor_msgs/nav_msgs/diagnostic_msgs；battery_low + fault event） | 无需关心 | 无需关心 | — | 单测 15 条；真机 rostopic pub 验证步骤见 `docs/ros_state_integration.md` |
| StateStore & 10Hz 状态推送 | ✅（`RobotState` + `RobotStateExtras`，真实电量/IMU/odom/故障填入；BLE/TCP/MQTT 三路广播协议 STATE） | 🟡（`stateStream` OK） | 🟡（展示 battery/roll/pitch/yaw） | — | extras（odom/fault）仅通过 MQTT event 下发 |
| 命令队列（move 覆盖 / discrete FIFO / 未 ACK 阻塞重传） | —（server 不维护独立发送队列；负责 ACK + `seq/payload` 去重） | 🟡（`CommandQueue` 已用于 RobotClient，重试 3 次 + 100ms） | 无需关心 | — | 发送端队列当前只在 SDK 侧实现 |
| 自动切换传输（BLE > TCP > MQTT） | 无需关心 | ❌ | ❌ | — | 完全未实现 |
| 统一连接状态模型（transport + state + error） | — | 🟡（`RobotConnectionState` + `connectionState` 已有） | 🟡（已接连接状态展示） | — | 自动切换 / 更细错误模型仍待补 |
| 设备搜索 / 绑定 | — | — | 🟡 | — | 已有 BLE 扫描流程，绑定与持久化仍待补 |
| 基础运动控制 UI（摇杆 / 方向） | — | — | 🟡 | — | 已有首页快捷动作直控，仍缺摇杆 / 连续运动控制 UI |
| 动作编排（Action Engine） | — | — | 🟡（顺序 / 暂停 / 停止 OK；序列硬编码；无错误反馈） | — | 用户不能编辑序列 |
| 启动 / 部署 | ✅（`.env.example` + 启动脚本 + systemd 示例已补齐） | — | 🟡（`android/` / `ios/` 已补齐） | — | 仍缺更完整交付流程与自动化验证 |

图例：✅ 可用 / 🟡 部分或 stub / ❌ 缺失。

---

## 2. 按优先级排序的 backlog

> 规则：`[P0]` 必须尽快，`[P1]` 短期内，`[P2]` 机会性；规模 `S ≤ 0.5d`、`M ≈ 1–3d`、`L ≥ 3d`。  
> 每条都标注 **所属模块** 与 **是否影响 ROS1 Noetic 真机部署**（🖧 = 直接影响真机 / 🧪 = 仅影响开发与联调 / — = 与部署无关）。

### P0 — 阻塞型 / 近期里程碑先决

| # | 条目 | 模块 | 规模 | 真机 |
|---|---|---|---|---|
| P0-1 | **统一 Python 目标版本**：在 `AGENTS.md`、`protocol/python/pyproject.toml`、`robot_server/pyproject.toml` 三处对齐。若按 AGENTS 保留 Python 3.8：消除所有 `@dataclass(slots=True)`、`X \| Y` 运行时、`list[int]`/`dict[str, Any]` 运行时泛型（见下面清单）；若改为 3.10+：更新 AGENTS 并记录 Noetic 部署用 pyenv / conda。 ✅ 2026-04-21 完成：选定 Python 3.8；清除全部 `@dataclass(slots=True)`；所有 PEP 604 / PEP 585 写法改回 `typing.Optional/Union/List/Dict/Deque/Set` 并保留 `from __future__ import annotations`；两个 `pyproject.toml` 的 `requires-python` 改为 `>=3.8`；README 补充说明；Python 3.13 下 `protocol/python` 5 个单测 + `robot_server` 3 个单测全部通过；`ast.parse(..., feature_version=(3,8))` 全量 27 个 `.py` 文件通过。 | `protocol` + `robot_server` | L | 🖧 |
| P0-2 | **ACK / CommandQueue 语义收口**：明确 server 不维护独立发送队列，删除未接入的 `runtime/command_queue.py`；`RobotControlService` 改为“解析成功 + 本地处理链接受成功后 ACK”，重复包按 `seq + payload` 去重。 ✅ 2026-04-24 完成（见 Milestone 10） | `robot_server` | M | 🖧 |
| P0-3 | **BLE 端到端联调**：BlueZ GATT 权限 / MTU 协商策略 / ACK 走 state 特征的客户端契约文档化；Flutter 侧选型真实插件并实现 `BleTransport.connect/send + stream decoder`；App 补原生工程与 BLE 权限。 🟢 2026-04-21/22：服务端 BlueZ backend、SDK `BleTransport`、App 扫描页与原生权限均已落地。 🟢 2026-04-23（用户反馈，本轮未复测）：客户端已可搜索、连接机器狗 BLE 服务，并进行数据交互，基础连通性闭环完成。剩余主要是长时稳定性、10Hz STATE 压测、多终端回归和 smoke 自动化。 | `robot_server` + `mobile_sdk` + `apps/robot_app` | L | 🖧 |
| P0-4 | **App 补原生工程**：`flutter create .` 模板生成 `android/` / `ios/`，加入 BLE / 网络权限，Info.plist 的 `NSBluetoothAlwaysUsageDescription` 与 Android `BLUETOOTH_SCAN/CONNECT` 等。 ✅ 2026-04-21 完成：已生成 `android/` 与 `ios/` 工程，补齐 Android BLE 权限与 iOS 蓝牙用途说明，`Podfile` 平台版本设为 iOS 12.0。 | `apps/robot_app` | M | 🖧 |
| P0-5 | **设备管理 UI**（搜索 / 选择 / 绑定 / 连接状态）：至少支持 BLE 扫描列表 + 记住最近设备；TCP / MQTT 加参数配置屏（host/port/broker/device-id），替换掉当前硬编码 / 缺省值。 🟡 2026-04-21 已完成最小 BLE 扫描列表与设备选择回连；最近设备记忆、TCP/MQTT 参数配置、结构化连接状态仍待继续。 | `apps/robot_app` | L | 🖧 |
| P0-6 | **收敛 SDK 对外 export**：`mobile_sdk.dart` 只 export `RobotClient` + 配置模型 + 必要类型；`BleTransport`/`TcpTransport`/`MqttTransport`/`CommandQueue` 改为内部实现，避免 App 绕过 `RobotClient`。 | `mobile_sdk` | S | — |
| P0-7 | **部署脚手架**：`.env.example`（`ROBOT_*` 全量）、`robot_server` README 补 Noetic 安装步骤、`systemd` unit 示例、依赖声明补 `robot-protocol`。 ✅ 2026-04-22 完成（Milestone 8）：仓库根新增 `.env.example`（按 BLE/TCP/MQTT/ROS 分组的全量 `ROBOT_*`）；新增 `scripts/start_robot_server.sh`（source ROS1 Noetic + 加载 env + 组装 PYTHONPATH，默认从 `/etc/robot_factory/robot_server.env` 读取）+ `scripts/robot_server.service`（systemd unit 示例，带安装/回滚命令注释）；新增 `docs/deploy.md`（拓扑 / 系统 apt 包 / Python 依赖 / 环境变量表 / 启动依赖顺序 / TCP·BLE·MQTT·ROS 联调步骤 / 排错矩阵 / 上线前待办）与 `docs/acceptance_checklist.md`（§0 环境、§1 单测、§2 启动存活、§3–§7 各 transport + ROS、§8 Action Engine、§9 降级、§10 网络观察、§11 报告模板、§12 预发布判定）。`robot-protocol` 依赖尚未通过 `pyproject.toml` 显式声明（仍依赖 `PYTHONPATH` 方式），真机走 `pip install -e protocol/python`；systemd 示例默认 `User=root` 以规避 polkit BLE 限制。 | `robot_server` | M | 🖧 |
| P0-8 | **Python ↔ Dart 协议 golden vectors 测试**：固定字节向量双端回归，防止将来两边漂移。 | `protocol` | M | — |
| P0-9 | **K12 两周 MVP 范围收敛**：首版只交付简单图形化编程，用 block 调用当前已有连接与动作控制能力，支撑课堂演示；不做复杂参数化编辑器、视觉能力和 SKILL 平台。 | `mobile_sdk` + `apps/robot_app` | M | — |

### P1 — 近期跟进

| # | 条目 | 模块 | 规模 | 真机 |
|---|---|---|---|---|
| P1-1 | **统一连接状态模型（Milestone 3 核心）**：`Disconnected / Connecting / Ready / Degraded` + 当前 `TransportKind` + 结构化 `RobotError` + 对外 Stream，在 `RobotClient` 暴露。 | `mobile_sdk` | M | — |
| P1-2 | **BLE > TCP > MQTT 自动切换**：失败检测 / 回落策略 / 命令队列不丢失；保留显式 `switchTo(transport)` 扩展点。 | `mobile_sdk` | M | — |
| P1-3 | **`RobotClient` Future 语义**：文档化或改造 `move/stand/...`，区分"入队完成"与"ACK 完成"；至少让 `stand/sit/stop` 返回 `CommandResult`。 | `mobile_sdk` | M | — |
| P1-4 | **TCP Transport 健壮化**：连接超时、断线事件上抛、`StreamController.close`、`_frames` 终结语义；与 `RobotClient` 联动 `disconnect`。 ✅ 2026-04-21 完成（Milestone 4）：`mobile_sdk/tcp_transport.dart` 接入 `connectTimeout`、`onDone`/`onError` → `frames` error（触发 `RobotClient._handleTransportFailure` → 重连策略），`disconnect()` 释放 socket / subscription / controller，`dispose()` 关闭 `StreamController`；`TcpConnectionOptions` 新增 `connectTimeout`；新增 4 个 `mobile_sdk/test/tcp_transport_test.dart` 用真实 `ServerSocket` 覆盖 connect+ACK/peer-close/send-disconnected/connect-timeout 路径。 | `mobile_sdk` | M | 🧪 |
| P1-5 | **MQTT 全链路**（Milestone 5）：`mqtt_client`（或等价） + `robot/{id}/control|state|event` + 鉴权 / TLS / clientId；服务端 `MqttRouterTransport` 同步加鉴权、退避、重连。 ✅ 2026-04-21 完成：`robot_server` 端 `MQTTConfig` 扩展 username/password/TLS/keepalive/reconnect 退避；`MqttRouterTransport` 支持注入 client factory、paho-mqtt 2.x callback v2、`publish_event()` JSON 序列化、reply 统一走 state topic。`mobile_sdk` 接入 `mqtt_client ^10.4.0`，`MqttTransport` 采用 PlatformAdapter 模式（`MqttClientSession` 接口），订阅 state→StreamFrameDecoder、订阅 event→`events` Stream、发布 control；`MqttConnectionOptions` 扩展 clientId/username/password/keepAlive/TLS/QoS/subscribeEvents。`apps/robot_app` 新增 `MqttConnectDialog`（host/port/robotId/clientId/鉴权/TLS 校验），`home_page.dart` 接入 + 记忆最近配置 + 状态面板展示 MQTT cfg。脚本 `scripts/mqtt_smoke.py` 做端到端 ACK+STATE 校验（需本地 broker，无 broker 时给清晰提示）。测试：`robot_server` 新增 9 个 MQTT 单测（配置校验/topic/binary-JSON 分流/reply 路由/鉴权 TLS/disabled noop），`mobile_sdk` 新增 8 个 MQTT 单测（订阅/解码/发布/JSON 事件/断开/失败）；Python 单测 17/17 通过、Dart 单测 21/21（`flutter test -j 1`）通过。全部改动 py3.8 ast 校验通过。 | `mobile_sdk` + `robot_server` | L | 🖧 |
| P1-6 | **ROS 真实状态采集**（Milestone 6）：订阅电池 / IMU / odom → 写入 `StateStore`；提供"无传感器"降级与 topic 名称配置项。 ✅ 2026-04-21 完成（见里程碑进度追踪 Milestone 6 条目）。 | `robot_server` | L | 🖧 |
| P1-7 | **`RosControlBridge` 单测**（mock `rospy` / `Twist`）：覆盖发布频率、STOP 清零、异常路径。 | `robot_server` | M | 🧪 |
| P1-8 | **Runtime 集成单测**：多 peer `StreamDecoder`、`RobotControlService` 的 ACK / 去重 / 状态更新、`RobotRuntime` 广播取消。 | `robot_server` | M | 🧪 |
| P1-9 | **`RobotClient` + mock transport 测试**：ACK 驱动 `_pumpQueue`、重试耗尽、discrete 与 move 交织、订阅泄漏检查。 | `mobile_sdk` | M | 🧪 |
| P1-10 | **Action Engine 产品化**（Milestone 7 前置）：序列可编辑（增 / 删 / 改 / 拖拽排序）、本地持久化、步骤级失败 / 重试反馈、运行结束回到 `idle`。 🟡 2026-04-22 完成大部分（Milestone 7）：`ActionStep` 扩展 id/maxRetries/copyWith/title/summary；`ActionEngine` 引入 `ActionProgress` + 步骤级状态机（pending/running/done/failed/skipped）+ per-step 重试 + 可注入 sleep/now；新增 `ActionProgramView`（ReorderableListView + 拖拽 handle + Dismissible 删除 + 参数弹窗）与 `ActionStepEditorDialog`（vx/vy/yaw/duration/retries 校验）；`HomePage` 替换硬编码 `_demoProgram` 为可编辑视图；新增 5 个 `action_engine_test.dart`（顺序/重试/失败跳过/暂停/停止）+ 2 个 `action_program_view_test.dart`（初始列表/空态）；`apps/robot_app` 9/9 单测通过。**本地持久化（SharedPreferences）未纳入本轮**，运行结束自动回到 idle 按语义靠 `completed/stopped` 展示（UI 上暂未主动转回 idle）。 | `apps/robot_app` | L | — |
| P1-11 | **App 订阅 `RobotClient.errors`**：全局错误条、loading、重试入口；告别裸 SnackBar。 | `apps/robot_app` | M | — |
| P1-12 | **主控制面**（摇杆 / 方向键 / 速度条 + stand/sit/stop 三大按钮），全部走 `RobotClient`。 🟡 2026-04-24 已补首页快捷动作直控（stand/sit/stop + 常用 dog behavior），仍缺摇杆 / 连续运动控制面。 | `apps/robot_app` | L | — |
| P1-13 | **protocol STATE battery clamp 统一**：Python `& 0xFF` vs Dart `clamp(0,100)` 任选其一并文档化；明确 pitch/yaw 字段类型约定。 | `protocol` | S | — |
| P1-14 | **Dart 协议测试补齐**：STATE、ACK、DISCRETE、`StreamFrameDecoder` 粘包 / CRC 错误恢复。 | `protocol` | M | 🧪 |

### P2 — 机会性优化

| # | 条目 | 模块 | 规模 | 真机 |
|---|---|---|---|---|
| P2-1 | BLE MTU / 分片策略与 central 协商记录；多 central session 区分（当前 `session_id="central"` 写死）。 | `robot_server` | M | 🖧 |
| P2-2 | 统一 `control_hz` 与 `state_hz` 节拍（可选同一 asyncio 调度 / 单调时钟对齐）。 | `robot_server` | S | — |
| P2-3 | `StreamDecoder` 坏 CRC / 错长度 / 半魔数等边界单测。 | `protocol` | S | 🧪 |
| P2-4 | SDK 重试从 20ms 轮询改事件驱动（降耗电）。 | `mobile_sdk` | S | — |
| P2-5 | `flutter_lints` + 关键路径 widget test + `integration_test`（mock transport）。 | `apps/robot_app` | M | 🧪 |
| P2-6 | 文案本地化、主导航（连接 / 控制 / 编排 / 设置）、主题样式。 | `apps/robot_app` | M | — |
| P2-7 | 连接质量指标（RSSI / 延迟 / 丢包）在 UI 或 state stream 暴露。 | `mobile_sdk` + `apps/robot_app` | M | — |
| P2-8 | paho-mqtt 2.x 回调签名 / MQTT v5 `properties` 兼容性评审，避免升级破坏。 | `robot_server` | S | 🖧 |
| P2-9 | `protocol` ACK 重传"数据结构"抽象（seq tracker + 超时计时器，无 I/O），让 server/SDK 复用同一状态机。 | `protocol` | M | — |
| P2-10 | 扩展 `pyproject` 依赖分组（`[dev]` / `[ros]` / `[ble]` / `[mqtt]`）便于部署按需装。 | `robot_server` | S | 🖧 |

---

## 3. Python 3.8 兼容性清单（若确认走 3.8）

> ✅ 2026-04-21：本清单全部条目已落地修复；保留以作回归与 review 索引。

### `@dataclass(slots=True)` — 3.10+ 专属（**必须改**）

- `protocol/python/robot_protocol/models.py:20,27,38,43`
- `robot_server/robot_server/config.py:16,26,33,54,63`
- `robot_server/robot_server/models.py:10`
- `robot_server/robot_server/runtime/command_queue.py:8`

### PEP 604 `X | Y` 运行时（3.10+，注解以外的使用需改）

- `robot_server/transports/ble/bluez_gatt.py:201–204`
- `robot_server/transports/tcp/server.py:15–16`
- `robot_server/transports/mqtt/router.py:22–24`
- `robot_server/runtime/robot_runtime.py:19,28`
- `robot_server/runtime/state_store.py:39`
- `robot_server/runtime/command_queue.py:14,26,27,30,43,63`
- `robot_server/ros/bridge.py:24,45`

### PEP 585 运行时内置泛型 `list[...]` / `dict[...]`（3.9+）

- `protocol/python/robot_protocol/stream_decoder.py:12,17`
- `robot_server/transports/ble/bluez_gatt.py:55,62,76,81,104,113`
- `robot_server/transports/tcp/server.py:17`
- `robot_server/transports/mqtt/router.py:54`
- `robot_server/runtime/robot_runtime.py:17,26,28`
- `robot_server/runtime/control_service.py:29–30`

### 元数据

- `protocol/python/pyproject.toml:9`、`robot_server/pyproject.toml`：`requires-python = ">=3.11"` 与 Python 3.8 目标冲突。

> 行号为 explore 时刻快照，修复前请以实际为准。

---

## 4. 影响 ROS1 Noetic 真机部署的关键风险

只列"没这几项真机上就跑不起来 / 跑不稳"的条目：

1. **Python 版本对齐**（P0-1）—— 决定 Noetic 上能否 `import`。
2. **`robot_server` 依赖声明齐全 + `.env.example` + systemd**（P0-7）—— 决定能不能交付部署。
3. **BLE 联调**（P0-3 + P0-4）—— BlueZ 权限、MTU、GATT 注册失败的排错。
4. ~~**ROS 真实状态采集**（P1-6）—— 现在 battery / 姿态都是常量，真机上等于假状态。~~ ✅ 2026-04-21 完成，见 Milestone 6 条目；真机仍需 rostopic pub 验证。
5. **MQTT 鉴权 / TLS**（P1-5）—— 真机长期上云最起码的安全面。
6. **原生权限配置**（P0-4）—— 没有 `android/` `ios/`，Flutter App 真机装不上。

---

## 里程碑进度追踪

- ✅ **Milestone 9 / BLE-only 默认模式**（2026-04-22）：
  - `robot_server/robot_server/config.py`：`TCPConfig.enabled` 默认改为 `False`；`BLEConfig`/`TCPConfig` 注释说明「BLE 为主链路、TCP 为调试旁路」；`load_config_from_env` 的 `ROBOT_TCP_ENABLED` 默认同步改为 `false`
  - `.env.example`：头部新增「默认模式：BLE-only」段落；TCP 段默认值改为 `false` 并加注「调试旁路」说明；MQTT 段保留默认 `false` 并标注「上云 / 多路观测时再启用」
  - `robot_server/README.md`：新增「默认链路：BLE-only」小节，列出 `python3 -m robot_server` 的默认行为（BLE=on / TCP=off / MQTT=off / ROS 按部署决定）
  - 验证：`build_transports(load_config_from_env())` 默认仅返回 `['ble']`；`robot_server` 35/35 单测通过；`ReadLints` 无告警
  - 剩余：① TCP/MQTT transport 代码、单测、文档均保留，随环境变量可重开；② BLE 基础功能已联通，但长时压测与多终端回归仍未系统执行
- ✅ **Milestone 10 / ACK 语义收口**（2026-04-24）：
  - `robot_server/robot_server/runtime/control_service.py`：`CMD` 改为先 parse，再 `apply_command()` / `observe_command()`，成功后才回 ACK；解析失败或 bridge 抛错不回 ACK；重复包从纯 `seq` 升级为 `seq + payload` 指纹窗口
  - 删除 `robot_server/robot_server/runtime/command_queue.py` 与 `robot_server/tests/test_command_queue.py`；`robot_server/runtime/__init__.py` 和包根 `__init__.py` 不再导出 `CommandQueue` / `QueuedCommand`
  - 新增 `robot_server/tests/test_control_service.py`：覆盖成功 ACK、重复包只 ACK 不重执、同 `seq` 不同 payload 视为新命令、parse failure 不 ACK、bridge failure 不 ACK 且重试不被误判重复
  - 文档同步：根 `README.md`、`robot_server/README.md`、`docs/phase0_design.md`、`docs/ble_ros_sdk_execution_plan.md`、`docs/deploy.md`
- ✅ **Milestone 1 / Python 3.8 基座对齐**（见 P0-1）
- ✅ **Milestone 2.2 / BLE 端到端**（见 P0-3，客户端基础链路已验，稳定性回归待补）
- ✅ **Milestone 3 / SDK 统一连接管理**（`RobotConnectionState` + `connectionState` Stream + `switchTransport` + 默认无重连策略，测试覆盖优先级/失败/切换/BLE 保留，见 `mobile_sdk/test/robot_client_connection_test.dart`）
- ✅ **Milestone 5 / MQTT 全链路**（2026-04-21）：
  - `robot_server/robot_server/config.py`：`MQTTConfig` 新增 username/password/client_id/keepalive/tls/reconnect_min_delay/reconnect_max_delay；`__post_init__` 校验 robot_id（禁止 `/ + #`）与 qos（0/1/2）；`load_config_from_env` 补全新增字段
  - `robot_server/robot_server/transports/mqtt/router.py`：支持 `client_factory` 注入；paho-mqtt 2.x callback_api_version=VERSION2（附 <2.0 回退）；auth / TLS / `reconnect_delay_set` 在 start() 落地；新增 `publish_event` 做 JSON 序列化 + 异常兜底；reply/broadcast 统一走 state topic
  - `robot_server/robot_server/runtime/robot_runtime.py`：新增 `RobotRuntime.publish_event` 扇出到所有支持 `publish_event` 的 transport（目前为 MQTT）
  - `mobile_sdk/pubspec.yaml`：新增 `mqtt_client: ^10.4.0`
  - `mobile_sdk/lib/src/models/connection_options.dart`：`MqttConnectionOptions` 扩展 clientId/username/password/keepAlive/connectTimeout/useTls/qos/subscribeEvents；`MqttQosLevel` 枚举；暴露 controlTopic/stateTopic/eventTopic getter
  - `mobile_sdk/lib/src/transports/mqtt_transport.dart`（新）：`MqttClientSession` 抽象 + 默认 `_MqttClientSessionImpl`（基于 `MqttServerClient`），`MqttTransport` 订阅 state→`StreamFrameDecoder`、订阅 event→`events` Stream（JSON Map）、发布 control；`connect` 带 `connectTimeout`、失败写入 `frames` 错误并 rethrow；`disconnect` 幂等释放 session/subscription；`dispose` 关闭 controllers
  - `apps/robot_app/lib/src/mqtt_connect_dialog.dart`（新）：host/port/robotId/clientId/username/password/TLS 校验 + 通配符守卫
  - `apps/robot_app/lib/src/home_page.dart`：`_connectMqtt` 走 dialog 记忆 `_lastMqttOptions`；状态面板新增 `MQTT cfg` 行；复用 `RobotConnectionState` / `errors` Stream
  - `scripts/mqtt_smoke.py`（新）：in-process runtime + 真实 paho 客户端完成 MOVE/STAND/STOP → ACK 0/1/2 + ≥1 STATE；broker 不可达时直接退出 10
  - 测试：`robot_server/tests/test_mqtt_router.py` 9 个 test（配置校验 / topic / binary-JSON 分流 / reply 路由 / 鉴权 TLS / disabled noop）；`mobile_sdk/test/mqtt_transport_test.dart` 8 个 test（订阅 / 解码 / JSON 事件 / 发布 / 断开 / 连接失败）；Python 17/17 通过、Flutter mobile_sdk 21/21（`-j 1`）通过、`apps/robot_app` 2/2 通过
  - 剩余风险：smoke 脚本需要真 broker（mosquitto/emqx），未在 CI 集成；`MqttTransport` 的 `autoReconnect` 目前依赖 `mqtt_client` 的内置行为，重连 + 命令队列恢复未做端到端回归；`_MqttClientSessionImpl` 的 `onDisconnected` 把断开事件当错误抛出，后续可与 `RobotClient.reconnectPolicy` 做更细化联动
- ✅ **Milestone 6 / ROS 状态采集与上报完善**（2026-04-21）：
  - `robot_server/robot_server/config.py`：`ROSConfig` 新增 `state_enabled` 以及 `battery_*` / `imu_*` / `odom_*` / `diagnostics_*`（topic + msg_type）、`battery_low_threshold` / `battery_event_debounce_sec` / `queue_size`；`load_config_from_env` 补全对应 `ROBOT_ROS_*` 环境变量
  - `robot_server/robot_server/runtime/state_store.py`：扩展 `OdometrySample` + `RobotStateExtras`（odometry + fault_codes），新增 `set_odometry` / `set_fault_codes` / `snapshot_extras`；协议 STATE 帧字段不变（仍是 battery / roll / pitch / yaw）
  - `robot_server/robot_server/ros/state_bridge.py`（新）：`RosStateBridge` 订阅 battery / IMU / odom / diagnostics；动态 import msg class（`pkg/Msg` 字符串）；四元数 → RPY 弧度；电池 percentage 0..1 与 0..100 两种写法 + `charge/capacity` 兜底；battery_low 事件去抖（默认 60s）；fault event 仅在 fault_codes 变化时触发；注入 `subscriber_factory` / `message_registry` / `clock` 便于单测，不依赖真实 rospy
  - `robot_server/robot_server/runtime/robot_runtime.py`：新增 `state_store` property 与 `attach_ros_state_bridge`；`start/stop` 联动 bridge 生命周期 + 传入当前事件循环；保持 10Hz 运动控制路径与 `_state_loop` 10Hz 广播不变
  - `robot_server/robot_server/app.py`：`build_runtime` 在 `ros.enabled && ros.state_enabled` 时自动装配 `RosStateBridge`，并以 `runtime.publish_event` 作为 event emitter（故障 / 低电量 event 经 `MqttRouterTransport.publish_event` 走到 `robot/{id}/event`）
  - `robot_server/robot_server/ros/__init__.py` / `runtime/__init__.py` / `__init__.py`：暴露 `RosStateBridge` / `OdometrySample` / `RobotStateExtras`；调整 runtime 子包 import 顺序 + `RobotRuntime` 侧用 `TYPE_CHECKING` 引 `RosStateBridge` 以避免循环 import
  - `robot_server/tests/test_ros_state_bridge.py`（新）：15 个 test 覆盖 quaternion 数学、battery 抽取（ratio / 0..100 / charge+capacity / 非法值）、订阅启停 / topic 禁用 / 自定义厂商 topic + msg / 回调写 StateStore / battery_low 去抖 / fault 变化时触发
  - 文档：新增 `docs/ros_state_integration.md`（设计、全量 env 表、真机部署步骤、事件协议、剩余风险），`robot_server/README.md` 同步说明 + env 速查表
  - 测试结果：`protocol/python` 5/5 通过；`robot_server` 35/35 通过（含新增 15 个 ROS state bridge 单测）；全部改动文件 `ast.parse(..., feature_version=(3,8))` 通过；`ReadLints` 无告警
  - 剩余风险：① `RosStateBridge` 需要真机 `rospy` + `*_msgs` 才能实跑，macOS 本地只能单测覆盖，端到端需在机器狗上用 `rostopic pub` 验证（步骤见 `docs/ros_state_integration.md` §3.3）；② 厂商自定义电池消息 schema 与 `sensor_msgs/BatteryState` 差异过大时需要 adapter，目前仅支持 `percentage` + `charge/capacity` 两种 fallback；③ `diagnostics` 频繁抖动下可能产生事件噪声，现仅以 fault_codes 集合变化做去抖；④ event 只走 MQTT，BLE/TCP 客户端拿不到 fault / battery_low 结构化事件——符合 AGENTS.md 协议约束，如需跨 transport 需要扩协议
- 🟡 **Milestone 7 / 动作编排模块产品化**（2026-04-22）：
  - `apps/robot_app/lib/src/action_models.dart`：`ActionStep` 增加稳定 id、`maxRetries`、`copyWith`、`title/summary`；新增 `ActionStepStatus` / `ActionStepProgress` / `ActionProgress` 快照类型
  - `apps/robot_app/lib/src/action_engine.dart`：维护 per-step 状态机（pending/running/done/failed/skipped），新增 `progressStream` + `currentProgress`；执行 `maxRetries+1` 次失败后当前步 failed、后续步 skipped 并停止；`stop()` 调用 `client.stop()` 并容错异常；`run/pause/resume` 幂等；`now/sleep` 可注入以便测试
  - `apps/robot_app/lib/src/action_step_editor_dialog.dart`（新）：move 支持 vx/vy/yaw/duration 编辑，stand/sit/stop 仅编辑 `maxRetries`；数字/整数/非负校验
  - `apps/robot_app/lib/src/action_program_view.dart`（新）：`ReorderableListView` 长按拖拽、`Dismissible` 左滑删除、`+ stand/move/sit/stop` 快速添加（move 自动弹编辑框）、执行/暂停/恢复/停止/清空按钮按状态禁用、每步展示状态 Pill + 尝试次数 + 错误消息
  - `apps/robot_app/lib/src/home_page.dart`：移除硬编码 `_demoProgram` + 旧 `_ProgramPreview`，接入 `ActionProgramView`（预置一个可编辑的 demo 序列作为默认值）
  - 测试：`apps/robot_app/test/action_engine_test.dart`（5 个 test：顺序执行 / 重试成功 / 耗尽失败后跳过 / pause-resume / stop）+ `apps/robot_app/test/action_program_view_test.dart`（2 个 test：初始列表 & 空态）；`flutter test` 9/9 通过；`ReadLints` 无告警
  - 剩余风险：① 未接入本地持久化（SharedPreferences），热重启丢失自定义序列；② `ActionProgramView` 在 `running/paused` 期间锁定拖拽与删除，但尚未加"预计剩余时长 / 时间轴"可视化；③ 未实现 P1-10 中提到的"运行结束自动回 idle"——当前展示 `completed/stopped`，需用户点"执行"才回到可执行态；④ 条件触发 / 场景化脚本 / 时间轴为 P2，未纳入本轮
- ✅ **Milestone 8 / 部署与验收**（2026-04-22）：
  - 新增 `.env.example`（BLE/TCP/MQTT/ROS 全量 `ROBOT_*`，含约束注释）
  - 新增 `scripts/start_robot_server.sh`（source `/opt/ros/noetic/setup.bash`、按优先级加载 env 文件、拼 `PYTHONPATH=protocol/python:robot_server`、`exec python3 scripts/run_robot_server.py`）
  - 新增 `scripts/robot_server.service`（systemd unit；`After=network-online.target bluetooth.service`；`EnvironmentFile=-/etc/robot_factory/robot_server.env`；`Restart=on-failure`；日志走 journal；安装/回滚命令作为 header 注释）
  - 新增 `docs/deploy.md`（交付物清单 / 拓扑图 / apt & Python 依赖 / 环境变量分组表 / systemd 安装步骤 / 启动依赖与启动顺序 / TCP·BLE·MQTT·ROS 联调 / 故障排查矩阵 / 上线前待办 / 文档索引）
  - 新增 `docs/acceptance_checklist.md`（12 节验收清单，含预发布判定）
  - 剩余风险 / 未覆盖点：
    - `robot-protocol` 未通过 `pyproject.toml extras` 分组安装，仍需 `pip install -e protocol/python`
    - `.env` 仍是明文存凭证，生产需接入密钥管理（KMS / Vault / `LoadCredential=`）
    - 无主动健康探针（liveness endpoint），systemd 下仅靠 `Restart=on-failure`
    - MQTT TLS 证书签发流程仓库不提供
    - BLE 已完成功能性联调；10Hz STATE 连续压测、多终端回归与 smoke 自动化尚未执行
    - `scripts/*_smoke.py` 未集成到 CI（MQTT 需要 ephemeral broker）
- ✅ **Milestone 4 / TCP 全链路**（2026-04-21）：
  - `robot_server/transports/tcp/server.py`：加日志、session_id 单调后缀、send 失败自动剔除 client、stop 幂等关闭
  - `robot_server/app.py`（新）：`build_runtime(ServerConfig)` 工厂，transport 按配置开关（BLE/TCP/MQTT 任意组合）
  - `scripts/run_robot_server.py`（新）：环境变量驱动、Ctrl+C 优雅退出的最小运行入口
  - `scripts/tcp_smoke.py`（新）：端到端烟雾脚本（MOVE/STAND/STOP → 3 个 ACK + ≥1 STATE）
  - `mobile_sdk/tcp_transport.dart`：`connectTimeout` / `onDone` → 断线错误 / 资源释放，详见 P1-4
  - `mobile_sdk/models/connection_options.dart`：`TcpConnectionOptions` 新增 `connectTimeout`
  - `apps/robot_app/tcp_connect_dialog.dart`（新）：Host/Port 输入对话框（带校验）
  - `apps/robot_app/home_page.dart`：订阅 `RobotClient.connectionState` + `errors` 统一展示，保留上次 TCP 配置，新增 Disconnect 按钮
  - 测试：`robot_server/tests/test_tcp_transport.py`（3 test）+ `mobile_sdk/test/tcp_transport_test.dart`（4 test），全通过

## 5. 推荐下一步（当前状态）

1. **P0-5 / P1-11 / P1-12 App 产品化**：补设备绑定、配置持久化、全局错误条和正式运动控制 UI，让 App 从演示控制台往可交付产品收敛。
2. **BLE 稳定性回归**：基础搜索 / 连接 / 数据交互已验证，后续若需要继续投入，重点应转向长时压测、10Hz STATE 连续运行、重连场景和多终端覆盖。
3. **P0-8 / P1-8 / P1-9 协议与运行时回归**：补 Python ↔ Dart golden vectors、`RobotRuntime` 集成单测和 `RobotClient` mock transport 测试，继续压实协议契约。
4. **CI / Smoke 集成**：优先把 MQTT/BLE 相关 smoke 验证沉淀成自动化，避免只靠手工联调守质量。

> 每个里程碑结束时，请在本文件对应条目后面追加：`✅ 完成 / 失败 / 推迟 + 一句话结论 + PR/commit 引用`，形成递进式收敛。
