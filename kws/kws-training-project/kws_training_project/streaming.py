from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

try:
    import torch
except Exception:  # pragma: no cover
    torch = None

from .audio import read_wav_pcm16
from .features import StreamingFeatureExtractor, log_mel_spectrogram
from .model import build_model
from .tokenizer import normalize_phrase


def _require_torch() -> None:
    if torch is None:
        raise RuntimeError("PyTorch is required for streaming inference.")


@dataclass
class DetectionEvent:
    keyword: str
    score: float
    frame_index: int
    sample_index: int


class StreamingKeywordSpotter:
    def __init__(self, config: Dict[str, Any], tokens: Sequence[str], checkpoint: Optional[Dict[str, Any]] = None, model=None):
        _require_torch()
        self.config = config
        self.sample_rate = int(config.get("sample_rate", 16000))
        self.frame_length_ms = int(config.get("frame_length_ms", 25))
        self.frame_shift_ms = int(config.get("frame_shift_ms", 10))
        self.num_mel_bins = int(config.get("num_mel_bins", 40))
        self.streaming_cfg = dict(config.get("streaming", {}))
        self.posterior_threshold = float(self.streaming_cfg.get("posterior_threshold", 0.6))
        self.blank_margin = float(self.streaming_cfg.get("blank_margin", 0.15))
        self.decision_window_ms = int(self.streaming_cfg.get("decision_window_ms", 160))
        self.cooldown_ms = int(self.streaming_cfg.get("cooldown_ms", 600))
        self.tokens = list(tokens)
        self.token_to_id = {token: index for index, token in enumerate(self.tokens)}
        self.keyword_tokens = [token for token in self.tokens if token != "<blank>"]
        self.keyword_to_phrase = {normalize_phrase(keyword): keyword for keyword in config.get("keywords", [])}
        self.chunk_features = StreamingFeatureExtractor(
            sample_rate=self.sample_rate,
            num_mel_bins=self.num_mel_bins,
            frame_length_ms=self.frame_length_ms,
            frame_shift_ms=self.frame_shift_ms,
        )
        self.model = model
        if self.model is None:
            if checkpoint is None:
                raise ValueError("Either a model instance or a checkpoint must be provided.")
            self.model = build_model(vocab_size=len(tokens), config=config)
            self.model.load_state_dict(checkpoint["model_state_dict"])
        self.model.eval()
        self.state = None
        self.recent_scores = deque(maxlen=max(1, self.decision_window_ms // self.frame_shift_ms))
        self.cooldown_frames = max(1, self.cooldown_ms // self.frame_shift_ms)
        self.cooldown_left = 0
        self.frame_index = 0
        self.sample_index = 0

    def reset(self):
        self.chunk_features.reset()
        self.state = None
        self.recent_scores.clear()
        self.cooldown_left = 0
        self.frame_index = 0
        self.sample_index = 0

    def _score_frame(self, logits) -> DetectionEvent | None:
        probs = torch.softmax(logits, dim=-1)
        blank_prob = float(probs[..., 0].mean().item())
        keyword_probs = []
        for token in self.keyword_tokens:
            token_id = self.token_to_id[token]
            keyword_probs.append((token, float(probs[..., token_id].mean().item())))
        if not keyword_probs:
            return None
        best_keyword, best_score = max(keyword_probs, key=lambda item: item[1])
        self.recent_scores.append((best_keyword, best_score, blank_prob))
        avg_score = sum(score for _, score, _ in self.recent_scores) / float(len(self.recent_scores))
        avg_blank = sum(blank for _, _, blank in self.recent_scores) / float(len(self.recent_scores))
        if self.cooldown_left > 0:
            self.cooldown_left -= 1
            return None
        if best_score >= self.posterior_threshold and (best_score - avg_blank) >= self.blank_margin and avg_score >= self.posterior_threshold:
            self.cooldown_left = self.cooldown_frames
            phrase = self.keyword_to_phrase.get(best_keyword, best_keyword)
            return DetectionEvent(
                keyword=phrase,
                score=best_score,
                frame_index=self.frame_index,
                sample_index=self.sample_index,
            )
        return None

    def accept_waveform(self, waveform):
        _require_torch()
        features = self.chunk_features.accept_waveform(waveform)
        if features.numel() == 0:
            self.sample_index += int(waveform.numel())
            return None
        if self.model.spec.encoder_type == "lstm":
            logits, self.state = self.model.stream_forward(features.unsqueeze(0), self.state)
        else:
            lengths = torch.tensor([features.size(0)], dtype=torch.long)
            logits, _, _ = self.model(features.unsqueeze(0), lengths)
        event = self._score_frame(logits)
        self.frame_index += int(features.size(0))
        self.sample_index += int(waveform.numel())
        return event

    def accept_wav_file(self, path: str | Path, chunk_samples: int = 1600):
        waveform = torch.tensor(read_wav_pcm16(path, sample_rate=self.sample_rate), dtype=torch.float32)
        events = []
        for start in range(0, waveform.numel(), chunk_samples):
            event = self.accept_waveform(waveform[start : start + chunk_samples])
            if event is not None:
                events.append(event)
        return events
