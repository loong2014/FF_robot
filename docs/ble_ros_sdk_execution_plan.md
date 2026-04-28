# BLE -> ROS 桥接与客户端 SDK 执行方案

> 目的：把下一步要做的两件事收敛成一份可直接执行的实施方案。
>
> 目标：
> 1. 机器狗端通过 BLE 接收二进制控制命令后，转换成 ROS 控制消息执行。
> 2. 提供给客户端使用的 SDK，封装 BLE 连接、数据发送/接收，并对外暴露高层接口，如 `connect`、`disconnect`、`doAction`、`doDogBehavior`。

相关文档：

- 协议格式：[`docs/ble_control_data_format.md`](ble_control_data_format.md)
- 技能/动作来源：[`docs/skill_action.md`](skill_action.md)
- 当前 BLE 联调说明：[`docs/ble_integration.md`](ble_integration.md)
- 机器人话题清单：[`docs/rostopic_list.md`](rostopic_list.md)

---

## 1. 当前基线

### 1.1 已有能力

- `protocol` 已有外层帧格式、CRC16、stream decoder、ACK、STATE 编解码。
- `protocol` 已支持 `0x20 skill_invoke` 的一期子集：`do_action` / `do_dog_behavior`。
- `robot_server` 已能通过 BLE 接收 `move/stand/sit/stop` 与 `skill_invoke`。
- `robot_server` 当前已支持把 `MoveCommand` 转成 ROS motion topic；AlphaDog 默认使用 `/alphadog_node/set_velocity`，并保留 `/cmd_vel` 作为兼容回退。
- `robot_server` 已支持把 `stand/sit/stop` 与 `skill_invoke` 桥接到 `/agent_skill/.../execute`。
- `mobile_sdk` 已具备 BLE 连接、发包、收包、ACK 重试和状态流基础能力。

### 1.2 当前缺口

- `mobile_sdk` 还没有一层对外友好的高层接口文件，客户端目前只能操作低层 `RobotClient.move/stand/sit/stop`。
- 当前 ACK 已收口为“命令成功进入 server 本地处理链”的确认，但还不是动作执行完成确认。

---

## 2. 一期范围

一期只做最小闭环，先把 BLE 指令到 ROS 和 SDK 高层接口打通。

### 2.1 纳入一期

- 摇杆控制
  - `move(vx, vy, yaw)`
  - `stop()`
- 基础姿态
  - `stand()`
  - `sit()`
- 技能动作
  - `doAction(actionId)`
  - `doDogBehavior(behavior)`
- 客户端 SDK 高层接口
  - `connect()`
  - `disconnect()`
  - `move()`
  - `stop()`
  - `stand()`
  - `sit()`
  - `doAction()`
  - `doDogBehavior()`

### 2.2 暂不纳入一期

- `setFan`
- `onPatrol`
- `phoneCall`
- `watchDog`
- `setMotionParams`
- ROS 执行结果回传
- BLE 以外 transport 的同等高层封装

---

## 3. 目标架构

```text
App / Client
  -> mobile_sdk 高层 API
  -> protocol(dart) 编码 CMD 帧
  -> BLE cmd_char
  -> robot_server BLE transport
  -> protocol(python) 解码 CMD 帧
  -> RobotControlService
  -> RosControlBridge / RosSkillBridge
  -> ROS topics / action goal topics
```

分流规则：

- 摇杆控制命令
  - 进入 `RosControlBridge`
  - AlphaDog 默认走 `/alphadog_node/set_velocity`
- 技能/动作命令
  - 进入新增的 `RosSkillBridge`
  - 发布到 `/agent_skill/do_action/execute/goal`
  - 或 `/agent_skill/do_dog_behavior/execute/goal`

---

## 4. 协议实施方案

协议以 [`docs/ble_control_data_format.md`](ble_control_data_format.md) 为准。

### 4.1 保持不变

- 外层帧：
  - `0xAA55 | Type | Seq | Len | Payload | CRC16`
- `ACK` payload：
  - `ack_seq:uint8`
- `STATE` payload：
  - `battery:uint8 | roll:int16 | pitch:int16 | yaw:int16`

### 4.2 一期要落地的 CMD

- `0x01 joystick_velocity`
  - `vx:int16 | vy:int16 | yaw:int16`
- `0x10 stand`
- `0x11 sit`
- `0x12 stop`
- `0x20 skill_invoke`
  - `service_id | op | flags | arg_len | args`

### 4.3 一期只实现的 `skill_invoke`

- `service_id = 0x01 do_action`
  - `args = action_id:uint16`
- `service_id = 0x02 do_dog_behavior`
  - `args = behavior_id:uint8`

### 4.4 ACK 语义

一期建议调整为：

- 服务端**成功解析命令并成功进入 server 本地处理链（含对应 bridge 成功接收）后**再回 ACK
- 若解析失败或 ROS bridge 拒绝发送，则不回 ACK，由客户端走超时失败

注意：

- 这仍然只是“发送成功/桥接成功”
- 不是“机器人动作执行完成”
- 真正执行结果回传放到二期再做

---

## 5. 服务端实施方案

### 5.1 核心思路

在现有 `RosControlBridge` 之外，新加一层 `RosSkillBridge`：

- `RosControlBridge`
  - 负责摇杆速度类控制
  - AlphaDog 默认发 `/alphadog_node/set_velocity`
- `RosSkillBridge`
  - 负责 `do_action` / `do_dog_behavior`
  - 直接发布 `agent_msgs/ExecuteActionGoal`

### 5.2 一期推荐桥接目标

#### 摇杆控制

AlphaDog 机型直接适配原生运动 topic：

- `/alphadog_node/set_velocity`

原因：

- 机器人实测的运动 subscriber 就在这个 topic 上
- `RosControlBridge` 已支持按 topic 选择消息类型
- 能避免 `/cmd_vel` 空发但本体不动的假闭环

兼容说明：

- `RosControlBridge` 仍保留 `/cmd_vel` 的兼容路径，便于其他机型复用

#### 动作/行为控制

按 `docs/skill_action.md` 里的示例桥接：

- `do_action`
  - 目标 topic：`/agent_skill/do_action/execute/goal`
- `do_dog_behavior`
  - 目标 topic：`/agent_skill/do_dog_behavior/execute/goal`

消息类型：

- `agent_msgs/ExecuteActionGoal`

消息构造要点：

- `goal.invoker`
  - 默认如 `mobile_sdk`
- `goal.invoke_priority`
  - 先给固定默认值，如 `25`
- `goal.hold_time`
  - `do_action` 默认 `5.0`
  - `do_dog_behavior` 默认 `5.0`
- `goal.args`
  - JSON 字符串
  - `do_action`：`{"action_id": 20739}`
  - `do_dog_behavior`：`{"behavior": "wave_hand"}`

### 5.3 服务端代码改动点

#### `protocol/python`

- 新增高层命令模型：
  - `SkillInvokeCommand`
  - `ServiceId`
  - `Operation`
  - `DogBehavior`
- 新增 `0x20 skill_invoke` 的编解码

#### `robot_server/robot_server/ros/`

- 新增 `skill_bridge.py`
  - `RosSkillBridge`
  - 内部维护 ROS publishers
  - 负责构造 `ExecuteActionGoal`

#### `robot_server/robot_server/runtime/control_service.py`

- 解析后分派：
  - `MoveCommand` -> `RosControlBridge`
  - `DiscreteCommand` -> 原逻辑
  - `SkillInvokeCommand` -> `RosSkillBridge`
- ACK 时机后移：
  - bridge 成功接收后 ACK
  - 失败则不 ACK

#### `robot_server/robot_server/app.py`

- 在 `build_runtime()` 里装配 `RosSkillBridge`

#### `robot_server/robot_server/config.py`

为 `RosSkillBridge` 加配置：

- `ROBOT_ROS_SKILL_ENABLED=true/false`
- `ROBOT_ROS_ACTION_GOAL_TOPIC=/agent_skill/do_action/execute/goal`
- `ROBOT_ROS_BEHAVIOR_GOAL_TOPIC=/agent_skill/do_dog_behavior/execute/goal`
- `ROBOT_ROS_SKILL_INVOKER=mobile_sdk`
- `ROBOT_ROS_SKILL_PRIORITY=25`
- `ROBOT_ROS_SKILL_HOLD_TIME=5.0`

### 5.4 服务端一期验收标准

- BLE 收到 `do_action(actionId)` 后能发出对应 ROS goal topic
- BLE 收到 `do_dog_behavior(behavior)` 后能发出对应 ROS goal topic
- 成功发出 topic 时客户端能收到 ACK
- 解析失败或 bridge 失败时客户端拿不到 ACK，并按超时失败

---

## 6. SDK 实施方案

### 6.1 目标

对客户端提供一层更稳定、简单的高层 SDK，调用方不需要直接处理 BLE 包、协议帧和重试逻辑。

### 6.2 对外接口设计

建议新增高层 facade，例如：

```dart
abstract class AlphaDogSdk {
  Future<void> connect({required BleConnectionOptions options});
  Future<void> disconnect();

  Future<void> move({
    required double vx,
    double vy = 0,
    required double yaw,
  });

  Future<void> stop();
  Future<void> stand();
  Future<void> sit();

  Future<CommandAck> doAction({
    required int actionId,
    SkillInvokeOptions options = const SkillInvokeOptions(),
  });

  Future<CommandAck> doDogBehavior({
    required DogBehavior behavior,
    SkillInvokeOptions options = const SkillInvokeOptions(),
  });

  Stream<RobotState> get stateStream;
  Stream<RobotConnectionState> get connectionState;
  Stream<Object> get errors;
}
```

### 6.3 SDK 分层建议

#### 保留现有低层

- `RobotClient`
  - 继续负责 transport、命令队列、ACK、重试、状态流

#### 新增高层

- `AlphaDogSdk`
  - 对外高层接口
- `AlphaDogSdkImpl`
  - 内部组合 `RobotClient`
  - 把高层方法转换成协议命令

### 6.4 参数设计

#### `doAction`

```dart
Future<CommandAck> doAction({
  required int actionId,
  SkillInvokeOptions options = const SkillInvokeOptions(),
});
```

原因：

- `action_id` 很多，且有扩展动作
- 用 `int` 比 enum 更实用

#### `doDogBehavior`

```dart
Future<CommandAck> doDogBehavior({
  required DogBehavior behavior,
  SkillInvokeOptions options = const SkillInvokeOptions(),
});
```

原因：

- 行为数量有限
- enum 更适合 SDK 使用
- 也能和协议里的 `behavior_id` 映射

#### `SkillInvokeOptions`

一期先保留：

- `invoker`
- `priority`
- `holdTime`

注意：

- 这三个字段一期不一定编码进 BLE payload
- 也可以先由服务端配置统一注入
- 如果二期需要客户端细化控制，再扩进协议

### 6.5 SDK 代码改动点

#### `protocol/dart`

- 补 `SkillInvokeCommand`
- 补 `ServiceId` / `Operation` / `DogBehavior`
- 增加 `0x20 skill_invoke` 编解码

#### `mobile_sdk/lib/src/robot_client.dart`

- 保持低层能力
- 只新增一个通用内部入口：
  - `_sendCommand(RobotCommand command)`

#### `mobile_sdk`

- 新增高层文件，例如：
  - `lib/src/alphadog_sdk.dart`
  - `lib/src/models/skill_invoke_options.dart`
  - `lib/src/models/command_ack.dart`

#### `mobile_sdk/lib/mobile_sdk.dart`

- 调整 export
- 对外优先暴露高层 facade
- 尽量减少 transport 直接暴露

### 6.6 SDK 一期验收标准

- 客户端可直接调用：
  - `connect()`
  - `disconnect()`
  - `move()`
  - `stand()`
  - `sit()`
  - `stop()`
  - `doAction()`
  - `doDogBehavior()`
- 调用方不需要自己拼二进制 payload
- 指令类接口能以 ACK 作为“发送成功”判定

---

## 7. 测试方案

### 7.1 协议层

Python + Dart 都要补：

- `SkillInvokeCommand` round-trip
- `do_action` payload round-trip
- `do_dog_behavior` payload round-trip
- 非法 `service_id` / `behavior_id` / `arg_len` 报错

### 7.2 服务端

优先做 fake publisher / fake bridge 单测：

- 收到 `do_action` 命令，是否调用 `RosSkillBridge.publish_action(action_id)`
- 收到 `do_dog_behavior` 命令，是否调用 `RosSkillBridge.publish_behavior(behavior)`
- 发送成功后是否 ACK
- bridge 抛错后是否不 ACK

### 7.3 SDK

- `doAction()` 是否发出正确二进制 payload
- `doDogBehavior()` 是否发出正确二进制 payload
- 收到 ACK 后 Future 是否完成
- ACK 超时是否失败
- `move()` 是否仍保持 latest-only 语义

---

## 8. 实施顺序

建议严格按这个顺序做，避免 UI 先走在协议和服务端前面：

1. `protocol/python` 与 `protocol/dart`
   - 先加新命令模型和编解码
2. `robot_server`
   - 加 `RosSkillBridge`
   - 改 `RobotControlService`
   - 调整 ACK 时机
3. `mobile_sdk`
   - 新增高层 facade
   - 封装 `doAction/doDogBehavior`
4. 测试
   - 协议单测
   - 服务端 bridge 单测
   - SDK 单测
5. App 接入
   - 最后再把现有 App 改成调高层 SDK

---

## 9. 关键风险

### 9.1 ACK 语义风险

一期 ACK 只能表示：

- 服务端收到了命令
- 成功把命令推入 ROS 发送链路

它不能表示：

- 机器狗动作执行完成
- 行为执行成功

如果后续需要执行结果，必须新增事件/result 通道。

### 9.2 摇杆 ROS 目标不确定

当前仓库已有兼容的 `/cmd_vel` 路径，但 AlphaDog 原生运动 topic 是：

- `/alphadog_node/set_velocity`

所以一期建议：

- AlphaDog 优先直接用原生 motion topic 完成闭环
- 其他机型可继续走 `/cmd_vel` 兼容路径

### 9.3 ROS 消息依赖风险

如果目标机缺少：

- `agent_msgs`
- `geometry_msgs`

则：

- `RosSkillBridge` 或 `RosControlBridge` 无法真正运行

因此服务端实现时要做：

- import 容错
- 启动时清晰日志
- 单测下的 fake message 注入

---

## 10. 完成标准

做到以下几点，即可认为一期闭环完成：

1. BLE 收到 `move/stop/stand/sit/doAction/doDogBehavior` 命令后，服务端能正确解析。
2. 摇杆控制能进入 ROS 控制桥。
3. `doAction/doDogBehavior` 能发布到对应 `/agent_skill/.../execute/goal`。
4. 客户端 SDK 提供高层接口，不再要求调用方直接处理协议帧。
5. 指令类方法能基于 ACK 返回“发送成功/失败”。
6. `protocol`、`robot_server`、`mobile_sdk` 都有对应单测。

---

## 11. 建议的首个执行任务

下次如果直接开工，建议从这条开始：

> 按 `docs/ble_ros_sdk_execution_plan.md` 与 `docs/ble_control_data_format.md`，
> 先实现 `protocol/python` 和 `protocol/dart` 的 `SkillInvokeCommand`、
> `ServiceId`、`DogBehavior`、`0x20 skill_invoke` 编解码，
> 并补 Python / Dart round-trip 单测；暂不改 App UI。

这样可以先把协议层锁死，再往 `robot_server` 和 `mobile_sdk` 上叠。
