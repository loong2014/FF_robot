from __future__ import annotations

import argparse
import json
from pathlib import Path

try:
    import torch
except Exception:  # pragma: no cover
    torch = None

from kws_training_project.config import load_config
from kws_training_project.streaming import StreamingKeywordSpotter


def run_torch_backend(args):
    checkpoint = torch.load(args.checkpoint, map_location="cpu")
    config = dict(load_config(args.config))
    config.update(checkpoint.get("config", {}))
    tokens = checkpoint["tokens"]
    spotter = StreamingKeywordSpotter(config=config, tokens=tokens, checkpoint=checkpoint)
    events = spotter.accept_wav_file(args.wav, chunk_samples=args.chunk_samples)
    if not events:
        print("No keyword detected.")
        return 0
    for event in events:
        print(
            json.dumps(
                {
                    "keyword": event.keyword,
                    "score": round(event.score, 4),
                    "frame_index": event.frame_index,
                    "sample_index": event.sample_index,
                },
                ensure_ascii=False,
            )
        )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Minimal streaming KWS demo.")
    parser.add_argument("--config", required=True, help="Path to config.yaml")
    parser.add_argument("--wav", required=True, help="Input 16 kHz mono PCM wav file")
    parser.add_argument("--checkpoint", required=True, help="PyTorch checkpoint for the demo backend")
    parser.add_argument("--chunk-samples", type=int, default=1600, help="Streaming chunk size in samples")
    args = parser.parse_args()

    return run_torch_backend(args)


if __name__ == "__main__":
    raise SystemExit(main())
