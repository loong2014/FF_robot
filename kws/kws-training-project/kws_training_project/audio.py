from __future__ import annotations

import sys
import wave
from array import array
from pathlib import Path
from typing import Dict, List, Tuple


class WavFormatError(RuntimeError):
    pass


def inspect_wav(path: str | Path) -> Dict[str, int | str]:
    with wave.open(str(path), "rb") as wf:
        meta = {
            "channels": wf.getnchannels(),
            "sample_width": wf.getsampwidth(),
            "sample_rate": wf.getframerate(),
            "num_frames": wf.getnframes(),
            "comptype": wf.getcomptype(),
            "compname": wf.getcompname(),
        }
    return meta


def validate_wav_16k_mono_pcm(path: str | Path, sample_rate: int = 16000) -> Dict[str, int | str]:
    meta = inspect_wav(path)
    if meta["channels"] != 1:
        raise WavFormatError(f"{path}: expected mono wav, got {meta['channels']} channels")
    if meta["sample_width"] != 2:
        raise WavFormatError(f"{path}: expected 16-bit PCM, got sample width {meta['sample_width']}")
    if meta["sample_rate"] != sample_rate:
        raise WavFormatError(f"{path}: expected {sample_rate} Hz, got {meta['sample_rate']} Hz")
    if str(meta["comptype"]).upper() != "NONE":
        raise WavFormatError(f"{path}: expected PCM (NONE), got {meta['comptype']}")
    return meta


def wav_duration(path: str | Path) -> float:
    meta = inspect_wav(path)
    sample_rate = float(meta["sample_rate"])
    num_frames = float(meta["num_frames"])
    return num_frames / sample_rate if sample_rate > 0 else 0.0


def read_wav_pcm16(path: str | Path, sample_rate: int = 16000) -> List[float]:
    validate_wav_16k_mono_pcm(path, sample_rate=sample_rate)
    with wave.open(str(path), "rb") as wf:
        raw = wf.readframes(wf.getnframes())
    samples = array("h")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    return [sample / 32768.0 for sample in samples]

