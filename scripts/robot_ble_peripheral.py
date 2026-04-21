#!/usr/bin/env python3
from __future__ import annotations

import json
import logging
import os
import queue
import shlex
import signal
import subprocess
import threading
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

import dbus
import dbus.exceptions
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib


BLUEZ_SERVICE_NAME = "org.bluez"
DBUS_OM_IFACE = "org.freedesktop.DBus.ObjectManager"
DBUS_PROP_IFACE = "org.freedesktop.DBus.Properties"
LE_ADVERTISEMENT_IFACE = "org.bluez.LEAdvertisement1"
LE_ADVERTISING_MANAGER_IFACE = "org.bluez.LEAdvertisingManager1"
GATT_MANAGER_IFACE = "org.bluez.GattManager1"
GATT_SERVICE_IFACE = "org.bluez.GattService1"
GATT_CHRC_IFACE = "org.bluez.GattCharacteristic1"
ADAPTER_IFACE = "org.bluez.Adapter1"

APP_PATH = "/com/robotdog/ble"
DEFAULT_SERVICE_UUID = "7c2e0001-59d7-4b8b-9f3d-1bb8e31a0001"
DEFAULT_COMMAND_UUID = "7c2e0001-59d7-4b8b-9f3d-1bb8e31a0002"
DEFAULT_STATUS_UUID = "7c2e0001-59d7-4b8b-9f3d-1bb8e31a0003"
DEFAULT_HOOK_TIMEOUT_SEC = 5.0
DEFAULT_STATUS_MAX_BYTES = 240
DEFAULT_LOG_PAYLOAD_LIMIT = 96


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


class InvalidArgsException(dbus.exceptions.DBusException):
    _dbus_error_name = "org.freedesktop.DBus.Error.InvalidArgs"


class NotSupportedException(dbus.exceptions.DBusException):
    _dbus_error_name = "org.bluez.Error.NotSupported"


class NotPermittedException(dbus.exceptions.DBusException):
    _dbus_error_name = "org.bluez.Error.NotPermitted"


class FailedException(dbus.exceptions.DBusException):
    _dbus_error_name = "org.bluez.Error.Failed"


@dataclass(frozen=True)
class Config:
    service_uuid: str
    command_uuid: str
    status_uuid: str
    local_name: str
    hook_command: List[str]
    hook_timeout_sec: float
    status_max_bytes: int
    log_payload_limit: int

    @classmethod
    def from_env(cls, adapter_alias: str) -> "Config":
        local_name = os.getenv("ROBOT_BLE_LOCAL_NAME", "").strip() or adapter_alias
        hook_command = shlex.split(os.getenv("ROBOT_BLE_COMMAND_HOOK", "").strip())
        hook_timeout_sec = float(os.getenv("ROBOT_BLE_HOOK_TIMEOUT_SEC", str(DEFAULT_HOOK_TIMEOUT_SEC)))
        status_max_bytes = int(os.getenv("ROBOT_BLE_STATUS_MAX_BYTES", str(DEFAULT_STATUS_MAX_BYTES)))
        log_payload_limit = int(os.getenv("ROBOT_BLE_LOG_PAYLOAD_LIMIT", str(DEFAULT_LOG_PAYLOAD_LIMIT)))
        return cls(
            service_uuid=os.getenv("ROBOT_BLE_SERVICE_UUID", DEFAULT_SERVICE_UUID).strip(),
            command_uuid=os.getenv("ROBOT_BLE_COMMAND_UUID", DEFAULT_COMMAND_UUID).strip(),
            status_uuid=os.getenv("ROBOT_BLE_STATUS_UUID", DEFAULT_STATUS_UUID).strip(),
            local_name=local_name,
            hook_command=hook_command,
            hook_timeout_sec=hook_timeout_sec,
            status_max_bytes=max(64, status_max_bytes),
            log_payload_limit=max(16, log_payload_limit),
        )


def find_adapter(bus: dbus.SystemBus) -> str:
    manager = dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, "/"), DBUS_OM_IFACE)
    objects = manager.GetManagedObjects()
    for path, interfaces in objects.items():
        if GATT_MANAGER_IFACE in interfaces and LE_ADVERTISING_MANAGER_IFACE in interfaces:
            return path
    raise RuntimeError("No BLE adapter with GATT + LE advertising support found")


def get_adapter_alias(bus: dbus.SystemBus, adapter_path: str) -> str:
    props = dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, adapter_path), DBUS_PROP_IFACE)
    try:
        return str(props.Get(ADAPTER_IFACE, "Alias"))
    except dbus.DBusException:
        return "RobotDog"


class Application(dbus.service.Object):
    def __init__(self, bus: dbus.SystemBus) -> None:
        self.path = APP_PATH
        self.services: List[Service] = []
        super().__init__(bus, self.path)

    def get_path(self) -> dbus.ObjectPath:
        return dbus.ObjectPath(self.path)

    def add_service(self, service: "Service") -> None:
        self.services.append(service)

    @dbus.service.method(DBUS_OM_IFACE, out_signature="a{oa{sa{sv}}}")
    def GetManagedObjects(self):
        managed: Dict[dbus.ObjectPath, Dict[str, Dict[str, Any]]] = {}
        for service in self.services:
            managed[service.get_path()] = service.get_properties()
            for characteristic in service.get_characteristics():
                managed[characteristic.get_path()] = characteristic.get_properties()
        return managed


class Service(dbus.service.Object):
    PATH_BASE = APP_PATH

    def __init__(self, bus: dbus.SystemBus, index: int, uuid: str, primary: bool) -> None:
        self.path = f"{self.PATH_BASE}/service{index}"
        self.bus = bus
        self.uuid = uuid
        self.primary = primary
        self.characteristics: List[Characteristic] = []
        super().__init__(bus, self.path)

    def get_properties(self) -> Dict[str, Dict[str, Any]]:
        return {
            GATT_SERVICE_IFACE: {
                "UUID": self.uuid,
                "Primary": self.primary,
                "Characteristics": dbus.Array([c.get_path() for c in self.characteristics], signature="o"),
            }
        }

    def get_path(self) -> dbus.ObjectPath:
        return dbus.ObjectPath(self.path)

    def add_characteristic(self, characteristic: "Characteristic") -> None:
        self.characteristics.append(characteristic)

    def get_characteristics(self) -> List["Characteristic"]:
        return self.characteristics

    @dbus.service.method(DBUS_PROP_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface != GATT_SERVICE_IFACE:
            raise InvalidArgsException()
        return self.get_properties()[GATT_SERVICE_IFACE]


class Characteristic(dbus.service.Object):
    def __init__(self, bus: dbus.SystemBus, index: int, uuid: str, flags: List[str], service: Service) -> None:
        self.path = f"{service.path}/char{index}"
        self.bus = bus
        self.uuid = uuid
        self.flags = flags
        self.service = service
        self.notifying = False
        super().__init__(bus, self.path)

    def get_properties(self) -> Dict[str, Dict[str, Any]]:
        return {
            GATT_CHRC_IFACE: {
                "Service": self.service.get_path(),
                "UUID": self.uuid,
                "Flags": dbus.Array(self.flags, signature="s"),
                "Descriptors": dbus.Array([], signature="o"),
            }
        }

    def get_path(self) -> dbus.ObjectPath:
        return dbus.ObjectPath(self.path)

    @dbus.service.method(DBUS_PROP_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface != GATT_CHRC_IFACE:
            raise InvalidArgsException()
        return self.get_properties()[GATT_CHRC_IFACE]

    @dbus.service.method(GATT_CHRC_IFACE, in_signature="a{sv}", out_signature="ay")
    def ReadValue(self, options):
        raise NotSupportedException()

    @dbus.service.method(GATT_CHRC_IFACE, in_signature="aya{sv}")
    def WriteValue(self, value, options):
        raise NotSupportedException()

    @dbus.service.method(GATT_CHRC_IFACE)
    def StartNotify(self):
        raise NotSupportedException()

    @dbus.service.method(GATT_CHRC_IFACE)
    def StopNotify(self):
        raise NotSupportedException()

    @dbus.service.signal(DBUS_PROP_IFACE, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass


class Advertisement(dbus.service.Object):
    PATH_BASE = f"{APP_PATH}/advertisement"

    def __init__(self, bus: dbus.SystemBus, index: int, service_uuid: str, local_name: str) -> None:
        self.path = f"{self.PATH_BASE}{index}"
        self.bus = bus
        self.ad_type = "peripheral"
        self.service_uuid = service_uuid
        self.local_name = local_name
        super().__init__(bus, self.path)

    def get_path(self) -> dbus.ObjectPath:
        return dbus.ObjectPath(self.path)

    def get_properties(self) -> Dict[str, Dict[str, Any]]:
        return {
            LE_ADVERTISEMENT_IFACE: {
                "Type": self.ad_type,
                "ServiceUUIDs": dbus.Array([self.service_uuid], signature="s"),
                "LocalName": dbus.String(self.local_name),
                "Includes": dbus.Array(["tx-power"], signature="s"),
            }
        }

    @dbus.service.method(DBUS_PROP_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface != LE_ADVERTISEMENT_IFACE:
            raise InvalidArgsException()
        return self.get_properties()[LE_ADVERTISEMENT_IFACE]

    @dbus.service.method(LE_ADVERTISEMENT_IFACE, in_signature="", out_signature="")
    def Release(self):
        logging.info("Advertisement released")


class StatusCharacteristic(Characteristic):
    def __init__(self, bus: dbus.SystemBus, index: int, service: "RobotBleService") -> None:
        super().__init__(bus, index, service.config.status_uuid, ["read", "notify"], service)
        self.robot_service = service
        self.current_value = service.current_status_bytes()

    def _read_offset(self, value: bytes, options: Dict[str, Any]) -> bytes:
        offset = int(options.get("offset", 0))
        if offset < 0 or offset > len(value):
            raise InvalidArgsException("Invalid offset")
        return value[offset:]

    @staticmethod
    def _to_dbus_bytes(payload: bytes) -> dbus.Array:
        return dbus.Array(bytearray(payload), signature="y")

    @dbus.service.method(GATT_CHRC_IFACE, in_signature="a{sv}", out_signature="ay")
    def ReadValue(self, options):
        self.current_value = self.robot_service.current_status_bytes()
        return self._to_dbus_bytes(self._read_offset(self.current_value, options))

    @dbus.service.method(GATT_CHRC_IFACE)
    def StartNotify(self):
        if self.notifying:
            return
        self.notifying = True
        self.emit_status(self.robot_service.current_status_bytes())

    @dbus.service.method(GATT_CHRC_IFACE)
    def StopNotify(self):
        self.notifying = False

    def emit_status(self, payload: bytes) -> bool:
        self.current_value = payload
        if self.notifying:
            self.PropertiesChanged(GATT_CHRC_IFACE, {"Value": self._to_dbus_bytes(payload)}, [])
        return False


class CommandCharacteristic(Characteristic):
    def __init__(self, bus: dbus.SystemBus, index: int, service: "RobotBleService") -> None:
        super().__init__(bus, index, service.config.command_uuid, ["write", "write-without-response"], service)
        self.robot_service = service

    @dbus.service.method(GATT_CHRC_IFACE, in_signature="aya{sv}")
    def WriteValue(self, value, options):
        offset = int(options.get("offset", 0))
        if offset != 0:
            raise NotPermittedException("Offset writes are not supported")
        payload = bytes(value)
        self.robot_service.enqueue_command(payload, options)


class RobotBleService(Service):
    def __init__(self, bus: dbus.SystemBus, config: Config) -> None:
        super().__init__(bus, 0, config.service_uuid, True)
        self.config = config
        self._lock = threading.Lock()
        self._stopped = threading.Event()
        self._seq = 0
        self._status: Dict[str, Any] = {
            "state": "idle",
            "seq": 0,
            "at": utc_now(),
            "name": self.config.local_name,
            "hook": "enabled" if self.config.hook_command else "disabled",
            "msg": "ready",
        }
        self._command_queue: "queue.Queue[Optional[Dict[str, Any]]]" = queue.Queue()
        self.status_characteristic = StatusCharacteristic(bus, 1, self)
        self.add_characteristic(CommandCharacteristic(bus, 0, self))
        self.add_characteristic(self.status_characteristic)
        self._worker = threading.Thread(target=self._worker_loop, name="robot-ble-hook", daemon=True)
        self._worker.start()

    def stop(self) -> None:
        if self._stopped.is_set():
            return
        self._stopped.set()
        self._command_queue.put(None)
        self._worker.join(timeout=1.0)

    def current_status_bytes(self) -> bytes:
        with self._lock:
            payload = self._serialize_status(self._status)
        return payload

    def enqueue_command(self, payload: bytes, options: Dict[str, Any]) -> None:
        preview = payload[: self.config.log_payload_limit]
        preview_text = preview.decode("utf-8", errors="replace")
        logging.info("BLE command received: text=%r hex=%s", preview_text, preview.hex())
        with self._lock:
            self._seq += 1
            command = {
                "seq": self._seq,
                "at": utc_now(),
                "hex": payload.hex(),
                "text": self._safe_text(payload),
                "device": str(options.get("device", "")),
            }
            self._status = {
                "state": "queued",
                "seq": command["seq"],
                "at": command["at"],
                "name": self.config.local_name,
                "hook": "enabled" if self.config.hook_command else "disabled",
                "text": command["text"],
                "hex": command["hex"][: self.config.log_payload_limit * 2],
                "msg": "queued",
            }
            status_bytes = self._serialize_status(self._status)
        GLib.idle_add(self.status_characteristic.emit_status, status_bytes)
        self._command_queue.put({"payload": payload, "meta": command})

    def _worker_loop(self) -> None:
        while True:
            item = self._command_queue.get()
            if item is None:
                return
            payload = item["payload"]
            meta = item["meta"]
            result = self._run_hook(payload)
            with self._lock:
                self._status = {
                    "state": result["state"],
                    "seq": meta["seq"],
                    "at": utc_now(),
                    "name": self.config.local_name,
                    "hook": "enabled" if self.config.hook_command else "disabled",
                    "text": meta["text"],
                    "hex": meta["hex"][: self.config.log_payload_limit * 2],
                    "rc": result["rc"],
                    "msg": result["msg"],
                }
                if result["out"]:
                    self._status["out"] = result["out"]
                if result["err"]:
                    self._status["err"] = result["err"]
                status_bytes = self._serialize_status(self._status)
            GLib.idle_add(self.status_characteristic.emit_status, status_bytes)

    def _run_hook(self, payload: bytes) -> Dict[str, Any]:
        if not self.config.hook_command:
            return {"state": "ok", "rc": 0, "msg": "no hook configured", "out": "", "err": ""}

        try:
            completed = subprocess.run(
                self.config.hook_command,
                input=payload,
                capture_output=True,
                timeout=self.config.hook_timeout_sec,
                check=False,
            )
            stdout = completed.stdout.decode("utf-8", errors="replace").strip()
            stderr = completed.stderr.decode("utf-8", errors="replace").strip()
            return {
                "state": "ok" if completed.returncode == 0 else "error",
                "rc": completed.returncode,
                "msg": "hook finished" if completed.returncode == 0 else "hook failed",
                "out": stdout[: self.config.log_payload_limit],
                "err": stderr[: self.config.log_payload_limit],
            }
        except subprocess.TimeoutExpired as exc:
            logging.error("BLE hook timed out after %.1fs", self.config.hook_timeout_sec)
            stderr = exc.stderr.decode("utf-8", errors="replace").strip() if exc.stderr else ""
            return {"state": "error", "rc": 124, "msg": "hook timeout", "out": "", "err": stderr[: self.config.log_payload_limit]}
        except FileNotFoundError:
            logging.exception("BLE hook binary not found")
            return {"state": "error", "rc": 127, "msg": "hook not found", "out": "", "err": ""}
        except Exception as exc:  # pragma: no cover - defensive path for runtime issues
            logging.exception("BLE hook execution failed")
            return {"state": "error", "rc": 1, "msg": f"hook error: {exc.__class__.__name__}", "out": "", "err": str(exc)[: self.config.log_payload_limit]}

    @staticmethod
    def _safe_text(payload: bytes) -> str:
        try:
            return payload.decode("utf-8")
        except UnicodeDecodeError:
            return ""

    def _serialize_status(self, status: Dict[str, Any]) -> bytes:
        def encode(payload: Dict[str, Any]) -> bytes:
            return json.dumps(payload, separators=(",", ":"), ensure_ascii=True).encode("utf-8")

        encoded = encode(status)
        if len(encoded) <= self.config.status_max_bytes:
            return encoded
        trimmed = dict(status)
        trimmed["msg"] = "status truncated"
        trimmed.pop("out", None)
        trimmed.pop("err", None)
        trimmed.pop("text", None)
        encoded = encode(trimmed)
        if len(encoded) <= self.config.status_max_bytes:
            return encoded
        fallback = {
            "state": trimmed.get("state", "error"),
            "seq": trimmed.get("seq", 0),
            "msg": "status truncated",
        }
        return encode(fallback)


def unregister_peripheral(
    managers: Dict[str, dbus.Interface],
    app: Application,
    advertisement: Advertisement,
    unregister_adv: bool = True,
    unregister_gatt: bool = True,
) -> None:
    if unregister_adv:
        try:
            managers["adv"].UnregisterAdvertisement(advertisement.get_path())
        except Exception:
            logging.exception("Failed to unregister advertisement")
    if unregister_gatt:
        try:
            managers["gatt"].UnregisterApplication(app.get_path())
        except Exception:
            logging.exception("Failed to unregister application")


def main() -> int:
    logging.basicConfig(
        level=os.getenv("ROBOT_BLE_LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(message)s",
    )

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    adapter_path = find_adapter(bus)
    adapter_alias = get_adapter_alias(bus, adapter_path)
    config = Config.from_env(adapter_alias)
    app = Application(bus)
    service = RobotBleService(bus, config)
    advertisement = Advertisement(bus, 0, config.service_uuid, config.local_name)
    app.add_service(service)
    adapter_object = bus.get_object(BLUEZ_SERVICE_NAME, adapter_path)
    managers: Dict[str, dbus.Interface] = {
        "gatt": dbus.Interface(adapter_object, GATT_MANAGER_IFACE),
        "adv": dbus.Interface(adapter_object, LE_ADVERTISING_MANAGER_IFACE),
    }

    logging.info("Using adapter %s as BLE peripheral %s", adapter_path, config.local_name)
    logging.info("Service UUID %s", config.service_uuid)
    loop = GLib.MainLoop()
    state = {"done": False, "exit_code": 0, "gatt_registered": False, "adv_registered": False}

    def shutdown() -> bool:
        if state["done"]:
            return False
        state["done"] = True
        logging.info("Stopping BLE peripheral")
        if state["gatt_registered"] or state["adv_registered"]:
            unregister_peripheral(
                managers,
                app,
                advertisement,
                unregister_adv=state["adv_registered"],
                unregister_gatt=state["gatt_registered"],
            )
        service.stop()
        loop.quit()
        return False

    def handle_signal(signum: int, _frame: Any) -> None:
        logging.info("Received signal %s", signum)
        GLib.idle_add(shutdown)

    def registration_error(error: Any) -> None:
        logging.error("BLE registration failed: %s", error)
        state["exit_code"] = 1
        GLib.idle_add(shutdown)

    def advertisement_registered() -> None:
        state["adv_registered"] = True
        logging.info("BLE application and advertisement registered")

    def application_registered() -> None:
        state["gatt_registered"] = True
        logging.info("GATT application registered")
        managers["adv"].RegisterAdvertisement(
            advertisement.get_path(),
            {},
            reply_handler=advertisement_registered,
            error_handler=registration_error,
        )

    def registration_timeout() -> bool:
        if state["adv_registered"]:
            return False
        logging.error("BLE registration timed out")
        state["exit_code"] = 1
        GLib.idle_add(shutdown)
        return False

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)
    GLib.timeout_add_seconds(15, registration_timeout)
    managers["gatt"].RegisterApplication(
        app.get_path(),
        {},
        reply_handler=application_registered,
        error_handler=registration_error,
    )

    try:
        loop.run()
        return state["exit_code"]
    finally:
        if not state["done"] and (state["gatt_registered"] or state["adv_registered"]):
            unregister_peripheral(
                managers,
                app,
                advertisement,
                unregister_adv=state["adv_registered"],
                unregister_gatt=state["gatt_registered"],
            )
        if not state["done"]:
            service.stop()


if __name__ == "__main__":
    raise SystemExit(main())
