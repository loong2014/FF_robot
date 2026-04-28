from __future__ import annotations

import json
import math
import random
from pathlib import Path
from typing import Any, Dict, Iterable, List, Sequence, Tuple

from .audio import validate_wav_16k_mono_pcm, wav_duration
from .tokenizer import keyword_specs_from_phrases, normalize_phrase, write_encoded_keywords, write_tokens_file
from .utils import ensure_dir, save_json, write_jsonl


def collect_wavs(directory: str | Path) -> List[Path]:
    base = Path(directory)
    if not base.exists():
        return []
    wavs = sorted([path for path in base.rglob("*.wav") if path.is_file()])
    return wavs


def make_manifest_entry(path: Path, label: str, keyword: str, sample_rate: int, record_id: str | None = None) -> Dict[str, Any]:
    validate_wav_16k_mono_pcm(path, sample_rate=sample_rate)
    duration = wav_duration(path)
    normalized = normalize_phrase(keyword) if keyword else ""
    return {
        "id": record_id or path.stem,
        "audio_filepath": str(path),
        "duration": round(duration, 3),
        "label": label,
        "keyword": normalized,
        "transcript": normalized,
        "is_positive": label == "positive",
    }


def split_records(records: Sequence[Dict[str, Any]], train_ratio: float, dev_ratio: float, seed: int) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], List[Dict[str, Any]]]:
    items = list(records)
    random.Random(seed).shuffle(items)
    n = len(items)
    n_train = int(round(n * train_ratio))
    n_dev = int(round(n * dev_ratio))
    if n_train + n_dev > n:
        n_dev = max(0, n - n_train)
    train = items[:n_train]
    dev = items[n_train : n_train + n_dev]
    test = items[n_train + n_dev :]
    return train, dev, test


def build_manifests(
    positive_dir: str | Path,
    negative_dir: str | Path,
    manifest_dir: str | Path,
    sample_rate: int,
    train_ratio: float,
    dev_ratio: float,
    test_ratio: float,
    keywords: Sequence[str],
    seed: int = 42,
) -> Dict[str, Any]:
    manifest_path = ensure_dir(manifest_dir)
    positive_paths = collect_wavs(positive_dir)
    negative_paths = collect_wavs(negative_dir)
    if not positive_paths and not negative_paths:
        raise FileNotFoundError(
            "No wav files found. Put 16 kHz mono PCM wavs under data/positive and data/negative."
        )

    keyword_specs = keyword_specs_from_phrases(keywords)
    positive_keyword_cycle = [spec.original for spec in keyword_specs] or ["lumi"]

    positive_records: List[Dict[str, Any]] = []
    for index, wav_path in enumerate(positive_paths):
        try:
            rel_parts = wav_path.relative_to(Path(positive_dir)).parts
        except Exception:
            rel_parts = ()
        record_id = "positive_" + "_".join(Path(*rel_parts).with_suffix("").parts) if rel_parts else f"positive_{wav_path.stem}"
        if len(rel_parts) > 1:
            keyword = rel_parts[0]
        else:
            keyword = positive_keyword_cycle[index % len(positive_keyword_cycle)]
        positive_records.append(make_manifest_entry(wav_path, "positive", keyword, sample_rate, record_id=record_id))

    negative_records: List[Dict[str, Any]] = []
    for wav_path in negative_paths:
        try:
            rel_parts = wav_path.relative_to(Path(negative_dir)).parts
        except Exception:
            rel_parts = ()
        record_id = "negative_" + "_".join(Path(*rel_parts).with_suffix("").parts) if rel_parts else f"negative_{wav_path.stem}"
        negative_records.append(make_manifest_entry(wav_path, "negative", "", sample_rate, record_id=record_id))

    all_records = positive_records + negative_records

    # Stratify by label so the split keeps both classes present when possible.
    pos_train, pos_dev, pos_test = split_records(positive_records, train_ratio, dev_ratio, seed)
    neg_train, neg_dev, neg_test = split_records(negative_records, train_ratio, dev_ratio, seed + 1)

    train_records = pos_train + neg_train
    dev_records = pos_dev + neg_dev
    test_records = pos_test + neg_test

    write_jsonl(manifest_path / "all.jsonl", all_records)
    write_jsonl(manifest_path / "train.jsonl", train_records)
    write_jsonl(manifest_path / "dev.jsonl", dev_records)
    write_jsonl(manifest_path / "test.jsonl", test_records)

    raw_keywords = []
    for spec in keyword_specs:
        raw_keywords.append(f"{spec.original} :{spec.boost} #{spec.threshold} @{spec.original}")
    if not raw_keywords:
        raw_keywords = ["Lumi :1.5 #0.35 @Lumi"]

    with open(manifest_path / "keywords_raw.txt", "w", encoding="utf-8") as f:
        for line in raw_keywords:
            f.write(line)
            f.write("\n")

    write_tokens_file(manifest_path / "tokens.txt", [spec.original for spec in keyword_specs] or ["Lumi"])
    write_encoded_keywords(manifest_path / "keywords.txt", raw_keywords)

    stats = {
        "sample_rate": sample_rate,
        "counts": {
            "positive": len(positive_records),
            "negative": len(negative_records),
            "all": len(all_records),
            "train": len(train_records),
            "dev": len(dev_records),
            "test": len(test_records),
        },
        "splits": {
            "train_ratio": train_ratio,
            "dev_ratio": dev_ratio,
            "test_ratio": test_ratio,
        },
        "keywords": [spec.original for spec in keyword_specs],
    }
    save_json(manifest_path / "stats.json", stats)
    return stats
