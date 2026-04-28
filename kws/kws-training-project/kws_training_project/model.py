from __future__ import annotations

import copy
from dataclasses import dataclass
from typing import Optional, Tuple

try:
    import torch
    import torch.nn as nn
    import torch.nn.functional as F
except Exception:  # pragma: no cover
    torch = None
    nn = None
    F = None


def _require_torch() -> None:
    if torch is None:
        raise RuntimeError("PyTorch is required for model definition.")


@dataclass
class ModelSpec:
    input_dim: int = 40
    hidden_dim: int = 128
    num_layers: int = 2
    num_heads: int = 4
    ff_dim: int = 256
    conv_kernel: int = 15
    dropout: float = 0.1
    encoder_type: str = "lstm"


class LstmEncoder(nn.Module):
    def __init__(self, input_dim: int, hidden_dim: int, num_layers: int, dropout: float):
        super().__init__()
        self.lstm = nn.LSTM(
            input_size=input_dim,
            hidden_size=hidden_dim // 2,
            num_layers=num_layers,
            batch_first=True,
            bidirectional=True,
            dropout=dropout if num_layers > 1 else 0.0,
        )

    def forward(self, x, lengths, state=None):
        packed = nn.utils.rnn.pack_padded_sequence(
            x, lengths.cpu(), batch_first=True, enforce_sorted=False
        )
        packed_out, state = self.lstm(packed, state)
        out, out_lengths = nn.utils.rnn.pad_packed_sequence(packed_out, batch_first=True)
        return out, out_lengths, state

    def stream_forward(self, x, state=None):
        out, state = self.lstm(x, state)
        return out, state


class FeedForward(nn.Module):
    def __init__(self, dim: int, ff_dim: int, dropout: float):
        super().__init__()
        self.net = nn.Sequential(
            nn.LayerNorm(dim),
            nn.Linear(dim, ff_dim),
            nn.SiLU(),
            nn.Dropout(dropout),
            nn.Linear(ff_dim, dim),
            nn.Dropout(dropout),
        )

    def forward(self, x):
        return self.net(x)


class ConvModule(nn.Module):
    def __init__(self, dim: int, kernel_size: int, dropout: float):
        super().__init__()
        padding = kernel_size // 2
        self.net = nn.Sequential(
            nn.LayerNorm(dim),
            nn.Conv1d(dim, dim * 2, kernel_size=1),
            nn.GLU(dim=1),
            nn.Conv1d(dim, dim, kernel_size=kernel_size, padding=padding, groups=dim),
            nn.BatchNorm1d(dim),
            nn.SiLU(),
            nn.Conv1d(dim, dim, kernel_size=1),
            nn.Dropout(dropout),
        )

    def forward(self, x):
        y = x.transpose(1, 2)
        y = self.net(y)
        return y.transpose(1, 2)


class ConformerBlock(nn.Module):
    def __init__(self, dim: int, num_heads: int, ff_dim: int, kernel_size: int, dropout: float):
        super().__init__()
        self.ff1 = FeedForward(dim, ff_dim, dropout)
        self.ff2 = FeedForward(dim, ff_dim, dropout)
        self.norm_mha = nn.LayerNorm(dim)
        self.mha = nn.MultiheadAttention(dim, num_heads, dropout=dropout, batch_first=True)
        self.conv = ConvModule(dim, kernel_size, dropout)
        self.final_norm = nn.LayerNorm(dim)

    def forward(self, x, key_padding_mask=None):
        x = x + 0.5 * self.ff1(x)
        attn_in = self.norm_mha(x)
        attn_out, _ = self.mha(attn_in, attn_in, attn_in, key_padding_mask=key_padding_mask, need_weights=False)
        x = x + attn_out
        x = x + self.conv(x)
        x = x + 0.5 * self.ff2(x)
        return self.final_norm(x)


class ConformerEncoder(nn.Module):
    def __init__(self, input_dim: int, hidden_dim: int, num_layers: int, num_heads: int, ff_dim: int, kernel_size: int, dropout: float):
        super().__init__()
        self.input_proj = nn.Sequential(
            nn.Linear(input_dim, hidden_dim),
            nn.Dropout(dropout),
        )
        self.blocks = nn.ModuleList(
            [ConformerBlock(hidden_dim, num_heads, ff_dim, kernel_size, dropout) for _ in range(num_layers)]
        )

    def forward(self, x, lengths):
        x = self.input_proj(x)
        max_len = x.size(1)
        mask = torch.arange(max_len, device=lengths.device).unsqueeze(0) >= lengths.unsqueeze(1)
        for block in self.blocks:
            x = block(x, key_padding_mask=mask)
        return x, lengths


class KwsCtcModel(nn.Module):
    def __init__(self, vocab_size: int, spec: ModelSpec):
        super().__init__()
        self.vocab_size = vocab_size
        self.spec = spec
        self.input_proj = nn.Sequential(
            nn.Linear(spec.input_dim, spec.hidden_dim),
            nn.Dropout(spec.dropout),
        )
        if spec.encoder_type == "conformer":
            self.encoder = ConformerEncoder(
                input_dim=spec.hidden_dim,
                hidden_dim=spec.hidden_dim,
                num_layers=spec.num_layers,
                num_heads=spec.num_heads,
                ff_dim=spec.ff_dim,
                kernel_size=spec.conv_kernel,
                dropout=spec.dropout,
            )
            self.is_streaming = False
        else:
            self.encoder = LstmEncoder(
                input_dim=spec.hidden_dim,
                hidden_dim=spec.hidden_dim,
                num_layers=spec.num_layers,
                dropout=spec.dropout,
            )
            self.is_streaming = True
        self.ctc_head = nn.Linear(spec.hidden_dim, vocab_size)
        self.dropout = nn.Dropout(spec.dropout)

    def forward(self, features, lengths, state=None):
        x = self.input_proj(features)
        if self.spec.encoder_type == "conformer":
            x, lengths = self.encoder(x, lengths)
            state = None
        else:
            x, lengths, state = self.encoder(x, lengths, state)
        logits = self.ctc_head(self.dropout(x))
        return logits, lengths, state

    def forward_export(self, features, lengths):
        x = self.input_proj(features)
        if self.spec.encoder_type == "conformer":
            x, lengths = self.encoder(x, lengths)
        else:
            x, _ = self.encoder.lstm(x)
        logits = self.ctc_head(self.dropout(x))
        return logits, lengths

    def stream_forward(self, features, state=None):
        if self.spec.encoder_type != "lstm":
            raise RuntimeError("Streaming forward is only supported for the LSTM encoder in this project.")
        x = self.input_proj(features)
        x, state = self.encoder.stream_forward(x, state)
        logits = self.ctc_head(self.dropout(x))
        return logits, state


def build_model(vocab_size: int, config) -> KwsCtcModel:
    _require_torch()
    spec = ModelSpec(
        input_dim=int(config["input_dim"]),
        hidden_dim=int(config["hidden_dim"]),
        num_layers=int(config["num_layers"]),
        num_heads=int(config.get("num_heads", 4)),
        ff_dim=int(config.get("ff_dim", 256)),
        conv_kernel=int(config.get("conv_kernel", 15)),
        dropout=float(config.get("dropout", 0.1)),
        encoder_type=str(config.get("encoder_type", "lstm")).lower(),
    )
    return KwsCtcModel(vocab_size=vocab_size, spec=spec)
