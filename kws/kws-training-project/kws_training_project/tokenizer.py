from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Sequence, Tuple

from .utils import ensure_dir

_NON_TOKEN_RE = re.compile(r"[^a-z0-9]+")


def normalize_keyword(text: str) -> str:
    cleaned = text.strip().lower()
    cleaned = _NON_TOKEN_RE.sub("_", cleaned)
    cleaned = cleaned.strip("_")
    return cleaned or "keyword"


def normalize_phrase(text: str) -> str:
    return normalize_keyword(text)


def unique_keywords(keywords: Iterable[str]) -> List[str]:
    seen = set()
    ordered: List[str] = []
    for keyword in keywords:
        token = normalize_keyword(keyword)
        if token and token not in seen:
            seen.add(token)
            ordered.append(token)
    return ordered


def build_tokens_txt(keywords: Sequence[str]) -> List[str]:
    tokens = ["<blank>"]
    tokens.extend(unique_keywords(keywords))
    return tokens


def write_tokens_file(path: str | Path, keywords: Sequence[str]) -> List[str]:
    tokens = build_tokens_txt(keywords)
    ensure_dir(Path(path).parent)
    with open(path, "w", encoding="utf-8") as f:
        for token in tokens:
            f.write(token)
            f.write("\n")
    return tokens


def parse_keyword_line(line: str) -> Tuple[str, str, str | None, str | None]:
    raw = line.strip()
    if not raw or raw.startswith("#"):
        return "", "", None, None
    phrase_part = raw
    if "@" in raw:
        phrase_part, original = raw.split("@", 1)
        phrase_part = phrase_part.strip()
        original = original.strip()
    else:
        original = None
    boost = None
    threshold = None
    pieces = phrase_part.split()
    phrase_tokens: List[str] = []
    for piece in pieces:
        if piece.startswith(":"):
            boost = piece[1:]
        elif piece.startswith("#"):
            threshold = piece[1:]
        else:
            phrase_tokens.append(piece)
    phrase = " ".join(phrase_tokens).strip()
    if original is None:
        original = phrase
    return phrase, original, boost, threshold


def encode_keyword_line(line: str) -> str:
    phrase, original, boost, threshold = parse_keyword_line(line)
    if not phrase:
        return ""
    token = normalize_phrase(phrase)
    parts = [token]
    if boost is not None and boost != "":
        parts.append(":" + boost)
    if threshold is not None and threshold != "":
        parts.append("#" + threshold)
    if original:
        parts.append("@" + original)
    return " ".join(parts)


def write_encoded_keywords(path: str | Path, lines: Iterable[str]) -> List[str]:
    encoded: List[str] = []
    ensure_dir(Path(path).parent)
    with open(path, "w", encoding="utf-8") as f:
        for line in lines:
            encoded_line = encode_keyword_line(line)
            if not encoded_line:
                continue
            encoded.append(encoded_line)
            f.write(encoded_line)
            f.write("\n")
    return encoded


@dataclass
class KeywordSpec:
    original: str
    token: str
    boost: float = 1.5
    threshold: float = 0.35


def keyword_specs_from_phrases(phrases: Sequence[str], boost: float = 1.5, threshold: float = 0.35) -> List[KeywordSpec]:
    specs: List[KeywordSpec] = []
    seen = set()
    for phrase in phrases:
        token = normalize_phrase(phrase)
        if token in seen:
            continue
        seen.add(token)
        specs.append(KeywordSpec(original=phrase, token=token, boost=boost, threshold=threshold))
    return specs
