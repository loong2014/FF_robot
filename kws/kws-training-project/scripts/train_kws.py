from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from kws_training_project.config import load_config
from kws_training_project.train import train_model


def main() -> int:
    parser = argparse.ArgumentParser(description="Train a tiny CTC KWS model.")
    parser.add_argument("--config", default="configs/kws_config.yaml", help="Path to config.yaml")
    parser.add_argument("--manifest-dir", default="data/manifest", help="Manifest directory")
    parser.add_argument("--checkpoint-dir", default="models/checkpoints", help="Checkpoint directory")
    parser.add_argument("--encoder", choices=["lstm", "conformer"], help="Override encoder type")
    args = parser.parse_args()

    config = load_config(Path(args.config))
    summary = train_model(
        config=config,
        manifest_dir=ROOT / Path(args.manifest_dir),
        checkpoint_dir=ROOT / Path(args.checkpoint_dir),
        encoder_override=args.encoder,
    )
    print(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

