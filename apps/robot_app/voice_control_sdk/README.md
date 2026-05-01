# voice_control_sdk

`voice_control_sdk` 是 `apps/robot_app` 内的独立 Flutter 语音输入 SDK，用于在 Android / iOS 上采集麦克风音频，并通过 Sherpa ONNX 离线完成 `KWS + ASR + VAD` 双阶段语音控制。SDK 本身不直接控制机器狗，上层业务需要把 `VoiceCommandEvent` 转成 `mobile_sdk.RobotClient` 调用。

当前定位是 App 内嵌插件，不是独立发布到 pub.dev 的公共包。

## 功能范围

- 启动 / 停止麦克风监听。
- 基于 Sherpa ONNX Keyword Spotter 识别唤醒词，默认唤醒词为 `Lumi`。
- 支持 `Lumi` 的英文、中文和中英混合唤醒别名，例如 `Lumi`、`loo me`、`露米`、`卢米`、`lu mi`。
- 唤醒后切换到 streaming ASR，持续识别到静音结束或超时。
- 使用 Silero VAD 判断命令语音是否开始和结束。
- 输出事件流：状态、唤醒、ASR 转写、命令、错误和遥测。
- 输出命令事件：站起、坐下、停止、前进、后退、左移、右移。
- 模型文件内置在插件 assets 中，运行时不需要联网下载。

## 目录结构

```text
voice_control_sdk/
├── lib/
│   ├── voice_control_sdk.dart                  # Dart 对外入口
│   └── src/
│       ├── voice_backend.dart                  # Sherpa KWS + ASR + VAD 编排
│       ├── voice_controller.dart               # 上层控制器
│       ├── voice_models.dart                   # 事件、配置、枚举模型
│       ├── voice_wake_mapper.dart              # 唤醒词别名和 keywords 生成
│       ├── voice_command_mapper.dart           # ASR 文本到命令的映射
│       ├── voice_control_sdk_method_channel.dart
│       └── voice_control_sdk_platform_interface.dart
├── android/src/main/kotlin/.../
│   ├── VoiceControlSdkPlugin.kt                # Android 插件入口与权限请求
│   ├── VoiceListeningService.kt                # Android 前台服务音频采集
│   ├── VoiceEventHub.kt                        # Android EventChannel 分发
│   └── VoiceConfig.kt                          # Android 原生配置模型
├── ios/Classes/
│   ├── VoiceControlSdkPlugin.swift             # iOS 插件入口
│   └── VoiceListeningCoordinator.swift         # iOS 前台音频采集
├── assets/voice_models/                        # KWS / ASR / VAD 模型
└── test/                                       # Dart 单测
```

## Dart API

入口类：

```dart
final controller = VoiceController();

final granted = await controller.ensurePermissions();
if (granted) {
  await controller.startListening(
    config: const VoiceConfig(wakeWord: 'Lumi'),
  );
}

controller.onWake.listen((VoiceWakeEvent event) {
  // 唤醒词命中
});

controller.onAsr.listen((VoiceAsrEvent event) {
  // ASR 实时或最终转写
});

controller.onCommand.listen((VoiceCommandEvent event) {
  // 上层可映射到 RobotClient last-wins 控制
});

await controller.stopListening();
await controller.dispose();
```

`startListening()` 会先在 Dart 层加载 / 复制 Sherpa 模型，再启动平台侧音频采集。重复调用时会先停止当前运行时并重建 Sherpa session。

## 事件模型

`VoiceEvent` 主要子类型：

| 类型 | 说明 |
| --- | --- |
| `VoiceStateEvent` | 监听状态、提示文案、是否正在监听、是否处于命令识别阶段 |
| `VoiceWakeEvent` | 唤醒词命中结果、唤醒词、别名 label、语言和置信度 |
| `VoiceAsrEvent` | ASR 转写文本、语言、置信度、是否最终结果 |
| `VoiceCommandEvent` | 命令枚举、原始文本、归一化文本、语言和置信度 |
| `VoiceErrorEvent` | 错误码、错误信息和恢复建议 |
| `VoiceTelemetryEvent` | 调试遥测事件 |

平台侧只负责推送 `audio` / `state` / `error` / `telemetry` 事件。Dart 层把 `audio` 事件送入 Sherpa，并产出 `wake`、`asr` 和 `command` 事件。

## 命令映射

`VoiceCommandMapper` 在 Dart 层只把最终 ASR 文本解释为机器人控制命令；partial ASR 只用于 UI。低于 0.70 置信度的最终结果会丢弃，同一命令 1 秒内重复出现只触发一次。

| 输入示例 | 输出 |
| --- | --- |
| `站起来` / `stand up` | `VoiceCommand.standUp` |
| `坐下` / `sit down` | `VoiceCommand.sitDown` |
| `停止` / `stop` | `VoiceCommand.stop` |
| `前进` / `move forward` | `VoiceCommand.forward` |
| `后退` / `go backward` | `VoiceCommand.backward` |
| `左移` / `move left` | `VoiceCommand.left` |
| `右移` / `move right` | `VoiceCommand.right` |

SDK 只输出命令事件，不直接调用 `RobotClient`。主 App 若要真正控制机器狗，应在页面或全局服务中订阅 `VoiceController.onCommand`，再调用 `VoiceActionMapper.execute()` 或直接调用 `RobotClient`。手动语音控制应使用 `RobotClient` 默认 last-wins API；如果语音命令被用于图形化编排，必须显式使用 `*Queued` API。

## 技术架构

```text
Flutter App
  -> VoiceController.startListening()
    -> SherpaVoiceBackend
      -> copy package assets to app support directory
      -> KeywordSpotter(KWS)
      -> OnlineRecognizer(ASR)
      -> VoiceActivityDetector(VAD)
      -> MethodChannel("voice_control_sdk")
        -> Android VoiceListeningService / iOS VoiceListeningCoordinator
          -> Microphone PCM stream
          -> EventChannel("voice_control_sdk/events")
      -> VoiceEvent stream
  -> 上层业务映射到 mobile_sdk.RobotClient
```

Android / iOS 平台层负责权限和麦克风 PCM 采集。Sherpa 推理、唤醒状态机、VAD 结束判断、ASR 文本归一化和命令映射均在 Dart 层完成。

## Android 实现

Android 主入口是 `android/src/main/kotlin/com/xinzhang/voice_control_sdk/VoiceControlSdkPlugin.kt` 和 `VoiceListeningService.kt`。

关键实现：

- `ensurePermissions()` 请求 `RECORD_AUDIO`；Android 13+ 同时请求 `POST_NOTIFICATIONS`。
- `startListening()` 启动 `VoiceListeningService` 前台服务。
- `VoiceListeningService` 使用 `AudioRecord` + `MediaRecorder.AudioSource.VOICE_RECOGNITION` 采集单声道 PCM16。
- 默认采样率来自 `VoiceConfig.sampleRate`，当前为 16000 Hz。
- 前台服务类型为 `microphone`，通知 channel 为 `voice_control_sdk`。
- 音频通过 `EventChannel("voice_control_sdk/events")` 以 `audio` 事件持续送回 Dart。

Android 宿主 App 必须声明：

- `android.permission.RECORD_AUDIO`
- `android.permission.FOREGROUND_SERVICE`
- `android.permission.FOREGROUND_SERVICE_MICROPHONE`
- `android.permission.POST_NOTIFICATIONS`（Android 13+ 运行时还需授权）

## iOS 实现

iOS 主入口是 `ios/Classes/VoiceListeningCoordinator.swift`。

关键实现：

- 通过 `AVAudioSession.requestRecordPermission` 请求麦克风权限。
- `AVAudioSession` 配置：`category = .playAndRecord`，`mode = .voiceChat`，`options = [.duckOthers]` 加上 BT 选项（iOS 17+ 用 `.allowBluetoothHFP`，老系统 fallback 到 `.allowBluetooth`）。`.voiceChat` 模式启用系统级 AGC、降噪与回声消除，与 Android 侧 `MediaRecorder.AudioSource.VOICE_RECOGNITION` 在语音识别场景下的语义对齐，确保 Sherpa KWS 能拿到电平稳定的输入。
- 调用 `audioEngine.prepare()` 后再读 `inputNode.outputFormat(forBus: 0)`，规避部分 iOS 版本上首次调用拿到 0 sampleRate 的问题。
- 麦克风硬件常以 48 kHz / 44.1 kHz 采样，Sherpa KWS / ASR / VAD 模型按 16 kHz 训练，因此 iOS 内部用 `AVAudioConverter` 把硬件 buffer 转成 `f32le` 单声道 16 kHz 后再跨平台 channel 送给 Dart。这样 sherpa-onnx 内部不会再二次重采样，`VoiceActivityDetector.acceptWaveform`（无 sampleRate 参数，按模型采样率切窗）才能正确工作。
- 注册 `AVAudioSession.interruptionNotification` / `routeChangeNotification` / `mediaServicesWereResetNotification`：被来电、Siri、其他 App 占用、耳机插拔或系统媒体服务重置打断时，主动 stop 引擎并发出 telemetry 与 stopped 状态，避免 UI 上仍然显示 listening 但其实已经收不到音频。
- iOS 当前只保证前台监听；不声明后台语音常驻能力。

iOS 宿主 App 必须声明：

- `NSMicrophoneUsageDescription`

当前 App 也声明了 `NSSpeechRecognitionUsageDescription`，但本 SDK 的识别路径是 Sherpa 离线推理，不依赖系统 Speech framework。

## 模型资产

模型随插件 assets 内置：

```text
assets/voice_models/
├── kws/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20/
│   ├── encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx
│   ├── decoder-epoch-13-avg-2-chunk-16-left-64.onnx
│   ├── joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx
│   └── tokens.txt
├── asr/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16/
│   ├── encoder-epoch-99-avg-1.int8.onnx
│   ├── decoder-epoch-99-avg-1.int8.onnx
│   ├── joiner-epoch-99-avg-1.int8.onnx
│   ├── tokens.txt
│   └── bpe.model
└── vad/silero_vad.onnx
```

`voice_control_sdk/pubspec.yaml` 已显式声明三个 assets 目录。`VoiceConfig` 默认使用 package asset 路径：

- `packages/voice_control_sdk/assets/voice_models/kws/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20`
- `packages/voice_control_sdk/assets/voice_models/asr/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16`
- `packages/voice_control_sdk/assets/voice_models/vad/silero_vad.onnx`

如果移动模型路径，必须同步更新：

- `voice_control_sdk/pubspec.yaml`
- `VoiceConfig.kwsAssetBasePath`
- `VoiceConfig.asrAssetBasePath`
- `VoiceConfig.vadAssetPath`
- `assets/voice_models/README.md`

如果替换模型包，先把新模型放回上述目录，再从仓库根目录运行：

```bash
scripts/prune_voice_models.sh
```

## 与 Robot App 集成

App 入口在 `apps/robot_app/lib/src/voice_module_page.dart`。

当前集成方式：

- `HomePage` 创建并持有 App 级 `VoiceRobotController`，其中包含 `VoiceController` 和当前 `RobotClient`。
- `VoiceModulePage` 只接收同一个 `VoiceRobotController`，负责展示状态、事件流和启动 / 停止按钮。
- 页面关闭不会停止语音采集；用户点击“停止服务”或 App 级服务销毁才会停止。iOS 进入后台 / 失活时会释放麦克风，Android 由前台通知和停止按钮控制。
- 语音命令通过 `RobotClient` 默认 last-wins API 执行：`stand` / `sit` / `stop` / `move`，不使用 `*Queued`。
- 如果当前未连接机器人，语音命令会保留识别反馈但不会下发控制。

首版 UI 固定唤醒词为 `Lumi`，不提供动态唤醒词、语言或灵敏度调节入口。

## 权限与平台要求

Android：

- `RECORD_AUDIO`
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_MICROPHONE`
- `POST_NOTIFICATIONS`（Android 13+）
- Android 10+ 前台服务使用 `foregroundServiceType="microphone"`

iOS：

- `NSMicrophoneUsageDescription`
- 仅前台监听；后台常驻需要另行评估系统限制和产品合规。

通用：

- 目标设备需要支持 Sherpa ONNX 对应平台 native 库。
- 首次启动会把模型 assets 复制到应用支持目录，模型缺失或路径不一致会产生 `sherpa_asset_missing`。

## 测试

Dart 单测：

```bash
cd /path/to/robot_factory/apps/robot_app/voice_control_sdk
flutter test
```

静态检查：

```bash
cd /path/to/robot_factory/apps/robot_app/voice_control_sdk
flutter analyze
```

宿主 App 测试：

```bash
cd /path/to/robot_factory/apps/robot_app
flutter test
flutter analyze lib test
```

## 真机验收清单

每次修改权限、音频采集、模型路径、KWS keywords、VAD 或 ASR 状态机后，至少在真机验证：

- Android：第一次启动监听时能弹出麦克风权限；Android 13+ 能弹出通知权限。
- Android：授权后出现前台服务通知。
- Android：事件流持续出现音频相关遥测或状态，不应直接进入 `error`。
- Android：说 `Lumi` / `露米` / `loo me` 后产生 `VoiceWakeEvent`。
- Android：唤醒后说“站起来 / 坐下 / 前进 / 后退”能产生 `VoiceCommandEvent`。
- iOS：第一次启动监听时能弹出麦克风权限。
- iOS：前台打开语音模块后能采集音频。
- iOS：telemetry 中可观察到 `targetRate=16000 converter=true/false`，rms / peak 在正常说话距离下不应长时间为 0。
- iOS：说 `Lumi` / `露米` 后产生 `VoiceWakeEvent`。
- iOS：唤醒后说“站起来 / 坐下 / 前进 / 后退”能产生 `VoiceCommandEvent`。
- iOS：锁屏、切后台或离开语音页后不会声称仍在监听。
- iOS：监听过程中接听电话或被 Siri 打断后，事件流出现 `audio_session_interrupted` telemetry 并切换到 `stopped` 状态。
- 关闭语音页后再次打开，模型加载和监听不应卡住。

## 常见问题

### 主 App 里说 `Lumi` 没反应

当前主 App 没有全局语音监听。语音监听只在 `VoiceModulePage` 内手动启动，页面关闭时会停止。要在 App 主界面常驻唤醒，需要把 `VoiceController` 从页面状态提升到 App 级服务，并订阅其事件流。

### 点了“开始监听”但没有唤醒

先看事件流和状态卡片：

- 如果出现 `microphone_permission_denied`，到系统设置打开麦克风权限；Android 13+ 还要允许通知权限。
- 如果出现 `sherpa_asset_missing`，检查 `voice_control_sdk/pubspec.yaml` assets 声明和模型目录名是否一致。
- 如果状态停在“正在加载 Sherpa 模型”，优先检查设备 CPU / 内存和模型复制耗时。
- 如果能进入“正在采集音频”但没有 `wake`，优先调低唤醒灵敏度阈值、靠近麦克风，并确认使用的是 `Lumi`、`露米` 或 `loo me` 这类已配置别名。
- iOS 上若 telemetry 里 `rate` 不是 `16000`、或长期 `rms` 接近 0，说明系统级 AGC 没启用或 `AVAudioConverter` 没构造成功，检查 `AVAudioSession` 是否被其他 App 抢占。

### 识别到了唤醒但机器狗不动

SDK 只输出 `VoiceCommandEvent`，不会直接调用机器狗控制 API。宿主 App 必须订阅命令事件并调用 `RobotClient`。当前 `voice_module_page.dart` 还没有把 `VoiceActionMapper.execute()` 接到页面主流程。

### Android 启动前台服务失败

检查宿主 App manifest 是否包含 `FOREGROUND_SERVICE_MICROPHONE`，并确认服务声明带有 `android:foregroundServiceType="microphone"`。Android 13+ 还需要通知权限，否则前台服务通知可能不可见或启动受限。

### 模型路径调整后启动失败

`VoiceConfig` 使用 package asset 路径，不能只改文件夹名。目录名、`pubspec.yaml` assets、`VoiceConfig` 默认路径和 `assets/voice_models/README.md` 必须一起改。
