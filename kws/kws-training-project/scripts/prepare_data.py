from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from kws_training_project.config import load_config
from kws_training_project.data import build_manifests


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare manifests for KWS training.")
    parser.add_argument("--config", default="configs/kws_config.yaml", help="Path to config.yaml")
    parser.add_argument("--data-root", default="data", help="Project data root")
    args = parser.parse_args()

    config = load_config(Path(args.config))
    data_root = Path(args.data_root)
    manifest_dir = ROOT / Path(config.get("manifest_dir", data_root / "manifest"))
    stats = build_manifests(
        positive_dir=ROOT / Path(config.get("positive_dir", data_root / "positive")),
        negative_dir=ROOT / Path(config.get("negative_dir", data_root / "negative")),
        manifest_dir=manifest_dir,
        sample_rate=int(config.get("sample_rate", 16000)),
        train_ratio=float(config.get("train_split", 0.8)),
        dev_ratio=float(config.get("dev_split", 0.1)),
        test_ratio=float(config.get("test_split", 0.1)),
        keywords=config.get("keywords", []),
        seed=int(config.get("random_seed", 42)),
    )
    print(stats)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

