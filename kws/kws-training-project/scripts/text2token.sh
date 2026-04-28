#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <keywords_raw.txt> <tokens.txt> <keywords.txt>" >&2
  exit 1
fi

RAW_TEXT=$1
TOKENS_OUT=$2
ENCODED_OUT=$3

if [[ "${KWS_USE_SHERPA_TEXT2TOKEN:-0}" == "1" ]] && command -v sherpa-onnx-cli >/dev/null 2>&1; then
  exec sherpa-onnx-cli text2token --text "$RAW_TEXT" --tokens "$TOKENS_OUT" "$RAW_TEXT" "$ENCODED_OUT"
fi

exec python3 "$SCRIPT_DIR/../tools/text2token.py" "$RAW_TEXT" "$TOKENS_OUT" "$ENCODED_OUT"
