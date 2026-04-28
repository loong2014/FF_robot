from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from kws_training_project.config import load_config
from kws_training_project.export import export_model


def main() -> int:
    parser = argparse.ArgumentParser(description="Export a trained KWS checkpoint to ONNX.")
    parser.add_argument("--config", default="configs/kws_config.yaml", help="Path to config.yaml")
    parser.add_argument("--checkpoint", default="models/checkpoints/best_model.pt", help="Training checkpoint")
    parser.add_argument("--output", default="export/lumi_kws.onnx", help="Output ONNX path")
    parser.add_argument("--export-dir", default="export", help="Directory for config/tokens/keywords bundle")
    args = parser.parse_args()

    config = load_config(Path(args.config))
    metadata = export_model(
        config=config,
        checkpoint_path=ROOT / Path(args.checkpoint),
        output_path=ROOT / Path(args.output),
        export_dir=ROOT / Path(args.export_dir),
    )
    print(metadata)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

