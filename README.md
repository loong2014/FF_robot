# Robot OS Lite

`robot_factory/` 是按 `prd.md` 搭建的机器狗控制系统 monorepo，覆盖以下三阶段：

- Phase 0：完整系统设计，见 [docs/phase0_design.md](docs/phase0_design.md)
- Codex 开发路线图，见 [docs/codex_development_roadmap.md](docs/codex_development_roadmap.md)
- Phase 1：工程骨架与接口分层，目录见下方结构
- Phase 2：统一协议、命令队列、BLE/TCP/MQTT/ROS1、Flutter SDK 与图形化动作引擎的第一版实现

## Monorepo 结构

```text
robot_factory/
├── apps/robot_app          # Flutter 示例应用 + 图形化动作引擎
├── docs                    # Phase 0 设计文档
├── mobile_sdk              # Flutter/Dart SDK
├── protocol                # Python + Dart 共享二进制协议
└── robot_server            # Ubuntu/ROS1 机器人端服务
```

## 当前实现范围

- 协议层：统一二进制帧、CRC16、流式解包、ACK/重传辅助能力
- 机器人端：BLE GATT 框架、TCP 服务端、MQTT Router、ROS1 `/cmd_vel` 桥接、10Hz 状态推送循环
- App 侧：`RobotClient`、命令队列、TCP 传输、BLE/MQTT 接口占位、图形化动作引擎

## 本地开发

### Python 侧

```bash
cd /Users/xinzhang/gitProject/robot/robot_factory
PYTHONPATH=protocol/python:robot_server python3 -m unittest discover -s protocol/python/tests
PYTHONPATH=protocol/python:robot_server python3 -m unittest discover -s robot_server/tests
```

### Flutter / Dart 侧

```bash
cd /Users/xinzhang/gitProject/robot/robot_factory/mobile_sdk
flutter pub get

cd /Users/xinzhang/gitProject/robot/robot_factory/apps/robot_app
flutter pub get
flutter run
```

## 运行服务端

```bash
cd /Users/xinzhang/gitProject/robot/robot_factory
PYTHONPATH=protocol/python:robot_server python3 -m robot_server.main
```

## 说明

- 目标运行环境：Ubuntu 20.04 + ROS1 Noetic + **Python 3.8**。`protocol/python` 与 `robot_server` 已全量兼容 Python 3.8（统一使用 `from __future__ import annotations` + `typing.Optional/Union/List/Dict/Deque/Set` 语义，不使用 `@dataclass(slots=...)`、PEP 604 `X | Y` 运行期联合、PEP 585 运行期泛型、`match/case`、`functools.cache`、`zoneinfo` 等 3.9+/3.10+ 专属特性）；`pyproject.toml` 的 `requires-python` 同步为 `>=3.8`。
- BLE 服务端依赖 BlueZ 与 `dbus-next`，MQTT Router 依赖 `paho-mqtt`。
- Flutter 侧 BLE/MQTT 已预留清晰接口，后续可直接接入具体插件。
