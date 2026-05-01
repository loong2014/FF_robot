# project_tree.md

本文件用于新 job / 新 Agent 快速理解 `robot_factory` 代码结构。它不是需求来源，也不是完整 API 文档；如果与需求文档冲突，以 `prd.md`、`brd.md`、`docs/backlog.md` 为准。

## 一眼总览

`robot_factory/` 是机器狗控制系统 monorepo，主链路是：

```text
apps/robot_app
  -> mobile_sdk
    -> protocol/dart
      -> BLE / TCP / MQTT
        -> robot_server
          -> protocol/python
          -> ROS1 / BlueZ / MQTT broker
```

核心模块职责：

| 目录 | 职责 | 常见修改场景 |
| --- | --- | --- |
| `apps/robot_app/` | Flutter App，包含连接、控制页、图形化编排、语音/手势入口 | 改 UI、页面流程、动作编排、BLE 扫描体验 |
| `mobile_sdk/` | Flutter/Dart SDK，统一封装 `RobotClient`、连接、队列、transport | 改客户端 API、命令队列、BLE/TCP/MQTT 发送逻辑 |
| `protocol/` | Python + Dart 共享二进制协议 | 改帧格式、命令 payload、CRC、stream decoder |
| `robot_server/` | 机器人端服务，接 BLE/TCP/MQTT，转 ROS1 控制与状态 | 改机器人端接入、ACK、ROS 桥、状态上报 |
| `docs/` | 设计、backlog、部署、联调文档 | 更新能力状态、部署步骤、联调流程 |
| `scripts/` | 启动、部署、smoke、同步脚本 | 改本地/真机启动流程、联调脚本 |
| `robot_skill/` | 厂商动作/行为映射与推送脚本 | 改 `do_action` / `do_dog_behavior` 资源 |
| `kws/` | 关键词唤醒训练工程 | 训练/导出自定义唤醒词模型 |
| `ui/` | UI 参考图等静态素材 | 查设计参考 |

## 根目录文件

| 文件 | 说明 |
| --- | --- |
| `AGENTS.md` | 项目级协作约束，开始跨模块任务前必须读 |
| `README.md` | 项目总览、运行入口、当前能力概览 |
| `prd.md` | 主需求来源 |
| `brd.md` | 产品背景 |
| `.env.example` | `robot_server` 环境变量模板 |
| `project_tree.md` | 当前文件，新 job 快速定位代码结构 |

## `apps/robot_app/` Flutter App

职责：面向用户的 App / 演示控制台。业务层不应绕过 `mobile_sdk.RobotClient` 直接依赖 transport。

主要目录：

```text
apps/robot_app/
├── lib/
│   ├── main.dart
│   └── src/
├── test/
├── android/
├── ios/
├── voice_control_sdk/
└── hand_gesture_sdk/
```

关键入口：

| 路径 | 说明 |
| --- | --- |
| `apps/robot_app/lib/main.dart` | App 启动入口 |
| `apps/robot_app/lib/src/home_page.dart` | 首页，连接入口、状态卡片、快捷控制、完整动作控制入口、编排入口 |
| `apps/robot_app/lib/src/control_page.dart` | 正式遥控页 UI，双摇杆 + 动作矩阵 |
| `apps/robot_app/lib/src/control_page_controller.dart` | 控制页状态与 `RobotClient` 调用 |
| `apps/robot_app/lib/src/quick_control_panel.dart` | 首页快捷动作直控 |
| `apps/robot_app/lib/src/skill_control_page.dart` | 完整动作控制页，展示状态、`do_action` 和 `do_dog_behavior` |
| `apps/robot_app/lib/src/robot_skill_catalog.dart` | 加载 App assets 中的 `robot_skill` 动作/行为资源 |
| `apps/robot_app/lib/src/action_engine.dart` | 图形化编排执行引擎 |
| `apps/robot_app/lib/src/action_models.dart` | 编排步骤模型 |
| `apps/robot_app/lib/src/action_program_view.dart` | 编排列表 UI |
| `apps/robot_app/lib/src/action_step_editor_dialog.dart` | 编排步骤编辑弹窗 |
| `apps/robot_app/lib/src/ble_scan_page.dart` | BLE 扫描页面 |
| `apps/robot_app/lib/src/ble_device_store.dart` | 最近 BLE 设备持久化 |
| `apps/robot_app/lib/src/ble_reconnect_policy.dart` | BLE 自动重连策略 |
| `apps/robot_app/lib/src/tcp_connect_dialog.dart` | TCP 连接参数弹窗 |
| `apps/robot_app/lib/src/mqtt_connect_dialog.dart` | MQTT 连接参数弹窗 |
| `apps/robot_app/lib/src/voice_action_mapper.dart` | 语音文本到控制命令映射 |
| `apps/robot_app/lib/src/voice_module_page.dart` | 语音模块页面 |
| `apps/robot_app/lib/src/gesture_module_page.dart` | 手势模块页面 |
| `apps/robot_app/assets/robot_skill/do_action/ext_actions.json` | App 打包的 `do_action` 动作资源 |
| `apps/robot_app/assets/robot_skill/do_dog_behavior/dog_behaviors.json` | App 打包的 `do_dog_behavior` 行为资源 |

控制语义：

| 场景 | 应使用 API | 说明 |
| --- | --- | --- |
| 手动控制、摇杆、快捷按钮 | `RobotClient.move/stand/sit/stop/doAction/doDogBehavior` | 默认 last-wins，只保留最后一个尚未发送命令 |
| 图形化编排 | `RobotClient.*Queued()` | FIFO，按程序顺序执行 |

测试入口：

```bash
cd apps/robot_app
flutter test
flutter analyze lib test
```

注意：

| 目录 | 说明 |
| --- | --- |
| `apps/robot_app/android/` | Flutter Android 原生工程，改权限、Gradle、Android 插件时看这里 |
| `apps/robot_app/ios/` | Flutter iOS 原生工程，改权限、Pod、Swift 插件时看这里 |
| `apps/robot_app/build/` | 生成物，不要手改 |
| `apps/robot_app/.dart_tool/` | 生成物，不要手改 |

## `apps/robot_app/voice_control_sdk/`

职责：App 内语音控制插件/SDK，基于 Sherpa ONNX 处理 `KWS + ASR + VAD`。

常见入口：

| 路径 | 说明 |
| --- | --- |
| `apps/robot_app/voice_control_sdk/lib/voice_control_sdk.dart` | 语音 SDK Dart 对外入口 |
| `apps/robot_app/voice_control_sdk/lib/src/voice_controller.dart` | 语音控制状态机 |
| `apps/robot_app/voice_control_sdk/lib/src/voice_wake_mapper.dart` | 唤醒词映射 |
| `apps/robot_app/voice_control_sdk/lib/src/voice_command_mapper.dart` | 语音命令映射 |
| `apps/robot_app/voice_control_sdk/lib/src/voice_models.dart` | 模型资产配置 |
| `apps/robot_app/voice_control_sdk/assets/voice_models/` | KWS / ASR / VAD 模型资产 |
| `apps/robot_app/voice_control_sdk/ios/Classes/` | iOS 原生语音插件实现 |

测试：

```bash
cd apps/robot_app/voice_control_sdk
flutter test
```

## `apps/robot_app/hand_gesture_sdk/`

职责：手势识别 SDK / 插件，当前属于独立子模块。

常见入口：

| 路径 | 说明 |
| --- | --- |
| `apps/robot_app/hand_gesture_sdk/lib/` | 手势 SDK Dart 代码 |
| `apps/robot_app/hand_gesture_sdk/lib/gesture_control_state.dart` | 手势 `command` / `follow` 双模式状态机 |
| `apps/robot_app/hand_gesture_sdk/test/` | 手势 SDK 测试 |
| `apps/robot_app/hand_gesture_sdk/PLAN.md` | 手势模块计划 |

注意：全量 `apps/robot_app` analyze 可能扫到该子模块的既有 info。若当前任务只改主 App，优先使用 `flutter analyze lib test`。

## `mobile_sdk/` Flutter/Dart SDK

职责：App 与传输层之间的统一 SDK。App 业务应通过 `RobotClient` 使用能力，不直接操作 transport。

主要目录：

```text
mobile_sdk/
├── lib/
│   ├── mobile_sdk.dart
│   └── src/
└── test/
```

关键入口：

| 路径 | 说明 |
| --- | --- |
| `mobile_sdk/lib/mobile_sdk.dart` | SDK 对外 export 边界 |
| `mobile_sdk/lib/src/robot_client.dart` | SDK 核心入口，连接、命令、状态、ACK 重试 |
| `mobile_sdk/lib/src/queue/command_queue.dart` | 命令队列，默认 last-wins，`*Queued` FIFO |
| `mobile_sdk/lib/src/models/connection_options.dart` | BLE/TCP/MQTT 连接配置模型 |
| `mobile_sdk/lib/src/models/connection_state.dart` | 连接状态模型 |
| `mobile_sdk/lib/src/connection/reconnect_policy.dart` | 重连策略接口 |
| `mobile_sdk/lib/src/transports/transport.dart` | transport 抽象 |
| `mobile_sdk/lib/src/transports/ble_transport.dart` | BLE transport |
| `mobile_sdk/lib/src/transports/tcp_transport.dart` | TCP transport |
| `mobile_sdk/lib/src/transports/mqtt_transport.dart` | MQTT transport |
| `mobile_sdk/lib/src/protocol/protocol_exports.dart` | Dart 协议导出 |

命令队列语义：

| API | 语义 | 使用场景 |
| --- | --- | --- |
| `move/stand/sit/stop/doAction/doDogBehavior` | last-wins，清掉尚未发送的旧命令 | 手动控制、按钮、摇杆、语音即时控制 |
| `moveQueued/standQueued/...` | FIFO，按入队顺序执行 | 图形化编程、动作编排 |
| `*Latest` | 默认 API 的显式别名 | 代码可读性需要强调实时控制时可用 |

测试：

```bash
cd mobile_sdk
flutter test
flutter analyze
```

## `protocol/` 共享二进制协议

职责：纯协议逻辑。不得依赖 Flutter、ROS、BlueZ 或 App 业务。

主要目录：

```text
protocol/
├── dart/
│   ├── lib/
│   └── test/
└── python/
    ├── robot_protocol/
    └── tests/
```

关键入口：

| 路径 | 说明 |
| --- | --- |
| `protocol/dart/lib/robot_protocol.dart` | Dart 协议包入口 |
| `protocol/dart/lib/src/codec.dart` | Dart 编解码 |
| `protocol/dart/lib/src/frame_types.dart` | 帧类型、命令 ID、枚举 |
| `protocol/dart/lib/src/models.dart` | Dart 协议模型 |
| `protocol/dart/lib/src/stream_decoder.dart` | Dart stream decoder，处理粘包/半包 |
| `protocol/dart/lib/src/crc16.dart` | Dart CRC16 |
| `protocol/python/robot_protocol/codec.py` | Python 编解码 |
| `protocol/python/robot_protocol/constants.py` | Python 常量 |
| `protocol/python/robot_protocol/models.py` | Python 协议模型 |
| `protocol/python/robot_protocol/stream_decoder.py` | Python stream decoder |
| `protocol/python/robot_protocol/crc.py` | Python CRC |

协议约束摘要：

```text
0xAA55 | Type | Seq | Len | Payload | CRC16
Type:
  0x01 CMD
  0x02 STATE
  0x03 ACK
```

测试：

```bash
PYTHONPATH=protocol/python python3 -m unittest discover -s protocol/python/tests

cd protocol/dart
dart test
```

## `robot_server/` 机器人端服务

职责：Ubuntu + ROS1 Noetic 机器人端服务，接收 BLE/TCP/MQTT 控制帧，解析协议，ACK，分发到 ROS 控制/skill，广播状态。

主要目录：

```text
robot_server/
├── robot_server/
│   ├── runtime/
│   ├── transports/
│   └── ros/
└── tests/
```

关键入口：

| 路径 | 说明 |
| --- | --- |
| `robot_server/robot_server/main.py` | Python 包主入口 |
| `robot_server/robot_server/app.py` | 根据配置构建 runtime / transports |
| `robot_server/robot_server/config.py` | 环境变量配置模型 |
| `robot_server/robot_server/models.py` | 服务端内部模型 |
| `robot_server/robot_server/runtime/robot_runtime.py` | runtime 编排，状态循环与 transport 生命周期 |
| `robot_server/robot_server/runtime/control_service.py` | CMD 解析、ACK、去重、分发 |
| `robot_server/robot_server/runtime/state_store.py` | 状态存储，`RobotState` 与扩展状态 |
| `robot_server/robot_server/transports/base.py` | transport 抽象 |
| `robot_server/robot_server/transports/ble/bluez_gatt_glib.py` | BlueZ GATT BLE 外设主实现 |
| `robot_server/robot_server/transports/ble/bluez_gatt.py` | BLE 兼容层 |
| `robot_server/robot_server/transports/tcp/server.py` | TCP server |
| `robot_server/robot_server/transports/mqtt/router.py` | MQTT topic router |
| `robot_server/robot_server/ros/bridge.py` | ROS1 运动控制桥 |
| `robot_server/robot_server/ros/skill_bridge.py` | ROS1 skill bridge |
| `robot_server/robot_server/ros/state_bridge.py` | ROS1 状态采集桥 |

运行与测试：

```bash
PYTHONPATH=protocol/python:robot_server python3 -m unittest discover -s robot_server/tests

cp .env.example .env
bash scripts/start_robot_server.sh
```

注意：

| 约束 | 说明 |
| --- | --- |
| Python 版本 | 目标运行环境是 Ubuntu 20.04 + ROS1 Noetic + Python 3.8 |
| ACK 语义 | ACK 表示命令成功进入服务端本地处理链，不表示机器狗动作执行完成 |
| 默认 transport | 默认 BLE-only，TCP/MQTT 通过环境变量开启 |
| ROS 依赖 | 真机需要 `rospy`、`geometry_msgs`、`sensor_msgs` 等 ROS 包 |

## `docs/` 文档

职责：需求、设计、部署、联调、backlog。

常见入口：

| 路径 | 说明 |
| --- | --- |
| `docs/backlog.md` | 当前状态、优先级、里程碑完成度 |
| `docs/phase0_design.md` | Phase 0 设计 |
| `docs/deploy.md` | 真机部署 |
| `docs/acceptance_checklist.md` | 验收清单 |
| `docs/ble_integration.md` | BLE 联调 |
| `docs/ble_control_data_format.md` | BLE 控制格式 |
| `docs/ros_state_integration.md` | ROS 状态采集 |
| `docs/robot_control_api.md` | 机器狗操控 API、协议、状态与 ROS 数据流说明 |
| `docs/skill_action.md` | 历史兼容入口，指向 `docs/robot_control_api.md` |
| `docs/voice_detection.md` | 语音检测说明 |
| `docs/codex_development_roadmap.md` | Codex 协作路线图 |
| `docs/cursor_opus_development_roadmap.md` | Cursor/Opus 协作路线图 |

注意：文档必须反映真实代码能力，不要把 PRD 目标状态写成已完成。

## `scripts/` 脚本

职责：启动、部署、同步、smoke、系统服务。

常见入口：

| 路径 | 说明 |
| --- | --- |
| `scripts/start_robot_server.sh` | 真机/本地启动 robot_server |
| `scripts/run_robot_server.py` | Python 运行入口 |
| `scripts/robot_server.service` | systemd 服务示例 |
| `scripts/install_robot_server_service.sh` | 安装 systemd 服务 |
| `scripts/sync_to_robot.sh` | 同步仓库到机器人 |
| `scripts/watch_and_sync_to_robot.sh` | 监听并同步 |
| `scripts/tcp_smoke.py` | TCP smoke |
| `scripts/mqtt_smoke.py` | MQTT smoke |
| `scripts/recover_bluetooth.sh` | 蓝牙恢复脚本 |
| `scripts/robot_ble_peripheral.py` | BLE 外设相关脚本 |
| `scripts/bluetooth.service.d/robot-factory.conf` | bluetooth systemd override |

## `robot_skill/`

职责：厂商动作与行为映射资源，以及推送/执行脚本。

常见入口：

| 路径 | 说明 |
| --- | --- |
| `robot_skill/do_action/ext_actions.yaml` | `do_action` 动作 ID 映射 |
| `robot_skill/do_action/ext_actions.json` | `do_action` JSON 资源 |
| `robot_skill/do_dog_behavior/dog_behaviors.yaml` | `do_dog_behavior` 行为映射 |
| `robot_skill/do_dog_behavior/dog_behaviors.json` | `do_dog_behavior` JSON 资源 |
| `robot_skill/push_ext_actions_to_server.sh` | 推送动作资源 |
| `robot_skill/run_action_on_dog.sh` | 在机器狗上执行动作 |
| `robot_skill/AlphaDog_功能清单.md` | AlphaDog 功能清单 |

## `kws/`

职责：关键词唤醒模型训练工程，不是 App 主运行路径。

主要入口：

| 路径 | 说明 |
| --- | --- |
| `kws/kws-training-project/README.md` | KWS 训练工程说明 |
| `kws/kws-training-project/configs/kws_config.yaml` | 训练配置 |
| `kws/kws-training-project/scripts/prepare_data.py` | 生成 manifest |
| `kws/kws-training-project/scripts/train_kws.py` | 训练 |
| `kws/kws-training-project/scripts/export_onnx.py` | 导出 ONNX |
| `kws/kws-training-project/scripts/run_pipeline.sh` | 一键流程 |
| `kws/kws-training-project/kws_training_project/` | KWS 训练代码 |
| `kws/kws-training-project/export/` | 导出模型 |

注意：`kws/.venv/` 是本地虚拟环境，不应纳入代码修改范围。

## `ui/`

职责：UI 参考素材。目前主要包含控制页参考图。

| 路径 | 说明 |
| --- | --- |
| `ui/control.png` | 控制页参考图 |

## 按任务快速定位

| 任务 | 优先查看 |
| --- | --- |
| 改 App 首页、连接入口、状态展示 | `apps/robot_app/lib/src/home_page.dart` |
| 改正式遥控页 | `apps/robot_app/lib/src/control_page.dart`、`apps/robot_app/lib/src/control_page_controller.dart` |
| 改手动控制连续点击逻辑 | `mobile_sdk/lib/src/robot_client.dart`、`mobile_sdk/lib/src/queue/command_queue.dart` |
| 改图形化编排顺序执行 | `apps/robot_app/lib/src/action_engine.dart`、`apps/robot_app/lib/src/action_models.dart` |
| 改 BLE 扫描/连接 App 流程 | `apps/robot_app/lib/src/ble_scan_page.dart`、`mobile_sdk/lib/src/transports/ble_transport.dart` |
| 改 TCP 连接 | `mobile_sdk/lib/src/transports/tcp_transport.dart`、`robot_server/robot_server/transports/tcp/server.py` |
| 改 MQTT 连接 | `mobile_sdk/lib/src/transports/mqtt_transport.dart`、`robot_server/robot_server/transports/mqtt/router.py` |
| 改协议字段或命令格式 | `protocol/dart/lib/src/codec.dart`、`protocol/python/robot_protocol/codec.py` |
| 改 ACK / 去重 / 服务端命令分发 | `robot_server/robot_server/runtime/control_service.py` |
| 改 ROS 运动控制 | `robot_server/robot_server/ros/bridge.py` |
| 改 ROS skill 映射 | `robot_server/robot_server/ros/skill_bridge.py`、`robot_skill/` |
| 改 ROS 状态采集 | `robot_server/robot_server/ros/state_bridge.py`、`robot_server/robot_server/runtime/state_store.py` |
| 改启动或部署 | `.env.example`、`scripts/start_robot_server.sh`、`scripts/robot_server.service`、`docs/deploy.md` |
| 改语音控制 | `apps/robot_app/lib/src/voice_action_mapper.dart`、`apps/robot_app/voice_control_sdk/` |
| 改唤醒词训练 | `kws/kws-training-project/` |

## 模块边界

| 边界 | 规则 |
| --- | --- |
| App -> SDK | App 必须通过 `RobotClient` 做连接与控制，不直接拼协议帧或操作 transport |
| SDK -> protocol | SDK 复用 `protocol/dart` 编解码，不复制协议逻辑 |
| server -> protocol | server 复用 `protocol/python` parser，不手写业务字节解析 |
| protocol | 只放纯协议，不依赖 Flutter、ROS、BlueZ |
| robot_server transport | BLE/TCP/MQTT 都应进入统一 runtime/control service |
| docs | 改行为、启动方式、环境变量、测试方式时同步更新相关 README/docs |

## 不要优先看的目录

这些目录通常是生成物、缓存或本地环境，新 job 定位问题时不要优先阅读或修改：

| 路径 | 原因 |
| --- | --- |
| `.git/` | Git 内部数据 |
| `.idea/` | IDE 配置 |
| `apps/robot_app/.dart_tool/` | Flutter 生成物 |
| `apps/robot_app/build/` | Flutter build 输出 |
| `mobile_sdk/.dart_tool/` | Flutter 生成物 |
| `mobile_sdk/build/` | Flutter build 输出 |
| `protocol/dart/.dart_tool/` | Dart 生成物 |
| `robot_server/**/__pycache__/` | Python 缓存 |
| `kws/.venv/` | 本地 Python 虚拟环境 |

## 常用验证命令

```bash
# Python protocol
PYTHONPATH=protocol/python python3 -m unittest discover -s protocol/python/tests

# robot_server
PYTHONPATH=protocol/python:robot_server python3 -m unittest discover -s robot_server/tests

# mobile_sdk
cd mobile_sdk
flutter test
flutter analyze

# robot_app
cd apps/robot_app
flutter test
flutter analyze lib test
```

## 新 job 推荐阅读顺序

1. 先读 `AGENTS.md`，确认项目约束。
2. 再读 `README.md`，了解当前整体能力。
3. 再读 `docs/backlog.md`，确认当前缺口和优先级。
4. 如果任务涉及某个模块，读对应模块 README。
5. 根据本文件的“按任务快速定位”进入源码。
