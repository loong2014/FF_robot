# 语音控制 MVP：AI / 开发者实现指引（robot_factory）

> **用途**：指导在本仓库中落地 Flutter 双平台可交付的「语音控制服务 + Lumi / 鲁米唤醒 + ASR 指令识别 + VAD 静音回待唤醒」第一版功能。实现应满足下文 **MUST** 规格；这是首次发布，旧页面级监听、动态唤醒词、旧状态名、旧命令映射等与本规格冲突的逻辑必须删除或改写，不做兼容。
> **范围**：`voice_control_sdk`（Dart Sherpa 编排 + iOS / Android 原生音频采集）、`apps/robot_app` 内接入与 `mobile_sdk.RobotClient` 映射。
> **非目标**：不引入云端 ASR / NLU；不做多轮对话；不做自定义唤醒词 UI；不在 `voice_control_sdk` 内 `import mobile_sdk`；不承诺 iOS 锁屏 / 后台常驻。

---

## 1. 完成定义（Done = 可验收）

同时满足：

1. **双平台语音服务**：用户启动语音服务后进入 `waiting_for_wake`，持续采集麦克风并等待 Lumi / 鲁米唤醒；Android 使用前台服务保活，iOS 在 App 前台运行期间持续监听。
2. **固定唤醒词**：仅支持 `Lumi` 主唤醒词及内置别名（`Lumi`、`loo me`、`lu mi`、`鲁米`、`露米`、`卢米` 等）；用户不能在 UI 动态改唤醒词。
3. **状态机明确**：`stopped -> starting -> waiting_for_wake -> wake_detected -> active_listening -> processing_command -> waiting_for_wake`；错误进入 `error`，用户停止进入 `stopped`。
4. **KWS**：等待态只跑离线 KWS；命中 Lumi 后发 `VoiceWakeEvent`，进入 ASR + VAD 活跃监听；唤醒后 2s 内不接受新的唤醒。
5. **ASR**：唤醒后使用离线 streaming ASR；partial 结果只用于 UI，只有 `isFinal == true` 的最终结果参与命令匹配。
6. **VAD**：活跃监听期间使用 Silero VAD；从最后一个有效人声段结束开始计时，连续 **5.0s** 无有效语音则结束本轮，回到 `waiting_for_wake`。小于 **300ms** 的噪声尖峰不算有效语音，不重置静音计时器。
7. **指令匹配**：最终 ASR 文本通过关键词表映射为机器狗控制意图：站起、坐下、停止、向前、向后、左移、右移。低置信度结果丢弃；1s 内重复命令只触发一次。
8. **App 控制**：App 持有已连接 `RobotClient` 时，将 `VoiceCommandEvent` 映射为 `stand` / `sit` / `stop` / `move` 等；语音属于手动控制，必须使用 last-wins API，不使用 `*Queued`。
9. **测试**：Dart 侧对唤醒别名、状态机、VAD 5s 静音、最终 ASR 命令匹配、低置信度丢弃、重复命令去重、App 映射有可重复单测（伪造事件序列 + 可控时钟）。

---

## 2. 仓库硬约束（实现前必读）

| 约束 | 说明 |
| --- | --- |
| SDK 边界 | `voice_control_sdk` 不得依赖 `mobile_sdk`；所有 `RobotClient` 调用必须在 App 层，如新建 App 级 `VoiceRobotController`。 |
| 控制入口 | App 业务流程通过 `RobotClient`；不得绕过协议层手写帧字节。 |
| 交付平台 | 本 MVP 必须同时支持 iOS 和 Android。用户群体侧重 iOS，因此 iOS 真机验收优先，但 Android 也必须达到基础可交付。 |
| 平台生命周期 | Android 使用通知栏前台服务持续监听；iOS 使用 App 前台语音服务，App 进入后台、锁屏、系统中断时必须停止或暂停采集并释放麦克风。 |
| 离线识别 | KWS / ASR / VAD 全部使用本地 Sherpa ONNX / Silero 模型；不允许调用网络 API。 |
| 唤醒词 | UI 不提供 `wakeWord` 输入框；`VoiceConfig.wakeWord` 固定为 `Lumi`。 |
| 首版策略 | 这是语音 SDK 首次发布，不保留旧页面级监听生命周期、不保留动态灵敏度/语言/唤醒词 UI、不保留旧状态输出作为兼容层。 |
| 资源释放 | 停止服务、权限被收回、iOS `AVAudioSession` 中断、Android 音频焦点永久丢失、App 退后台（iOS）或音频路由不可用时，必须停止采集并释放麦克风。 |
| 文档 | 实现完成后更新本文件「实现状态」或 `voice_control_sdk/README.md` 的当前能力；里程碑级再同步 `docs/backlog.md`。 |

---

## 3. 状态机与每帧处理流程（逻辑模型）

### 3.1 状态定义

必须新增 `voice_session_state.dart`（或同名等价文件）作为单一语音状态机；`SherpaVoiceBackend` 负责音频、Sherpa 对象生命周期与事件转发，并委托该状态机决定 KWS / ASR / VAD 阶段切换。

| 状态 | 含义 | UI 文案 |
| --- | --- | --- |
| `stopped` | 服务未运行 | `语音服务已停止` |
| `starting` | 权限检查、模型准备、启动平台音频采集 | `正在启动语音控制` |
| `waiting_for_wake` | 平台音频采集中，等待 Lumi / 鲁米唤醒 | `等待 Lumi / 鲁米 唤醒` |
| `wake_detected` | KWS 命中，准备进入 ASR | `已唤醒，请说指令` |
| `active_listening` | ASR + VAD 采集中 | `正在识别语音指令` |
| `processing_command` | 最终 ASR 文本转命令 | `正在处理指令` |
| `error` | 权限、音频、模型或推理异常 | `语音控制异常` |

必须扩展 `VoiceRecognitionState`：新增 `waitingForWake`、`processingCommand`，wireName 分别为 `waiting_for_wake`、`processing_command`。现有 `listening` 不再作为等待唤醒状态输出；`cooldown` 不作为本 MVP 的对外状态输出，识别完成后直接回到 `waiting_for_wake`。

### 3.2 维护的状态

- `current_state`：当前状态。
- `wake_debounce_until`：唤醒后 2s 冷却截止时间。
- `active_started_at`：进入 `active_listening` 的时间。
- `speech_active`：当前是否处于有效人声段。
- `last_speech_ended_at`：最后一个有效人声段结束时间。
- `last_command` / `last_command_at`：1s 重复命令去重。
- `restart_window`：异常重启计数，30s 内超过 3 次则停止服务并发错误。

### 3.3 音频处理顺序（MUST 顺序）

1. 平台原生层采集麦克风音频，通过 EventChannel 发 `audio` 事件给 Dart：
   - iOS：`VoiceListeningCoordinator` 通过 `AVAudioEngine` 采集并转换为 `16kHz / mono / f32le`。
   - Android：`VoiceListeningService` 通过 `AudioRecord` 前台服务采集 `16kHz / mono / pcm16le`。
2. `waiting_for_wake`：音频只进入 KWS；命中 Lumi 别名且 `now >= wake_debounce_until` 时发 `VoiceWakeEvent`，设置 `wake_debounce_until = now + 2s`，进入 `wake_detected -> active_listening`。
3. `active_listening`：音频同时进入 ASR 与 VAD；ASR partial 只发 UI 事件，不做命令匹配。
4. VAD 判定有效人声段开始后，才认为本轮有用户输入；小于 300ms 的噪声段必须忽略。
5. 从最后一个有效人声段结束开始，连续 5.0s 无有效语音时，调用 `inputFinished()` 结束 ASR，进入 `processing_command`。
6. `processing_command`：只读取最终 ASR 文本，做低置信度过滤、命令匹配和去重；完成后释放本轮 ASR stream / VAD buffer，重置 KWS stream，回到 `waiting_for_wake`。
7. 如果唤醒后 5.0s 内完全没有有效人声，也结束本轮并回到 `waiting_for_wake`，发 `VoiceTelemetryEvent(message: speech_timeout)`，但不发命令。

---

## 4. KWS 唤醒规格（MUST）

### 4.1 唤醒词与别名

固定唤醒词为 `Lumi`，内置别名必须覆盖：

- 英文/拼写：`Lumi`、`lumi`、`loo me`、`lu mi`
- 中文：`鲁米`、`露米`、`卢米`、`噜米`

`VoiceWakeMapper` 继续生成 Sherpa keywords 文件，但不允许从 UI 动态改 `wakeWord`。`VoiceConfig` 可以保留 `wakeWord` 字段，App 层必须始终传固定值 `Lumi`。

### 4.2 唤醒规则

- 仅 `waiting_for_wake` 状态处理 KWS 命中。
- 唤醒命中后发 `VoiceWakeEvent`，字段至少包含：`wakeWord`、`recognizedText`、`resultLabel`、`language`、`confidence`。
- 唤醒后 2s 内忽略新的 KWS 命中，防止同一唤醒词重复触发。
- KWS 命中后必须进入 `active_listening`，不得直接匹配命令。

---

## 5. ASR + VAD 规格（MUST）

### 5.1 ASR

- 使用离线 streaming ASR，不使用 iOS Speech framework 或云 API。
- ASR partial 可发 `VoiceAsrEvent(isFinal: false)` 供 UI 展示，但不得参与命令匹配。
- 只有本轮结束时的最终结果 `VoiceAsrEvent(isFinal: true)` 能进入命令匹配。
- 若最终文本为空，回到 `waiting_for_wake`，不发命令。
- 如果引擎能提供置信度，`confidence < 0.70` 的最终结果直接丢弃；当前 Sherpa 无真实置信度时可固定 `1.0`，并在代码注释写明。

### 5.2 VAD 静音结束

- 使用 Silero VAD，不允许只靠简单能量阈值。
- `speech_min_duration = 300ms`：短于该时长的噪声不算有效语音。
- `silence_timeout = 5s`：从最后一个有效人声段结束开始计时。
- `active_no_speech_timeout = 5s`：唤醒后 5s 内没有有效人声，也结束本轮。
- `max_active_duration = 12s`：单次唤醒最长识别 12s，超过后强制结束本轮，避免 ASR 挂住。
- 本轮结束后必须重置 ASR stream、VAD buffer 和 KWS stream，再回到 `waiting_for_wake`。

---

## 6. ASR 文本 -> 机器狗意图映射（MUST）

命令匹配必须是关键词表，不做深度自然语言理解。匹配前先归一化：

- 转小写。
- 删除标点和多余空格。
- 中文保留原字符，英文按 token 匹配。
- 同一句包含多个命令时，按下表优先级只触发一个。

| 优先级 | 意图 | 关键词 / 短语 | 输出 |
| --- | --- | --- | --- |
| 1 | `stop` | `停止`、`停下`、`别动`、`stop` | `VoiceCommand.stop` |
| 2 | `stand_up` | `站起`、`站起来`、`起立`、`stand up`、`stand` | `VoiceCommand.standUp` |
| 3 | `sit_down` | `坐下`、`坐下来`、`蹲下`、`sit down`、`sit` | `VoiceCommand.sitDown` |
| 4 | `forward` | `前进`、`向前`、`往前`、`走`、`forward`、`go forward` | `VoiceCommand.forward` |
| 5 | `backward` | `后退`、`向后`、`往后`、`backward`、`go back`、`move back` | `VoiceCommand.backward` |
| 6 | `left` | `左移`、`向左`、`往左`、`left`、`move left` | `VoiceCommand.left` |
| 7 | `right` | `右移`、`向右`、`往右`、`right`、`move right` | `VoiceCommand.right` |

去重规则：

- `dedupe_window = 1s`。
- 同一 `VoiceCommand` 在 1s 内重复出现，只保留第一次。
- 不同命令不互相去重。

---

## 7. App 层 `RobotClient` 映射（MUST）

`voice_control_sdk` 只输出 `VoiceCommandEvent`，不直接控制机器狗。App 层必须持有当前 `RobotClient` 并映射：

| `VoiceCommand` | `RobotClient` 调用 |
| --- | --- |
| `standUp` | `client.stand()` |
| `sitDown` | `client.sit()` |
| `stop` | `client.stop()` |
| `forward` | `client.move(+0.32, 0, 0)`，持续 800ms 后 `client.stop()` |
| `backward` | `client.move(-0.26, 0, 0)`，持续 800ms 后 `client.stop()` |
| `left` | `client.move(0, +0.25, 0)`，持续 500ms 后 `client.stop()` |
| `right` | `client.move(0, -0.25, 0)`，持续 500ms 后 `client.stop()` |

要求：

- 语音控制属于手动控制，必须使用 `RobotClient` 默认 last-wins API，不使用 `*Queued`。
- 如果机器人未连接，App 不崩溃；展示“未连接机器人，已识别但未执行”反馈。
- 本 MVP 必须新增 App 级 `VoiceRobotController`，内部持有 `VoiceController` 与当前 `RobotClient`；`VoiceModulePage` 只作为状态面板和启动/停止控制面板。
- 首页打开语音页时必须传入同一个 `VoiceRobotController`；不得在 `VoiceModulePage.dispose()` 中停止 iOS 语音采集；只有用户点击“停止服务”、App 进入后台或 App 级服务销毁时才停止。

---

## 8. 平台原生音频服务规格（MUST）

### 8.1 Android 前台服务

Android 必须可交付：

- 权限：`RECORD_AUDIO`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MICROPHONE`、Android 13+ `POST_NOTIFICATIONS`。
- 缺权限时不得启动服务，必须发 `VoiceErrorEvent(code: microphone_permission_denied)`。
- `VoiceListeningService` 必须以 foreground service 启动，Android Q+ 使用 `FOREGROUND_SERVICE_TYPE_MICROPHONE`。
- 通知 channel 固定为 `voice_control_sdk`。
- 通知必须 `ongoing = true`，展示当前状态，并提供“停止服务” action，触发 `VoiceListeningService.ACTION_STOP`。
- 通知文案：
  - `waiting_for_wake`：`等待 Lumi / 鲁米 唤醒`
  - `active_listening`：`正在识别语音指令`
  - `processing_command`：`正在处理指令`
  - `error`：`语音控制异常`
- `AudioRecord` 使用 `MediaRecorder.AudioSource.VOICE_RECOGNITION`。
- 音频格式固定 `16kHz / PCM16 / mono`。
- 音频采集必须在后台线程，不阻塞主线程。
- 停止服务、销毁、音频异常或音频焦点永久丢失时必须 `stop()` + `release()` `AudioRecord`。
- 电话、闹钟、系统录音占用等导致 `AudioRecord` 失败时，发错误事件并尝试重启音频流水线；30s 内自动重启超过 3 次时进入 `error`，等待用户手动重启。

### 8.2 iOS App 前台语音服务

启动前必须确认：

- `NSMicrophoneUsageDescription` 已配置。
- `AVAudioSession.recordPermission == .granted`。

缺权限时不得启动采集，必须发 `VoiceErrorEvent(code: microphone_permission_denied)`。

#### `AVAudioSession`

iOS 原生层必须：

- 使用 `AVAudioSession.Category.playAndRecord`。
- 使用 `.voiceChat` mode，以获得系统级 AGC、降噪与回声处理。
- 使用 `.duckOthers`；蓝牙输入按现有实现保留 `.allowBluetoothHFP` / `.allowBluetooth`。
- `preferredSampleRate` 设置为 `16000`。
- `setActive(true)` 成功后才启动 `AVAudioEngine`。
- 注册并处理：
  - `AVAudioSession.interruptionNotification`
  - `AVAudioSession.routeChangeNotification`
  - `AVAudioSession.mediaServicesWereResetNotification`

#### 音频采集与格式

- 使用 `AVAudioEngine.inputNode.installTap` 采集麦克风。
- 采集线程不得阻塞 Flutter UI 线程。
- 由于 iOS 硬件常输出 44.1kHz / 48kHz，必须使用 `AVAudioConverter` 转为 `16kHz / mono / f32le`。
- EventChannel `audio` 事件必须包含：
  - `format: f32le`
  - `samples: FlutterStandardTypedData`
  - `sampleRate: 16000`
  - `channels: 1`
  - `sampleCount`
  - `source: ios`
  - `timestampMs`

#### 生命周期与异常恢复

- 用户点击停止、App 进入后台、权限被收回、音频中断、路由不可用、媒体服务重置时，必须停止 `AVAudioEngine`、移除 tap、释放 converter，并 `setActive(false)`。
- `mediaServicesWereReset` 后必须丢弃旧 `AVAudioEngine` 并创建新实例，避免继续访问失效 inputNode。
- 音频异常时发 `VoiceErrorEvent`；30s 内自动重启超过 3 次时进入 `error` 并等待用户手动重启。
- App 回到前台后不自动偷启麦克风；只有用户明确启动服务或 App 级服务仍处于应运行状态时，才可恢复采集。

---

## 9. 数据契约（MUST）

### 9.1 平台事件

iOS / Android 平台层通过 EventChannel 推送：

| type | 必填字段 | 说明 |
| --- | --- | --- |
| `audio` | `samples`、`sampleRate: 16000`、`channels: 1`、`format`、`timestampMs`、`source` | 音频块；iOS `format=f32le`，Android `format=pcm16le` |
| `state` | `state`、`message`、`listening`、`activeListening`、`engine: sherpa`、`timestampMs`、`source` | 平台采集状态 |
| `error` | `code`、`message`、`timestampMs`、`source` | 平台错误 |
| `telemetry` | `message`、`timestampMs`、`source` | 调试遥测 |

### 9.2 SDK 事件

Dart 层必须输出：

| 类型 | 说明 |
| --- | --- |
| `VoiceStateEvent` | 状态机状态和 UI 文案 |
| `VoiceWakeEvent` | Lumi / 鲁米唤醒命中 |
| `VoiceAsrEvent(isFinal: false)` | ASR partial，仅 UI |
| `VoiceAsrEvent(isFinal: true)` | 最终 ASR，命令匹配输入 |
| `VoiceCommandEvent` | 机器狗控制意图 |
| `VoiceErrorEvent` | 权限、模型、音频、推理错误 |
| `VoiceTelemetryEvent` | 调试遥测 |

---

## 10. 实现任务清单（按顺序执行）

1. **Dart 模型**：扩展 `VoiceCommand`，新增 `stop`、`left`、`right`；扩展 wireName / parser / tests。
2. **Dart 状态**：扩展 `VoiceRecognitionState`，新增 `waitingForWake`、`processingCommand`；停止对外输出旧 `listening` / `cooldown` 状态作为首版主状态。
3. **Dart 配置**：收敛 `VoiceConfig` 默认值：`wakeWord = Lumi`、`wakeDebounce = 2s`、`vadSilence = 5s`、`activeNoSpeechTimeout = 5s`、`maxActiveDuration = 12s`、`sampleRate = 16000`。
4. **Dart 状态机**：新增 `voice_session_state.dart`，实现 §3–§5；`SherpaVoiceBackend` 必须委托它处理状态切换，确保 partial ASR 不触发命令，最终 ASR 才匹配命令。
5. **Dart 命令映射**：按 §6 改写 `VoiceCommandMapper`，加入低置信度丢弃和 1s 去重。
6. **iOS 原生**：完善 `VoiceListeningCoordinator` 权限、`AVAudioSession`、路由/中断/媒体服务重置、前后台生命周期、异常重启计数和资源释放。
7. **Android 原生**：完善 `VoiceListeningService` 前台通知、停止 action、音频焦点、异常重启计数和资源释放。
8. **App 级服务**：新增 App 级 `VoiceRobotController`，持有 `VoiceController` 与当前 `RobotClient`，负责启动/停止语音服务、订阅 `VoiceCommandEvent`、执行 §7 映射。
9. **App 页面接入**：`VoiceModulePage` 改为接收 `VoiceRobotController`；`HomePage` 创建并持有同一个 `VoiceRobotController`，打开语音页时传入；页面销毁不得停止语音采集；Android 由通知 action 或用户停止按钮停止，iOS 由用户停止、App 退后台或 App 级服务销毁停止。
10. **UI 收敛**：移除唤醒词输入框和动态语言/灵敏度调节控件，避免第一版暴露非目标能力。
11. **测试**：改写 / 新增 `voice_wake_mapper_test.dart`、`voice_command_mapper_test.dart`、`voice_controller_test.dart`，新增状态机/后端/App 映射测试，覆盖 §11。

---

## 11. 验收清单（AI 自检）

- [ ] 启动服务后状态进入 `waiting_for_wake`，UI 显示等待 Lumi / 鲁米唤醒。
- [ ] 未授权麦克风时不启动采集，并输出 `microphone_permission_denied`。
- [ ] `Lumi` / `鲁米` / `露米` / `卢米` 可唤醒；唤醒后进入 `active_listening`。
- [ ] 唤醒后 2s 内重复 Lumi 不会重复进入新会话。
- [ ] ASR partial 不触发命令；最终 ASR 才触发命令匹配。
- [ ] 连续 5s 无有效语音后回到 `waiting_for_wake`。
- [ ] 小于 300ms 的噪声尖峰不重置静音计时器。
- [ ] 低置信度最终 ASR 不触发命令。
- [ ] 1s 内相同命令去重。
- [ ] 站起、坐下、停止、前进、后退、左移、右移都能映射到 `VoiceCommandEvent`。
- [ ] App 连接机器人时，语音命令通过 `RobotClient` last-wins API 执行。
- [ ] App 未连接机器人时，识别命令不崩溃，并给出未执行反馈。
- [ ] Android 启动后出现前台通知，通知可停止服务。
- [ ] iOS App 退后台、音频中断、路由不可用、用户停止服务时释放麦克风。
- [ ] Android 服务停止、音频焦点永久丢失或音频异常时释放麦克风。
- [ ] iOS 真机上 `AVAudioEngine` 输出经过转换后的 `16kHz / mono / f32le` 音频事件。
- [ ] Android 真机上 `AudioRecord` 输出 `16kHz / mono / pcm16le` 音频事件。

---

## 12. 实现状态（由人类维护勾选）

- [ ] §3 状态机已按 `waiting_for_wake / active_listening / processing_command` 落地
- [ ] §4 Lumi / 鲁米 KWS 唤醒已落地
- [ ] §5 ASR final-only + VAD 5s 静音已落地
- [ ] §6 命令映射与去重已落地
- [ ] §7 App 已接 `RobotClient`
- [ ] §8 iOS 音频采集、路由/中断处理、资源释放已落地
- [ ] §8 Android 前台服务、通知 action、音频焦点、资源释放已落地
- [ ] §11 单测 + 至少一轮 iOS 真机验证 + Android 真机基础验证已完成

---

## 13. 附录：本仓库等价主循环

`iOS VoiceListeningCoordinator` / `Android VoiceListeningService` 采集 PCM -> `EventChannel audio` -> **Dart Sherpa KWS** 等待 Lumi / 鲁米 -> **Dart Sherpa ASR + Silero VAD** 识别单条指令 -> `VoiceCommandEvent` -> **App** `RobotClient.move/stand/sit/stop`。
