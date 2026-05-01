# 手势控制 MVP：AI / 开发者实现指引（robot_factory）

> **用途**：指导在本仓库中**落地**「手势指令模式 + 手势跟随模式」的完整业务逻辑与**边界处理**。实现应满足下文 **MUST** 规格；与规格冲突的旧行为（如 350ms 冷却、胜利 900ms 进入 follow、无投票、旧面积 baseline 触发）必须删除，不做兼容。  
> **范围**：`hand_gesture_sdk`（Dart + 原生 metrics 契约）、`apps/robot_app` 内接入与 `mobile_sdk.RobotClient` 映射。  
> **非目标**：不引入 Python 运行时；不存在 `dog_api`；不在 `hand_gesture_sdk` 内 `import mobile_sdk`。

---

## 1. 完成定义（Done = 可验收）

同时满足：

1. **双模式**：`command`（离散指令）与 `follow`（连续速度跟随）可切换；默认 `command`。
2. **`command` 模式**：高置信 `张开手掌` 连续保持 2s 进入 `follow`；高置信 `指向` 按当前画面左右位置触发横移；高置信 `握拳` 输出停止移动；其它手势首版不处理。
3. **`follow` 模式**：交互优先级为 **「先左右、再前后；二者互斥」**。
   - 手掌中心 `x` 偏离屏幕中心（`|dx| > lateral_dead_zone`）时只输出左右横移 `vy`，`vx` 强制为 0；
   - 手掌处于横向死区内（视为画面中央）时才以手掌面积 `area` 映射前后跟随：手变大前进、手变小后退；
   - 速度映射在死区外保留饱和与 `sqrt` 非线性，前后保留手部面积熔断与恢复；
   - 不再做横向自激抑制（旧 200 ms 灵敏度衰减），避免横向命令断断续续被零速覆盖。
4. **机器人侧**：在已连接 `RobotClient` 时，将解释器输出映射为 `move` / `stand` / `sit` / `stop` 等（**手动控制用 last-wins**，与 `AGENTS.md` 一致）。
5. **测试**：Dart 侧对 2s 模式切换、握拳停止 / 回 command、指向左右位置、跟随映射与熔断有可重复单测（伪造事件序列 + 可控时钟）。
6. **识别页方向**：进入原生手势识别页后固定为单一横屏；Android 使用 `landscape`，iOS 使用 `.landscapeRight`。不做左右横屏自动旋转，避免相机画面、MediaPipe 输入和 overlay 方向处理复杂化；退出识别页后 App 释放方向限制。

---

## 2. 仓库硬约束（实现前必读）

| 约束 | 说明 |
| --- | --- |
| SDK 边界 | `hand_gesture_sdk` **不得**依赖 `mobile_sdk`；所有 `RobotClient` 调用在 **App**（如 `gesture_module_page` 或新建 `GestureRobotController`）。 |
| 控制入口 | App 业务流程通过 `RobotClient`；不得绕过协议层手写帧字节。 |
| 协议语义 | `RobotClient.move(vx, vy, yaw)` 使用 SDK 约定的物理尺度，由 `mobile_sdk` 编码为协议 `int16`（×100）；跟随模式输出的 `linear_vel` / `lateral_vel` 必须映射到 `vx/vy/yaw` 的符号与轴含义（见 §9）。 |
| 首版策略 | 本 MVP 是手势 SDK 第一版交付，不保留旧解释器行为、不保留旧 metrics fallback、不为旧 UI 输出额外兼容事件。 |
| 文档 | 实现完成后更新本文件「实现状态」勾选或 `hand_gesture_sdk/README.md` 中解释器表格；里程碑级同步 `docs/backlog.md`（若团队要求）。 |

---

## 3. 状态与每帧处理流程（逻辑模型）

### 3.1 维护的状态（建议在 Dart 单一类中集中管理）

- `current_mode ∈ { command, follow }`，初始 `command`。
- `open_palm_started_at`：`command` 模式下 `张开手掌` 高置信连续保持的起始时间；达到 2s 后进入 `follow`。
- `follow_fist_started_at`：`follow` 模式下 `握拳` 高置信连续保持的起始时间；2s 内停止移动，达到 2s 后回到 `command`。
- `follow` 专用：
  - `neutral_hand_area`：进入 `follow` 后的面积基准。默认从首个有效手掌帧初始化；若首帧不可用，使用配置默认值 `0.18`。
  - `fuse_active`（或等价）、`fuse_release_since`（面积 <0.3 的起始时间）。
  - 不再维护横向自激抑制计时器（`lateral_suppress_until`），新交互的横向输出每帧独立计算。

### 3.2 每步输入（由 `HandGestureEvent` 归一化得到）

在解释器入口将事件转为**一帧逻辑输入**（字段不齐时在原生侧补齐，见 §8）：

- `hand_detected: bool`
- `gesture_class: String`（内部可用英文常量，但与原生 `gesture` 中文需可映射）
- `gesture_confidence: double` ∈ [0,1]
- `palm_center_x, palm_center_y` ∈ [0,1]
- `hand_bbox_area` ∈ [0,1]（手部包围框面积 / 画面总面积）

### 3.3 处理顺序（MUST 顺序）

1. 将原生事件归一化为 `hand_detected`、`gesture_class`、`gesture_confidence`、`palm_center_x/y`、`hand_bbox_area`。
2. 按 `current_mode` 分支调用 `process_command_mode()` 或 `process_follow_mode()`（函数名可改，语义保留）。
3. 输出：`HandGestureCommand?` 或扩展类型；模式切换必须输出 `modeChanged` / `feedbackHint` 等价信号供 App 做 Toast（SDK 不弹 UI）。

**澄清**：本调试版取消 `command` 投票和冷却路径，避免“识别成功但因 ROI / 投票 / 冷却无法控制”的不可见状态。`follow` 应持续每帧（或节流后的帧）输出 `move` 或内部零速。

---

## 4. `command` 模式 — 边界规格（MUST）

进入 `process_command_mode` 时只处理 `张开手掌`、`握拳`、`指向` 三类高置信输入。`胜利`、OK、点赞、一指、两指、三指等其它手势只用于 UI 展示，不映射控制。

### 4.1 置信度分档

- `gesture_confidence < 0.4` **或** `hand_detected == false` → 本帧视为 **`none`**（强制）。
- `0.4 ≤ gesture_confidence < 0.85` → **`uncertain`**：不触发控制。
- `gesture_confidence ≥ 0.85` → 高置信，进入 §6 映射。

### 4.2 模式切换保持

- `command` 模式下 `张开手掌` 高置信连续保持 2s：输出 `modeChanged(follow)`；切换后清空保持计时、跟随面积基准和熔断状态。
- 已在 `follow` 模式时，`张开手掌` 不重复输出 `modeChanged(follow)`。
- `follow` 模式下 `握拳` 高置信：立即输出 `stop`；若连续保持 2s，输出 `modeChanged(command)`。

### 4.3 指向横移

- `command` 模式下 `指向` 高置信且 `handCenterX < 0.45`：输出左移 `move(vx: 0, vy: +0.25, yaw: 0)`。
- `command` 模式下 `指向` 高置信且 `handCenterX > 0.55`：输出右移 `move(vx: 0, vy: -0.25, yaw: 0)`。
- `0.45 ≤ handCenterX ≤ 0.55` 是中心死区，不输出离散横移。

---

## 5. `follow` 模式 — 边界规格（MUST）

`follow` 模式必须满足本仓库的交付定义：**先看横向位置，再看手掌大小；横向与前后互斥下发**。`palm_center_y` 首版只保留为可观测输入，不映射到机器人高度或速度。若后续真机确认高度控制 API 可用，再单独扩展 `y -> stand/sit/height` 映射。

> **设计动机**：`RobotClient.move` 对手动控制为 last-wins 语义。如果同一帧把 `vx` 与 `vy` 一起下发，前一帧偏前后但横向接近 0 的命令会反复把刚发出的横向意图盖掉，导致只能前后、几乎不能左右。`follow` 改为优先横向、独占下发后，左右移动可以连续生效。

### 5.1 面积基准与死区

- `neutral_hand_area`：进入 `follow` 后首个有效帧的 `hand_bbox_area`，夹在 `[0.08, 0.45]`；若首帧无手或面积无效，使用 `default_neutral_area = 0.18`。
- `area_dead_zone = 0.04`：`abs(hand_bbox_area - neutral_hand_area) <= area_dead_zone` 时前后速度为 0。
- `lateral_dead_zone = 0.10`：`abs(palm_center_x - 0.5) <= lateral_dead_zone` 视为「手掌在中心」，**只在中心时才允许前后**。
- 中心 + 面积死区内 → 零速：`HandGestureCommand.move(vx: 0, vy: 0, yaw: 0)`。首版统一使用零速 `move`，不使用 `stop()`，避免连续跟随时频繁切离运动模式。
- `palm_center_y` 首版不参与速度映射；只可用于 UI 调试、后续高度控制扩展或原生姿态判断。

### 5.2 处理顺序与速度映射

每帧检测到手时，按以下顺序选择**唯一输出分支**：

1. `dx = palm_center_x - 0.5`；若 `|dx| > lateral_dead_zone` → 走 **转向分支**：
   - `effective_dx = (|dx| - lateral_dead_zone) * sign(dx)`
   - `norm_x = clamp(|effective_dx| / (max_x_offset - lateral_dead_zone), 0, 1)`，`max_x_offset = 0.35`
   - `speed_ratio_x = sqrt(norm_x)`，`MAX_YAW_VEL = 0.9`（与正式遥控页转向摇杆一致）
   - `yaw_vel = -speed_ratio_x * MAX_YAW_VEL * sign(dx)`：画面左侧 `yaw > 0`（左转），画面右侧 `yaw < 0`（右转）
   - 输出 `move(vx: 0, vy: 0, yaw: yaw_vel)`，message="跟随转向"
   - **不做横向自激抑制**；同样输入产生同样的转向速度。
   - 注：不走 `vy`（横向平移），原因是 `vy` 需要 `ROBOT_ROS_ENABLE_LATERAL=true` 才生效，`yaw` 走标准 `/cmd_vel angular.z` 默认可用。
2. 否则走 **前后分支**：
   - `area_error = hand_bbox_area - neutral_hand_area`
   - `effective_area = (|area_error| - area_dead_zone) * sign(area_error)`
   - `norm_area = clamp(|effective_area| / (max_area_offset - area_dead_zone), 0, 1)`，`max_area_offset = 0.30`
   - `speed_ratio_area = sqrt(norm_area)`，`MAX_LINEAR_VEL = 0.5`
   - `linear_vel = speed_ratio_area * MAX_LINEAR_VEL * sign(area_error)`：变大 → `vx > 0` 前进，变小 → `vx < 0` 后退
   - 经面积熔断（§5.3）后输出 `move(vx: fused_linear_vel, vy: 0, yaw: 0)`，message="跟随前后"

### 5.3 面积熔断

- `hand_bbox_area ≥ 0.6` → 进入熔断：`linear_vel = min(linear_vel, 0)`（禁止继续前进，只允许后退或横移），避免手掌过近时机器人继续贴近用户。
- 仅当 `hand_bbox_area < 0.3` **连续满 2.0 s** 才退出熔断。
- 熔断只作用在前后分支；横向分支不受熔断影响（横向独占下发，已经天然不前进）。

---

## 6. 手势 → 行为映射（须实现且可配置）

原外部 spec 使用英文类名；本仓库原生输出**中文** `gesture`。本 MVP 固定采用 **Dart 内建映射表 + 时序派生标签**，不要求原生新增 `gestureKey`。

| 目标行为（原 spec） | 建议映射（中文 `gesture`） | 输出 / 副作用 |
| --- | --- | --- |
| `stop` | `握拳` | `HandGestureCommand.stop`；App 层必须映射为零速 `move(0,0,0)`，只停止当前运动，不调用急停 / recovery 型停止。 |
| `left` | `command` 模式下识别为 `指向`，且 `handCenterX < 0.45`。首版只使用 `handCenterX`，不依赖 `indexTipX` 或挥动轨迹。 | 默认横向平移：`HandGestureCommand.move(vx: 0, vy: +0.25, yaw: 0)`；App 层执行短促后补零速。 |
| `right` | `command` 模式下识别为 `指向`，且 `handCenterX > 0.55`。首版只使用 `handCenterX`，不依赖 `indexTipX` 或挥动轨迹。 | 默认横向平移：`HandGestureCommand.move(vx: 0, vy: -0.25, yaw: 0)`；App 层执行短促后补零速。 |
| 进入 `follow` | `command` 模式下 `张开手掌` 连续保持 2s。 | `modeChanged(follow)`；已在 `follow` 时不重复进入，不额外发运动命令。 |
| 退出 `follow` | `follow` 模式下 `握拳` 立即停止移动；若连续保持 2s，则进入 `command`。 | 2s 内输出 `stop`；达到 2s 后输出 `modeChanged(command)`。 |
| 其它手势 | `胜利`、OK、点赞、一指、两指、三指等 | 首版不处理，不切模式、不下发运动。 |
| `follow` 进入提示 | 模式切到 `follow` 时只输出 `modeChanged(follow)` 反馈信号；不额外发 `HandGestureCommand.follow`。 | App 只展示模式变化，不映射成运动命令。 |

**本 MVP 的明确决策**：

- 模式切换改为「张开手掌 2s 进入 follow；follow 下握拳停止，握拳 2s 回 command」；`胜利` 不再参与模式切换。
- `command` 模式不再使用 `张开手掌` 触发前进 / 后退，也不再使用 `backward_proxy` 近似后退。
- 指向控制改为按当前屏幕左右位置触发横移，不再要求 300–700ms 左右挥动。
- OK、点赞、一指、两指、三指等其它手势首版保留识别展示，不映射控制。

---

## 7. 数据契约 — `HandGestureEvent` / `metrics`（MUST 补齐或可推导）

解释器**不得**依赖含糊字符串解析 `message`。下列键必须在 **metrics** 中由 Android/iOS 填齐；Dart 侧只读取这些规范键，不解析旧别名：

| 键 | 类型 | 含义 |
| --- | --- | --- |
| `handDetected` | bool | 是否检测到手 |
| `handCenterX` | double | 0–1，归一化 |
| `handCenterY` | double | 0–1 |
| `handBBoxArea` | double | 0–1，面积比（与 §5.3 阈值一致） |
| `bboxWidth` | double | 0–1，手部 bbox 宽度；用于“布”近似判断 |
| `bboxHeight` | double | 0–1，手部 bbox 高度；用于“布”近似判断 |

`confidence` 对应 `gesture_confidence`。若某帧无手，原生应发 `handDetected: false` 或 `gesture == null`。

当前 Android / iOS 已输出旧键 `handArea`。实现时必须把原生输出改为规范键 `handBBoxArea`，并补齐 `handDetected`。Dart 新状态机不读取 `handArea`。

---

## 8. 实现任务清单（建议顺序，供 AI 分步提交）

1. **Dart**：新建 `gesture_control_state.dart`（或等价）实现 §3–§5 状态机 + `processCommandMode` / `processFollowMode`。
2. **Dart**：将 §4–§5 全部常数提取为构造函数参数或 `GestureControlConfig`，默认值与本文一致。
3. **Dart**：重写 `GestureCommandInterpreter`，让它只委托新状态机；删除旧 `_followHold`、350ms 冷却、旧 baseline ratio 面积触发、旧「胜利 900ms → follow」逻辑。
4. **Dart**：扩展/确认 `HandGestureEvent.fromMap` 读取 §7 规范键；缺关键字段时安全默认（视为无手或 `none`），但不读取旧 `handArea`。
5. **原生**：修改 `GestureActivity.kt` / `GestureViewController.swift`，输出 `handDetected`、`handBBoxArea`、`handCenterX`、`handCenterY`、`bboxWidth`、`bboxHeight`。
6. **测试清理**：删除或改写旧解释器测试，测试期望必须完全按本 MD 新规则，不保留旧行为断言。
7. **App**：`GestureModulePage` 必须接收当前 `RobotClient`（首页打开时传入 `_client`），新建控制器订阅 `HandGestureSdk.instance.commands`（或事件流），实现 §9 映射与 `onModeChanged` 的 SnackBar。
8. **测试**：`test/gesture_control_state_test.dart`（或改写现有 interpreter 测试）覆盖：张开手掌 2s 进 `follow`、`follow` 下张开手掌不重复切换、握拳停止、握拳 2s 回 `command`、指向按左右位置横移、其它手势忽略、`area` 前进/后退、`x` 横移、横向 / 前后互斥优先级、中心死区落入零速、面积熔断与 2s 恢复、横向连续输出不被衰减、姿态 / 状态事件被忽略不污染状态机。

---

## 9. `RobotClient` 映射（App 层 MUST）

- `HandGestureCommand.stop` → `robotClient.move(0,0,0)`。这里的停止只是停止当前运动，不是急停，也不应让机器狗进入需要 recovery 才能继续控制的状态。
- `stand` / `sit` → `stand()` / `sit()`。
- `move` 离散短促指令 → App 层调用 `robotClient.move(vx, vy, yaw)` 后延迟 300–500ms 再补 `robotClient.move(0, 0, 0)`；该补零速仍使用 last-wins API，不使用 `*Queued`。
- **`follow` 连续控制**：将 §5 的 `linear_vel` → **`vx`**（前后），`lateral_vel` → **`vy`**（左右横移），`yaw` 默认 0。**符号**须与真机前进/横移方向验证；首版按现有解释器语义写入注释：`vx > 0` 表示机器人前进，画面左侧 `vy > 0`，画面右侧 `vy < 0`。
- **节流**：跟随模式可对 `RobotClient.move` 做 **30–50 Hz → 10 Hz** 降采样或与 `robot_server` 状态频率匹配，避免蓝牙拥塞；不得破坏协议 ACK 语义。

---

## 10. 验收清单（AI 自检）

- [ ] `command`：置信度在 [0.4,0.85) **不触发**控制。
- [ ] `command`：`张开手掌` 连续保持 2s 后进入 `follow`，已在 `follow` 时不重复进入。
- [ ] `command`：`握拳` 输出停止移动，App 映射为零速 `move(0,0,0)`。
- [ ] `command`：`指向` 按 `handCenterX` 当前左右位置触发默认横向平移，中心死区不输出。
- [ ] `command`：`胜利`、OK、点赞、一指、两指、三指等其它手势不处理。
- [ ] `follow`：`握拳` 立即停止移动，连续保持 2s 后进入 `command`。
- [ ] 原生 metrics：Android / iOS 均输出 `handDetected` 与 `handBBoxArea`，Dart 不读取旧 `handArea`。
- [ ] 旧逻辑：`_followHold`、350ms 冷却、1s 投票、1.5s 冷却、旧 baseline ratio 面积触发、旧「胜利 900ms → follow」、`张开手掌` 前后移动、`指向` 挥动识别逻辑已删除或不可达。
- [ ] `follow`：`x` 在中心横向死区内（`|dx| ≤ 0.10`）且 `area` 大于基准时 `vx > 0`，小于基准时 `vx < 0`，`vy` 始终为 0。
- [ ] `follow`：`x` 偏左/右（`|dx| > 0.10`）时只输出 `vy` 横移，`vx` 强制为 0，`yaw` 保持 0。
- [ ] `follow`：中心横向死区内 + 面积死区内 → 输出零速 `move(0,0,0)`。
- [ ] `follow`：手面积 ≥0.6 且当前帧落在前后分支时前进被钳制；<0.3 连续 2s 后恢复。
- [ ] `follow`：连续多帧给出相同的偏离 `x`，对应 `vy` 输出**保持一致**（不再被旧 200ms 横向抑制衰减）。
- [ ] 连接机器人时：手势页可实际控制；断开时不崩溃。

---

## 11. 实现状态（由人类维护勾选）

- [x] §4 `command` 边界已全部在 Dart 落地
- [x] §5 `follow` 边界已全部在 Dart 落地
- [x] §6 手势映射与 OK/过渡方案已落地并写清
- [x] §7 metrics 原生双端一致
- [x] §9 App 已接 `RobotClient`
- [x] 原生识别页固定单一横屏，关闭后恢复 App 方向偏好
- [ ] §10 单测 + 真机各至少跑通一轮（Dart / Flutter 单测已跑；真机手势控制待 Android / iOS 设备联调）

---

## 12. 附录：与原「主循环伪代码」的对应关系

原：`while True: frame → detect_hand → 边界 → dog_api.send_command`

本仓库等价：

`EventChannel` 推送 `HandGestureEvent` → **Dart 状态机（本文 §3–§5）** → `HandGestureCommand` 流 → **App** `RobotClient.move/stand/sit/stop`。
