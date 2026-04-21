from __future__ import annotations

import asyncio
import unittest
from typing import List

from robot_protocol import (
    CommandId,
    DiscreteCommand,
    FrameType,
    MoveCommand,
    StreamDecoder,
    build_command_frame,
    encode_frame,
    parse_state_payload,
)

from robot_server.config import (
    BLEConfig,
    DebugStateTickConfig,
    MQTTConfig,
    ROSConfig,
    ServerConfig,
    TCPConfig,
)
from robot_server import build_runtime
from robot_server.models import TransportEnvelope
from robot_server.transports.tcp import TcpTransport


async def _pick_free_port() -> int:
    server = await asyncio.start_server(lambda r, w: None, host="127.0.0.1", port=0)
    port = server.sockets[0].getsockname()[1]
    server.close()
    await server.wait_closed()
    return port


class TcpTransportUnitTests(unittest.IsolatedAsyncioTestCase):
    async def test_start_dispatches_envelopes_and_send_delivers_bytes(self) -> None:
        transport = TcpTransport(host="127.0.0.1", port=await _pick_free_port())
        received: List[TransportEnvelope] = []
        done = asyncio.Event()

        async def handler(envelope: TransportEnvelope) -> None:
            received.append(envelope)
            await envelope.reply(b"pong:" + envelope.payload)
            done.set()

        await transport.start(handler)
        try:
            reader, writer = await asyncio.open_connection(transport.host, transport.port)
            writer.write(b"ping")
            await writer.drain()
            await asyncio.wait_for(done.wait(), timeout=1.0)

            data = await asyncio.wait_for(reader.read(64), timeout=1.0)
            self.assertEqual(data, b"pong:ping")

            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass
        finally:
            await transport.stop()

        self.assertEqual(len(received), 1)
        self.assertEqual(received[0].transport_name, "tcp")
        self.assertTrue(received[0].payload.startswith(b"ping"))
        # session_id should be unique even across reconnects (monotonic suffix).
        self.assertIn("#", received[0].session_id)

    async def test_send_to_unknown_session_is_noop(self) -> None:
        transport = TcpTransport(host="127.0.0.1", port=await _pick_free_port())
        await transport.start(lambda envelope: asyncio.sleep(0))
        try:
            await transport.send("no-such-session", b"payload")
            await transport.broadcast(b"broadcast-with-no-clients")
        finally:
            await transport.stop()


class TcpRuntimeIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def test_runtime_acks_commands_and_broadcasts_state(self) -> None:
        port = await _pick_free_port()
        config = ServerConfig(
            ble=BLEConfig(enabled=False),
            tcp=TCPConfig(enabled=True, host="127.0.0.1", port=port),
            mqtt=MQTTConfig(enabled=False),
            ros=ROSConfig(enabled=False),
            state_hz=25,
        )
        runtime = build_runtime(config)
        await runtime.start()
        try:
            reader, writer = await asyncio.open_connection("127.0.0.1", port)
            frames = []
            decoder = StreamDecoder()
            collected = asyncio.Event()
            ack_seen = set()
            state_seen = False

            async def collect() -> None:
                nonlocal state_seen
                while True:
                    data = await reader.read(4096)
                    if not data:
                        return
                    for frame in decoder.feed(data):
                        frames.append(frame)
                        if frame.frame_type == FrameType.ACK:
                            ack_seen.add(frame.seq)
                        elif frame.frame_type == FrameType.STATE:
                            state_seen = True
                        if ack_seen >= {0, 1, 2} and state_seen:
                            collected.set()

            task = asyncio.create_task(collect())

            writer.write(
                encode_frame(
                    build_command_frame(
                        seq=0, command=MoveCommand(vx=0.3, vy=0.0, yaw=0.1)
                    )
                )
            )
            writer.write(
                encode_frame(
                    build_command_frame(
                        seq=1, command=DiscreteCommand(CommandId.STAND)
                    )
                )
            )
            writer.write(
                encode_frame(
                    build_command_frame(
                        seq=2, command=DiscreteCommand(CommandId.STOP)
                    )
                )
            )
            await writer.drain()

            try:
                await asyncio.wait_for(collected.wait(), timeout=2.0)
            finally:
                writer.close()
                try:
                    await writer.wait_closed()
                except Exception:
                    pass
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass
                except Exception:
                    pass

            self.assertEqual({0, 1, 2}, ack_seen)
            self.assertTrue(
                any(frame.frame_type == FrameType.STATE for frame in frames),
                "expected at least one STATE frame broadcast within grace window",
            )
        finally:
            await asyncio.wait_for(runtime.stop(), timeout=3.0)

    async def test_runtime_debug_state_ticker_changes_broadcast_states(self) -> None:
        port = await _pick_free_port()
        config = ServerConfig(
            ble=BLEConfig(enabled=False),
            tcp=TCPConfig(enabled=True, host="127.0.0.1", port=port),
            mqtt=MQTTConfig(enabled=False),
            ros=ROSConfig(enabled=False),
            debug_state_tick=DebugStateTickConfig(enabled=True, interval_sec=0.05),
            state_hz=20,
        )
        runtime = build_runtime(config)
        await runtime.start()
        try:
            reader, writer = await asyncio.open_connection("127.0.0.1", port)
            decoder = StreamDecoder()
            seen_states = set()
            collected = asyncio.Event()

            async def collect() -> None:
                while True:
                    data = await reader.read(4096)
                    if not data:
                        return
                    for frame in decoder.feed(data):
                        if frame.frame_type != FrameType.STATE:
                            continue
                        state = parse_state_payload(frame.payload)
                        seen_states.add(
                            (
                                state.battery,
                                state.roll,
                                state.pitch,
                                state.yaw,
                            )
                        )
                        if len(seen_states) >= 3:
                            collected.set()
                            return

            task = asyncio.create_task(collect())

            try:
                await asyncio.wait_for(collected.wait(), timeout=2.0)
            finally:
                writer.close()
                try:
                    await writer.wait_closed()
                except Exception:
                    pass
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass
                except Exception:
                    pass

            self.assertGreaterEqual(
                len(seen_states),
                3,
                "expected debug state ticker to produce changing STATE frames",
            )
        finally:
            await asyncio.wait_for(runtime.stop(), timeout=3.0)


if __name__ == "__main__":
    unittest.main()
