#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_pipeline.sh [options]

Options:
  --config <path>          Config file, default: configs/kws_config.yaml
  --positive-raw <dir>     Optional raw positive audio directory
  --negative-raw <dir>     Optional raw negative audio directory
  --positive-dest <dir>    Converted positive audio destination, default: data/positive
  --negative-dest <dir>    Converted negative audio destination, default: data/negative
  --tool ffmpeg|sox        Audio conversion tool, default: ffmpeg
  --sample-rate <rate>     Conversion sample rate, default: 16000
  --manifest-dir <dir>     Manifest directory, default: data/manifest
  --checkpoint-dir <dir>   Checkpoint directory, default: models/checkpoints
  --export-dir <dir>       Export bundle directory, default: export
  --output <path>          Exported ONNX path, default: export/lumi_kws.onnx
  --encoder <type>         Encoder override, lstm or conformer
  --skip-convert           Skip audio conversion step
  -h, --help               Show this help

Examples:
  # Full flow from raw audio
  ./scripts/run_pipeline.sh \
    --positive-raw raw_audio/positive \
    --negative-raw raw_audio/negative \
    --tool ffmpeg

  # Data already prepared, just prepare/train/export
  ./scripts/run_pipeline.sh --skip-convert

Notes:
  - Conversion is recursive and preserves subdirectories.
  - This script expects python3 available in PATH.
  - The project-local virtualenv can be activated before running this script.
EOF
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="configs/kws_config.yaml"
POS_RAW=""
NEG_RAW=""
POS_DEST="data/positive"
NEG_DEST="data/negative"
TOOL="ffmpeg"
SAMPLE_RATE="16000"
MANIFEST_DIR="data/manifest"
CHECKPOINT_DIR="models/checkpoints"
EXPORT_DIR="export"
OUTPUT_PATH="export/lumi_kws.onnx"
ENCODER=""
SKIP_CONVERT="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    --positive-raw)
      POS_RAW="${2:-}"
      shift 2
      ;;
    --negative-raw)
      NEG_RAW="${2:-}"
      shift 2
      ;;
    --positive-dest)
      POS_DEST="${2:-}"
      shift 2
      ;;
    --negative-dest)
      NEG_DEST="${2:-}"
      shift 2
      ;;
    --tool)
      TOOL="${2:-}"
      shift 2
      ;;
    --sample-rate)
      SAMPLE_RATE="${2:-}"
      shift 2
      ;;
    --manifest-dir)
      MANIFEST_DIR="${2:-}"
      shift 2
      ;;
    --checkpoint-dir)
      CHECKPOINT_DIR="${2:-}"
      shift 2
      ;;
    --export-dir)
      EXPORT_DIR="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    --encoder)
      ENCODER="${2:-}"
      shift 2
      ;;
    --skip-convert)
      SKIP_CONVERT="1"
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

cd "$ROOT_DIR"

if [[ "$SKIP_CONVERT" != "1" ]]; then
  if [[ -n "$POS_RAW" ]]; then
    bash scripts/convert_audio.sh --source "$POS_RAW" --dest "$POS_DEST" --tool "$TOOL" --sample-rate "$SAMPLE_RATE"
  fi
  if [[ -n "$NEG_RAW" ]]; then
    bash scripts/convert_audio.sh --source "$NEG_RAW" --dest "$NEG_DEST" --tool "$TOOL" --sample-rate "$SAMPLE_RATE"
  fi
fi

python3 scripts/prepare_data.py --config "$CONFIG_PATH"

train_args=(
  python3 scripts/train_kws.py
  --config "$CONFIG_PATH"
  --manifest-dir "$MANIFEST_DIR"
  --checkpoint-dir "$CHECKPOINT_DIR"
)
if [[ -n "$ENCODER" ]]; then
  train_args+=(--encoder "$ENCODER")
fi
"${train_args[@]}"

python3 scripts/export_onnx.py \
  --config "$CONFIG_PATH" \
  --checkpoint "$CHECKPOINT_DIR/best_model.pt" \
  --output "$OUTPUT_PATH" \
  --export-dir "$EXPORT_DIR"

echo "Pipeline finished successfully."
echo "ONNX bundle: $OUTPUT_PATH"

