# voice_control_sdk

`voice_control_sdk` 是 `apps/robot_app` 里的本地 Flutter 插件，用于基于 Sherpa ONNX 的离线语音控制。

## 当前定位

这是语音能力的接入壳：

- Dart 层统一对外暴露 `VoiceController`、`VoiceConfig`、事件模型和唤醒词 / 命令归一化逻辑
- 底层采用 `KWS + ASR + VAD` 双阶段链路
  - `IDLE`：Keyword Spotting 只识别唤醒词 `Lumi`
  - `ACTIVE`：唤醒后切换到 streaming ASR；默认等待 5 秒命令语音，检测到语音后再用 VAD 静音结束
- KWS 模型、ASR 模型和 VAD 模型都打包在 `assets/voice_models/` 下，首次启动时会复制到可写缓存目录
- `VoiceWakeEvent` 会返回原始命中结果 `recognizedText` 和 `language`
- `VoiceAsrEvent` 会返回实时转写和最终转写
- `VoiceCommandEvent` 仅在最终转写命中机器人命令时产生
- Android 侧使用前台服务采集麦克风 PCM，iOS 侧仅保证前台可用
- `VoiceController.ensurePermissions()` 会在启动监听前请求必要权限：Android 请求麦克风和 Android 13+ 通知权限，iOS 请求麦克风权限

## 模型落地清单

如果要把 Sherpa 模型放进 App assets，请严格使用下面这三个目标位点，不要改目录名：

- `assets/voice_models/kws/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20/`
- `assets/voice_models/asr/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16/`
- `assets/voice_models/vad/silero_vad.onnx`

推荐的官方下载源：

- KWS: `https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20.tar.bz2`
- ASR: `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16.tar.bz2`
- VAD: `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx`

只需要把归档内的模型文件复制到上面的目录，不需要把 `keywords.txt` 一起打进 assets。`keywords.txt` 会由后端在首次启动时生成到可写缓存目录。

当前最小发布体积保留的文件如下：

- KWS:
  - `encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx`
  - `decoder-epoch-13-avg-2-chunk-16-left-64.onnx`
  - `joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx`
  - `tokens.txt`
- ASR:
  - `encoder-epoch-99-avg-1.int8.onnx`
  - `decoder-epoch-99-avg-1.int8.onnx`
  - `joiner-epoch-99-avg-1.int8.onnx`
  - `tokens.txt`
  - `bpe.model`
- VAD:
  - `silero_vad.onnx`

如果你后面替换模型，先把新包放回上述目录，再运行仓库根目录下的 `scripts/prune_voice_models.sh`，它会把 fp32 和示例文件裁掉，只保留最小发布集。

如果你更改模型目录名，需要同时更新 `voice_control_sdk/pubspec.yaml` 里的 assets 声明，否则 Flutter 不会把新模型文件打进 App bundle。

## 对外 API

- `VoiceController.startListening()`
- `VoiceController.stopListening()`
- `VoiceController.ensurePermissions()`
- `VoiceController.onWake`
- `VoiceController.onAsr`
- `VoiceController.onCommand`
- `VoiceController.state`
- `VoiceWakeMapper.buildKeywordsFileContent()` / `VoiceWakeMapper.matchResultLabel()`：用于构造和匹配 Lumi 的中英混合唤醒别名
- `VoiceCommandMapper.normalizeTranscript()`：把原始转写归一化为可比对文本
- `VoiceConfig` 支持配置唤醒词、模型语言、灵敏度、前导缓存、唤醒后无语音超时和静音结束阈值

## 设计约束

- Android 适合前台服务常驻监听
- iOS 只做前台监听
- 语音识别与唤醒都在 Dart 侧通过 Sherpa ONNX 完成
- 当前默认唤醒词是 `Lumi`
