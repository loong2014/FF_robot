# Cursor + Opus 4.7 分步 Prompt 清单

配合 `docs/cursor_opus_development_roadmap.md` 使用。每一步开一个**新 Chat**，模型选 **Claude Opus 4.7**，直接复制对应区块粘贴即可。

## 使用规则（请先看一眼）

1. 每个里程碑 = 一个新 Chat + 一条新 git 分支。
2. Step 0 **必须最先执行一次**，产出 `AGENTS.md` 和 `docs/backlog.md`。之后所有里程碑都依赖这两份文件。
3. 标注【Plan 模式】的步骤请先在 Cursor 右下角切到 Plan 模式，方案确认后再切 Agent 执行。
4. 标注【Agent 模式】的步骤默认在 Agent 模式执行。
5. 如果中途 AI 跑偏，直接说"请回到 @docs/cursor_opus_development_roadmap.md 的 Milestone X 约束"即可。

---

## Step 0. 固化项目规则 + 现状盘点 【Agent 模式】

> 新开一个 Chat，Opus 4.7，Agent 模式。

```text
请阅读以下文档并执行任务：
- @docs/cursor_opus_development_roadmap.md
- /Users/xinzhang/gitProject/robot/prd.md
- /Users/xinzhang/gitProject/robot/brd.md

本轮目标：固化项目规则 + 现状盘点（不改业务代码）。

执行步骤：
1. 先用 TodoWrite 列出本轮任务清单。
2. 基于路线图第 3 节，生成 /Users/xinzhang/gitProject/robot/robot_factory/AGENTS.md，
   内容要结合 prd.md / brd.md 的真实约束，不要照抄模板。
3. 并行启动 explore subagent，分别扫描：
   - @protocol
   - @robot_server
   - @mobile_sdk
   - @apps/robot_app
   汇总出：每个模块的完成度、stub 位置、与 prd/brd 的差距。
4. 产出 docs/backlog.md：
   - 按优先级排序的 backlog
   - 每项标注所属模块
   - 标注是否影响 ROS1 Noetic 真机部署
   - 标注建议的里程碑归属（对应路线图 Milestone 1~8）
5. 只新增 AGENTS.md 和 docs/backlog.md，不修改业务代码。

完成后汇报：
- 两份文档的路径与关键结论
- 推荐的下一个里程碑（通常是 Milestone 1）
- 有没有发现会影响路线图假设的意外情况
```

---

## Milestone 1. Python 3.8 / ROS1 Noetic 基座对齐 【Agent 模式】

```text
本轮目标：让 protocol/python 和 robot_server 全量兼容 Python 3.8 + ROS1 Noetic。

执行步骤：
1. 用 TodoWrite 列出本轮任务清单。
2. 并行 explore subagent 扫描 @protocol/python 和 @robot_server，
   找出所有 Python 3.9+ 专属写法：
   - `X | Y` 联合类型（非字符串注解场景）
   - 运行期直接使用 `list[int]` / `dict[str, Any]` / `tuple[...]`
   - `match` / `case` 语句
   - `typing.Self`
   - `:=` 在不支持位置
   - `@dataclass(slots=True)` 等 3.10+ 参数
   - `functools.cache`（3.9+）
   - `zoneinfo`、`tomllib` 等 3.9+/3.11+ 标准库
3. 改为 Python 3.8 兼容写法（from __future__ import annotations、typing.Union/Optional/List 等），
   保持业务逻辑不变。
4. 更新 pyproject.toml / README 中的 Python 版本与运行环境说明。
5. 保持 BLE / TCP / MQTT / ROS 的现有架构不变。

完成后必须：
- 运行：PYTHONPATH=protocol/python python3 -m unittest discover -s protocol/python/tests
- 运行：PYTHONPATH=protocol/python:robot_server python3 -m unittest discover -s robot_server/tests
- 对所有改动文件跑 ReadLints，并修复新引入的 lint
- 汇报：修改文件清单、测试结果、剩余风险、推荐的下一步
```

---

## Milestone 2.1 BLE 端到端闭环 · 方案评审 【Plan 模式】

> 切到 Plan 模式。

```text
进入 Plan 模式。基于 @docs/prd.md @docs/brd.md @docs/backlog.md
以及 @robot_server @mobile_sdk @apps/robot_app 的当前代码，
为 BLE 端到端闭环输出完整实施方案。

方案必须覆盖三端：

1. robot_server 侧（@robot_server/transports/ble）：
   - BlueZ GATT Server 搭建方式
   - RobotControlService 注册
   - cmd_char（write without response）
   - state_char（notify）
   - MTU 协商与分片策略
   - stream decoder 对接
   - ACK + 重传逻辑与协议层协同
   - 10Hz 状态推送实现
   - Python 3.8 / ROS1 Noetic 兼容点

2. mobile_sdk 侧（@mobile_sdk/lib/src/transports/ble_transport.dart）：
   - Flutter BLE 插件选型与理由（flutter_blue_plus / flutter_reactive_ble 等）
   - BleTransport 实现要点
   - cmd_char 写、state_char 订阅
   - MTU 分片发送、stream decoder 解包
   - RobotClient.connectBLE / stateStream / move / stand / sit / stop 对接

3. robot_app 侧（@apps/robot_app）：
   - BLE 扫描 / 连接 / 绑定交互
   - 连接方式与状态展示
   - 与现有首页 / 动作引擎页面的集成方式

还需要输出：
- 与现有 TCP / MQTT 代码的交叉点清单，保证不被破坏
- 风险项（权限、平台差异、iOS / Android 适配等）
- 分阶段验证计划（先单端自测 → SDK 对 Mock Server → 端到端）
- 如有必要，建议拆分子里程碑（例如先 robot_server，再 SDK + App）

只输出方案，不写代码。
```

---

## Milestone 2.2 BLE 端到端闭环 · 实施 【Agent 模式】

> 回到 Agent 模式。**基于 2.1 确认的方案**。

```text
切回 Agent 模式。基于刚才在 Plan 模式确认的 BLE 端到端方案，开始实施。

修改范围：
- @robot_server/transports/ble/ 及相关
- @protocol/（如方案涉及）
- @mobile_sdk/lib/src/transports/ble_transport.dart 及相关
- @mobile_sdk/pubspec.yaml（BLE 插件）
- @apps/robot_app（设备扫描 / 连接 / 状态 UI）

执行要求：
1. 用 TodoWrite 拆解并按 todo 推进，每完成一个勾掉。
2. 优先复用已有 stub 与抽象；TCP / MQTT 代码不得被破坏。
3. 设备绑定先做 App 内设备记录，不引入账号体系。
4. Flutter BLE 插件在 pubspec 引入，注释说明选型理由。
5. 涉及权限（Android / iOS）要同步更新 manifest / Info.plist。

完成后必须：
- 运行 BLE 相关 Python 单测
- 运行 `flutter test`（mobile_sdk 与 robot_app）
- 对改动文件跑 ReadLints 并修复
- 更新 @docs：BLE 启动依赖、联调步骤
- 汇报：文件清单 / 测试结果 / 剩余风险 / 下一步建议

如中途发现实施量明显超出一轮可控范围，请暂停并汇报，建议拆分子里程碑。
```

---

## Milestone 3. SDK 统一连接管理（BLE > TCP > MQTT）【Agent 模式】

```text
本轮目标：在 @mobile_sdk 中实现统一连接管理能力。

执行步骤：
1. 用 TodoWrite 列出本轮任务清单。
2. 设计并实现统一连接状态模型：
   - 当前传输类型（BLE / TCP / MQTT / None）
   - 连接状态（idle / connecting / connected / reconnecting / failed）
   - 最近状态时间戳
   - 最近错误码与描述
3. 提供连接状态 Stream，供 robot_app 订阅。
4. 实现按 BLE > TCP > MQTT 优先级自动尝试连接。
5. 支持显式切换传输方式，切换过程不丢命令队列。
6. 不要求复杂自动重连策略，但必须预留扩展点（重连策略接口 + 默认实现）。
7. 保持 RobotClient API 对 App 友好、向后兼容（connectBLE / connectTCP / connectMQTT 继续可用）。

完成后必须：
- 新增或更新 mobile_sdk 单测：优先级选择、切换、状态流、异常路径
- 运行 `flutter test`
- 对改动文件跑 ReadLints 并修复
- 汇报：状态模型设计、切换策略、后续扩展点（心跳 / QoS / 断线重连 / 命令队列持久化）
```

---

## Milestone 4. TCP 全链路 【Agent 模式】

```text
本轮目标：打通 TCP 全链路（robot_server + mobile_sdk + robot_app），行为与 BLE 路径对齐。

执行步骤：
1. 用 TodoWrite 列出本轮任务清单。
2. 完善 @robot_server 的 TCP socket server：
   - 接入统一 protocol parser 与 stream decoder
   - 命令队列、ACK、状态推送与 BLE 路径一致
3. 完善 @mobile_sdk/lib/src/transports/tcp_transport.dart：
   - 复用 Milestone 3 的统一连接状态模型
   - 复用 protocol 层的 frame 与 decoder
4. 在 @apps/robot_app 中：
   - 加入 TCP 连接入口（Host / Port 输入）
   - 复用统一连接状态展示
5. 不做 BLE 级别的过度优化；协议格式不变。

完成后必须：
- 运行 Python 单测与 `flutter test`
- 如有条件，补 TCP 端到端最小验证脚本（脚本模式即可）
- 对改动文件跑 ReadLints 并修复
- 汇报：文件清单 / 测试结果 / 剩余风险
```

---

## Milestone 5. MQTT 全链路 【Agent 模式】

```text
本轮目标：打通 MQTT 全链路（robot_server Router + mobile_sdk transport + robot_app 接入）。

执行步骤：
1. 用 TodoWrite 列出本轮任务清单。
2. 完善 @robot_server 的 MQTT Router，严格遵循 topic：
   - robot/{id}/control（binary，使用统一协议）
   - robot/{id}/state（binary，使用统一协议）
   - robot/{id}/event（JSON）
3. 在 @mobile_sdk 中实现 MQTT transport：
   - 复用统一连接状态模型
   - 复用 protocol 层的 frame 与 decoder
4. 在 @apps/robot_app 中加入 MQTT 入口：
   - Broker 地址、端口、clientId、账号密码（可选）
   - 复用统一连接状态展示
5. 云端鉴权不做硬依赖，保留接口与配置能力；默认可用无鉴权方式连本地 broker。

完成后必须：
- 新增或更新 MQTT 相关单测（Router 分发、topic 格式、binary/JSON 分流）
- 运行 Python 单测与 `flutter test`
- 对改动文件跑 ReadLints 并修复
- 汇报：topic 设计、Router 逻辑、客户端接入方式、测试结果、剩余风险
```

---

## Milestone 6. ROS 状态采集与上报完善 【Agent 模式】

```text
本轮目标：完善 ROS1 集成，让真实设备状态能通过 BLE / TCP / MQTT 上报到 App。

执行步骤：
1. 用 TodoWrite 列出本轮任务清单。
2. 保持 /cmd_vel 的 10Hz 控制同步不变。
3. 新增机器人状态采集路径：
   - 电量、姿态（IMU）、里程、故障码等
   - 写入 StateStore
4. 通过统一协议把状态推送到 BLE / TCP / MQTT 三条路径。
5. 状态 topic 名称做成可配置（配置文件 / 环境变量），提供默认值，避免写死某一台机器狗。
6. 在 @docs 中明确标出哪些部分是真机环境相关配置。

约束：
- ROS1 Noetic
- Python 3.8 兼容
- 不得写死单一机器狗厂家的 topic

完成后必须：
- 更新 docs / README
- 运行 Python 单测，对改动文件跑 ReadLints
- 汇报：状态来源、配置项、验证方式、剩余风险
```

---

## Milestone 7. 动作编排模块产品化 【Agent 模式】

```text
本轮目标：基于现有 action_engine 完善 App 动作编排，达到可演示程度。

执行步骤：
1. 用 TodoWrite 列出本轮任务清单。
2. 基于 @apps/robot_app 的 action_engine 继续开发，不要重写架构。
3. 支持动作序列：
   - 编辑（新增 / 删除 / 拖拽排序 / 参数配置）
   - 执行（顺序 / 暂停 / 恢复 / 停止）
4. 支持原子动作：move / stand / sit / stop 顺序执行与组合
5. 每个动作必须有：
   - 执行状态（pending / running / done / failed）
   - 失败反馈与错误提示
   - 可选重试策略
6. 所有动作经 mobile_sdk.RobotClient 调用，不绕过 SDK 直写 transport。
7. UI 要适合移动端：列表 / 拖拽 / 参数弹窗，不只是调试按钮。

完成后必须：
- 运行 `flutter test`
- 对改动文件跑 ReadLints 并修复
- 汇报：动作状态机设计、UI 改动、后续扩展项（时间轴 / 条件触发 / 场景化脚本）
```

---

## Milestone 8. 部署与验收 【Agent 模式】

```text
本轮目标：补齐 robot_server 的部署能力与端到端验收闭环。

执行步骤：
1. 用 TodoWrite 列出本轮任务清单。
2. 产出面向 Ubuntu 20.04 / ROS1 Noetic 的部署说明（docs/deploy.md）：
   - 依赖安装（系统包、Python 包、ROS 包）
   - BlueZ / 网络 / MQTT Broker 依赖
3. 提供启动脚本或 systemd service 示例。
4. 提供 .env.example 等环境变量示例。
5. 梳理 BLE / TCP / MQTT / ROS 各自的启动依赖与启动顺序。
6. 输出端到端联调步骤：
   - 手机端如何验证（扫描 / 连接 / 发命令 / 看状态）
   - 机器狗端如何验证（日志 / topic / GATT）
   - 网络侧如何验证（抓包 / broker 观察）
7. 输出验收 checklist（docs/acceptance_checklist.md）。

约束：
- 不引入与当前项目无关的复杂 DevOps 体系
- 文档要能直接交给开发或测试同学使用

完成后汇报：
- 部署文档路径
- 验收 checklist 路径
- 仍未覆盖的上线前工作
```

---

## 附录 A. 通用"修复 / 续作"prompt 模板

当一个里程碑没跑完、测试红、或需要补漏时：

```text
本轮目标：继续完成 Milestone X 中未完成/失败的部分。

请先：
1. 阅读 @docs/cursor_opus_development_roadmap.md 的 Milestone X
2. 阅读 @docs/backlog.md 中该里程碑的状态
3. 运行相关测试，确认当前失败点
4. 用 TodoWrite 列出待修项
5. 逐项修复

完成后：
- 再次运行相关测试至全绿
- 对改动文件跑 ReadLints
- 更新 @docs/backlog.md，标记该里程碑状态
- 汇报本轮改动与剩余问题
```

## 附录 B. 通用"只调研 / 不改代码"prompt 模板

调研未知领域、或评估方案时：

```text
只做调研，不改代码。切换到 Ask 或 Plan 模式。

调研目标：<一句话描述>

范围：
- @<目录或文件>

请并行使用 explore subagent 做信息搜集，产出：
1. 现状事实（附文件/行号引用）
2. 候选方案对比（至少 2 种）
3. 推荐方案与理由
4. 对 @docs/cursor_opus_development_roadmap.md 里程碑的潜在影响
5. 下一步建议的执行 prompt（可直接复用）
```

## 附录 C. 每轮结束的自检 checklist（可贴到 prompt 末尾）

```text
结束前自检：
- [ ] TodoWrite 全部勾掉
- [ ] 相关测试已运行且全绿（或明确说明失败原因）
- [ ] 改动文件跑过 ReadLints，无新增 lint
- [ ] AGENTS.md 中的环境/架构约束未被破坏
- [ ] docs/backlog.md 已根据本轮成果更新
- [ ] 本轮新产生的风险已列出
- [ ] 给出下一步建议（下一条 prompt 或下一个里程碑）
```
