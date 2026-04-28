#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  convert_audio.sh --source <raw_audio_dir> --dest <output_dir> [--tool ffmpeg|sox] [--sample-rate 16000]

Examples:
  # Convert raw_audio/Lumi/*.mp3 to data/positive/Lumi/*.wav
  ./scripts/convert_audio.sh --source raw_audio --dest data/positive --tool ffmpeg

  # Convert negative samples with sox
  ./scripts/convert_audio.sh --source raw_audio/negative --dest data/negative --tool sox

Notes:
  - The script walks the source tree recursively.
  - It preserves relative subdirectories under the destination directory.
  - Output files are always 16 kHz, mono, 16-bit PCM WAV.
EOF
}

tool="ffmpeg"
sample_rate="16000"
source_dir=""
dest_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      source_dir="${2:-}"
      shift 2
      ;;
    --dest)
      dest_dir="${2:-}"
      shift 2
      ;;
    --tool)
      tool="${2:-}"
      shift 2
      ;;
    --sample-rate)
      sample_rate="${2:-}"
      shift 2
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

if [[ -z "$source_dir" || -z "$dest_dir" ]]; then
  echo "Both --source and --dest are required." >&2
  usage >&2
  exit 1
fi

if [[ ! -d "$source_dir" ]]; then
  echo "Source directory does not exist: $source_dir" >&2
  exit 1
fi

mkdir -p "$dest_dir"

convert_with_ffmpeg() {
  local input="$1"
  local output="$2"
  ffmpeg -y -i "$input" -ac 1 -ar "$sample_rate" -c:a pcm_s16le "$output" >/dev/null 2>&1
}

convert_with_sox() {
  local input="$1"
  local output="$2"
  sox "$input" -c 1 -r "$sample_rate" -b 16 "$output" >/dev/null 2>&1
}

case "$tool" in
  ffmpeg|sox)
    ;;
  *)
    echo "Unsupported tool: $tool" >&2
    echo "Choose ffmpeg or sox." >&2
    exit 1
    ;;
esac

while IFS= read -r -d '' input; do
  rel_path="${input#"$source_dir"/}"
  rel_dir="$(dirname "$rel_path")"
  base_name="$(basename "${input%.*}")"
  output_dir="$dest_dir/$rel_dir"
  output_file="$output_dir/$base_name.wav"
  mkdir -p "$output_dir"

  if [[ "$tool" == "ffmpeg" ]]; then
    convert_with_ffmpeg "$input" "$output_file"
  else
    convert_with_sox "$input" "$output_file"
  fi

  echo "converted: $input -> $output_file"
done < <(find "$source_dir" -type f \( -iname '*.wav' -o -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.flac' -o -iname '*.ogg' \) -print0)

