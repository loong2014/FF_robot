"""GLib-based BlueZ GATT transport built from the proven robot BLE service.

The previous BLE implementation in ``robot_server`` tried to support multiple
BlueZ backends and a larger state machine. The code that has actually been
validated on the robot dog is the standalone ``robot_ble_peripheral.py`` in
the sibling project. This module ports that implementation back into
``robot_server`` while keeping the existing ``RuntimeTransport`` contract and
the current unit-test surface.
"""

from __future__ import annotations

import asyncio
import functools
import logging
import threading
from typing import Any, Callable, Dict, List, Optional, TypeVar

from ...config import BLEConfig
from ...models import TransportEnvelope
from ..base import EnvelopeHandler, RuntimeTransport

_logger = logging.getLogger(__name__)
_T = TypeVar("_T")
_ASYNCIO_TO_THREAD = getattr(asyncio, "to_thread", None)

try:
    import dbus  # type: ignore[import-not-found]
    import dbus.exceptions  # type: ignore[import-not-found]
    import dbus.mainloop.glib  # type: ignore[import-not-found]
    import dbus.service  # type: ignore[import-not-found]
    from gi.repository import GLib  # type: ignore[import-not-found]

    _HAS_GLIB_STACK = True
    _GLIB_IMPORT_ERROR: Optional[BaseException] = None
except ImportError as _imp_err:  # pragma: no cover - optional dependency
    dbus = None  # type: ignore[assignment]
    GLib = None  # type: ignore[assignment]
    _HAS_GLIB_STACK = False
    _GLIB_IMPORT_ERROR = _imp_err


BLUEZ_SERVICE_NAME = "org.bluez"
DBUS_OM_IFACE = "org.freedesktop.DBus.ObjectManager"
DBUS_PROP_IFACE = "org.freedesktop.DBus.Properties"
LE_ADVERTISEMENT_IFACE = "org.bluez.LEAdvertisement1"
LE_ADVERTISING_MANAGER_IFACE = "org.bluez.LEAdvertisingManager1"
GATT_MANAGER_IFACE = "org.bluez.GattManager1"
GATT_SERVICE_IFACE = "org.bluez.GattService1"
GATT_CHRC_IFACE = "org.bluez.GattCharacteristic1"
ADAPTER_IFACE = "org.bluez.Adapter1"
DEVICE_IFACE = "org.bluez.Device1"
_ADV_REGISTER_MAX_ATTEMPTS = 5
_ADV_REGISTER_RETRY_DELAY_MS = 1200


def glib_stack_available() -> bool:
    return _HAS_GLIB_STACK


def _unwrap_variant(value: object) -> object:
    return getattr(value, "value", value)


def _coerce_bool(value: object) -> Optional[bool]:
    raw = _unwrap_variant(value)
    if raw is None:
        return None
    if isinstance(raw, bool):
        return raw
    if isinstance(raw, (int, float)):
        return bool(int(raw))

    text = str(raw).strip().lower()
    if text in {"1", "true", "yes", "on"}:
        return True
    if text in {"0", "false", "no", "off"}:
        return False
    return None


async def _call_in_thread(func: Callable[..., _T], *args: Any, **kwargs: Any) -> _T:
    """Python 3.8-compatible ``asyncio.to_thread`` wrapper."""

    if _ASYNCIO_TO_THREAD is not None:
        return await _ASYNCIO_TO_THREAD(func, *args, **kwargs)

    loop = asyncio.get_running_loop()
    bound = functools.partial(func, *args, **kwargs)
    return await loop.run_in_executor(None, bound)


class StateCharacteristic:
    """Pure-Python state characteristic used by tests and dbus exporters."""

    def __init__(self, path: str, uuid: str, service_path: str, default_mtu: int, max_mtu: int) -> None:
        self.path = path
        self.uuid = uuid
        self.service_path = service_path
        self._value = b""
        self._notifying = False
        self._default_mtu = self._clamp_mtu(default_mtu, max_mtu)
        self._max_mtu = max_mtu
        self._active_session_id = "central"
        self._session_mtu: Dict[str, int] = {}
        self._emit_value: Optional[Callable[[bytes], None]] = None

    @property
    def active_session_id(self) -> str:
        return self._active_session_id

    @property
    def notifying(self) -> bool:
        return self._notifying

    def attach_emitter(self, emit_value: Callable[[bytes], None]) -> None:
        self._emit_value = emit_value

    def set_session(self, session_id: str, mtu: Optional[int] = None) -> None:
        self._active_session_id = session_id
        if mtu is not None:
            self._session_mtu[session_id] = self._clamp_mtu(mtu, self._max_mtu)

    def _clamp_mtu(self, mtu: int, max_mtu: int) -> int:
        return max(23, min(int(mtu), int(max_mtu)))

    def chunk_payload(self, payload: bytes, session_id: Optional[str] = None) -> List[bytes]:
        target_session = session_id or self._active_session_id
        mtu = self._session_mtu.get(target_session, self._default_mtu)
        chunk_size = max(20, mtu - 3)
        return [payload[index : index + chunk_size] for index in range(0, len(payload), chunk_size)] or [b""]

    def ReadValue(self, options: Optional[Dict[str, object]] = None) -> bytes:
        opts = options or {}
        offset = int(_unwrap_variant(opts.get("offset", 0)))
        if offset < 0 or offset > len(self._value):
            raise ValueError("invalid offset")
        return self._value[offset:]

    def StartNotify(self) -> None:
        self._notifying = True

    def StopNotify(self) -> None:
        self._notifying = False

    def set_value(self, value: bytes) -> None:
        self._value = value
        if self._emit_value is not None and self._notifying:
            self._emit_value(value)

    def push_frame(self, payload: bytes, session_id: Optional[str] = None) -> None:
        if not self._notifying:
            return
        target_session = session_id or self._active_session_id
        self._active_session_id = target_session
        for chunk in self.chunk_payload(payload, target_session):
            self.set_value(chunk)

    async def push(self, payload: bytes, session_id: Optional[str] = None) -> None:
        if not self._notifying:
            return
        target_session = session_id or self._active_session_id
        self._active_session_id = target_session
        for chunk in self.chunk_payload(payload, target_session):
            self.set_value(chunk)
            await asyncio.sleep(0)


if _HAS_GLIB_STACK:

    def _to_dbus_bytes(payload: bytes):
        return dbus.Array(bytearray(payload), signature="y")


    class _Application(dbus.service.Object):  # type: ignore[misc,no-redef]
        def __init__(self, bus: Any, path: str) -> None:
            self.path = path
            self._services: List["_Service"] = []
            super().__init__(bus, path)

        def get_path(self):
            return dbus.ObjectPath(self.path)

        def add_service(self, service: "_Service") -> None:
            self._services.append(service)

        @dbus.service.method(DBUS_OM_IFACE, out_signature="a{oa{sa{sv}}}")
        def GetManagedObjects(self):
            managed: Dict[Any, Dict[str, Dict[str, Any]]] = {}
            for service in self._services:
                managed[service.get_path()] = service.get_properties()
                for characteristic in service.get_characteristics():
                    managed[characteristic.get_path()] = characteristic.get_properties()
            return managed


    class _Service(dbus.service.Object):  # type: ignore[misc,no-redef]
        def __init__(self, bus: Any, path: str, uuid: str, primary: bool = True) -> None:
            self.path = path
            self.uuid = uuid
            self.primary = primary
            self._characteristics: List[Any] = []
            super().__init__(bus, path)

        def add_characteristic(self, characteristic: Any) -> None:
            self._characteristics.append(characteristic)

        def get_characteristics(self) -> List[Any]:
            return self._characteristics

        def get_path(self):
            return dbus.ObjectPath(self.path)

        def get_properties(self) -> Dict[str, Dict[str, Any]]:
            return {
                GATT_SERVICE_IFACE: {
                    "UUID": self.uuid,
                    "Primary": self.primary,
                    "Characteristics": dbus.Array([c.get_path() for c in self._characteristics], signature="o"),
                }
            }

        @dbus.service.method(DBUS_PROP_IFACE, in_signature="s", out_signature="a{sv}")
        def GetAll(self, interface):
            if interface != GATT_SERVICE_IFACE:
                raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs")
            return self.get_properties()[GATT_SERVICE_IFACE]


    class _CommandExporter(dbus.service.Object):  # type: ignore[misc,no-redef]
        def __init__(
            self,
            bus: Any,
            path: str,
            uuid: str,
            service_path: str,
            on_write: Callable[[bytes, Dict[str, object]], None],
        ) -> None:
            self.path = path
            self.uuid = uuid
            self.service_path = service_path
            self.flags = ["write", "write-without-response"]
            self._value = b""
            self._on_write = on_write
            super().__init__(bus, path)

        def get_path(self):
            return dbus.ObjectPath(self.path)

        def get_properties(self) -> Dict[str, Dict[str, Any]]:
            return {
                GATT_CHRC_IFACE: {
                    "Service": dbus.ObjectPath(self.service_path),
                    "UUID": self.uuid,
                    "Flags": dbus.Array(self.flags, signature="s"),
                    "Descriptors": dbus.Array([], signature="o"),
                    "Value": _to_dbus_bytes(self._value),
                }
            }

        @dbus.service.method(DBUS_PROP_IFACE, in_signature="s", out_signature="a{sv}")
        def GetAll(self, interface):
            if interface != GATT_CHRC_IFACE:
                raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs")
            return self.get_properties()[GATT_CHRC_IFACE]

        @dbus.service.method(GATT_CHRC_IFACE, in_signature="aya{sv}")
        def WriteValue(self, value, options):
            payload = bytes(value)
            self._value = payload
            self._on_write(payload, dict(options))


    class _StateExporter(dbus.service.Object):  # type: ignore[misc,no-redef]
        def __init__(self, bus: Any, characteristic: StateCharacteristic) -> None:
            self._characteristic = characteristic
            self.path = characteristic.path
            self.uuid = characteristic.uuid
            self.flags = ["read", "notify"]
            characteristic.attach_emitter(self._emit_value)
            super().__init__(bus, self.path)

        def get_path(self):
            return dbus.ObjectPath(self.path)

        def get_properties(self) -> Dict[str, Dict[str, Any]]:
            return {
                GATT_CHRC_IFACE: {
                    "Service": dbus.ObjectPath(self._characteristic.service_path),
                    "UUID": self.uuid,
                    "Flags": dbus.Array(self.flags, signature="s"),
                    "Descriptors": dbus.Array([], signature="o"),
                    "Value": _to_dbus_bytes(self._characteristic.ReadValue({})),
                    "Notifying": self._characteristic.notifying,
                }
            }

        @dbus.service.method(DBUS_PROP_IFACE, in_signature="s", out_signature="a{sv}")
        def GetAll(self, interface):
            if interface != GATT_CHRC_IFACE:
                raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs")
            return self.get_properties()[GATT_CHRC_IFACE]

        @dbus.service.method(GATT_CHRC_IFACE, in_signature="a{sv}", out_signature="ay")
        def ReadValue(self, options):
            try:
                return _to_dbus_bytes(self._characteristic.ReadValue(dict(options)))
            except ValueError as exc:
                raise dbus.exceptions.DBusException(
                    "org.freedesktop.DBus.Error.InvalidArgs",
                    str(exc),
                )

        @dbus.service.method(GATT_CHRC_IFACE)
        def StartNotify(self):
            self._characteristic.StartNotify()
            _logger.info("BLE state notify enabled")

        @dbus.service.method(GATT_CHRC_IFACE)
        def StopNotify(self):
            self._characteristic.StopNotify()
            _logger.info("BLE state notify disabled")

        def _emit_value(self, payload: bytes) -> None:
            self.PropertiesChanged(GATT_CHRC_IFACE, {"Value": _to_dbus_bytes(payload)}, [])

        @dbus.service.signal(DBUS_PROP_IFACE, signature="sa{sv}as")
        def PropertiesChanged(self, interface, changed, invalidated):
            pass


    class _Advertisement(dbus.service.Object):  # type: ignore[misc,no-redef]
        def __init__(self, bus: Any, path: str, service_uuid: str, local_name: str) -> None:
            self.path = path
            self.service_uuid = service_uuid
            self.local_name = local_name
            super().__init__(bus, path)

        def get_path(self):
            return dbus.ObjectPath(self.path)

        def get_properties(self) -> Dict[str, Dict[str, Any]]:
            return {
                LE_ADVERTISEMENT_IFACE: {
                    "Type": "peripheral",
                    "ServiceUUIDs": dbus.Array([self.service_uuid], signature="s"),
                    "LocalName": self.local_name,
                    "Includes": dbus.Array(["tx-power"], signature="s"),
                }
            }

        @dbus.service.method(DBUS_PROP_IFACE, in_signature="s", out_signature="a{sv}")
        def GetAll(self, interface):
            if interface != LE_ADVERTISEMENT_IFACE:
                raise dbus.exceptions.DBusException("org.freedesktop.DBus.Error.InvalidArgs")
            return self.get_properties()[LE_ADVERTISEMENT_IFACE]

        @dbus.service.method(LE_ADVERTISEMENT_IFACE, in_signature="", out_signature="")
        def Release(self):
            _logger.info("BLE advertisement released")


def find_adapter(bus: Any) -> str:
    if not _HAS_GLIB_STACK:
        raise RuntimeError("dbus-python + GLib are required")
    manager = dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, "/"), DBUS_OM_IFACE)
    objects = manager.GetManagedObjects()
    for path, interfaces in objects.items():
        if GATT_MANAGER_IFACE in interfaces and LE_ADVERTISING_MANAGER_IFACE in interfaces:
            return str(path)
    raise RuntimeError("No BLE adapter with GATT + LE advertising support found")


def unregister_peripheral(
    managers: Dict[str, Any],
    app: Any,
    advertisement: Any,
    unregister_adv: bool = True,
    unregister_gatt: bool = True,
) -> None:
    if unregister_adv:
        try:
            managers["adv"].UnregisterAdvertisement(advertisement.get_path())
        except Exception:  # pragma: no cover - best effort cleanup
            _logger.exception("Failed to unregister advertisement")
    if unregister_gatt:
        try:
            managers["gatt"].UnregisterApplication(app.get_path())
        except Exception:  # pragma: no cover - best effort cleanup
            _logger.exception("Failed to unregister application")


class BlueZGATTTransportGLib(RuntimeTransport):
    name = "ble"

    def __init__(self, config: BLEConfig) -> None:
        self._config = config
        self._handler: Optional[EnvelopeHandler] = None
        self._asyncio_loop: Optional[asyncio.AbstractEventLoop] = None
        self._thread: Optional[threading.Thread] = None
        self._ready = threading.Event()
        self._start_error: Optional[BaseException] = None
        self._glib_loop: Optional[Any] = None
        self._bus: Optional[Any] = None
        self._adapter_path: Optional[str] = None
        self._managers: Dict[str, Any] = {}
        self._app: Optional[Any] = None
        self._advertisement: Optional[Any] = None
        self._state_char: Optional[StateCharacteristic] = None
        self._gatt_registered = False
        self._adv_registered = False
        self._registering_advertisement = False
        self._adv_register_attempts = 0
        self._session_id = "central"

    async def start(self, handler: EnvelopeHandler) -> None:
        if not self._config.enabled:
            return
        if not _HAS_GLIB_STACK:
            raise RuntimeError(
                "GLib BLE backend requires dbus-python + PyGObject "
                "(python3-dbus / python3-gi). Import error: {}.".format(_GLIB_IMPORT_ERROR)
            )
        self._handler = handler
        self._asyncio_loop = asyncio.get_running_loop()
        await _call_in_thread(self._start_blocking)

    def _start_blocking(self) -> None:
        if self._thread is not None:
            return
        self._ready.clear()
        self._start_error = None
        self._thread = threading.Thread(target=self._run_glib, name="robot-ble-glib", daemon=True)
        self._thread.start()
        timeout = max(15.0, float(self._config.ready_timeout_sec))
        if not self._ready.wait(timeout=timeout):
            raise RuntimeError("BLE registration timed out after {:.1f}s".format(timeout))
        if self._start_error is not None:
            err = self._start_error
            self._start_error = None
            self._thread.join(timeout=1.0)
            self._thread = None
            raise err

    def _run_glib(self) -> None:
        assert _HAS_GLIB_STACK
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        self._glib_loop = GLib.MainLoop()
        try:
            self._bus = dbus.SystemBus()
            self._bus.add_signal_receiver(
                self._on_properties_changed,
                dbus_interface=DBUS_PROP_IFACE,
                signal_name="PropertiesChanged",
                path_keyword="path",
            )
            self._adapter_path = find_adapter(self._bus)
            self._build_objects()
            self._register_objects()
            GLib.timeout_add_seconds(max(15, int(self._config.ready_timeout_sec)), self._registration_timeout)
            self._glib_loop.run()
        except BaseException as exc:  # noqa: BLE001
            self._start_error = exc
            self._ready.set()
        finally:
            self._glib_loop = None
            self._bus = None

    def _build_objects(self) -> None:
        assert self._bus is not None
        app_path = self._config.app_path
        service_path = f"{app_path}/service0"
        state_char = StateCharacteristic(
            path=f"{service_path}/char1",
            uuid=self._config.state_char_uuid,
            service_path=service_path,
            default_mtu=self._config.mtu_default,
            max_mtu=self._config.mtu_max,
        )
        command_char = _CommandExporter(
            self._bus,
            path=f"{service_path}/char0",
            uuid=self._config.cmd_char_uuid,
            service_path=service_path,
            on_write=self._on_command_write_from_glib,
        )
        state_exporter = _StateExporter(self._bus, state_char)
        service = _Service(self._bus, service_path, self._config.service_uuid, primary=True)
        service.add_characteristic(command_char)
        service.add_characteristic(state_exporter)
        app = _Application(self._bus, app_path)
        app.add_service(service)
        advertisement = _Advertisement(
            self._bus,
            path=f"{app_path}/advertisement0",
            service_uuid=self._config.service_uuid,
            local_name=self._config.device_name,
        )

        self._state_char = state_char
        self._app = app
        self._advertisement = advertisement

    def _register_objects(self) -> None:
        assert self._bus is not None
        assert self._adapter_path is not None
        assert self._app is not None
        assert self._advertisement is not None

        adapter_object = self._bus.get_object(BLUEZ_SERVICE_NAME, self._adapter_path)
        self._managers = {
            "gatt": dbus.Interface(adapter_object, GATT_MANAGER_IFACE),
            "adv": dbus.Interface(adapter_object, LE_ADVERTISING_MANAGER_IFACE),
        }
        self._managers["gatt"].RegisterApplication(
            self._app.get_path(),
            {},
            reply_handler=self._application_registered,
            error_handler=self._registration_error,
        )

    def _application_registered(self) -> None:
        self._gatt_registered = True
        if not self._config.advertise_enabled:
            self._ready.set()
            return
        self._adv_register_attempts = 0
        self._register_advertisement()

    def _register_advertisement(self) -> None:
        assert self._advertisement is not None
        self._registering_advertisement = True
        self._adv_register_attempts += 1
        self._managers["adv"].RegisterAdvertisement(
            self._advertisement.get_path(),
            {},
            reply_handler=self._advertisement_registered,
            error_handler=self._registration_error,
        )

    def _advertisement_registered(self) -> None:
        self._adv_registered = True
        self._registering_advertisement = False
        _logger.info(
            "BLE advertisement registered adapter=%s name=%s service=%s",
            self._adapter_path,
            self._config.device_name,
            self._config.service_uuid,
        )
        self._ready.set()

    def _registration_error(self, error: Any) -> None:
        if self._registering_advertisement and self._adv_register_attempts < _ADV_REGISTER_MAX_ATTEMPTS:
            self._registering_advertisement = False
            _logger.warning(
                "BLE advertisement registration failed (attempt %d/%d): %s; retrying in %.1fs",
                self._adv_register_attempts,
                _ADV_REGISTER_MAX_ATTEMPTS,
                error,
                _ADV_REGISTER_RETRY_DELAY_MS / 1000.0,
            )
            if self._glib_loop is not None:
                GLib.timeout_add(_ADV_REGISTER_RETRY_DELAY_MS, self._retry_advertisement_registration)
                return
        self._start_error = RuntimeError("BLE registration failed: {}".format(error))
        self._ready.set()
        if self._glib_loop is not None:
            self._glib_loop.quit()

    def _retry_advertisement_registration(self) -> bool:
        if self._ready.is_set():
            return False
        self._register_advertisement()
        return False

    def _registration_timeout(self) -> bool:
        if self._ready.is_set():
            return False
        self._start_error = RuntimeError("BLE registration timed out")
        self._ready.set()
        if self._glib_loop is not None:
            self._glib_loop.quit()
        return False

    def _on_properties_changed(
        self,
        interface: str,
        changed: Dict[str, object],
        invalidated: List[str],
        path: Optional[object] = None,
    ) -> None:
        del invalidated
        if interface != DEVICE_IFACE:
            return

        connected = _coerce_bool(changed.get("Connected"))
        if connected is None:
            return

        device_path = "" if path is None else str(path)
        device_label = self._device_label(device_path)
        if connected:
            _logger.info("BLE central connected device=%s path=%s", device_label, device_path)
            return

        _logger.info("BLE central disconnected device=%s path=%s", device_label, device_path)
        if device_path and device_path == self._session_id:
            self._session_id = "central"

    @staticmethod
    def _device_label(device_path: str) -> str:
        marker = "dev_"
        if marker not in device_path:
            return device_path or "unknown"
        address = device_path.rsplit(marker, 1)[-1]
        return address.replace("_", ":")

    async def stop(self) -> None:
        if self._thread is None:
            return
        await _call_in_thread(self._stop_blocking)

    def _stop_blocking(self) -> None:
        if self._thread is None:
            return

        done = threading.Event()

        def shutdown() -> bool:
            try:
                if self._app is not None and self._advertisement is not None and self._managers:
                    unregister_peripheral(
                        self._managers,
                        self._app,
                        self._advertisement,
                        unregister_adv=self._adv_registered,
                        unregister_gatt=self._gatt_registered,
                    )
            finally:
                self._gatt_registered = False
                self._adv_registered = False
                self._registering_advertisement = False
                self._adv_register_attempts = 0
                if self._glib_loop is not None:
                    self._glib_loop.quit()
                done.set()
            return False

        if _HAS_GLIB_STACK and self._glib_loop is not None:
            GLib.idle_add(shutdown)
            done.wait(timeout=5.0)
        self._thread.join(timeout=5.0)
        self._thread = None
        self._app = None
        self._advertisement = None
        self._state_char = None
        self._managers = {}

    async def send(self, session_id: str, payload: bytes) -> None:
        if self._state_char is None:
            return
        if not _HAS_GLIB_STACK or self._glib_loop is None:
            await self._state_char.push(payload, session_id=session_id)
            return

        loop = asyncio.get_running_loop()
        fut: "asyncio.Future[None]" = loop.create_future()
        state_char = self._state_char

        def do_send() -> bool:
            try:
                state_char.push_frame(payload, session_id=session_id)
            except BaseException as exc:  # noqa: BLE001
                loop.call_soon_threadsafe(fut.set_exception, exc)
            else:
                loop.call_soon_threadsafe(fut.set_result, None)
            return False

        GLib.idle_add(do_send)
        await fut

    async def broadcast(self, payload: bytes) -> None:
        await self.send(self._session_id, payload)

    def _on_command_write_from_glib(self, payload: bytes, options: Dict[str, object]) -> None:
        if self._asyncio_loop is None:
            return
        future = asyncio.run_coroutine_threadsafe(
            self._handle_command_write(payload, options),
            self._asyncio_loop,
        )
        future.add_done_callback(self._log_command_exception)

    @staticmethod
    def _log_command_exception(future: "asyncio.Future[Any]") -> None:
        try:
            future.result()
        except Exception:  # pragma: no cover - best effort logging
            _logger.exception("BLE command handler failed")

    async def _handle_command_write(self, payload: bytes, options: Dict[str, object]) -> None:
        if self._handler is None:
            return

        session_id = self._session_id_from_options(options)
        mtu = self._mtu_from_options(options)
        _logger.info(
            "BLE cmd write peer=%s mtu=%s payload_len=%d payload_hex=%s",
            session_id,
            "-" if mtu is None else mtu,
            len(payload),
            payload.hex(),
        )
        self._session_id = session_id
        if self._state_char is not None:
            self._state_char.set_session(session_id, mtu)

        async def reply(frame: bytes) -> None:
            await self.send(session_id, frame)

        envelope = TransportEnvelope(
            transport_name=self.name,
            session_id=session_id,
            payload=payload,
            reply=reply,
        )
        await self._handler(envelope)

    @staticmethod
    def _session_id_from_options(options: Dict[str, object]) -> str:
        device = _unwrap_variant(options.get("device"))
        if isinstance(device, str) and device:
            return device
        if device is not None:
            text = str(device)
            if text:
                return text
        return "central"

    @staticmethod
    def _mtu_from_options(options: Dict[str, object]) -> Optional[int]:
        mtu_value = _unwrap_variant(options.get("mtu"))
        try:
            if mtu_value is None:
                return None
            return int(mtu_value)
        except (TypeError, ValueError):
            return None
