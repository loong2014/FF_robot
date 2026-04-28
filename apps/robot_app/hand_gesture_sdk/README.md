# hand_gesture_sdk

`hand_gesture_sdk` 是一个独立的 Flutter 视觉输入 SDK，用于手势识别和基础动作识别。

## 支持平台

- Android
- iOS

## 对外能力

- `startRecognition()`：打开识别页
- `stopRecognition()`：关闭识别页
- `events`：原始事件流，包含 `status` / `gesture` / `pose`
- `commands`：命令建议流，输出 `move` / `stand` / `sit` / `follow` / `stop`

## 识别能力

- 手势：张开手掌、握拳、胜利、指向、点赞
- 动作：远离、接近、平移左、平移右、站起、蹲下、跟随

## 架构说明

当前实现是“契约优先”的 SDK：

- 平台层负责采集相机与识别结果
- Dart 层负责把原始事件解释成命令建议
- 上层业务再通过协议层接口控制机器狗
- MediaPipe 模型随包内置，不依赖运行时联网下载

这样 SDK 与机器人控制逻辑保持解耦，后续替换 Android / iOS 的识别引擎时不需要修改上层接口。

## 运行

在 `apps/robot_app` 中直接打开“手势识别模块”即可。

## 测试

```bash
cd /path/to/robot_factory/apps/robot_app
flutter test hand_gesture_sdk/test
```
