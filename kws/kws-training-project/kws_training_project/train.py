from __future__ import annotations

import csv
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple

try:
    import torch
    import torch.nn.functional as F
    from torch.utils.data import DataLoader, Dataset
except Exception:  # pragma: no cover
    torch = None
    F = None
    DataLoader = None
    Dataset = object

from .audio import read_wav_pcm16
from .features import feature_lengths, log_mel_spectrogram
from .model import build_model
from .tokenizer import build_tokens_txt, normalize_phrase
from .utils import ensure_dir, load_json, read_jsonl, save_json, set_seed, timestamp


def _require_torch() -> None:
    if torch is None:
        raise RuntimeError("PyTorch is required for training.")


class KeywordDataset(Dataset):
    def __init__(self, manifest_path: str | Path, tokens: Sequence[str], config: Dict[str, Any]):
        self.records = read_jsonl(manifest_path)
        self.tokens = list(tokens)
        self.token_to_id = {token: index for index, token in enumerate(self.tokens)}
        self.config = config
        self.sample_rate = int(config["sample_rate"])
        self.num_mel_bins = int(config["num_mel_bins"])
        self.frame_length_ms = int(config["frame_length_ms"])
        self.frame_shift_ms = int(config["frame_shift_ms"])

    def __len__(self) -> int:
        return len(self.records)

    def _encode_target(self, record: Dict[str, Any]) -> List[int]:
        if not record.get("is_positive"):
            return []
        keyword = normalize_phrase(record.get("keyword") or record.get("transcript") or "")
        if not keyword:
            return []
        token_id = self.token_to_id.get(keyword)
        if token_id is None:
            raise KeyError(f"Keyword token '{keyword}' not found in tokens.txt")
        return [token_id]

    def __getitem__(self, index: int):
        record = self.records[index]
        samples = read_wav_pcm16(record["audio_filepath"], sample_rate=self.sample_rate)
        waveform = torch.tensor(samples, dtype=torch.float32)
        features = log_mel_spectrogram(
            waveform,
            sample_rate=self.sample_rate,
            num_mel_bins=self.num_mel_bins,
            frame_length_ms=self.frame_length_ms,
            frame_shift_ms=self.frame_shift_ms,
        )
        target = self._encode_target(record)
        return {
            "features": features,
            "feature_length": features.size(0),
            "target": torch.tensor(target, dtype=torch.long),
            "target_length": len(target),
            "label": record.get("label", ""),
            "record": record,
        }


def collate_batch(batch):
    feature_lengths = torch.tensor([item["feature_length"] for item in batch], dtype=torch.long)
    max_len = int(feature_lengths.max().item()) if len(batch) else 0
    feat_dim = int(batch[0]["features"].size(1)) if batch else 0
    features = torch.zeros(len(batch), max_len, feat_dim, dtype=torch.float32)
    for row, item in enumerate(batch):
        features[row, : item["feature_length"]] = item["features"]
    target_pieces = [item["target"] for item in batch if item["target_length"] > 0]
    targets = torch.cat(target_pieces, dim=0) if target_pieces else torch.empty(0, dtype=torch.long)
    target_lengths = torch.tensor([item["target_length"] for item in batch], dtype=torch.long)
    labels = [item["label"] for item in batch]
    records = [item["record"] for item in batch]
    return features, feature_lengths, targets, target_lengths, labels, records


def greedy_decode(logits, lengths):
    probs = torch.log_softmax(logits, dim=-1)
    best = probs.argmax(dim=-1)
    outputs = []
    for row, length in zip(best, lengths):
        prev = None
        seq = []
        for token in row[: int(length.item())].tolist():
            if token == 0:
                prev = None
                continue
            if token != prev:
                seq.append(token)
            prev = token
        outputs.append(seq)
    return outputs


def evaluate(model, dataloader, device, blank_id: int = 0):
    model.eval()
    total_loss = 0.0
    total_items = 0
    correct = 0
    positive_total = 0
    positive_correct = 0
    criterion = torch.nn.CTCLoss(blank=blank_id, zero_infinity=True)
    with torch.no_grad():
        for features, lengths, targets, target_lengths, labels, records in dataloader:
            features = features.to(device)
            lengths = lengths.to(device)
            targets = targets.to(device)
            target_lengths = target_lengths.to(device)
            logits, out_lengths, _ = model(features, lengths)
            log_probs = torch.log_softmax(logits, dim=-1).transpose(0, 1)
            loss = criterion(log_probs, targets, out_lengths.cpu(), target_lengths.cpu())
            total_loss += float(loss.item()) * len(labels)
            total_items += len(labels)
            decoded = greedy_decode(logits, out_lengths)
            for seq, record in zip(decoded, records):
                predicted_positive = len(seq) > 0
                target_positive = bool(record.get("is_positive"))
                if predicted_positive == target_positive:
                    correct += 1
                if target_positive:
                    positive_total += 1
                    if predicted_positive:
                        positive_correct += 1
    accuracy = correct / total_items if total_items else 0.0
    positive_recall = positive_correct / positive_total if positive_total else 0.0
    return {
        "loss": total_loss / total_items if total_items else 0.0,
        "accuracy": accuracy,
        "positive_recall": positive_recall,
        "items": total_items,
    }


def train_model(config: Dict[str, Any], manifest_dir: str | Path, checkpoint_dir: str | Path, encoder_override: str | None = None):
    _require_torch()
    set_seed(int(config.get("random_seed", 42)))
    checkpoint_dir = ensure_dir(checkpoint_dir)
    manifest_dir = Path(manifest_dir)
    tokens_path = manifest_dir / "tokens.txt"
    if not tokens_path.exists():
        raise FileNotFoundError(f"Missing {tokens_path}. Run prepare_data.py first.")
    with open(tokens_path, "r", encoding="utf-8") as f:
        tokens = [line.strip() for line in f if line.strip()]
    if not tokens or tokens[0] != "<blank>":
        raise ValueError("tokens.txt must start with <blank>.")

    train_manifest = manifest_dir / "train.jsonl"
    dev_manifest = manifest_dir / "dev.jsonl"
    if not train_manifest.exists() or not dev_manifest.exists():
        raise FileNotFoundError("Missing train/dev manifests. Run prepare_data.py first.")

    if encoder_override:
        config = dict(config)
        config["encoder_type"] = encoder_override

    train_set = KeywordDataset(train_manifest, tokens, config)
    dev_set = KeywordDataset(dev_manifest, tokens, config)
    train_loader = DataLoader(
        train_set,
        batch_size=int(config.get("batch_size", 16)),
        shuffle=True,
        num_workers=0,
        collate_fn=collate_batch,
    )
    dev_loader = DataLoader(
        dev_set,
        batch_size=int(config.get("batch_size", 16)),
        shuffle=False,
        num_workers=0,
        collate_fn=collate_batch,
    )

    device_name = config.get("device", "cpu")
    if device_name == "mps" and not torch.backends.mps.is_available():
        device_name = "cpu"
    device = torch.device(device_name)

    model = build_model(vocab_size=len(tokens), config=config).to(device)
    optimizer = torch.optim.AdamW(
        model.parameters(),
        lr=float(config.get("learning_rate", 1e-3)),
        weight_decay=float(config.get("weight_decay", 1e-4)),
    )
    criterion = torch.nn.CTCLoss(blank=0, zero_infinity=True)

    log_path = checkpoint_dir / "training.log"
    best_path = checkpoint_dir / "best_model.pt"
    last_path = checkpoint_dir / "last_model.pt"
    best_loss = float("inf")
    epochs = int(config.get("epochs", 20))

    with open(log_path, "w", encoding="utf-8") as log_file:
        log_file.write(f"{timestamp()} start training\n")
        for epoch in range(1, epochs + 1):
            model.train()
            running_loss = 0.0
            item_count = 0
            for features, lengths, targets, target_lengths, labels, records in train_loader:
                features = features.to(device)
                lengths = lengths.to(device)
                targets = targets.to(device)
                target_lengths = target_lengths.to(device)
                optimizer.zero_grad()
                logits, out_lengths, _ = model(features, lengths)
                log_probs = torch.log_softmax(logits, dim=-1).transpose(0, 1)
                loss = criterion(log_probs, targets, out_lengths.cpu(), target_lengths.cpu())
                loss.backward()
                torch.nn.utils.clip_grad_norm_(model.parameters(), 5.0)
                optimizer.step()
                running_loss += float(loss.item()) * len(labels)
                item_count += len(labels)

            train_loss = running_loss / item_count if item_count else 0.0
            dev_metrics = evaluate(model, dev_loader, device)
            line = (
                f"{timestamp()} epoch={epoch} train_loss={train_loss:.4f} "
                f"dev_loss={dev_metrics['loss']:.4f} dev_acc={dev_metrics['accuracy']:.3f} "
                f"dev_recall={dev_metrics['positive_recall']:.3f}"
            )
            print(line)
            log_file.write(line + "\n")
            log_file.flush()

            checkpoint = {
                "model_state_dict": model.state_dict(),
                "optimizer_state_dict": optimizer.state_dict(),
                "config": config,
                "tokens": tokens,
                "epoch": epoch,
                "dev_metrics": dev_metrics,
            }
            torch.save(checkpoint, last_path)
            if dev_metrics["loss"] <= best_loss:
                best_loss = dev_metrics["loss"]
                torch.save(checkpoint, best_path)

        log_file.write(f"{timestamp()} finished training\n")

    summary = {
        "best_model": str(best_path),
        "last_model": str(last_path),
        "log": str(log_path),
        "best_dev_loss": best_loss,
    }
    save_json(checkpoint_dir / "summary.json", summary)
    return summary
