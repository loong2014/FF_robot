You are a senior mobile + embedded AI engineer.
Help me build a production-ready Keyword Spotting (KWS) + command recognition system inside a Flutter app.

# 🎯 Project Goal

Build a Flutter-based voice control system for a robot dog with two core capabilities:

## 1. Wake Word Detection (KWS)

* Wake word: "D-Dog"
* The system should continuously listen (low latency, low power)
* When "D-Dog" is detected:

  * Wake up the app (bring to foreground if needed)
  * Trigger a callback: onWakeWordDetected()

## 2. Command Recognition (Fixed Commands)

After wake word is detected, recognize a small set of commands:

### Chinese:

* "站起来"
* "坐下"
* "前进"
* "后退"

### English:

* "stand up"
* "sit down"
* "forward"
* "backward"

Return structured command results like:
{
"command": "sit_down",
"language": "en"
}

---

# 🧱 Technical Constraints

## Platform

* Flutter (Dart)
* Android priority (must work reliably in background with microphone)
* iOS supported but only in foreground

## Architecture Requirements

Design a clean architecture:

* Audio Capture Layer
* KWS Engine Layer
* Command Recognition Layer
* Flutter Bridge Layer
* UI Trigger Layer

---

# 🔊 Audio Handling

Use platform channels to integrate native audio:

### Android:

* Use AudioRecord
* Run inside Foreground Service
* Continuous streaming

### iOS:

* Use AVAudioEngine (foreground only)

---

# 🧠 KWS Engine

Use one of the following (prefer Porcupine):

* Porcupine SDK (preferred)
* or lightweight TensorFlow Lite model

Requirements:

* Frame-based processing
* Real-time detection
* Low CPU usage

---

# 🗣 Command Recognition

After wake word:

Option A (recommended):

* Use on-device ASR with Sherpa ONNX small RNN-T bilingual model

Option B:

* Use a simple short-buffer keyword matcher only for fallback or debug

Commands must be mapped to normalized intents:

* "sit down" / "坐下" → SIT_DOWN
* "stand up" / "站起来" → STAND_UP

## Sherpa model layout

The App expects these exact asset paths:

* `apps/robot_app/voice_control_sdk/assets/voice_models/kws/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20/`
* `apps/robot_app/voice_control_sdk/assets/voice_models/asr/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16/`
* `apps/robot_app/voice_control_sdk/assets/voice_models/vad/silero_vad.onnx`

Official download sources:

* KWS archive: `https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20.tar.bz2`
* ASR archive: `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16.tar.bz2`
* VAD file: `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx`

Required files inside the copied assets:

* KWS:
  * `encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx`
  * `decoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx`
  * `joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx`
  * `tokens.txt`
* ASR:
  * `encoder-epoch-99-avg-1.int8.onnx`
  * `decoder-epoch-99-avg-1.int8.onnx`
  * `joiner-epoch-99-avg-1.int8.onnx`
  * `tokens.txt`
* VAD:
  * `silero_vad.onnx`

`keywords.txt` is generated at runtime in the writable cache directory and should not be copied into assets.

---

# 🔁 Flow Design

Implement this pipeline:

1. Start background listening
2. Detect wake word ("D-Dog")
3. Enter "active listening" mode and keep streaming until VAD detects silence
4. Capture command speech
5. Recognize command
6. Emit result to Flutter
7. Trigger robot action callback

---

# 🔌 Flutter Integration

Provide:

## Dart API

class VoiceController {
void startListening();
void stopListening();

Stream<WakeEvent> onWake;
Stream<CommandEvent> onCommand;
}

---

# ⚡ Performance Requirements

* Wake latency < 300ms
* CPU usage low (<10%)
* Avoid continuous high-power ASR
* Use two-stage detection:

  * KWS (always on)
  * ASR (only after wake)

---

# 🔋 Power Optimization

* Use low sample rate (16kHz or lower)
* Buffer frames efficiently
* Avoid unnecessary allocations

---

# 🧪 Edge Cases

Handle:

* Noise environments
* False positives
* Partial commands
* Repeated wake triggers

---

# 📦 Output Requirements

Generate:

1. Full Flutter plugin structure (platform channel)
2. Android implementation (KWS + service)
3. iOS implementation (foreground only)
4. Dart interface code
5. Example usage in Flutter UI
6. Command mapping logic
7. Lifecycle handling (start/stop)

---

# 🚀 Bonus (if possible)

* Add configurable wake word sensitivity
* Add bilingual command support
* Add debounce for repeated triggers

---

Write clean, production-level code with comments.
