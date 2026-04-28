#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VOICE_MODELS_ROOT="${VOICE_MODELS_ROOT:-$REPO_ROOT/apps/robot_app/voice_control_sdk/assets/voice_models}"
KWS_DIR="${KWS_DIR:-$VOICE_MODELS_ROOT/kws/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20}"
ASR_DIR="${ASR_DIR:-$VOICE_MODELS_ROOT/asr/sherpa-onnx-streaming-zipformer-small-bilingual-zh-en-2023-02-16}"
VAD_FILE="${VAD_FILE:-$VOICE_MODELS_ROOT/vad/silero_vad.onnx}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  scripts/prune_voice_models.sh [--dry-run]

Environment overrides:
  VOICE_MODELS_ROOT   Root directory for voice assets
  KWS_DIR             KWS model directory
  ASR_DIR             ASR model directory
  VAD_FILE            VAD onnx file path

The script keeps only the minimal publish set:
  KWS: encoder/joiner int8 + official decoder + tokens.txt
  ASR: encoder/decoder/joiner int8 + tokens.txt + bpe.model
  VAD: silero_vad.onnx
EOF
}

log() {
  printf '%s\n' "$*"
}

remove_path() {
  local path="$1"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "rm -rf $path"
    return
  fi
  rm -rf "$path"
}

prune_directory() {
  local dir="$1"
  shift

  if [[ ! -d "$dir" ]]; then
    echo "Missing directory: $dir" >&2
    exit 1
  fi

  local -a keep_names=("$@")
  local entry
  while IFS= read -r -d '' entry; do
    local name="${entry##*/}"
    local keep=0
    local keep_name
    for keep_name in "${keep_names[@]}"; do
      if [[ "$name" == "$keep_name" ]]; then
        keep=1
        break
      fi
    done
    if [[ $keep -eq 0 ]]; then
      remove_path "$entry"
    fi
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0)
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
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

prune_directory "$KWS_DIR" \
  encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx \
  decoder-epoch-13-avg-2-chunk-16-left-64.onnx \
  joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx \
  tokens.txt

prune_directory "$ASR_DIR" \
  encoder-epoch-99-avg-1.int8.onnx \
  decoder-epoch-99-avg-1.int8.onnx \
  joiner-epoch-99-avg-1.int8.onnx \
  tokens.txt \
  bpe.model

if [[ ! -f "$VAD_FILE" ]]; then
  echo "Missing VAD file: $VAD_FILE" >&2
  exit 1
fi

log "Voice model pruning complete."
log "Kept:"
log "  KWS: $KWS_DIR"
log "  ASR: $ASR_DIR"
log "  VAD: $VAD_FILE"
