# robot_factory 项目约束（AGENTS.md）

本文件是 `robot_factory/` 仓库的项目级 Agent 约束。所有 AI 协作（Cursor Agent / Plan / Ask、Subagent、Background、Cloud Agent）在本仓库内工作时，必须遵守以下约束，不需要每条 prompt 重复提示。

> 本文件参考 `docs/cursor_opus_development_roadmap.md` 第 3 节沉淀。若本文件与路线图冲突，以路线图 + 最新 `docs/backlog.md` 为准。

---

## 1. 需求来源

- 主：`/Users/xinzhang/gitProject/robot/robot_factory/prd.md`（仓库根目录 `prd.md`）
- 辅：`/Users/xinzhang/gitProject/robot/robot_factory/brd.md`（仓库根目录 `brd.md`）
- 现状盘点与 backlog：`docs/backlog.md`（每个里程碑结束回写）
- 整体路线图：`docs/cursor_opus_development_roadmap.md`
- Phase 0 设计：`docs/phase0_design.md`

当需求描述出现冲突时，优先级：`prd.md` > `brd.md` > 路线图 > 旧代码。

---

## 2. 架构约束

- 保持当前 monorepo 结构，不得新增顶层目录或推翻既有布局：
  - `apps/robot_app`：Flutter 产品 App + 图形化动作引擎（action engine）
  - `mobile_sdk`：Flutter / Dart SDK（`RobotClient`、transports、命令队列）
  - `robot_server`：Ubuntu + ROS1 Noetic 机器人端（BLE / TCP / MQTT / ROS 桥接）
  - `protocol`：Python + Dart 共享的二进制协议（帧结构、CRC、stream decoder、ACK）
  - `docs`：设计、路线图、backlog
- 增量修改，优先复用已有 stub、接口与抽象，**不得**顺手重构与当前任务无关的模块。
- 模块边界：
  - App 不得绕过 `mobile_sdk.RobotClient` 直接操作 transport。
  - `robot_server` 各 transport（BLE / TCP / MQTT）必须走统一 protocol parser + StateStore，不得自建帧格式。
  - `protocol` 只放纯协议逻辑，不依赖 ROS / Flutter / BlueZ。

---

## 3. 环境约束

### 机器人端

- 目标运行环境：Ubuntu 20.04 + ROS1 Noetic + Python 3.8。
- **禁止**引入 Python 3.9+ 专属语法：
  - 运行时使用的 `X | Y` 类型（仅 `from __future__ import annotations` 后作为注解可接受）
  - 直接用 `list[int]` / `dict[str, Any]` 等 PEP 585 泛型（注解外不得使用）
  - `match` 语句
  - `typing.Self`、`typing.ParamSpec` 等 3.10+ 特性
  - `:=` 在不支持上下文中的使用
- 允许依赖：`paho-mqtt`（MQTT）、`dbus-next`（BlueZ BLE）、`rospy`（ROS1）。新增依赖需在 PR 说明理由与版本。

### Flutter / Dart 端

- 与现有 `mobile_sdk/pubspec.yaml`、`apps/robot_app/pubspec.yaml` 保持兼容，不主动升 Dart SDK 主版本。
- BLE / MQTT 插件选型需单独说明；优先选择维护活跃、跨平台（Android + iOS）支持完善的插件。
- 禁止在 SDK 里硬编码具体 UI / Navigator 逻辑，UI 交互只放在 `apps/robot_app`。

---

## 4. 协议约束

- `control` / `state` 走二进制协议，帧格式：`0xAA55 | Type | Seq | Len | Payload | CRC16`
  - `Type`：`0x01` CMD、`0x02` STATE、`0x03` ACK
  - `CMD` 载荷：MOVE（`cmd_id=0x01`, `vx/vy/yaw` int16，实际值 * 100）/ DISCRETE（`0x10` stand / `0x11` sit / `0x12` stop）
  - `STATE` 载荷：`battery | roll(int16) | pitch | yaw`
  - `ACK` 载荷：`seq`
  - 所有实现必须支持粘包 + CRC 校验 + stream decoder
- `event` 走 JSON（仅 MQTT topic 使用）。
- MQTT topic 严格遵循：
  - `robot/{id}/control`（binary）
  - `robot/{id}/state`（binary）
  - `robot/{id}/event`（JSON）
- 命令队列：`move` 仅保留最新（覆盖语义），`discrete` FIFO；未 ACK 阻塞重传（3 次，100ms 超时）。
- 状态推送：10Hz。

---

## 5. 工作方式约束（Cursor + Opus 4.7）

1. **先计划，后执行**：跨模块任务先进入 Plan 模式产出方案，确认后切 Agent。
2. **TodoWrite 驱动**：任务开始时用 TodoWrite 列清单，中途更新状态。
3. **并行 explore subagent**：大范围扫描（多模块、Python 3.8 兼容性、命名一致性等）优先用 `Task(subagent_type="explore")` 并行探索，再汇总到主线。
4. **@ 引用优先**：尽量用 `@docs/prd.md` / `@robot_server/transports/ble/` 之类的 @ 引用，而不是绝对路径。
5. **长耗时任务后台化**：真机日志分析、全仓迁移、回归测试适合放 Background / Cloud Agent。
6. **一次闭环**：Opus 4.7 有能力在一轮里完成"机器人端 + SDK + App"闭环，鼓励一次闭环但必须 Plan 充分。

---

## 6. 每次任务完成标准

无论任务大小，结束前必须：

1. **直接修改真实代码**（除非任务明确是"只分析 / 只出方案"）。
2. **跑相关测试**：
   - Python 侧：
     ```bash
     PYTHONPATH=protocol/python python3 -m unittest discover -s protocol/python/tests
     PYTHONPATH=protocol/python:robot_server python3 -m unittest discover -s robot_server/tests
     ```
   - Dart 侧：`cd mobile_sdk && flutter test`、`cd apps/robot_app && flutter test`
   - 若新增/修改了测试，在汇报里显式列出。
3. **跑 `ReadLints`** 对改动文件自检，并修复本轮新引入的 lint。
4. **汇报四件套**：
   - 修改 / 新增 / 删除文件清单
   - 测试结果（通过 / 失败 / 跳过）
   - 剩余风险与未覆盖点
   - 推荐的下一步（通常指向下一个里程碑或 backlog 条目）
5. **回写 backlog**：里程碑级任务结束后，在 `docs/backlog.md` 更新完成度和剩余条目。

---

## 7. 禁止事项

- 不得修改 `AGENTS.md`、`docs/prd.md`（若存在）、`prd.md`、`brd.md`、路线图文档，除非任务明确为"更新项目约束"。
- 不得绕过命令队列 / 协议层直接拼字节。
- 不得引入重型 DevOps 体系（k8s、helm 等），部署文档保持可交付给测试同学直接复用的粒度。
- 不得硬编码设备 ID、broker 地址、凭证等；全部走配置文件或环境变量，并在 `.env.example` 中给示例。
- 不得在 SDK 层引入全局单例导致 App 难以测试。
