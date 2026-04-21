"""Compatibility shim.

The BLE server implementation proven on the robot dog is the dbus-python +
GLib peripheral server. Re-export it here so the existing ``BlueZGATTTransport``
name and tests keep working.
"""

from __future__ import annotations

from .bluez_gatt_glib import BlueZGATTTransportGLib, StateCharacteristic, glib_stack_available

BlueZGATTTransport = BlueZGATTTransportGLib

__all__ = [
    "BlueZGATTTransport",
    "BlueZGATTTransportGLib",
    "StateCharacteristic",
    "glib_stack_available",
]
