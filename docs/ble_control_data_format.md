# BLE 控制数据格式定义

> 目的：基于 `docs/skill_action.md`，为下一步的 BLE 控制能力补齐一份可实施的二进制数据格式定义。
>
> 范围：只定义 **App <-> 机器狗** 的 BLE 二进制控制/确认格式，不改 GATT 服务结构，不改现有帧头。
>
> 状态：`protocol` 与 `robot_server` 已按本文落地 `0x20 skill_invoke` 的一期子集：`do_action` / `do_dog_behavior`；`mobile_sdk` / `apps/robot_app` 仍主要暴露 `move/stand/sit/stop` 高层 API。

## 1. 设计目标

- 保持现有外层二进制帧不变，避免重做 CRC、stream decoder、ACK 队列。
- 把控制分成两类：
  - **摇杆控制**：高频、连续、只关心最新值。
  - **指令控制**：低频、离散、需要通过 ACK 确认“发送成功”。
- 尽量复用 `docs/skill_action.md` 已有的 `action_id`，避免再造一套动作编号。
- 对 `do_dog_behavior`、`set_fan`、`on_patrol` 等没有现成整数 ID 的能力，定义稳定的二进制编号。

## 2. 外层帧格式

沿用当前协议外层：

```text
0xAA55 | Type | Seq | Len | Payload | CRC16
```

- `Type`
  - `0x01` CMD
  - `0x02` STATE
  - `0x03` ACK
- `Seq`
  - 发送端递增，范围 `0..255`
- `Len`
  - `Payload` 长度，little-endian
- `CRC16`
  - `Type | Seq | Len | Payload` 的 CRC16-CCITT-FALSE

GATT 层保持不变：

- `cmd_char`：App 写入二进制 CMD 帧
- `state_char`：机器人 notify 下发 STATE / ACK 二进制帧

## 3. STATE 与 ACK

### 3.1 STATE

本阶段不改 STATE payload，仍沿用当前实现：

```text
battery:uint8 | roll:int16 | pitch:int16 | yaw:int16
```

- 姿态字段按 `x100` 缩放
- little-endian

### 3.2 ACK

本阶段不改 ACK payload，仍沿用：

```text
ack_seq:uint8
```

语义定义：

- **ACK 只表示“机器人端已正确收到并接受该 CMD 帧进入处理链路”**。
- 对“指令控制”，App 侧以收到相同 `seq` 的 ACK 作为“发送成功”判定。
- 若后续需要“动作执行成功/失败”语义，应新增结果事件或扩展状态通道，不建议复用 ACK。

## 4. CMD Payload 总览

| `cmd_id` | 名称 | 用途 |
| --- | --- | --- |
| `0x01` | `joystick_velocity` | 摇杆方向/转向控制，高频连续控制 |
| `0x10` | `stand` | 兼容保留：快速站立 |
| `0x11` | `sit` | 兼容保留：快速坐下 |
| `0x12` | `stop` | 兼容保留：快速停止 |
| `0x20` | `skill_invoke` | 统一指令入口，覆盖 `docs/skill_action.md` 中的技能/动作控制 |

说明：

- `0x10/0x11/0x12` 继续保留，作为最常用姿态指令的低延迟快捷命令。
- 复杂动作与技能统一进入 `0x20 skill_invoke`，避免后面继续碎片化新增 `cmd_id`。

## 5. 摇杆控制格式

`cmd_id = 0x01`

```text
cmd_id:uint8 | vx:int16 | vy:int16 | yaw:int16
```

- `vx`
  - 前后速度，单位抽象为 m/s，按 `x100` 缩放
- `vy`
  - 左右横移速度，按 `x100` 缩放
  - 若底层机器狗不支持横移，发送端固定写 `0`
- `yaw`
  - 旋转角速度，按 `x100` 缩放
- 全部 little-endian

示例：

- 前进 `0.60`、不横移、右转 `-0.20`

```text
01 3C 00 00 00 EC FF
```

发送策略：

- 摇杆命令属于高频控制，沿用现有“`move` 只保留最新值”的队列语义。
- 松开摇杆时发送一次零速度 `MOVE(0,0,0)` 或 `0x12 stop`，不要依赖最后一帧自然衰减。
- BLE 意外断开时，App 已无法再补发 stop；机器人端必须在 BLE central 断开事件上把 ROS 连续速度清零。当前 `robot_server` 已在 BLE 断开回调中执行该保护。
- 当前 STATE payload 没有“运行模式”字段。遥控页不能从 BLE STATE 精确判断真机是否已经进入运行模式，只能在新摇杆会话、重连、命令错误后保守重发 `enterMotionMode()`。

## 6. 指令控制格式

### 6.1 通用结构

`cmd_id = 0x20`

```text
cmd_id:uint8 | service_id:uint8 | op:uint8 | flags:uint8 | arg_len:uint8 | args[arg_len]
```

字段说明：

- `service_id`
  - 指向 `docs/skill_action.md` 中的具体能力域
- `op`
  - 执行动作、开始、停止、设置等操作
- `flags`
  - `bit0 = 1`：发送端需要等待 ACK 才把本次指令标记为“发送成功”
  - 其余 bit 预留，当前固定 `0`
- `arg_len`
  - `args` 长度
- `args`
  - 按 `service_id + op` 解释

对 UI 的建议：

- 所有按钮类离散指令都应设置 `flags.bit0 = 1`
- 只有收到匹配 `seq` 的 ACK，UI 才提示“已发送”
- ACK 超时走现有 `100ms * 3 次` 重传语义

### 6.2 `service_id` 定义

| `service_id` | 能力 | 来源 |
| --- | --- | --- |
| `0x01` | `do_action` | `docs/skill_action.md` 二、三节 |
| `0x02` | `do_dog_behavior` | `docs/skill_action.md` 四节 |
| `0x03` | `set_fan` | `docs/skill_action.md` 一节 |
| `0x04` | `on_patrol` | `docs/skill_action.md` 一节 |
| `0x05` | `phone_call` | `docs/skill_action.md` 一节 |
| `0x06` | `watch_dog` | `docs/skill_action.md` 一节 |
| `0x07` | `set_motion_params` | `docs/skill_action.md` 一、五节，先保留 |
| `0x08` | `smart_action` | `docs/skill_action.md` 一节，先保留 |

### 6.3 `op` 定义

| `op` | 语义 |
| --- | --- |
| `0x01` | `execute` |
| `0x02` | `start` |
| `0x03` | `stop` |
| `0x04` | `set` |

## 7. 各服务的 `args` 格式

### 7.1 `do_action` (`service_id = 0x01`, `op = 0x01 execute`)

```text
action_id:uint16
```

- 直接复用 `docs/skill_action.md` 中已有的 `action_id`
- 基础动作与扩展动作共用同一字段
- `uint16` 足够覆盖 `20736` 这类扩展动作 ID

示例：执行 `Jump (action_id=257)`

```text
20 01 01 01 02 01 01
```

解释：

- `20`：`skill_invoke`
- `01`：`do_action`
- `01`：`execute`
- `01`：需要 ACK
- `02`：参数长度 2
- `01 01`：`257` 的 little-endian

### 7.2 `do_dog_behavior` (`service_id = 0x02`, `op = 0x01 execute`)

```text
behavior_id:uint8
```

- `behavior_id` 采用本文件附录 A 的稳定编号
- 使用整数而不是字符串，减小 BLE payload 并避免 UTF-8/拼写歧义

示例：执行 `wave_hand`

```text
20 02 01 01 01 24
```

其中 `0x24 = 36 = wave_hand`

### 7.3 `set_fan` (`service_id = 0x03`, `op = 0x04 set`)

```text
enabled:uint8 | level:uint8
```

- `enabled`
  - `0` 关闭
  - `1` 开启
- `level`
  - `0..100`

### 7.4 `on_patrol` / `phone_call` / `watch_dog`

支持：

- `op = 0x02 start`
- `op = 0x03 stop`

```text
arg_len = 0
```

示例：启动巡逻

```text
20 04 02 01 00
```

### 7.5 `set_motion_params` (`service_id = 0x07`, `op = 0x04 set`)

该能力在 `docs/skill_action.md` 中只列出 topic 名称，没有给出精确参数范围，因此本阶段只先定义骨架：

```text
param_id:uint8 | value_count:uint8 | values:int16[value_count]
```

建议保留的 `param_id`：

| `param_id` | 参数 |
| --- | --- |
| `0x01` | `set_velocity` |
| `0x02` | `set_gait` |
| `0x03` | `set_body_position` |
| `0x04` | `set_rpy` |
| `0x05` | `set_foot_height` |
| `0x06` | `set_friction` |

说明：

- 只有在服务端明确每个参数的数值范围、缩放和单位后，才建议真正开放这类 BLE 指令。
- 在未补齐约束前，App 侧不应直接暴露该能力。

### 7.6 `smart_action` (`service_id = 0x08`)

`docs/skill_action.md` 没给出明确参数定义，因此本阶段只保留编号，不定义 `args` 细节。

## 8. 兼容策略

- 现有 `0x01 move`、`0x10 stand`、`0x11 sit`、`0x12 stop` 保持可用。
- 新增的高层动作/技能命令统一进入 `0x20 skill_invoke`。
- 已有 ACK / 队列 / stream decoder / CRC 逻辑可复用，不需要重新定义 BLE 基础帧。

## 9. 建议的首批实现范围

如果按最小闭环落地，建议优先只实现：

1. `0x01 joystick_velocity`
2. `0x10 stand`
3. `0x11 sit`
4. `0x12 stop`
5. `0x20 + service_id=0x01 do_action`
6. `0x20 + service_id=0x02 do_dog_behavior`

这样已经能覆盖：

- 摇杆方向/转向
- 常用站立/坐下/停止
- 绝大多数预设动作
- 绝大多数拟生物行为

其余 `set_fan` / `on_patrol` / `watch_dog` / `set_motion_params` 可在服务端桥接能力准备好后继续加。

## 附录 A：`do_dog_behavior` 编号表

| `behavior_id` | 行为名 |
| --- | --- |
| `0x01` | `confused` |
| `0x02` | `confused_again` |
| `0x03` | `recovery_balance_stand_1` |
| `0x04` | `recovery_balance_stand` |
| `0x05` | `recovery_balance_stand_high` |
| `0x06` | `force_recovery_balance_stand` |
| `0x07` | `force_recovery_balance_stand_high` |
| `0x08` | `recovery_dance_stand_and_params` |
| `0x09` | `recovery_dance_stand` |
| `0x0A` | `recovery_dance_stand_high` |
| `0x0B` | `recovery_dance_stand_high_and_params` |
| `0x0C` | `recovery_dance_stand_pose` |
| `0x0D` | `recovery_dance_stand_high_pose` |
| `0x0E` | `recovery_stand_pose` |
| `0x0F` | `recovery_stand_high_pose` |
| `0x10` | `wait` |
| `0x11` | `cute` |
| `0x12` | `cute_2` |
| `0x13` | `enjoy_touch` |
| `0x14` | `very_enjoy` |
| `0x15` | `eager` |
| `0x16` | `excited_2` |
| `0x17` | `excited` |
| `0x18` | `crawl` |
| `0x19` | `stand_at_ease` |
| `0x1A` | `rest` |
| `0x1B` | `shake_self` |
| `0x1C` | `back_flip` |
| `0x1D` | `front_flip` |
| `0x1E` | `left_flip` |
| `0x1F` | `right_flip` |
| `0x20` | `express_affection` |
| `0x21` | `yawn` |
| `0x22` | `dance_in_place` |
| `0x23` | `shake_hand` |
| `0x24` | `wave_hand` |
| `0x25` | `draw_heart` |
| `0x26` | `push_up` |
| `0x27` | `bow` |
