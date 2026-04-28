# KWS Training Project

This project is a lightweight end-to-end keyword spotting recipe for custom wake words such as `Lumi` or `Hey Robot`.

It is designed around the `sherpa-onnx` deployment workflow:

- 16 kHz mono PCM input
- `tokens.txt`
- `keywords.txt`
- `config.yaml`
- exported ONNX model

The training recipe itself is a small CTC model implemented in PyTorch. That keeps the project easy to train locally on macOS while staying compatible with the usual `sherpa-onnx` KWS asset bundle layout.

## What this project is

At a modeling level, KWS here is a **binary wake / non-wake classification problem** implemented with a tiny CTC network:

- `blank` = non-wake / silence / other speech
- `keyword token(s)` = one or more custom wake words

That means:

- you can train with positive and negative clips
- you can swap the ONNX bundle after training
- the mobile app does not need code changes as long as the input feature contract stays the same

The important contract is:

- audio must be 16 kHz
- mono
- PCM
- feature extraction settings must match between training and deployment

## Project Layout

```text
kws-training-project/
  ├── data/
  │    ├── positive/
  │    ├── negative/
  │    ├── manifest/
  ├── configs/
  │    ├── kws_config.yaml
  ├── scripts/
  │    ├── prepare_data.py
  │    ├── train_kws.py
  │    ├── export_onnx.py
  │    ├── text2token.sh
  │    ├── convert_audio.sh
  │    ├── run_pipeline.sh
  ├── models/
  │    ├── checkpoints/
  ├── export/
  │    ├── lumi_kws.onnx
  ├── docs/
  │    ├── sample_collection_guide.md
  │    ├── data_format_spec.md
  │    ├── training_checklist.md
  ├── tools/
  └── README.md
```

The `export/lumi_kws.onnx` file is produced by the export script after training. This repository contains the full code path to generate it.

## Additional Docs

- [Docs Index](docs/README.md)
- [Sample Collection Guide](docs/sample_collection_guide.md)
- [Data Format Spec](docs/data_format_spec.md)
- [Training Checklist](docs/training_checklist.md)

## Prerequisites

Recommended:

- Python 3.10+
- PyTorch
- onnxruntime for deployment/runtime validation

Optional:

- `sherpa-onnx` command-line tools

Example install:

```bash
python3 -m pip install -r requirements.txt
```

## macOS 本机训练命令清单

下面是一套从零开始，在 macOS 本机直接跑通的命令。路径以本项目根目录 `kws-training-project/` 为准。

### 1. 创建并激活虚拟环境

```bash
cd /Users/xinzhang/gitProject/robot/robot_factory/kws/kws-training-project
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

### 2. 准备训练数据目录

```bash
mkdir -p data/positive/Lumi
mkdir -p data/negative
```

### 3. 放入音频文件

把你录好的 wav 文件放到下面位置：

- `data/positive/Lumi/*.wav`
- `data/positive/Hey Robot/*.wav`
- `data/negative/*.wav`

### 4. 生成 manifest 和 tokens

```bash
python3 scripts/prepare_data.py --config configs/kws_config.yaml
```

### 5. 开始训练

```bash
python3 scripts/train_kws.py \
  --config configs/kws_config.yaml \
  --manifest-dir data/manifest \
  --checkpoint-dir models/checkpoints
```

### 6. 导出 ONNX

```bash
python3 scripts/export_onnx.py \
  --config configs/kws_config.yaml \
  --checkpoint models/checkpoints/best_model.pt \
  --output export/lumi_kws.onnx
```

### 7. 运行最小 demo

```bash
python3 tools/demo_stream.py \
  --config configs/kws_config.yaml \
  --checkpoint models/checkpoints/best_model.pt \
  --wav path/to/test.wav
```

### 一键跑完整流程

如果你想把“转码 -> prepare -> train -> export”一次跑完，可以直接用：

```bash
bash scripts/run_pipeline.sh \
  --positive-raw raw_audio/positive \
  --negative-raw raw_audio/negative \
  --tool ffmpeg
```

如果你已经把音频放进 `data/positive/` 和 `data/negative/`，只想直接准备、训练、导出：

```bash
bash scripts/run_pipeline.sh --skip-convert
```

## Data Preparation

Put your recordings here:

- `data/positive/` for keyword clips
- `data/negative/` for non-keyword speech and noise

Each audio file must be:

- `.wav`
- 16 kHz
- mono
- PCM 16-bit

If you organize positive clips under subdirectories, the subdirectory name is treated as the keyword label:

- `data/positive/Lumi/*.wav`
- `data/positive/Hey Robot/*.wav`

## 训练数据怎么收集

KWS 训练数据的核心是覆盖两类样本：

- 正样本：唤醒词本身
- 负样本：其他语音、环境噪声、静音、误触发场景

建议按下面方式采集：

- 正样本尽量来自不同说话人
- 同一个唤醒词要覆盖不同语速、音量、语气
- 录制场景要多样：安静房间、办公室、车内、走路、近讲、远讲
- 负样本要比正样本多，通常至少 5 倍以上
- 负样本里要包含“容易误触发”的内容，比如相似音节、日常对话、背景电视声
- 每条录音尽量短，单句唤醒词通常 0.5 到 2 秒比较合适

如果你要做多关键词训练，推荐目录结构直接按关键词分层：

```text
data/positive/Lumi/*.wav
data/positive/Hey Robot/*.wav
data/negative/*.wav
```

## 数据格式要求

训练脚本只接受满足以下条件的音频：

- 格式：`.wav`
- 采样率：`16 kHz`
- 声道：`mono`
- 位深：`16-bit PCM`
- 编码：非压缩 PCM，不要直接用 `mp3` / `aac`

如果你的录音不是这个格式，先统一转换，再放入 `data/positive/` 或 `data/negative/`。

## 音频批量转换命令

如果你手头是 `mp3`、`m4a`、`aac` 或者采样率不一致的 WAV，先批量转成训练所需格式。

### 使用 ffmpeg

把某个目录下的原始音频批量转换成 16 kHz mono PCM WAV：

```bash
mkdir -p data/positive/Lumi

for input in raw_audio/Lumi/*; do
  base=$(basename "$input")
  name="${base%.*}"
  ffmpeg -y \
    -i "$input" \
    -ac 1 \
    -ar 16000 \
    -c:a pcm_s16le \
    "data/positive/Lumi/${name}.wav"
done
```

把所有负样本也同样转换：

```bash
mkdir -p data/negative

for input in raw_audio/negative/*; do
  base=$(basename "$input")
  name="${base%.*}"
  ffmpeg -y \
    -i "$input" \
    -ac 1 \
    -ar 16000 \
    -c:a pcm_s16le \
    "data/negative/${name}.wav"
done
```

### 使用 sox

如果你更习惯 `sox`，也可以这样转：

```bash
mkdir -p data/positive/Lumi

for input in raw_audio/Lumi/*; do
  base=$(basename "$input")
  name="${base%.*}"
  sox "$input" -c 1 -r 16000 -b 16 "data/positive/Lumi/${name}.wav"
done
```

负样本同理：

```bash
mkdir -p data/negative

for input in raw_audio/negative/*; do
  base=$(basename "$input")
  name="${base%.*}"
  sox "$input" -c 1 -r 16000 -b 16 "data/negative/${name}.wav"
  done
```

如果你想一键递归转换整个目录，可以直接用脚本：

```bash
bash scripts/convert_audio.sh --source raw_audio --dest data/positive --tool ffmpeg
bash scripts/convert_audio.sh --source raw_audio/negative --dest data/negative --tool sox
```

## 数据放在哪里

所有原始训练音频都放在这两个目录下：

- `data/positive/`
- `data/negative/`

准备脚本会自动扫描这两个目录，并生成：

- `data/manifest/train.jsonl`
- `data/manifest/dev.jsonl`
- `data/manifest/test.jsonl`
- `data/manifest/all.jsonl`
- `data/manifest/stats.json`
- `data/manifest/tokens.txt`
- `data/manifest/keywords.txt`

Then run:

```bash
python3 scripts/prepare_data.py --config configs/kws_config.yaml
```

This generates:

- `data/manifest/train.jsonl`
- `data/manifest/dev.jsonl`
- `data/manifest/test.jsonl`
- `data/manifest/all.jsonl`
- `data/manifest/stats.json`
- `data/manifest/keywords_raw.txt`
- `data/manifest/tokens.txt`
- `data/manifest/keywords.txt`

## Keyword Definition

Edit `configs/kws_config.yaml` to set custom wake words:

- `Lumi`
- `Hey Robot`

The normalization logic maps them to tokens such as:

- `<blank>`
- `lumi`
- `hey_robot`

The `scripts/text2token.sh` wrapper falls back to the bundled Python implementation by default.
If you want it to delegate to the official `sherpa-onnx-cli text2token`, set `KWS_USE_SHERPA_TEXT2TOKEN=1`.

Example:

```bash
bash scripts/text2token.sh data/manifest/example_keywords_raw.txt data/manifest/tokens.txt data/manifest/keywords.txt
```

## Training

Train an LSTM model:

```bash
python3 scripts/train_kws.py \
  --config configs/kws_config.yaml \
  --manifest-dir data/manifest \
  --checkpoint-dir models/checkpoints
```

Train a small Conformer instead:

```bash
python3 scripts/train_kws.py \
  --config configs/kws_config.yaml \
  --manifest-dir data/manifest \
  --checkpoint-dir models/checkpoints \
  --encoder conformer
```

Outputs:

- `models/checkpoints/best_model.pt`
- `models/checkpoints/last_model.pt`
- `models/checkpoints/training.log`

## ONNX Export

Export the trained checkpoint to a deployable bundle:

```bash
python3 scripts/export_onnx.py \
  --config configs/kws_config.yaml \
  --checkpoint models/checkpoints/best_model.pt \
  --output export/lumi_kws.onnx
```

The export step also writes:

- `export/tokens.txt`
- `export/config.yaml`
- `export/keywords.txt`

## Minimal Demo

Run streaming inference on a WAV file:

```bash
python3 tools/demo_stream.py \
  --config configs/kws_config.yaml \
  --checkpoint models/checkpoints/best_model.pt \
  --wav path/to/test.wav
```

The exported ONNX bundle is for deployment inside a `sherpa-onnx` runtime, not for the local demo path.

## Deployment Flow

The runtime flow is:

1. microphone or audio stream captures 16 kHz PCM
2. frames are chunked into short windows
3. log-mel features are computed
4. the ONNX model emits CTC logits
5. the decoder checks whether a keyword token dominates a short streaming window
6. a wake event is triggered

This is intended to be always-on and low power:

- keep the feature extractor and model small
- use short streaming chunks
- detect on the keyword posterior instead of long post-processing

## Android / iOS

The deployment pattern is the same on Android and iOS:

- bundle `lumi_kws.onnx`
- bundle `tokens.txt`
- bundle `config.yaml`
- ensure the app feeds 16 kHz mono PCM to the runtime

If the app already has an audio capture pipeline, you usually only need to replace the model bundle:

- no UI code change
- no navigation code change
- no wake-word logic rewrite

That hot swap is only valid if the input feature contract stays identical.

## sherpa-onnx Notes

The official `sherpa-onnx` KWS docs describe keyword files and token conversion through `sherpa-onnx-cli text2token`.

This project follows the same asset contract:

- `tokens.txt`
- `keywords.txt`
- 16 kHz PCM
- short streaming chunks

The actual exported network here is a small CTC model tailored for custom wake-word classification.

## Example Data Format

`data/manifest/*.jsonl` entries look like this:

```json
{"id":"positive_0001","audio_filepath":"data/positive/lumi_0001.wav","duration":1.42,"label":"positive","keyword":"lumi","transcript":"lumi","is_positive":true}
{"id":"negative_0001","audio_filepath":"data/negative/noise_0001.wav","duration":2.10,"label":"negative","keyword":"","transcript":"","is_positive":false}
```

`keywords_raw.txt` entries look like this:

```text
Lumi :1.5 #0.35 @Lumi
Hey Robot :1.5 #0.35 @Hey Robot
```

`tokens.txt` entries look like this:

```text
<blank>
lumi
hey_robot
```

## Notes

- The model is intentionally small so it can be used as an always-on wake-word detector.
- The model itself is not the product UI. It is a hot-swappable backend artifact.
- Feature consistency matters more than model swap convenience. Keep sample rate and log-mel settings fixed across training and deployment.
