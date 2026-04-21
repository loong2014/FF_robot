# Codex 开发路线图与 Prompt 清单

本文用于指导基于当前 `robot_factory/` 架构，通过 Codex 分步完成机器狗控制系统开发。

约束原则：

- 以 `/Users/xinzhang/gitProject/robot/prd.md` 为主
- 以 `/Users/xinzhang/gitProject/robot/brd.md` 为辅
- 采用当前 monorepo 架构增量开发，不推翻已有目录结构
- 每次只让 Codex 完成一个明确阶段，避免一条 prompt 覆盖过多子系统

## 1. 当前项目结构

```text
robot_factory/
├── apps/robot_app
├── docs
├── mobile_sdk
├── protocol
└── robot_server
```

模块职责：

- `protocol`：统一二进制协议、CRC、流式解包
- `robot_server`：机器人端服务，接 BLE / TCP / MQTT / ROS1
- `mobile_sdk`：Flutter 侧统一 SDK
- `apps/robot_app`：产品级 App 与动作编排模块

## 2. 建议的 Codex 协作方式

推荐采用以下节奏：

1. 每次只做一个里程碑，例如“BLE 机器人端”或“SDK 连接管理”。
2. 每次 prompt 都明确：
   - 读取 `prd.md` 与 `brd.md`
   - 以 `prd.md` 为主
   - 只能增量修改当前仓库
   - 完成后必须运行相关测试
3. 优先让 Codex 修改真实代码，而不是只做分析。
4. 涉及跨端能力时，拆成“机器人端 -> SDK -> App”三步推进。
5. 每一步完成后，都先做本地验证，再进入下一步。

## 3. 每一步都建议带上的通用约束

下面这段可以作为每个任务 prompt 的固定前缀：

```text
请基于当前仓库 /Users/xinzhang/gitProject/robot/robot_factory 增量开发，不要重建项目结构。

先阅读：
- /Users/xinzhang/gitProject/robot/prd.md
- /Users/xinzhang/gitProject/robot/brd.md

以 prd.md 为主，brd.md 为辅。

约束：
- 保持当前 monorepo 架构
- 优先复用已有 protocol / robot_server / mobile_sdk / robot_app 代码
- 不要顺手重构无关模块
- 如需调整接口，请同步更新文档和测试
- 完成后请直接实现代码、运行相关测试，并汇报修改文件、测试结果、剩余风险
```

## 4. 推荐开发顺序

### Step 1. 现状盘点与 backlog

目标：

- 盘点当前代码相对 `prd.md` / `brd.md` 的完成度
- 生成清晰的 backlog
- 标记哪些是 stub，哪些可直接联调

建议 prompt：

```text
请基于当前仓库 /Users/xinzhang/gitProject/robot/robot_factory 进行分析，不要写代码。

先阅读：
- /Users/xinzhang/gitProject/robot/prd.md
- /Users/xinzhang/gitProject/robot/brd.md

以 prd.md 为主，brd.md 为辅。

任务：
1. 盘点当前代码已经实现了哪些需求，哪些还是 stub / 框架 / 占位。
2. 输出一个按优先级排序的开发 backlog。
3. 标记哪些任务属于 robot_server，哪些属于 mobile_sdk，哪些属于 robot_app。
4. 标记哪些任务会影响 ROS1 Noetic 部署。
5. 不要写代码，只输出分析和分步计划。
```

### Step 2. ROS1 Noetic / Python 3.8 兼容

目标：

- 让机器人端真正适配 Ubuntu 20.04 + ROS1 Noetic
- 修正 Python 3.11 专属写法
- 为后续真机部署扫清环境障碍

建议 prompt：

```text
请基于当前仓库 /Users/xinzhang/gitProject/robot/robot_factory 做增量修改，不要改动 monorepo 结构。

先阅读：
- /Users/xinzhang/gitProject/robot/prd.md
- /Users/xinzhang/gitProject/robot/brd.md

背景：
- 以 prd.md 为主，brd.md 为辅
- 机器人端目标环境是 Ubuntu 20.04 + ROS1 Noetic
- 当前 robot_server 需要兼容 Python 3.8

任务：
1. 检查 protocol/python 和 robot_server 中所有 Python 代码。
2. 将不兼容 Python 3.8 的写法改为兼容写法，但不要改变现有业务逻辑。
3. 更新 pyproject 和 README 中的运行环境说明。
4. 保持 BLE / TCP / MQTT / ROS 的现有架构不变。

完成后请执行并汇报：
- PYTHONPATH=protocol/python python3 -m unittest discover -s protocol/python/tests
- PYTHONPATH=protocol/python:robot_server python3 -m unittest discover -s robot_server/tests
```

### Step 3. BLE 机器人端

目标：

- 完成 `robot_server` 的 BLE 服务端核心能力
- 对齐 `prd.md` 中 BLE 为核心实现的要求

建议 prompt：

```text
请基于当前仓库 /Users/xinzhang/gitProject/robot/robot_factory 继续开发 BLE 机器人端，保持现有架构，不要推翻已有目录设计。

先阅读：
- /Users/xinzhang/gitProject/robot/prd.md
- /Users/xinzhang/gitProject/robot/brd.md
- robot_server 现有代码
- protocol 现有代码

目标：
1. 在 robot_server 中完成 BLE 机器人端实现。
2. 完成 BlueZ GATT Server 与 RobotControlService 对接。
3. 实现 cmd_char(write without response) 与 state_char(notify)。
4. 结合协议层处理 MTU、粘包、stream decoder。
5. 确保 ACK + 重传逻辑与协议层协同工作。
6. 保持 10Hz 状态推送。
7. 保持 Python 3.8 / ROS1 Noetic 兼容。

约束：
- 以 prd.md 为主，brd.md 为辅
- 优先复用现有 robot_server/transports/ble 和 protocol 代码
- 不要改坏 TCP / MQTT 结构

完成后：
1. 增加必要测试或最小可验证逻辑
2. 更新 README 或 docs，说明 BLE 的运行依赖与启动方式
3. 汇报修改文件、测试结果和剩余风险
```

### Step 4. BLE Flutter SDK

目标：

- 完成 `mobile_sdk` 中 BLE 传输层
- 让 `RobotClient.connectBLE()` 真正可用

建议 prompt：

```text
请基于当前仓库 /Users/xinzhang/gitProject/robot/robot_factory 开发 mobile_sdk 的 BLE 能力。

背景：
- 以 prd.md 为主，brd.md 为辅
- 当前 mobile_sdk 已有 RobotClient、Transport 抽象和 BLE 占位实现
- 目标是完成 SDK 层 BLE，不要同时大改 App UI

任务：
1. 选择合适的 Flutter BLE 插件并接入 mobile_sdk/pubspec.yaml。
2. 在 mobile_sdk/lib/src/transports/ble_transport.dart 中完成 BLE 传输实现。
3. 基于当前协议层实现：
   - 写 cmd_char
   - 订阅 state_char notify
   - 二进制帧收发
   - MTU 分片发送
   - stream decoder 解包
4. 接入 RobotClient，使 connectBLE()/stateStream/move()/stand()/sit()/stop() 可用。
5. 保持 TCP / MQTT 接口不被破坏。

完成后：
- 运行 mobile_sdk 相关测试
- 如果需要，补充新的单测
- 汇报插件选择原因、修改文件、验证方式
```

### Step 5. BLE App 集成与设备管理

目标：

- 落 `brd.md` 中的设备搜索、绑定、连接状态管理
- 完成 App 侧 BLE 接入

建议 prompt：

```text
请基于当前仓库 /Users/xinzhang/gitProject/robot/robot_factory 开发 robot_app 的 BLE 集成和设备管理能力。

要求：
- 以 prd.md 为主，brd.md 为辅

目标：
1. 在 apps/robot_app 中加入 BLE 设备搜索、连接、连接状态展示。
2. 接入 mobile_sdk 的 BLE 能力。
3. 展示当前连接方式、连接状态、绑定中的设备。
4. 保持现有动作引擎页面结构，可以在现有首页基础上扩展。
5. UI 不要只做调试页，要兼顾产品化和移动端可用性。

说明：
- “设备绑定”先实现为 App 内设备记录与连接目标管理，不要求一开始就做账号体系
- 设备状态至少包括：是否连接、当前连接方式、最近状态时间

完成后：
- 运行 flutter test
- 汇报新增交互、状态流、UI 修改和遗留问题
```

### Step 6. SDK 统一连接管理

目标：

- 实现 `BLE > TCP > MQTT` 的基础优先级
- 给 App 提供清晰的连接状态模型与切换能力

建议 prompt：

```text
请基于当前仓库 /Users/xinzhang/gitProject/robot/robot_factory 开发 mobile_sdk 的统一连接管理能力。

背景：
- 以 prd.md 为主，brd.md 为辅
- BRD 要求支持动态切换连接方式，并具备 BLE > TCP > MQTT 的优先级
- 当前 RobotClient 只有 connectBLE/connectTCP/connectMQTT 的基础接口

任务：
1. 为 mobile_sdk 增加统一连接状态模型。
2. 增加当前传输方式标识和连接状态流。
3. 增加按优先级自动尝试连接的能力。
4. 支持从 BLE 切换到 TCP 或 MQTT 的基础流程。
5. 不要求一次实现复杂的自动重连策略，但要把架构设计清楚并落成第一版代码。
6. 保持 RobotClient API 清晰，对 App 友好。

完成后：
- 增加或更新单测
- 说明连接状态模型、切换策略和后续扩展点
```

### Step 7. TCP 全链路

目标：

- 完善局域网 / USB 网络控制路径
- 保持与 BLE 一致的上层行为

建议 prompt：

```text
请基于当前仓库 /Users/xinzhang/gitProject/robot/robot_factory 开发 TCP 全链路能力。

目标：
1. 完善 robot_server 的 TCP socket server。
2. 确认接入统一 protocol parser 和 stream decoder。
3. 完善 mobile_sdk 的 TCP transport。
4. 在 robot_app 中接入 TCP 连接入口和状态展示。
5. 保持命令队列、ACK、状态流与 BLE 路径一致。

约束：
- 以 prd.md 为主
- 不做 BLE 级别的过度优化
- 保持现有协议格式不变，除非确有必要

完成后：
- 运行 Python 单测与 Flutter 测试
- 如有必要，补充 TCP 端到端最小验证
```

### Step 8. MQTT 全链路

目标：

- 完成远程控制框架与 Topic Router
- 对齐 `prd.md` 中的 topic 与分发要求

建议 prompt：

```text
请基于当前仓库 /Users/xinzhang/gitProject/robot/robot_factory 开发 MQTT 全链路能力。

目标：
1. 完善 robot_server 中的 MQTT Router。
2. 严格按照 prd.md 的 topic：
   - robot/{id}/control
   - robot/{id}/state
   - robot/{id}/event
3. control/state 走 binary protocol。
4. event 走 JSON。
5. 在 mobile_sdk 中接入 MQTT transport。
6. 在 robot_app 中接入 MQTT 连接入口和状态展示。

约束：
- 以 prd.md 为主，brd.md 为辅
- 优先保证架构清晰和可扩展
- 不要把云端鉴权做成硬依赖，先保留接口和配置能力

完成后：
- 汇报 topic 设计、router 逻辑、客户端接入方式和测试结果
```

### Step 9. ROS 状态上报完善

目标：

- 补齐状态采集链路
- 让 App 看到真实设备状态，而不仅是占位状态

建议 prompt：

```text
请基于当前仓库 /Users/xinzhang/gitProject/robot/robot_factory 完善 ROS1 集成，重点补状态上报。

目标：
1. 保持 /cmd_vel 的 10Hz 控制同步。
2. 增加机器人状态采集路径，把电量、姿态等状态写入 StateStore。
3. 通过统一协议把状态推送到 BLE / TCP / MQTT。
4. 如果真实硬件 topic 名称未知，请把状态 topic 做成可配置，并提供默认值。
5. 文档中明确说明哪些部分是真机环境相关配置。

约束：
- ROS1 Noetic
- 兼容 Python 3.8
- 不要写死只适配某一台机器狗的 topic

完成后：
- 更新 docs 或 README
- 汇报状态来源、配置项和验证方式
```

### Step 10. 动作编排模块

目标：

- 完善 App 内动作编排
- 提升到可用于产品演示的程度

建议 prompt：

```text
请基于当前仓库 /Users/xinzhang/gitProject/robot/robot_factory 完善 App 内动作编排功能。

目标：
1. 基于现有 action_engine 继续开发，不要重写架构。
2. 支持动作序列编辑、执行、暂停、恢复、停止。
3. 支持 move/stand/sit/stop 的顺序执行。
4. 给每个动作提供执行状态和失败反馈。
5. 调用 mobile_sdk 的 RobotClient，不绕过 SDK 直接写传输代码。
6. 页面交互要适合移动端，不只是演示按钮。

完成后：
- 运行 flutter test
- 汇报动作状态机设计、UI 改动和后续可扩展项
```

### Step 11. 部署与验收

目标：

- 让机器人端可以被真正部署
- 形成联调与验收闭环

建议 prompt：

```text
请基于当前仓库 /Users/xinzhang/gitProject/robot/robot_factory 补齐部署和验收能力。

目标：
1. 为 robot_server 提供面向 Ubuntu 20.04 / ROS1 Noetic 的部署说明。
2. 增加启动脚本或 systemd service 示例。
3. 增加环境变量示例文件。
4. 梳理 BLE / TCP / MQTT / ROS 的启动依赖。
5. 给出端到端联调步骤：手机端、机器狗端、网络侧分别怎么验证。

约束：
- 不要引入和当前项目无关的复杂 DevOps 体系
- 保持文档可直接给开发或测试同学使用

完成后：
- 输出部署文档路径
- 输出建议的验收 checklist
```

## 5. BLE / SDK / TCP / MQTT 的典型拆分方式

如果需求较大，建议用下面的粒度交给 Codex：

- BLE：
  - BLE 机器人端
  - BLE SDK
  - BLE App 集成
- SDK：
  - 连接状态模型
  - 传输选择与切换
  - 命令队列与失败恢复
- TCP：
  - robot_server TCP
  - mobile_sdk TCP
  - robot_app TCP 接入
- MQTT：
  - robot_server Router
  - mobile_sdk MQTT
  - robot_app MQTT 状态展示

这种拆分方式最适合 Codex，因为每一轮的上下文清晰，验证边界也明确。

## 6. 通用 prompt 模板

当你要新增某个功能时，可以直接替换下面模板中的 `<功能名>`：

```text
请基于当前仓库 /Users/xinzhang/gitProject/robot/robot_factory 增量开发，不要重建项目结构。

先阅读：
- /Users/xinzhang/gitProject/robot/prd.md
- /Users/xinzhang/gitProject/robot/brd.md

以 prd.md 为主，brd.md 为辅。

本次只完成：<功能名>

目标：
1. ...
2. ...
3. ...

修改范围：
- ...
- ...

约束：
- 保持现有 monorepo 架构
- 优先复用已有 protocol / robot_server / mobile_sdk / robot_app 代码
- 如需调整接口，同时更新文档和测试
- 不要顺手改无关模块

完成后请：
1. 直接实现代码
2. 运行相关测试
3. 汇报修改文件、测试结果、遗留风险
```

## 7. 推荐先执行的下一条 prompt

如果从当前项目状态继续推进，建议第一条执行：

```text
请基于当前仓库 /Users/xinzhang/gitProject/robot/robot_factory 做增量修改，不要改动 monorepo 结构。

先阅读：
- /Users/xinzhang/gitProject/robot/prd.md
- /Users/xinzhang/gitProject/robot/brd.md

背景：
- 以 prd.md 为主，brd.md 为辅
- 机器人端目标环境是 Ubuntu 20.04 + ROS1 Noetic
- 当前 robot_server 需要兼容 Python 3.8

任务：
1. 检查 protocol/python 和 robot_server 中所有 Python 代码。
2. 将不兼容 Python 3.8 的写法改为兼容写法，但不要改变现有业务逻辑。
3. 更新 pyproject 和 README 中的运行环境说明。
4. 保持 BLE / TCP / MQTT / ROS 的现有架构不变。

完成后请执行并汇报：
- PYTHONPATH=protocol/python python3 -m unittest discover -s protocol/python/tests
- PYTHONPATH=protocol/python:robot_server python3 -m unittest discover -s robot_server/tests
```

