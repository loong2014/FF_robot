# robot_factory 项目约束（AGENTS.md）

本文件是 `robot_factory/` 仓库的项目级 Agent 约束。所有 AI 协作（Codex、Cursor Agent、Plan、Ask、Subagent、Background、Cloud Agent 等）在本仓库内工作时，都应默认遵守本文件，不需要每条 prompt 反复复制约束。

> 若本文件与 `prd.md`、`brd.md`、`docs/backlog.md`、路线图冲突，以需求与最新 backlog 为准；README 只作为总览和启动入口，不是最终需求来源。

---

## 1. 需求与文档来源

- 主需求：`@prd.md`
- 产品背景：`@brd.md`
- 现状盘点与优先级：`@docs/backlog.md`
- Phase 0 设计：`@docs/phase0_design.md`
- 协作路线图：
  - `@docs/codex_development_roadmap.md`
  - `@docs/cursor_opus_development_roadmap.md`
- 总览与启动入口：`@README.md`

当描述冲突时，优先级按以下顺序处理：

`prd.md` > `brd.md` > `docs/backlog.md` > 路线图文档 > `README.md` / 模块 README > 旧代码与旧注释

---

## 2. 当前项目快照

开始任何跨模块任务前，先按下面的现实状态理解仓库，不要把它当成“只有骨架”的新项目：

- `protocol`：Python / Dart 协议实现已对齐，包含帧结构、CRC16、stream decoder 与基础测试。
- `robot_server`：已实现 BLE / TCP / MQTT transport、`StateStore`、10Hz STATE 广播、ROS1 `/cmd_vel` 控制桥、ROS 状态采集桥，以及 `.env.example` 与启动脚本。
- `mobile_sdk`：`RobotClient` 已提供 `connectBLE()` / `connectTCP()` / `connectMQTT()`、命令队列、ACK 重试、连接状态、BLE 扫描、重连策略扩展点。
- `apps/robot_app`：已实现 BLE 扫描、TCP / MQTT 连接、状态面板、动作序列编辑 / 执行，定位仍偏演示控制台。

当前仍需保持诚实记录的缺口：

- `robot_server/runtime/command_queue.py` 尚未接入 `RobotRuntime`，服务端“未 ACK 阻塞重传”语义还未真正落地。
- App 侧还没有完整的设备管理、配置持久化、正式遥控 UI。
- BLE / MQTT / ROS 仍依赖真机或真实 broker 才能完成最终联调，不要把本地单测当成端到端完成。

---

## 3. 架构约束

- 保持当前 monorepo 结构，不得新增顶层目录或推翻既有布局：
  - `apps/robot_app`：Flutter 产品 App + 动作编排
  - `mobile_sdk`：Flutter / Dart SDK（`RobotClient`、transports、连接管理、命令队列）
  - `robot_server`：Ubuntu + ROS1 Noetic 机器人端（BLE / TCP / MQTT / ROS）
  - `protocol`：Python + Dart 共享协议
  - `docs`：设计、backlog、联调与部署文档
  - `scripts`：启动脚本与 smoke 工具
- 增量修改，优先复用已有 stub、接口与抽象，不得顺手重构与当前任务无关的模块。
- 模块边界：
  - App 不得绕过 `mobile_sdk.RobotClient` 直接依赖 transport 实现做业务流程。
  - `robot_server` 各 transport 必须走统一 protocol parser、`StateStore` 和 runtime 编排。
  - `protocol` 只放纯协议逻辑，不依赖 ROS / Flutter / BlueZ。
- 文档必须反映真实代码能力，不得把 PRD 目标状态直接写成“已实现”。

---

## 4. 环境约束

### 机器人端

- 目标运行环境：Ubuntu 20.04 + ROS1 Noetic + Python 3.8。
- 禁止引入 Python 3.9+ 专属语法作为运行时前提：
  - 运行时使用的 `X | Y`
  - `list[int]` / `dict[str, Any]` 等 PEP 585 运行时泛型
  - `match`
  - `typing.Self`、`typing.ParamSpec`
- 允许依赖：`paho-mqtt`、`dbus-next` / `dbus-fast`、`dbus-python + gi`、`rospy`。
- 新增依赖必须说明原因、目标场景与版本。

### Flutter / Dart 端

- 与现有 `mobile_sdk/pubspec.yaml`、`apps/robot_app/pubspec.yaml` 保持兼容，不主动升 Dart SDK 主版本。
- SDK 不得硬编码 UI、页面跳转、Navigator 逻辑。
- 若新增 BLE / MQTT 插件或变更插件版本，需同步说明选型原因和平台约束。

---

## 5. 协议约束

- `control` / `state` 走二进制协议，帧格式固定为：

  `0xAA55 | Type | Seq | Len | Payload | CRC16`

- `Type`：
  - `0x01` CMD
  - `0x02` STATE
  - `0x03` ACK
- `CMD` payload：
  - MOVE：`cmd_id=0x01`，`vx/vy/yaw` 为 `int16`，实际值乘以 `100`
  - DISCRETE：`0x10 stand` / `0x11 sit` / `0x12 stop`
- `STATE` payload：`battery | roll(int16) | pitch(int16) | yaw(int16)`
- `ACK` payload：`seq`
- 所有实现都必须支持粘包、CRC 校验和 stream decoder。
- MQTT topic 必须遵循：
  - `robot/{id}/control`（binary）
  - `robot/{id}/state`（binary）
  - `robot/{id}/event`（JSON）
- 命令队列语义不允许私自改变：
  - `move` 仅保留最新
  - `discrete` FIFO
  - 未 ACK 阻塞重传（3 次，100ms 超时）
- 状态推送默认 10Hz。

---

## 6. 工作方式约束

1. 任何跨模块任务先做计划，再执行代码或文档修改；如果所在环境没有 Plan 模式，用等价计划工具或显式计划步骤替代。
2. 开始前先读 `README.md`、`docs/backlog.md`、相关模块 README 和对应源码入口，不要先拍脑袋下结论。
3. 大范围扫描优先并行探索，再集中实现；如果平台支持 subagent/explorer，可用于信息收集，但不要把阻塞主线的关键修改完全外包。
4. 引用优先使用仓库相对路径或 `@路径`，不要把绝对路径当成主要沟通方式。
5. 修改行为、启动方式、环境变量、测试方式时，要同步更新：
   - 根 `README.md`
   - 受影响模块的 `README.md`
   - 必要时更新 `docs/*.md`
6. 不要只看文档或只看代码的一侧；README / AGENTS / backlog 要互相收口，避免过期信息长期并存。
7. 长耗时任务（真机日志、全仓迁移、全量回归）优先后台化；但当前轮次的关键结论必须可复现、可落地。

---

## 7. 每次任务完成标准

无论任务大小，结束前都应尽量满足：

1. 直接修改真实文件，除非任务明确是“只分析 / 只出方案”。
2. 运行与本次改动直接相关的测试：
   - Python：
     - `PYTHONPATH=protocol/python python3 -m unittest discover -s protocol/python/tests`
     - `PYTHONPATH=protocol/python:robot_server python3 -m unittest discover -s robot_server/tests`
   - Dart / Flutter：
     - `cd mobile_sdk && flutter test`
     - `cd apps/robot_app && flutter test`
3. 对改动文件做 lint / 静态检查；如果当前环境没有 `ReadLints`，使用等价能力并在汇报中说明。
4. 汇报至少包含：
   - 修改 / 新增 / 删除文件
   - 测试结果（通过 / 失败 / 未跑）
   - 剩余风险和未覆盖点
   - 推荐下一步
5. 若属于里程碑级任务，要同步回写 `docs/backlog.md`。

---

## 8. 禁止事项

- 不得修改 `prd.md`、`brd.md`、路线图文档，除非任务明确要求更新它们。
- 不得绕过命令队列 / 协议层直接拼字节做业务逻辑。
- 不得硬编码设备 ID、broker 地址、用户名、密码、证书路径等运行环境信息；全部走配置文件或环境变量。
- 不得在 SDK 层引入难以测试的全局单例。
- 不得为了“顺手清理”重构与当前任务无关的目录、命名或架构。
- 不得把尚未联调或尚未测试的能力写成“已完成”。
