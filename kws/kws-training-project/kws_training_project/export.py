from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

try:
    import torch
except Exception:  # pragma: no cover
    torch = None

from .config import save_config
from .data import collect_wavs
from .model import build_model
from .tokenizer import write_encoded_keywords, write_tokens_file
from .utils import ensure_dir, load_json, save_json


def _require_torch() -> None:
    if torch is None:
        raise RuntimeError("PyTorch is required for ONNX export.")


def _to_export_config(config: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "project_name": config.get("project_name", "kws"),
        "sample_rate": int(config.get("sample_rate", 16000)),
        "num_mel_bins": int(config.get("num_mel_bins", 40)),
        "frame_length_ms": int(config.get("frame_length_ms", 25)),
        "frame_shift_ms": int(config.get("frame_shift_ms", 10)),
        "encoder_type": config.get("encoder_type", "lstm"),
        "input_dim": int(config.get("input_dim", 40)),
        "hidden_dim": int(config.get("hidden_dim", 128)),
        "num_layers": int(config.get("num_layers", 2)),
        "num_heads": int(config.get("num_heads", 4)),
        "ff_dim": int(config.get("ff_dim", 256)),
        "conv_kernel": int(config.get("conv_kernel", 15)),
        "dropout": float(config.get("dropout", 0.1)),
        "streaming": config.get("streaming", {}),
        "keywords": config.get("keywords", []),
    }


def export_model(config: Dict[str, Any], checkpoint_path: str | Path, output_path: str | Path, export_dir: str | Path | None = None) -> Dict[str, Any]:
    _require_torch()
    checkpoint = torch.load(checkpoint_path, map_location="cpu")
    tokens = checkpoint["tokens"]
    export_config = dict(config)
    if "config" in checkpoint:
        export_config.update(checkpoint["config"])
    export_config = _to_export_config(export_config)
    export_dir = ensure_dir(export_dir or Path(output_path).parent)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    model = build_model(vocab_size=len(tokens), config=export_config)
    model.load_state_dict(checkpoint["model_state_dict"])
    model.eval()

    sample_rate = int(export_config["sample_rate"])
    num_mel_bins = int(export_config["num_mel_bins"])
    frame_length_ms = int(export_config["frame_length_ms"])
    frame_shift_ms = int(export_config["frame_shift_ms"])

    class ExportWrapper(torch.nn.Module):
        def __init__(self, kws_model):
            super().__init__()
            self.kws_model = kws_model

        def forward(self, features, lengths):
            logits, out_lengths = self.kws_model.forward_export(features, lengths)
            return logits, out_lengths

    wrapper = ExportWrapper(model)
    dummy_features = torch.randn(1, 32, num_mel_bins, dtype=torch.float32)
    dummy_lengths = torch.tensor([32], dtype=torch.long)

    torch.onnx.export(
        wrapper,
        (dummy_features, dummy_lengths),
        str(output_path),
        input_names=["features", "lengths"],
        output_names=["logits", "out_lengths"],
        dynamic_axes={
            "features": {0: "batch", 1: "time"},
            "lengths": {0: "batch"},
            "logits": {0: "batch", 1: "time"},
            "out_lengths": {0: "batch"},
        },
        opset_version=17,
    )

    export_tokens = write_tokens_file(export_dir / "tokens.txt", [token for token in tokens if token != "<blank>"])
    raw_keywords = []
    for keyword in export_config.get("keywords", []):
        raw_keywords.append(f"{keyword} :{config.get('keyword_boost', 1.5)} #{config.get('keyword_threshold', 0.35)} @{keyword}")
    if not raw_keywords:
        raw_keywords = ["Lumi :1.5 #0.35 @Lumi"]
    encoded_keywords = write_encoded_keywords(export_dir / "keywords.txt", raw_keywords)
    save_config(export_dir / "config.yaml", export_config)

    metadata = {
        "onnx_path": str(output_path),
        "tokens_path": str(export_dir / "tokens.txt"),
        "keywords_path": str(export_dir / "keywords.txt"),
        "config_path": str(export_dir / "config.yaml"),
        "vocab_size": len(tokens),
        "sample_rate": sample_rate,
        "num_mel_bins": num_mel_bins,
        "frame_length_ms": frame_length_ms,
        "frame_shift_ms": frame_shift_ms,
        "encoder_type": export_config["encoder_type"],
    }
    save_json(export_dir / "metadata.json", metadata)
    return metadata
