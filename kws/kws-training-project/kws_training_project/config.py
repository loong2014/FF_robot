from __future__ import annotations

from pathlib import Path
from typing import Any, Dict

from .utils import load_json, save_json


def load_config(path: str | Path) -> Dict[str, Any]:
    return load_json(path)


def save_config(path: str | Path, data: Dict[str, Any]) -> None:
    save_json(path, data)

