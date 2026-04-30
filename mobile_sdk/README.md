# mobile_sdk

`mobile_sdk` 是 Flutter / Dart 侧统一控制 SDK，对外收敛机器狗连接、命令下发、状态订阅和连接状态管理。

## 当前能力

- `RobotClient.connectBLE()` / `connectTCP()` / `connectMQTT()`
- `RobotClient.move()` / `emergencyStop()` / `enterMotionMode()` / `recover()` / `stand()` / `sit()` / `stop()`
- `RobotClient.moveQueued()` / `standQueued()` / `sitQueued()` / `stopQueued()` / `doActionQueued()` / `doDogBehaviorQueued()` 等编排 API，用于图形化编程顺序执行
- `RobotClient.doAction(actionId)` / `doDogBehavior(behavior)`
- `RobotClient.stateStream` / `frameStream` / `errors` / `connectionState`
- BLE 扫描：`RobotClient.scanBLE()`
- 命令队列：默认控制 API 是 last-wins，会清掉尚未发送的待处理命令，只保留最后一次手动输入；`*Queued` API 保留 FIFO 顺序语义，供图形化编程 / 动作编排使用；ACK 超时重试默认 100ms、最多 3 次。
- 连接状态模型：`RobotConnectionState`
- 重连策略扩展点：`ReconnectPolicy`
- BLE 命令容错：单次 `send` 写入异常先作为命令级错误上报并交给 ACK 重试处理；只有 transport 已经处于断开状态时，才触发连接失败 / 重连流程，避免一个命令失败直接拆掉 BLE 连接。

## 当前实现

- BLE：基于 `flutter_blue_plus`，已实现扫描、连接、service/characteristic 发现、通知订阅、二进制帧收发，并已用于客户端搜索 / 连接 / 数据交互验证。
- TCP：基于 `Socket`，已实现连接、stream decoder、断开上抛。
- MQTT：基于 `mqtt_client`，已实现 `robot/{id}/control|state|event` topic 约定、二进制 state 解码与 JSON event 订阅。
- 协议层直接复用 `protocol/dart`。
- 高层动作类命令会编码为 `0x20 skill_invoke`，当前已接 `do_action` / `do_dog_behavior`；`emergencyStop()` / `enterMotionMode()` / `recover()` 分别映射到 `do_action(action_id=0)` / `do_action(action_id=4)` / `do_action(action_id=3)`。

## 当前限制

- 还没有真正的“自动多传输回退”流程；`RobotConnectionConfig.priority` 当前只负责选择连接目标，不会在失败后自动逐个 transport 兜底。
- App 侧业务应优先通过 `RobotClient` 使用 SDK，transport 细节不应直接成为 UI 层依赖。
- ACK 仍只表示机器人端接受命令进入本地处理链，不表示真机动作执行成功；命令处理失败会走 `errors` Stream 和重试语义，不应被 UI 当作 BLE 连接必然断开。
- 真正的端到端质量仍取决于机器人侧 BLE / MQTT / ROS 环境是否可用，本模块的单测不能替代真机验证。

## 测试

```bash
cd /path/to/robot_factory/mobile_sdk
flutter pub get
flutter test
```
