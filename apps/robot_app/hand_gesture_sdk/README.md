# hand_gesture_sdk

`hand_gesture_sdk` 是 `apps/robot_app` 内的独立 Flutter 视觉输入 SDK，用于在 Android / iOS 上打开相机识别手势和基础人体动作，并把识别结果输出为事件流和机器人控制建议。SDK 本身不直接控制机器狗，上层业务需要把 `commands` 转成 `mobile_sdk.RobotClient` 调用。

当前定位是 App 内嵌插件，不是独立发布到 pub.dev 的公共包。

## 功能范围

- 打开 / 关闭原生全屏识别页。
- 通过 MediaPipe 识别手势：张开手掌、握拳、胜利、指向、点赞。
- 通过 MediaPipe 识别基础姿态：站起、蹲下。
- 输出原始事件流：状态、手势、姿态、置信度和几何 metrics。
- 输出命令建议流：`move`、`modeChanged`、`stop`。
- 内置模型文件，运行时不需要联网下载模型。

## 目录结构

```text
hand_gesture_sdk/
├── lib/
│   ├── hand_gesture_sdk.dart                    # Dart 对外入口
│   ├── hand_gesture_sdk_event.dart              # 原始事件模型
│   ├── hand_gesture_sdk_command.dart            # 命令建议模型
│   ├── gesture_control_state.dart               # command / follow 双模式状态机
│   ├── hand_gesture_sdk_command_interpreter.dart # 只委托状态机的解释器
│   ├── hand_gesture_sdk_method_channel.dart     # Flutter MethodChannel / EventChannel 实现
│   └── hand_gesture_sdk_platform_interface.dart # 平台接口
├── android/src/main/kotlin/.../
│   ├── GestureActivity.kt                       # Android 相机、MediaPipe、识别页
│   ├── SkeletonOverlayView.kt                   # Android 骨架 overlay
│   └── HandGestureSdkPlugin.kt                  # Android 插件入口
├── ios/Classes/
│   ├── GestureViewController.swift              # iOS 相机、MediaPipe、识别页
│   ├── SkeletonOverlayView.swift                # iOS 骨架 overlay
│   └── HandGestureSdkPlugin.swift               # iOS 插件入口
├── test/                                        # Dart 单测
└── example/                                     # Flutter plugin 示例工程
```

## Dart API

入口类：

```dart
final sdk = HandGestureSdk.instance;

await sdk.startRecognition();
await sdk.stopRecognition();

sdk.events.listen((HandGestureEvent event) {
  // 原始识别事件
});

sdk.commands.listen((HandGestureCommand command) {
  // 上层可映射到 RobotClient 控制
});
```

`startRecognition()` 会打开原生全屏识别页；`stopRecognition()` 会关闭识别页。重复调用 `startRecognition()` 时，原生侧会复用当前识别页，不会重复打开多个页面。

## 事件模型

`HandGestureEvent` 字段：

| 字段 | 说明 |
| --- | --- |
| `type` | `status` / `ready` / `gesture` / `pose` / `error` |
| `message` | UI 可展示的信息 |
| `gesture` | 手势名称，例如 `张开手掌`、`握拳`、`胜利` |
| `pose` | 姿态名称，例如 `站起`、`蹲下` |
| `confidence` | 置信度，平台侧可选输出 |
| `metrics` | 几何指标，例如 `handDetected`、`handBBoxArea`、手部中心点、bbox 宽高 |
| `raw` | 原始 Map，便于调试和扩展 |

iOS / Android 原生侧通过 `EventChannel("hand_gesture_sdk/events")` 推送事件，Dart 侧在 `hand_gesture_sdk_method_channel.dart` 中转成 `HandGestureEvent`。

## 命令建议

`GestureCommandInterpreter` 在 Dart 层只委托 `GestureControlState`。状态机实现 `command` / `follow` 双模式，默认 `command`，不保留旧解释器的 350ms 冷却、面积 baseline ratio 触发或“胜利 900ms 进入 follow”路径。

| 输入 | 输出 |
| --- | --- |
| `command` 模式：`张开手掌` 高置信连续保持 2s | `modeChanged(follow)`，只切模式，不发运动命令；已在 `follow` 时不重复进入 |
| `command` 模式：`握拳` 高置信 | `HandGestureCommand.stop(message: "握拳停止移动")`；App 层映射为零速 `move(0,0,0)`，不是急停 |
| `command` 模式：`指向` 高置信且手部中心在画面左侧 / 右侧 | `move(vy: +/-0.25)`，上层短促执行后补零速；中心死区不输出 |
| `command` 模式：`胜利`、OK、点赞、一指、两指、三指等其它手势 | 不处理，不切模式、不下发运动 |
| `follow` 模式：`握拳` 高置信 | 立即 `stop`，App 层映射为零速 `move(0,0,0)` |
| `follow` 模式：`握拳` 高置信连续保持 2s | `modeChanged(command)`，只切模式，不发运动命令 |
| `follow` 模式：手部面积偏离中性面积 | 连续 `move(vx)`，面积变大前进，面积变小后退 |
| `follow` 模式：手部中心 x 偏离横向死区 | 连续 `move(vy)`，画面左侧 `vy > 0`、画面右侧 `vy < 0` |

`command` 模式首版只处理张开手掌、握拳和指向三类输入，避免胜利手势在 iOS 侧识别成功但无法稳定切换模式的问题。`follow` 模式持续输出 `move` 或零速 `move(0,0,0)`，包含面积熔断、2s 恢复和 200ms 横向抑制。SDK 只输出建议，不直接调用 `RobotClient`。

## 技术架构

```text
Flutter App
  -> HandGestureSdk.startRecognition()
    -> MethodChannel("hand_gesture_sdk")
      -> Android GestureActivity / iOS GestureViewController
        -> Camera preview
        -> MediaPipe HandLandmarker + PoseLandmarker
        -> SkeletonOverlayView
        -> EventChannel("hand_gesture_sdk/events")
  -> HandGestureSdk.events
  -> GestureCommandInterpreter
  -> HandGestureSdk.commands
  -> 上层业务映射到 mobile_sdk.RobotClient
```

平台层负责相机、模型推理、骨架绘制和原始事件。Dart 层负责事件模型、命令建议和上层集成边界。这样可以后续替换 Android / iOS 识别实现，而不影响 Flutter 业务侧调用。

## Android 实现

Android 主入口是 `android/src/main/kotlin/com/xinzhang/hand_gesture_sdk/GestureActivity.kt`。

关键实现：

- 使用 CameraX `Preview` + `ImageAnalysis`，默认前置摄像头。
- `GestureActivity` 固定为单一横屏 `landscape`，避免左右横屏自动旋转导致相机和 overlay 方向处理复杂化。
- `ImageAnalysis` 输出 RGBA buffer，按 `imageProxy.imageInfo.rotationDegrees` 先旋正 Bitmap。
- MediaPipe 使用 `RunningMode.VIDEO`，在 `modelExecutor` 中串行推理。
- `SkeletonOverlayView` 在预览之上绘制手部和人体关键点。
- 前置预览体验按镜像处理，overlay 设置 `setMirrorX(true)`。

Android 当前是已验证可用链路，修改 iOS 时应以 Android 的相机方向和 overlay 契约作为对照。

## iOS 实现

iOS 主入口是 `ios/Classes/GestureViewController.swift`。

关键实现：

- 使用 `AVCaptureSession` + `AVCaptureVideoDataOutput` 采集前置摄像头。
- `GestureViewController` 固定为 `.landscapeRight`，`shouldAutorotate = false`；关闭识别页后由 App 侧释放方向限制。
- session 配置和 `startRunning()` 必须走 `sessionQueue` 串行执行。
- `beginConfiguration()` / `commitConfiguration()` 必须完成后才能调用 `startRunning()`。
- `AVCaptureVideoDataOutput` 的 `videoOrientation` 会同步为当前界面方向。
- 送入 MediaPipe 的 `MPImage(sampleBuffer:orientation:)` 使用 `.up`，因为输出帧已经由 capture connection 旋正。
- preview layer 显式设置前置镜像；模型输入不镜像；overlay 通过 `setMirrorX(true)` 与镜像预览对齐。
- MediaPipe 使用 `runningMode = .liveStream`，timestamp 必须单调递增。

iOS 手势识别的关键约定：

- 不要同时在 `AVCaptureVideoDataOutput.connection.videoOrientation` 和 `MPImage.orientation` 两处补偿旋转，否则会出现骨架或手掌整体旋转 90 度。
- 当前约定是 video output 负责旋正，`MPImage.orientation` 固定 `.up`。
- 模型输入不做镜像；预览和 overlay 做镜像。
- 若以后改 `videoGravity = .resizeAspectFill` 或 overlay 映射，需要同步验证骨架是否仍贴合预览。

## 手势分类规则

平台侧根据 MediaPipe 手部 21 个关键点做规则分类。

当前 iOS 分类逻辑：

- 食指 / 中指 / 无名指 / 小指：用 `tip`、`pip`、`mcp` 三点的纵向关系判断是否伸直。
- 手掌：四根长指均伸直。
- 握拳：四根长指均弯曲。
- 胜利：食指和中指伸直，无名指和小指弯曲。
- 指向：仅食指伸直。
- 点赞：拇指向上或横向伸展，且其它长指多数弯曲。

当前规则是轻量启发式，适合演示和控制入口。若要提升复杂姿态准确率，优先考虑加入分类模型或更完整的时序平滑，不要只堆更多硬编码阈值。

## 模型资产

模型随平台包内置：

```text
ios/Resources/Models/hand_landmarker.task
ios/Resources/Models/pose_landmarker_lite.task
android/src/main/assets/models/hand_landmarker.task
android/src/main/assets/models/pose_landmarker_lite.task
```

如果移动模型路径，必须同步更新：

- Android `GestureActivity.HAND_MODEL_ASSET_PATH`
- Android `GestureActivity.POSE_MODEL_ASSET_PATH`
- iOS `bundleModelPath(named:subdirectory:)` 查找逻辑

## 与 Robot App 集成

App 入口在 `apps/robot_app/lib/src/gesture_module_page.dart`。

集成方式：

- 页面订阅 `HandGestureSdk.instance.events` 展示原始事件。
- 页面订阅 `HandGestureSdk.instance.commands` 展示命令建议。
- Flutter 手势模块页与原生相机识别页都会展示当前手势模式（`command` / `follow`）、`RobotClient` 连接状态、手势置信度 / 中心点 / 左中右位置诊断和最近一次机器人命令下发结果，便于排查“识别成功但机器狗未运动”的问题。
- `GestureModulePage` 接收当前 `RobotClient`，并把 `HandGestureCommand` 映射到 `RobotClient` 默认 last-wins API。
- `follow` 连续 `move` 在 App 层节流到约 10Hz；手势属于实时手动控制，不使用 `*Queued`。
- 原生识别页关闭时会发 `type == closed` 事件；App 收到后恢复 `SystemChrome` 方向偏好，避免横屏约束泄漏到其它页面。

## 权限与平台要求

宿主 App 必须声明相机权限。

iOS：

- `NSCameraUsageDescription`
- 如果与主 App 其它能力共用，还会涉及蓝牙、麦克风、语音识别权限，但手势 SDK 本身只依赖相机。

Android：

- `android.permission.CAMERA`

## 测试

Dart 单测：

```bash
cd /path/to/robot_factory/apps/robot_app/hand_gesture_sdk
flutter test
```

宿主 App iOS 构建：

```bash
cd /path/to/robot_factory/apps/robot_app
flutter build ios --no-codesign
```

安装到已连接 iPhone：

```bash
cd /path/to/robot_factory/apps/robot_app
flutter run -d <device-id> --release
```

查看设备：

```bash
cd /path/to/robot_factory/apps/robot_app
flutter devices
```

## 真机验收清单

每次修改相机、坐标、镜像、模型或分类规则后，至少在真机验证：

- Android：打开识别页后相机正常启动。
- Android：张开手掌、握拳、胜利、指向、点赞可识别。
- Android：骨架关键点贴合预览手部，没有整体旋转或左右错位。
- iOS：打开识别页后相机正常启动，没有 `AVCaptureSession startRunning` 异常。
- iOS：张开手掌、握拳、胜利、指向、点赞可识别。
- iOS：骨架关键点贴合预览手部，没有整体旋转 90 度。
- iOS：预览是前置镜像体验，overlay 与预览一致。
- 关闭识别页后再次打开，不应重复创建多个识别页或卡住相机会话。

## 常见问题

### iOS 报 `startRunning may not be called between calls to beginConfiguration and commitConfiguration`

原因是 `AVCaptureSession.startRunning()` 在配置窗口内被调用。必须保证 `beginConfiguration()` / `commitConfiguration()` 完成后，再在同一个串行 session 队列调用 `startRunning()`。

### iOS 骨架或手掌像旋转了 90 度

优先检查 `AVCaptureVideoDataOutput.connection.videoOrientation` 和 `MPImage.orientation`。当前约定是 output connection 负责旋正，`MPImage.orientation` 固定 `.up`。不要在两处同时补偿旋转。

### iOS 骨架左右反了

先区分模型输入和视觉展示。当前约定是模型输入不镜像，预览和 overlay 镜像。如果要改，需要同时检查 `previewLayer.connection.isVideoMirrored` 和 `SkeletonOverlayView.setMirrorX(true)`。

### 骨架方向正确但位置偏移

通常和 `AVCaptureVideoPreviewLayer.videoGravity = .resizeAspectFill` 的裁剪有关。需要让 `SkeletonOverlayView.mapPoint` 按 preview layer 的实际裁剪比例补偿，而不是直接 `x * width` / `y * height`。

## 修改注意事项

- 不要让 SDK 直接依赖 `mobile_sdk.RobotClient`；SDK 只输出视觉事件和命令建议。
- 不要在 Dart 层绕过平台 channel 直接做相机逻辑。
- 修改 iOS 相机方向时，同步验证 preview、MediaPipe 输入和 overlay 三者。
- 修改手势名称时，同步更新 `GestureControlState` 和测试。
- 修改事件字段时，同步 Android / iOS metrics 契约与 `HandGestureEvent.fromMap`。
- 修改命令建议节流参数时，补充 `gesture_control_state_test.dart`。
