from __future__ import annotations

import asyncio
import unittest

from robot_protocol import Frame, FrameType, StreamDecoder, build_ack_frame, encode_frame
from robot_server.config import BLEConfig
from robot_server.transports.ble.bluez_gatt import BlueZGATTTransport, StateCharacteristic
from robot_server.transports.ble.bluez_gatt_glib import DEVICE_IFACE


class _FakeVariant:
    def __init__(self, value: object) -> None:
        self.value = value


class _RecordingStateCharacteristic(StateCharacteristic):
    def __init__(self) -> None:
        super().__init__(
            path="/service0/char1",
            uuid="12345678-1234-5678-1234-56789abc0002",
            service_path="/service0",
            default_mtu=23,
            max_mtu=517,
        )
        self.emitted = []

    def set_value(self, value: bytes) -> None:
        self.emitted.append(value)
        super().set_value(value)


class BlueZGATTTransportTests(unittest.IsolatedAsyncioTestCase):
    async def test_state_push_chunks_payload_by_session_mtu(self) -> None:
        characteristic = _RecordingStateCharacteristic()
        characteristic.StartNotify()
        characteristic.set_session("peer-a", mtu=23)

        frame = encode_frame(Frame(frame_type=FrameType.STATE, seq=7, payload=b"x" * 48))
        await characteristic.push(frame, session_id="peer-a")

        self.assertGreater(len(characteristic.emitted), 1)
        self.assertTrue(all(len(chunk) <= 20 for chunk in characteristic.emitted))

        decoder = StreamDecoder()
        frames = decoder.feed(b"".join(characteristic.emitted))
        self.assertEqual(len(frames), 1)
        self.assertEqual(frames[0].frame_type, FrameType.STATE)
        self.assertEqual(frames[0].seq, 7)
        self.assertEqual(frames[0].payload, b"x" * 48)

    async def test_command_write_uses_device_path_as_session_and_updates_mtu(self) -> None:
        transport = BlueZGATTTransport(BLEConfig())
        state_char = _RecordingStateCharacteristic()
        state_char.StartNotify()
        transport._state_char = state_char

        captured = {}

        async def handler(envelope) -> None:
            captured["session_id"] = envelope.session_id
            captured["payload"] = envelope.payload
            await envelope.reply(encode_frame(build_ack_frame(5)))

        transport._handler = handler

        await transport._handle_command_write(
            b"\x01\x02",
            {
                "device": _FakeVariant("/org/bluez/hci0/dev_DE_AD_BE_EF"),
                "mtu": _FakeVariant(80),
            },
        )

        self.assertEqual(captured["session_id"], "/org/bluez/hci0/dev_DE_AD_BE_EF")
        self.assertEqual(captured["payload"], b"\x01\x02")
        self.assertEqual(state_char.active_session_id, "/org/bluez/hci0/dev_DE_AD_BE_EF")
        self.assertEqual(
            state_char.chunk_payload(b"a" * 100, session_id="/org/bluez/hci0/dev_DE_AD_BE_EF"),
            [b"a" * 77, b"a" * 23],
        )
        self.assertEqual(len(state_char.emitted), 1)
        self.assertEqual(StreamDecoder().feed(state_char.emitted[0])[0].frame_type, FrameType.ACK)

    async def test_device_disconnect_notifies_runtime_handler(self) -> None:
        transport = BlueZGATTTransport(BLEConfig())
        loop = asyncio.get_running_loop()
        transport._asyncio_loop = loop
        transport._session_id = "/org/bluez/hci0/dev_DE_AD_BE_EF"
        calls = []

        async def disconnect_handler(transport_name: str, session_id: str) -> None:
            calls.append((transport_name, session_id))

        transport.set_disconnect_handler(disconnect_handler)

        transport._on_properties_changed(
            DEVICE_IFACE,
            {"Connected": _FakeVariant(False)},
            [],
            path="/org/bluez/hci0/dev_DE_AD_BE_EF",
        )
        await loop.run_in_executor(None, lambda: None)

        self.assertEqual(calls, [("ble", "/org/bluez/hci0/dev_DE_AD_BE_EF")])
        self.assertEqual(transport._session_id, "central")


if __name__ == "__main__":
    unittest.main()
