# hand_gesture_sdk 方案计划

## 目标

把 `hand_gesture_sdk` 做成一个独立的视觉输入 SDK，负责：

- 相机识别手势和基础动作
- 输出统一事件流
- 输出可供上层消费的机器狗控制命令建议

SDK 本身不直接依赖 `mobile_sdk` 或 `RobotClient`，也不直接调用协议层发送控制帧。  
上层 App / 业务层拿到 SDK 事件后，再通过协议层接口控制机器狗。

## 需求范围

### 手势能力

- `张开手掌`
- `握拳`
- `胜利`
- `指向`
- `点赞`

### 动作能力

- `远离`
- `接近`
- `平移左`
- `平移右`
- `站起`
- `蹲下`
- `跟随`

### 对外输出

SDK 统一输出两类东西：

- 原始感知事件：`status` / `gesture` / `pose`
- 规范化命令事件：`command`

命令事件建议使用以下语义：

- `move`：连续控制，附带 `vx / vy / yaw`
- `stand`
- `sit`
- `follow`
- `stop`

## 长期技术路线

### 目标方案

最终目标是双端原生 MediaPipe：

- Android：MediaPipe Tasks Vision 原生接入
- iOS：MediaPipe Tasks Vision 原生接入

这样可以避免 WebView 方案在性能、权限、网络依赖上的不稳定性。

### 当前实现策略

当前优先做两件事：

1. 稳定 SDK 的事件契约和命令契约
2. 让 Android / iOS 共享同一套原始事件解释逻辑，但各自使用原生相机与 MediaPipe 识别实现

这样上层消费方可以先接入，不被具体识别引擎实现绑定。

## 实施阶段

### Phase 1：契约和事件模型

目标：

- 定义统一事件结构
- 定义命令结构
- 让 Dart 层能稳定解析平台返回的数据

产物：

- `HandGestureEvent`
- `HandGestureCommand`
- 命令映射工具
- 测试覆盖

### Phase 2：跨平台识别运行时

目标：

- Android / iOS 都能打开识别页
- 识别页使用平台原生相机与识别引擎
- 在原生层完成手势 / 动作识别

产物：

- Android 原生入口
- iOS 原生入口
- 统一事件协议
- MediaPipe 识别和命令生成

### Phase 3：原生 MediaPipe 替换

目标：

- 去掉 WebView 依赖
- Android / iOS 直接使用原生 MediaPipe Tasks Vision
- 保持 Phase 1 的事件契约不变
- 模型文件随包内置，不依赖运行时联网下载

产物：

- Android 原生识别实现
- iOS 原生识别实现
- 同样的事件协议输出

### Phase 4：上层接入

目标：

- App 或其他业务方订阅 SDK 命令事件
- 通过协议层接口把命令转换成机器人控制

原则：

- SDK 不直接依赖机器人控制实现
- 机器人控制留在消费方

## 命令建议

### 连续控制

- `接近` -> `move(vx > 0)`
- `远离` -> `move(vx < 0)`
- `平移左` -> `move(vy > 0)`
- `平移右` -> `move(vy < 0)`

### 离散控制

- `站起` -> `stand`
- `蹲下` -> `sit`
- `跟随` -> `follow`
- `握拳` -> `stop`

## 验收标准

1. Android 设备可打开识别页并输出事件。
2. iOS 设备可打开识别页并输出事件。
3. Dart 层能稳定解析 `gesture` / `pose` / `command`。
4. 上层业务可以仅通过事件流把命令映射到协议层接口。
5. SDK 与机器人控制逻辑解耦。

## 风险

- Android / iOS 的真机相机权限和前置摄像头行为需要实机确认。
- 识别页依赖随包内置的 MediaPipe 模型资源，资源加载失败时要能降级报错。
- 连续控制需要做去抖和节流，否则容易抖动误触发。
