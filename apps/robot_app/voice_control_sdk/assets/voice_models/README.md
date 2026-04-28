# Voice Models

This directory is reserved for Sherpa ONNX model assets bundled into `apps/robot_app`.

The voice backend expects the following exact package asset paths:

- `packages/voice_control_sdk/assets/voice_models/kws/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20/`
- `packages/voice_control_sdk/assets/voice_models/asr/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16/`
- `packages/voice_control_sdk/assets/voice_models/vad/silero_vad.onnx`

The backend copies these assets to a writable cache directory on first use and then generates `keywords.txt` in the cache. Do not add `keywords.txt` to the assets tree manually.

When you replace the model archives, run `scripts/prune_voice_models.sh` from the repo root to remove fp32 files and example files and keep only the minimal publish set.

The plugin `pubspec.yaml` declares the three leaf asset directories explicitly. If you change these model directory names, update `pubspec.yaml` and `VoiceConfig` together.

## 1. Download sources

Use the official Sherpa ONNX release artifacts:

- KWS archive:
  - `https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20.tar.bz2`
- ASR archive:
  - `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16.tar.bz2`
- VAD file:
  - `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx`

## 2. Expected local layout

After extraction and copy, the asset tree must look like this:

```text
assets/voice_models/
  kws/
    sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20/
      encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx
      decoder-epoch-13-avg-2-chunk-16-left-64.onnx
      joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx
      tokens.txt
  asr/
    sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16/
      encoder-epoch-99-avg-1.int8.onnx
      decoder-epoch-99-avg-1.int8.onnx
      joiner-epoch-99-avg-1.int8.onnx
      tokens.txt
      bpe.model
  vad/
    silero_vad.onnx
```

## 3. Copy checklist

Run these steps from the repo root after downloading and extracting the official archives:

```bash
mkdir -p apps/robot_app/voice_control_sdk/assets/voice_models/kws
mkdir -p apps/robot_app/voice_control_sdk/assets/voice_models/asr
mkdir -p apps/robot_app/voice_control_sdk/assets/voice_models/vad

cp -R sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20 \
  apps/robot_app/voice_control_sdk/assets/voice_models/kws/

cp -R sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16 \
  apps/robot_app/voice_control_sdk/assets/voice_models/asr/

cp silero_vad.onnx \
  apps/robot_app/voice_control_sdk/assets/voice_models/vad/silero_vad.onnx
```

## 4. File validation

Verify that these files exist before building the app:

- `apps/robot_app/voice_control_sdk/assets/voice_models/kws/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20/encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx`
- `apps/robot_app/voice_control_sdk/assets/voice_models/kws/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20/decoder-epoch-13-avg-2-chunk-16-left-64.onnx`
- `apps/robot_app/voice_control_sdk/assets/voice_models/kws/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20/joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx`
- `apps/robot_app/voice_control_sdk/assets/voice_models/kws/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20/tokens.txt`
- `apps/robot_app/voice_control_sdk/assets/voice_models/asr/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16/encoder-epoch-99-avg-1.int8.onnx`
- `apps/robot_app/voice_control_sdk/assets/voice_models/asr/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16/decoder-epoch-99-avg-1.int8.onnx`
- `apps/robot_app/voice_control_sdk/assets/voice_models/asr/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16/joiner-epoch-99-avg-1.int8.onnx`
- `apps/robot_app/voice_control_sdk/assets/voice_models/asr/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16/tokens.txt`
- `apps/robot_app/voice_control_sdk/assets/voice_models/asr/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16/bpe.model`
- `apps/robot_app/voice_control_sdk/assets/voice_models/vad/silero_vad.onnx`
