from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Optional, Tuple

try:
    import torch
    import torch.nn.functional as F
except Exception:  # pragma: no cover - torch is optional at import time
    torch = None
    F = None


def _require_torch() -> None:
    if torch is None:
        raise RuntimeError("PyTorch is required for feature extraction, training, and export.")


def hz_to_mel(freq):
    return 2595.0 * torch.log10(torch.tensor(1.0) + freq / 700.0)


def mel_to_hz(mel):
    return 700.0 * (torch.pow(10.0, mel / 2595.0) - 1.0)


def build_mel_filterbank(sample_rate: int, n_fft: int, n_mels: int, device=None, dtype=None):
    _require_torch()
    dtype = dtype or torch.float32
    device = device or torch.device("cpu")
    f_min = 0.0
    f_max = sample_rate / 2.0
    m_min = 2595.0 * math.log10(1.0 + f_min / 700.0)
    m_max = 2595.0 * math.log10(1.0 + f_max / 700.0)
    m_pts = torch.linspace(m_min, m_max, n_mels + 2, device=device, dtype=dtype)
    f_pts = 700.0 * (torch.pow(10.0, m_pts / 2595.0) - 1.0)
    bins = torch.floor((n_fft + 1) * f_pts / sample_rate).long()
    fb = torch.zeros(n_mels, n_fft // 2 + 1, device=device, dtype=dtype)
    for i in range(n_mels):
        left = int(bins[i].item())
        center = int(bins[i + 1].item())
        right = int(bins[i + 2].item())
        if center <= left:
            center = left + 1
        if right <= center:
            right = center + 1
        for j in range(left, center):
            if 0 <= j < fb.size(1):
                fb[i, j] = (j - left) / float(center - left)
        for j in range(center, right):
            if 0 <= j < fb.size(1):
                fb[i, j] = (right - j) / float(right - center)
    return fb


def log_mel_spectrogram(
    waveform,
    sample_rate: int = 16000,
    num_mel_bins: int = 40,
    frame_length_ms: int = 25,
    frame_shift_ms: int = 10,
    n_fft: Optional[int] = None,
):
    _require_torch()
    if waveform.dim() != 1:
        raise ValueError("Expected a 1D waveform tensor.")
    if waveform.numel() == 0:
        waveform = torch.zeros(1, dtype=torch.float32, device=waveform.device)
    waveform = waveform.float()
    win_length = int(sample_rate * frame_length_ms / 1000.0)
    hop_length = int(sample_rate * frame_shift_ms / 1000.0)
    n_fft = int(n_fft or 1 << (win_length - 1).bit_length())
    if waveform.numel() < win_length:
        pad = win_length - waveform.numel()
        waveform = F.pad(waveform, (0, pad))
    window = torch.hann_window(win_length, device=waveform.device, dtype=waveform.dtype)
    spec = torch.stft(
        waveform,
        n_fft=n_fft,
        hop_length=hop_length,
        win_length=win_length,
        window=window,
        center=False,
        return_complex=True,
    )
    power = spec.abs().pow(2.0)
    mel_fb = build_mel_filterbank(sample_rate, n_fft, num_mel_bins, device=waveform.device, dtype=waveform.dtype)
    mel = torch.matmul(mel_fb, power)
    log_mel = torch.log(torch.clamp(mel, min=1e-6))
    return log_mel.transpose(0, 1).contiguous()


def feature_lengths(num_samples: int, sample_rate: int = 16000, frame_length_ms: int = 25, frame_shift_ms: int = 10) -> int:
    win_length = int(sample_rate * frame_length_ms / 1000.0)
    hop_length = int(sample_rate * frame_shift_ms / 1000.0)
    if num_samples < win_length:
        return 1
    return 1 + (num_samples - win_length) // hop_length


@dataclass
class StreamingFeatureExtractor:
    sample_rate: int = 16000
    num_mel_bins: int = 40
    frame_length_ms: int = 25
    frame_shift_ms: int = 10

    def __post_init__(self):
        self._buffer = None
        self._last_frame_count = 0

    def reset(self):
        self._buffer = None
        self._last_frame_count = 0

    def accept_waveform(self, waveform):
        _require_torch()
        if waveform.dim() != 1:
            raise ValueError("Expected a 1D waveform tensor.")
        if self._buffer is None:
            self._buffer = waveform.detach().clone().float()
        else:
            self._buffer = torch.cat([self._buffer, waveform.detach().clone().float()], dim=0)
        features = log_mel_spectrogram(
            self._buffer,
            sample_rate=self.sample_rate,
            num_mel_bins=self.num_mel_bins,
            frame_length_ms=self.frame_length_ms,
            frame_shift_ms=self.frame_shift_ms,
        )
        new_features = features[self._last_frame_count :]
        self._last_frame_count = features.size(0)
        return new_features
