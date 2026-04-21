"""BLE transport factory.

`robot_server` 的 BLE 服务端实现已经切到当前项目里验证通过的 GLib 外设
骨架。保留 `backend` 参数主要是为了兼容既有配置和测试代码；真实实现以
`dbus-python + GLib` 版本为准。
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from .bluez_gatt import BlueZGATTTransport
from .bluez_gatt_glib import BlueZGATTTransportGLib, glib_stack_available

if TYPE_CHECKING:
    from ...config import BLEConfig
    from ..base import RuntimeTransport

_logger = logging.getLogger(__name__)

__all__ = [
    "BlueZGATTTransport",
    "BlueZGATTTransportGLib",
    "create_ble_transport",
]


def create_ble_transport(config: "BLEConfig") -> "RuntimeTransport":
    """Instantiate the BLE transport matching ``config.backend``."""
    backend = (config.backend or "auto").strip().lower()
    if backend not in {"auto", "glib", "dbus_next"}:
        _logger.warning(
            "Unknown ROBOT_BLE_BACKEND=%r, falling back to 'auto'", backend
        )
        backend = "auto"

    if backend == "dbus_next":
        _logger.warning(
            "ROBOT_BLE_BACKEND=dbus_next is kept for compatibility only; "
            "using the transplanted GLib peripheral implementation."
        )
        return BlueZGATTTransport(config)

    if backend == "glib":
        if not glib_stack_available():
            raise RuntimeError(
                "ROBOT_BLE_BACKEND=glib requested but dbus-python + "
                "PyGObject are not importable. Install python3-dbus + "
                "python3-gi, append /usr/lib/python3/dist-packages to "
                "PYTHONPATH, or set ROBOT_BLE_BACKEND=auto."
            )
        _logger.info("Using BLE backend: glib (ported robot BLE peripheral)")
        return BlueZGATTTransportGLib(config)

    # auto
    if glib_stack_available():
        _logger.info("Using BLE backend: glib (auto-selected)")
        return BlueZGATTTransportGLib(config)
    _logger.info(
        "GLib stack unavailable; constructing compatibility transport. "
        "BLE start() will still require python3-dbus + python3-gi at runtime."
    )
    return BlueZGATTTransport(config)
