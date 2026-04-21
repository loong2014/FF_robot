"""BLE backend factory + glib transport 纯 Python 逻辑单测。

在 Mac / CI 上 dbus-python + PyGObject 通常不可用，因此 glib 后端的 D-Bus /
GLib 行为留给真机烟测；这里只覆盖：

1. :func:`create_ble_transport` 按 ``backend`` 正确 dispatch
2. ``auto`` 在当前环境下的 fallback 行为
3. 与 backend 无关的 helper：``_session_id_from_options`` / ``_mtu_from_options``
"""

from __future__ import annotations

import unittest
from unittest import mock

from robot_server.config import BLEConfig
from robot_server.transports.ble import (
    BlueZGATTTransport,
    BlueZGATTTransportGLib,
    create_ble_transport,
)
from robot_server.transports.ble import bluez_gatt_glib as glib_mod


class CreateBleTransportTests(unittest.TestCase):
    def test_dbus_next_backend_always_dispatches_to_asyncio_impl(self) -> None:
        cfg = BLEConfig(backend="dbus_next")
        transport = create_ble_transport(cfg)
        self.assertIsInstance(transport, BlueZGATTTransport)

    def test_glib_backend_raises_when_stack_unavailable(self) -> None:
        with mock.patch.object(
            glib_mod, "_HAS_GLIB_STACK", False
        ), mock.patch.object(
            glib_mod, "_GLIB_IMPORT_ERROR", ImportError("no dbus on mac")
        ):
            cfg = BLEConfig(backend="glib")
            with self.assertRaises(RuntimeError) as exc_ctx:
                create_ble_transport(cfg)
            self.assertIn("python3-dbus", str(exc_ctx.exception))

    def test_glib_backend_uses_glib_impl_when_stack_available(self) -> None:
        with mock.patch.object(glib_mod, "_HAS_GLIB_STACK", True):
            cfg = BLEConfig(backend="glib")
            transport = create_ble_transport(cfg)
            self.assertIsInstance(transport, BlueZGATTTransportGLib)

    def test_auto_falls_back_to_dbus_next_without_glib_stack(self) -> None:
        with mock.patch.object(glib_mod, "_HAS_GLIB_STACK", False):
            cfg = BLEConfig(backend="auto")
            transport = create_ble_transport(cfg)
            self.assertIsInstance(transport, BlueZGATTTransport)

    def test_auto_prefers_glib_when_available(self) -> None:
        with mock.patch.object(glib_mod, "_HAS_GLIB_STACK", True):
            cfg = BLEConfig(backend="auto")
            transport = create_ble_transport(cfg)
            self.assertIsInstance(transport, BlueZGATTTransportGLib)

    def test_unknown_backend_warns_and_uses_auto(self) -> None:
        with mock.patch.object(glib_mod, "_HAS_GLIB_STACK", False):
            cfg = BLEConfig(backend="definitely-not-a-real-backend")
            transport = create_ble_transport(cfg)
            self.assertIsInstance(transport, BlueZGATTTransport)


class GlibOptionParsingTests(unittest.TestCase):
    """The option-parsing helpers are pure Python and backend-independent."""

    def test_coerce_bool_handles_python_and_dbus_like_values(self) -> None:
        self.assertTrue(glib_mod._coerce_bool(True))
        self.assertFalse(glib_mod._coerce_bool(False))
        self.assertTrue(glib_mod._coerce_bool(1))
        self.assertFalse(glib_mod._coerce_bool(0))

        class FakeVariant:
            def __init__(self, value):
                self.value = value

        self.assertTrue(glib_mod._coerce_bool(FakeVariant(1)))
        self.assertFalse(glib_mod._coerce_bool(FakeVariant(0)))
        self.assertIsNone(glib_mod._coerce_bool(FakeVariant("unknown")))

    def test_session_id_falls_back_to_central_when_no_device(self) -> None:
        self.assertEqual(
            BlueZGATTTransportGLib._session_id_from_options({}),
            "central",
        )

    def test_session_id_uses_string_device_path(self) -> None:
        opts = {"device": "/org/bluez/hci0/dev_AA_BB"}
        self.assertEqual(
            BlueZGATTTransportGLib._session_id_from_options(opts),
            "/org/bluez/hci0/dev_AA_BB",
        )

    def test_session_id_uses_str_of_non_string_device(self) -> None:
        class FakeObjectPath:
            def __str__(self) -> str:
                return "/org/bluez/hci0/dev_CC_DD"

        opts = {"device": FakeObjectPath()}
        self.assertEqual(
            BlueZGATTTransportGLib._session_id_from_options(opts),
            "/org/bluez/hci0/dev_CC_DD",
        )

    def test_mtu_from_options_handles_none_and_invalid(self) -> None:
        self.assertIsNone(BlueZGATTTransportGLib._mtu_from_options({}))
        self.assertIsNone(
            BlueZGATTTransportGLib._mtu_from_options({"mtu": "not-a-number"})
        )

    def test_mtu_from_options_coerces_dbus_uint_like(self) -> None:
        class FakeUInt16(int):
            pass

        self.assertEqual(
            BlueZGATTTransportGLib._mtu_from_options({"mtu": FakeUInt16(185)}),
            185,
        )
        self.assertEqual(
            BlueZGATTTransportGLib._mtu_from_options({"mtu": 100}),
            100,
        )


class GlibThreadCompatTests(unittest.IsolatedAsyncioTestCase):
    async def test_call_in_thread_falls_back_to_run_in_executor_on_python38(self) -> None:
        with mock.patch.object(glib_mod, "_ASYNCIO_TO_THREAD", None):
            result = await glib_mod._call_in_thread(lambda left, right: left + right, 2, 3)
        self.assertEqual(result, 5)


class GlibAdvertisementRetryTests(unittest.TestCase):
    def test_registration_error_retries_advertisement_registration(self) -> None:
        transport = BlueZGATTTransportGLib(BLEConfig())
        transport._glib_loop = mock.Mock()
        transport._registering_advertisement = True
        transport._adv_register_attempts = 1
        fake_glib = mock.Mock()

        with mock.patch.object(glib_mod, "GLib", fake_glib):
            transport._registration_error("org.bluez.Error.Failed: Failed to register advertisement")

        fake_glib.timeout_add.assert_called_once_with(
            glib_mod._ADV_REGISTER_RETRY_DELAY_MS,
            transport._retry_advertisement_registration,
        )
        self.assertIsNone(transport._start_error)
        self.assertFalse(transport._ready.is_set())

    def test_registration_error_fails_after_retry_budget_is_exhausted(self) -> None:
        transport = BlueZGATTTransportGLib(BLEConfig())
        transport._glib_loop = mock.Mock()
        transport._registering_advertisement = True
        transport._adv_register_attempts = glib_mod._ADV_REGISTER_MAX_ATTEMPTS
        fake_glib = mock.Mock()

        with mock.patch.object(glib_mod, "GLib", fake_glib):
            transport._registration_error("org.bluez.Error.Failed: Failed to register advertisement")

        fake_glib.timeout_add.assert_not_called()
        self.assertIsInstance(transport._start_error, RuntimeError)
        self.assertIn("Failed to register advertisement", str(transport._start_error))
        self.assertTrue(transport._ready.is_set())


if __name__ == "__main__":
    unittest.main()
