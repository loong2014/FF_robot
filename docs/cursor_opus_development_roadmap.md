# Cursor + Opus 4.7 AI 整体开发路线图

本文用于指导基于 `robot_factory/` 当前架构，在 **Cursor IDE + Claude Opus 4.7** 下由 AI 作为主力完成机器狗控制系统开发。

与 Codex 版路线图的核心差异：

- Opus 4.7 上下文窗口大、长程推理强、工具调用稳定，可以**一次吃下一个完整里程碑**而不是只做一小步。
- Cursor 提供 Agent / Plan / Ask 三种模式、@ 引用、Rules、Todo、并行 Subagent、Linter 反馈、MCP 工具等能力，应该被充分利用。
- 项目级约束建议沉淀到 `AGENTS.md` 或 `.cursor/rules/`，避免每条 prompt 重复复制粘贴长长的前缀。

约束原则（不变）：

- 以 `/Users/xinzhang/gitProject/robot/prd.md` 为主
- 以 `/Users/xinzhang/gitProject/robot/brd.md` 为辅
- 采用当前 monorepo 架构增量开发，不推翻已有目录结构
- AI 必须直接修改真实代码、运行测试、并自检 linter

---

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

---

## 2. Cursor + Opus 4.7 协作方式

推荐工作节奏：

1. **先用 Plan 模式讨论**：任何跨模块的里程碑（如 BLE 端到端、连接管理）都先让 Opus 4.7 进入 Plan 模式产出方案，确认后切到 Agent 执行。
2. **一次吃一个完整里程碑**：Opus 4.7 可以在一轮里同时完成机器人端 + SDK + App 的闭环，不必再拆成三条 prompt。
3. **用 TodoWrite 固化执行计划**：要求 AI 一开始就列 todo，并按 todo 推进，避免跑偏。
4. **并行 Subagent 做信息搜集**：在一轮任务里用 `explore` subagent 并行扫 `protocol/` 与 `robot_server/` 与 `mobile_sdk/`，再汇总到主线执行。
5. **每轮结束必做三件事**：运行相关测试 / 跑 `ReadLints` / 汇报剩余风险。
6. **充分用 @ 引用**：`@docs/prd.md`、`@robot_server/transports/ble/`、`@mobile_sdk/lib/src/transports/` 比绝对路径更符合 Cursor 习惯。
7. **大改动前开 Cloud Agent 或 Background**：耗时迁移、全仓 Python 3.8 适配等，适合放到后台执行。

---

## 3. 将通用约束沉淀为 Rules（一次配置，全局生效）

在仓库根目录创建 `AGENTS.md` 或 `.cursor/rules/robot_factory.mdc`，把以下内容写入，后续所有 prompt 就不需要再重复前缀：

```markdown
# robot_factory 项目约束

## 需求来源
- 以 `/Users/xinzhang/gitProject/robot/prd.md` 为主
- 以 `/Users/xinzhang/gitProject/robot/brd.md` 为辅

## 架构约束
- 保持当前 monorepo 结构：apps/robot_app, mobile_sdk, robot_server, protocol
- 增量修改，禁止推翻已有目录
- 优先复用 protocol / robot_server / mobile_sdk / robot_app 已有代码
- 不得顺手重构与当前任务无关的模块

## 环境约束
- 机器人端：Ubuntu 20.04 + ROS1 Noetic + Python 3.8
- 不得引入 Python 3.9+ 专属语法（如 `X | Y` 类型、`list[int]` 直接使用等）
- Flutter 侧保持与现有 pubspec 兼容

## 协议约束
- control / state 走二进制协议（带 CRC、MTU 分片、stream decoder）
- event 走 JSON
- MQTT topic 严格遵循：robot/{id}/control、robot/{id}/state、robot/{id}/event

## 每次任务完成标准
1. 直接修改真实代码，不只做分析（除非任务明确是"只分析"）
2. 运行相关测试（Python 单测、flutter test）
3. 运行 ReadLints 自检并修复新引入的 lint
4. 汇报：修改文件清单、测试结果、剩余风险、可选下一步
```

这样每条 prompt 只需描述本次目标，不再重复冗长前缀。

---

## 4. 推荐开发顺序（里程碑粒度已按 Opus 4.7 能力放大）

### Milestone 0. 现状盘点与 backlog（Ask / Plan 模式）

目标：基于 prd/brd 盘点当前完成度，输出优先级 backlog。

建议在 **Ask 模式** 或 **Plan 模式** 下执行：

```text
阅读 @docs/prd.md @docs/brd.md 以及 @robot_factory 全部代码，盘点：

1. 当前代码相对 prd.md / brd.md 的完成度，哪些是可联调的，哪些是 stub。
2. 输出按优先级排序的 backlog，并标注所属模块（robot_server / mobile_sdk / robot_app / protocol）。
3. 标注哪些工作会影响 ROS1 Noetic 真机部署。
4. 只输出分析与计划，不改代码。

请先用 explore subagent 并行扫描四个模块，然后汇总。
```

产出建议写入 `docs/backlog.md`，作为后续里程碑的依据。

---

### Milestone 1. 环境与基座对齐（Python 3.8 / ROS1 Noetic）

目标：

- 让 `protocol/python` 与 `robot_server` 完全兼容 Python 3.8
- 统一依赖与 README 运行说明
- 扫清真机部署的环境障碍

建议 prompt（Agent 模式）：

```text
目标：让 protocol/python 和 robot_server 全量兼容 Python 3.8 + ROS1 Noetic。

执行要求：
1. 先用 TodoWrite 列出本次任务清单。
2. 用 explore subagent 并行扫 @protocol/python 与 @robot_server，找出所有 3.9+ 专属写法
   （`X | Y` 类型、`list[int]` / `dict[str, Any]` 在注解外的使用、
   `match` 语句、`Self` 类型、`:=` 在不支持位置等）。
3. 改为 3.8 兼容写法，保持业务逻辑不变。
4. 更新 pyproject / README 中的运行环境说明。

完成后：
- 跑 `PYTHONPATH=protocol/python python3 -m unittest discover -s protocol/python/tests`
- 跑 `PYTHONPATH=protocol/python:robot_server python3 -m unittest discover -s robot_server/tests`
- 对改动文件跑 ReadLints
- 汇报改动清单、测试结果、剩余风险
```

---

### Milestone 2. BLE 端到端闭环（机器人端 + SDK + App 一轮完成）

Codex 版拆成 3 步；Opus 4.7 可以一次性完成，但建议**先 Plan 再 Agent**。

#### 2.1 Plan 模式：设计评审

```text
进入 Plan 模式。基于 @docs/prd.md @docs/brd.md 和当前 @robot_server @mobile_sdk @apps/robot_app，
为 BLE 端到端闭环输出实施方案：

1. robot_server 侧：BlueZ GATT Server、cmd_char (write w/o response)、state_char (notify)、
   MTU 协商、stream decoder、ACK/重传、10Hz 状态推送。
2. mobile_sdk 侧：选定 Flutter BLE 插件、BleTransport 实现、MTU 分片、解包、
   对接 RobotClient 的 connectBLE / stateStream / move / stand / sit / stop。
3. robot_app 侧：设备搜索、绑定、连接状态展示、连接方式指示。
4. 明确 Python 3.8 / ROS1 Noetic 兼容点。
5. 指出与现有 TCP / MQTT 架构的交叉点，保证不破坏其他路径。

产出：实施方案 + 风险项 + 分阶段验证计划。不写代码。
```

#### 2.2 Agent 模式：实施

```text
基于刚才确认的 BLE 方案，实施端到端闭环：

范围：
- @robot_server/transports/ble/
- @protocol/（如需）
- @mobile_sdk/lib/src/transports/ble_transport.dart 及相关
- @apps/robot_app/（BLE 设备搜索、连接状态、绑定）

要求：
1. 用 TodoWrite 明确每个子任务，分段推进。
2. 优先复用已有 stub 与抽象，保持 TCP/MQTT 代码不受破坏。
3. Flutter BLE 插件需在 pubspec 中引入，说明选型理由。
4. 设备绑定先做 App 内设备记录，不引入账号体系。

完成后：
- 跑 Python 单测（BLE 相关）
- 跑 `flutter test`（mobile_sdk + robot_app）
- 对改动文件跑 ReadLints
- 更新 @docs（BLE 启动依赖、联调步骤）
- 汇报：文件清单 / 测试结果 / 剩余风险 / 下一步
```

> 若改动量过大，可把 robot_server BLE 单独拆为一个前置子任务，再做 SDK+App。

---

### Milestone 3. SDK 统一连接管理（BLE > TCP > MQTT）

目标：实现传输优先级、统一连接状态模型、动态切换能力。

```text
在 @mobile_sdk 中实现统一连接管理：

1. 新增统一连接状态模型：
   - 当前传输类型、连接状态、最近状态时间、错误码。
2. 提供连接状态 Stream，供 App 订阅。
3. 按 BLE > TCP > MQTT 优先级自动尝试连接。
4. 支持显式切换传输方式（不丢失命令队列）。
5. 不要求复杂自动重连，但需预留扩展点（重连策略接口）。
6. 保持 RobotClient API 对 App 友好、向后兼容。

完成后：
- 补充或更新 mobile_sdk 单测（优先级选择、切换、状态流）。
- 对改动文件跑 ReadLints。
- 汇报状态模型、切换策略和后续扩展点（重连 / 心跳 / QoS）。
```

---

### Milestone 4. TCP 全链路

目标：robot_server TCP server + mobile_sdk TCP transport + robot_app TCP 接入，行为与 BLE 对齐。

```text
打通 TCP 全链路：

1. 完善 @robot_server 的 TCP socket server，接入统一 protocol parser 与 stream decoder。
2. 完善 @mobile_sdk/lib/src/transports/tcp_transport.dart，复用 Milestone 3 的连接状态模型。
3. 在 @apps/robot_app 中加入 TCP 连接入口（IP / 端口）与状态展示。
4. 保持命令队列、ACK、状态流与 BLE 路径一致。

约束：
- 不做 BLE 级别过度优化。
- 保持协议格式不变。

完成后：
- 跑 Python 单测与 flutter test。
- 补充 TCP 端到端最小验证脚本（可选）。
- 跑 ReadLints、汇报风险。
```

---

### Milestone 5. MQTT 全链路

目标：Topic Router、二进制控制、JSON 事件、App 接入。

```text
打通 MQTT 全链路：

1. 完善 @robot_server 的 MQTT Router，严格遵循：
   - robot/{id}/control（binary）
   - robot/{id}/state（binary）
   - robot/{id}/event（JSON）
2. 在 @mobile_sdk 中接入 MQTT transport，复用连接状态模型。
3. 在 @apps/robot_app 中加入 MQTT 入口（Broker / 凭证 / clientId）与状态展示。
4. 云端鉴权不做硬依赖，保留接口与配置。

完成后：
- 汇报 topic 设计、router 逻辑、客户端接入方式、测试结果。
- 跑 ReadLints。
```

---

### Milestone 6. ROS 状态采集与上报完善

目标：把真实设备状态打到 StateStore，三条传输路径都能看到。

```text
完善 ROS1 集成，重点在状态上报：

1. 保持 /cmd_vel 10Hz 控制同步。
2. 新增机器人状态采集（电量、姿态、故障码等），写入 StateStore。
3. 通过统一协议推送到 BLE / TCP / MQTT。
4. 状态 topic 名称做成可配置，提供默认值，避免写死。
5. 在 @docs 中明确哪些部分是真机配置相关。

约束：ROS1 Noetic + Python 3.8。

完成后：
- 更新 docs / README。
- 跑 ReadLints。
- 汇报状态来源、配置项、验证方式。
```

---

### Milestone 7. 动作编排模块产品化

目标：App 内动作编排达到可演示状态。

```text
基于 @apps/robot_app 的 action_engine 继续开发，不重写架构：

1. 动作序列编辑 / 执行 / 暂停 / 恢复 / 停止。
2. move / stand / sit / stop 顺序执行与组合。
3. 每个动作的执行状态、失败反馈、重试策略。
4. 所有动作经过 mobile_sdk.RobotClient，不绕过 SDK。
5. 移动端交互：手势、列表、拖拽排序，避免只做调试按钮。

完成后：
- 跑 flutter test。
- 汇报动作状态机设计、UI 改动、后续扩展项（时间轴 / 条件触发 / 场景化）。
```

---

### Milestone 8. 部署与验收

目标：机器人端能被真正部署，形成联调/验收闭环。

```text
补齐部署与验收能力：

1. 给 @robot_server 提供 Ubuntu 20.04 / ROS1 Noetic 部署说明。
2. 提供启动脚本或 systemd service 示例。
3. 提供 `.env.example` 等环境变量示例。
4. 梳理 BLE / TCP / MQTT / ROS 各自的启动依赖。
5. 输出端到端联调步骤：手机端 / 机器狗端 / 网络侧分别如何验证。
6. 输出验收 checklist。

约束：不要引入与项目无关的复杂 DevOps 体系，文档要能直接交给测试同学使用。

完成后：
- 输出部署文档路径。
- 输出验收 checklist 路径。
```

---

## 5. Plan vs Agent vs Ask：什么时候用哪个

| 场景 | 模式 | 说明 |
| --- | --- | --- |
| 需求理解、backlog、架构评估 | **Ask** 或 **Plan** | 只读，不会误改代码 |
| 跨模块里程碑（BLE 端到端、连接管理、MQTT） | **Plan → Agent** | 先定方案再实施 |
| 单模块明确任务（TCP 接入、单测补齐） | **Agent** | 直接改 |
| 全仓扫描（Python 3.8 兼容、命名一致性） | **Agent + explore subagent** | 主 agent 指挥，subagent 并行探索 |
| 长耗时任务（真机日志分析、回归跑测） | **Background / Cloud Agent** | 异步推进 |

---

## 6. Opus 4.7 专属能力利用建议

1. **并行工具调用**：Opus 4.7 支持一次调用多个独立工具，应在 prompt 中显式允许，例如"可并行读取多个文件"。
2. **Subagent 并行探索**：`Task(subagent_type="explore")` 启动只读探索代理，适合扫 protocol / robot_server / mobile_sdk / apps 四处代码。
3. **TodoWrite 驱动**：要求 AI 开头就列 Todo，便于中途恢复与复盘。
4. **Linter 闭环**：每次改完调用 `ReadLints` 自检，不要把 lint 留给下一轮。
5. **MCP 利用**：如接入 `cursor-ide-browser`，可让 AI 直接调试 Flutter Web 版或查 BLE 文档。
6. **长上下文**：允许一次性把 `prd.md` + `brd.md` + 相关目录全部挂进上下文，避免片段化阅读。
7. **自检**：要求每个里程碑结束时，AI 主动回读自己改的文件，检查是否有 TODO / FIXME / 未覆盖分支。

---

## 7. 通用 prompt 模板（搭配 AGENTS.md 使用）

当 `AGENTS.md` 已经沉淀了项目约束后，本模板可极致精简：

```text
本轮目标：<一句话里程碑名>

范围：
- @<目录1>
- @<目录2>

必须：
1. 用 TodoWrite 先列执行计划
2. 必要时并行 explore subagent 扫描相关代码
3. 实施代码（不是只分析）
4. 跑相关测试 + ReadLints
5. 汇报文件清单 / 测试结果 / 剩余风险 / 推荐下一步

可选增强：
- <例如：同步更新 docs/xxx.md>
- <例如：补最小端到端验证脚本>
```

---

## 8. 推荐先执行的下一条 prompt

若 `AGENTS.md` 尚未沉淀，先执行这一步（一次搞定规则固化 + 盘点）：

```text
本轮目标：固化项目规则 + 现状盘点。

步骤：
1. 基于 @docs/prd.md @docs/brd.md 和当前仓库实际情况，
   生成 /Users/xinzhang/gitProject/robot/robot_factory/AGENTS.md，
   内容参考 docs/cursor_opus_development_roadmap.md 第 3 节。
2. 并行使用 explore subagent 扫描 @protocol @robot_server @mobile_sdk @apps，
   产出 docs/backlog.md：完成度清单 + 按优先级排序的 backlog + 模块归属 + 真机部署影响。
3. 不修改业务代码，仅新增 AGENTS.md 与 docs/backlog.md。

完成后：
- 汇报两份文档路径与关键结论
- 给出下一步建议（通常是 Milestone 1: Python 3.8 / ROS1 Noetic 基座对齐）
```

之后按 Milestone 1 → 8 推进即可。每个里程碑结束，把成果和剩余风险回写到 `docs/backlog.md`，作为下一轮上下文锚点。
