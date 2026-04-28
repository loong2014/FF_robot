# Training Checklist

Use this checklist before running the training pipeline.

## Before Training

- [ ] Virtual environment created
- [ ] Dependencies installed
- [ ] Audio files placed under `data/positive/` and `data/negative/`
- [ ] All audio is 16 kHz mono PCM WAV
- [ ] Positive samples cover all intended wake words
- [ ] Negative samples include noise and near-miss speech

## Prepare Data

Run:

```bash
python3 scripts/prepare_data.py --config configs/kws_config.yaml
```

Or use the one-shot pipeline:

```bash
bash scripts/run_pipeline.sh --skip-convert
```

Check that these files exist:

- `data/manifest/train.jsonl`
- `data/manifest/dev.jsonl`
- `data/manifest/test.jsonl`
- `data/manifest/tokens.txt`
- `data/manifest/keywords.txt`
- `data/manifest/keywords_raw.txt`

## Train

Run:

```bash
python3 scripts/train_kws.py \
  --config configs/kws_config.yaml \
  --manifest-dir data/manifest \
  --checkpoint-dir models/checkpoints
```

Confirm the outputs:

- `models/checkpoints/best_model.pt`
- `models/checkpoints/last_model.pt`
- `models/checkpoints/training.log`

## Export

Run:

```bash
python3 scripts/export_onnx.py \
  --config configs/kws_config.yaml \
  --checkpoint models/checkpoints/best_model.pt \
  --output export/lumi_kws.onnx
```

Confirm the outputs:

- `export/lumi_kws.onnx`
- `export/tokens.txt`
- `export/config.yaml`
- `export/keywords.txt`

## Validate

- [ ] `tokens.txt` starts with `<blank>`
- [ ] `keywords.txt` matches the intended wake words
- [ ] `config.yaml` matches the training feature settings
- [ ] The ONNX export path exists
- [ ] The input feature contract remains 16 kHz mono PCM

## Common Failure Points

- Wrong sample rate
- Stereo audio
- AAC / MP3 files renamed to `.wav`
- Too few negative samples
- Positive samples from only one speaker
- Keywords in the config not matching the folder names
