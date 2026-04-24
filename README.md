# Robot OS Lite

`robot_factory/` 是机器狗控制系统的 monorepo，覆盖 Flutter App、Flutter/Dart SDK、Ubuntu/ROS1 机器人端服务，以及 Python/Dart 共享二进制协议。

这不是只到骨架阶段的仓库。当前代码已经具备协议层、`robot_server` 多传输运行时、`mobile_sdk` 统一客户端，以及 `apps/robot_app` 演示级控制台与动作编排能力；但距离“完整产品化交付”还有几处明确缺口。

## 项目判断

| 模块 | 当前状态 | 说明 |
| --- | --- | --- |
| `protocol` | 稳定 | Python / Dart 两套协议实现已对齐，包含帧结构、CRC16、stream decoder、ACK / STATE 编解码，以及 `0x20 skill_invoke`（`do_action` / `do_dog_behavior`）扩展。 |
| `robot_server` | 可运行 | 已实现 BLE / TCP / MQTT transport、10Hz 状态广播、ROS1 `/cmd_vel` 连续控制桥、ROS skill bridge（`do_action` / `do_dog_behavior`）、ROS 状态采集桥、`.env.example` 和启动脚本。 |
| `mobile_sdk` | 可集成 | `RobotClient` 已提供 `connectBLE()` / `connectTCP()` / `connectMQTT()`、`move/stand/sit/stop/doAction/doDogBehavior`、命令队列、ACK 重试、连接状态、BLE 扫描、TCP / BLE / MQTT transport；BLE 客户端基础链路已完成搜索 / 连接 / 数据交互验证。 |
| `apps/robot_app` | 演示级可用 | 已有 BLE 扫描与连接、TCP / MQTT 连接表单、状态看板、首页快捷动作直控，以及动作序列编辑与执行，并可通过动作编排下发 `do_action` / `do_dog_behavior`；仍不是完整的量产 App。 |
| `docs` / `scripts` | 基本齐全 | 已包含 BLE 联调、ROS 状态采集、部署、验收清单等文档，以及 `start_robot_server.sh` 启动脚本。 |

## 当前已知缺口

- ACK 目前只表示 `robot_server` 已接受命令进入本地处理链，不表示机器人动作执行完成；若需要结果语义，仍需额外 event / result 通道。
- `apps/robot_app` 还缺设备绑定、配置持久化、完整手动遥控 UI 等产品功能。
- BLE 基础链路已经完成客户端真实搜索、连接和数据交互验证；当前剩余重点是稳定性回归、长时压测和更多终端覆盖，而不是基础连通性。
- MQTT / BLE / ROS 的 smoke 验证主要靠本地脚本和手工联调，尚未形成 CI 级自动回归。

## Monorepo 结构

```text
robot_factory/
├── apps/robot_app          # Flutter 产品 App / 演示控制台 / 动作编排
├── docs                    # 设计、路线图、backlog、部署与联调文档
├── mobile_sdk              # Flutter/Dart SDK（RobotClient、transports、队列）
├── protocol                # Python + Dart 共享二进制协议
├── robot_server            # Ubuntu 20.04 + ROS1 Noetic 机器人端服务
├── scripts                 # 启动脚本与 smoke 工具
├── .env.example            # robot_server 环境变量模板
├── prd.md                  # 主需求
└── brd.md                  # 产品背景
```

## 架构概览

- App 侧通过 `mobile_sdk` 暴露的 `RobotClient` 收敛所有连接和控制入口。
- `protocol` 负责统一帧格式：`0xAA55 | Type | Seq | Len | Payload | CRC16`。
- `protocol` 当前保留 `MOVE / STAND / SIT / STOP`，并扩展 `0x20 skill_invoke` 以承载 `do_action` / `do_dog_behavior`。
- `robot_server` 统一接入 BLE / TCP / MQTT 三种 transport，再通过同一套 parser、`StateStore`、`/cmd_vel` bridge 和 ROS skill bridge 下发或上报。
- `event` 只走 MQTT JSON topic；`control` / `state` 均走二进制协议。

更多设计细节见 [`docs/phase0_design.md`](docs/phase0_design.md)。

## 快速开始

### 1. Python 依赖

```bash
cd /path/to/robot_factory
python3 -m venv .venv
source .venv/bin/activate
pip install -e protocol/python
pip install -e robot_server
```

若要在真实 Ubuntu 20.04 + ROS1 Noetic 机器人端启 BLE，还需要系统依赖：

- `python3-dbus`
- `python3-gi`
- `bluetooth.service`
- `rospy` 与相关 `*_msgs`

### 2. Python 单测

```bash
cd /path/to/robot_factory
PYTHONPATH=protocol/python python3 -m unittest discover -s protocol/python/tests
PYTHONPATH=protocol/python:robot_server python3 -m unittest discover -s robot_server/tests
```

### 3. 启动 robot_server

```bash
cd /path/to/robot_factory
cp .env.example .env
bash scripts/start_robot_server.sh
```

本地只想验证下行状态链路时，可以在 `.env` 打开：

```bash
ROBOT_DEBUG_STATE_TICK_ENABLED=true
```

### 4. Flutter 侧

```bash
cd /path/to/robot_factory/mobile_sdk
flutter pub get
flutter test

cd /path/to/robot_factory/apps/robot_app
flutter pub get
flutter test
flutter run
```

Flutter / Dart 侧当前要求满足 `>=3.5.0 <4.0.0`。

## 关键入口

- 机器人端启动：[`scripts/start_robot_server.sh`](scripts/start_robot_server.sh)
- 机器人端主入口：[`robot_server/robot_server/main.py`](robot_server/robot_server/main.py)
- 运行时装配：[`robot_server/robot_server/app.py`](robot_server/robot_server/app.py)
- SDK 入口：[`mobile_sdk/lib/src/robot_client.dart`](mobile_sdk/lib/src/robot_client.dart)
- App 首页：[`apps/robot_app/lib/src/home_page.dart`](apps/robot_app/lib/src/home_page.dart)

## 文档索引

- 需求与背景：[`prd.md`](prd.md)、[`brd.md`](brd.md)
- 现状与优先级：[`docs/backlog.md`](docs/backlog.md)
- Phase 0 设计：[`docs/phase0_design.md`](docs/phase0_design.md)
- BLE 控制格式：[`docs/ble_control_data_format.md`](docs/ble_control_data_format.md)
- BLE 联调：[`docs/ble_integration.md`](docs/ble_integration.md)
- ROS 状态采集：[`docs/ros_state_integration.md`](docs/ros_state_integration.md)
- 部署：[`docs/deploy.md`](docs/deploy.md)
- 验收清单：[`docs/acceptance_checklist.md`](docs/acceptance_checklist.md)
- AI 协作路线图：[`docs/codex_development_roadmap.md`](docs/codex_development_roadmap.md)、[`docs/cursor_opus_development_roadmap.md`](docs/cursor_opus_development_roadmap.md)
- 模块说明：[`robot_server/README.md`](robot_server/README.md)、[`mobile_sdk/README.md`](mobile_sdk/README.md)、[`apps/robot_app/README.md`](apps/robot_app/README.md)

## 推荐下一步

按当前代码与 backlog，优先级最高的工作仍是：

1. 把 App 从“演示控制台”继续推进到“可交付控制产品”，补设备管理、配置记忆和更完整的控制 UI。
2. 补 BLE 长时压测、多终端回归和 smoke 自动化，而不是重复做基础搜索 / 连接验证。
3. 补 Python ↔ Dart 协议 golden vectors 与更多 runtime / transport 回归，继续压实协议契约。
