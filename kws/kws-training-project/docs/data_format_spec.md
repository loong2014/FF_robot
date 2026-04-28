# Data Format Spec

This document defines the file format used by the KWS training pipeline.

## Raw Audio

Accepted raw input:

- file type: `.wav`
- sample rate: `16000`
- channels: `1`
- sample width: `16-bit`
- codec: PCM / uncompressed WAV

Non-compliant sources should be converted before training.

## Input Directories

Place raw data here:

- `data/positive/`
- `data/negative/`

Optional multi-keyword layout:

```text
data/positive/Lumi/*.wav
data/positive/Hey Robot/*.wav
data/negative/*.wav
```

## Generated Artifacts

After running `scripts/prepare_data.py`, the pipeline generates:

- `data/manifest/train.jsonl`
- `data/manifest/dev.jsonl`
- `data/manifest/test.jsonl`
- `data/manifest/all.jsonl`
- `data/manifest/stats.json`
- `data/manifest/keywords_raw.txt`
- `data/manifest/tokens.txt`
- `data/manifest/keywords.txt`

After training:

- `models/checkpoints/best_model.pt`
- `models/checkpoints/last_model.pt`
- `models/checkpoints/training.log`

After export:

- `export/lumi_kws.onnx`
- `export/tokens.txt`
- `export/config.yaml`
- `export/keywords.txt`
- `export/metadata.json`

## Manifest Schema

Each JSONL line is one sample:

```json
{
  "id": "positive_0001",
  "audio_filepath": "data/positive/Lumi/lumi_0001.wav",
  "duration": 1.42,
  "label": "positive",
  "keyword": "lumi",
  "transcript": "lumi",
  "is_positive": true
}
```

Negative samples look like:

```json
{
  "id": "negative_0001",
  "audio_filepath": "data/negative/noise_0001.wav",
  "duration": 2.10,
  "label": "negative",
  "keyword": "",
  "transcript": "",
  "is_positive": false
}
```

## Keyword Files

`keywords_raw.txt` contains the human-readable keyword definitions:

```text
Lumi :1.5 #0.35 @Lumi
Hey Robot :1.5 #0.35 @Hey Robot
```

`tokens.txt` contains the vocabulary used by the model:

```text
<blank>
lumi
hey_robot
```

`keywords.txt` contains the encoded keyword lines used by the runtime bundle.

## Conversion Commands

If your source audio is not already compliant, convert it first:

```bash
ffmpeg -y -i input.wav -ac 1 -ar 16000 -c:a pcm_s16le output.wav
```

Or with `sox`:

```bash
sox input.wav -c 1 -r 16000 -b 16 output.wav
```

You can also use the project script for recursive batch conversion:

```bash
bash scripts/convert_audio.sh --source raw_audio --dest data/positive --tool ffmpeg
```
