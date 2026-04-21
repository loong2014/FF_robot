"""TCP end-to-end smoke test.

Spins up a TcpTransport + RobotRuntime in-process (BLE / MQTT / ROS disabled),
then opens a real asyncio TCP client that:

1. Sends a MOVE command, a STAND command and a STOP command.
2. Asserts every command gets a matching ACK frame.
3. Asserts the 10Hz state loop broadcasts at least one STATE frame.

Run from repo root:

    PYTHONPATH=protocol/python:robot_server python3 scripts/tcp_smoke.py

Exits with code 0 on success, non-zero on any assertion failure.
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from typing import List

from robot_protocol import (
    CommandId,
    DiscreteCommand,
    Frame,
    FrameType,
    MoveCommand,
    StreamDecoder,
    build_command_frame,
    encode_frame,
)

from robot_server.config import (
    BLEConfig,
    MQTTConfig,
    ROSConfig,
    ServerConfig,
    TCPConfig,
)
from robot_server import build_runtime


async def _collect_frames(
    reader: asyncio.StreamReader,
    decoder: StreamDecoder,
    output: List[Frame],
    done: asyncio.Event,
) -> None:
    try:
        while not done.is_set():
            chunk = await reader.read(4096)
            if not chunk:
                return
            for frame in decoder.feed(chunk):
                output.append(frame)
    except asyncio.CancelledError:
        raise


async def _run(host: str, port: int) -> int:
    config = ServerConfig(
        ble=BLEConfig(enabled=False),
        tcp=TCPConfig(enabled=True, host=host, port=port),
        mqtt=MQTTConfig(enabled=False),
        ros=ROSConfig(enabled=False),
        state_hz=20,
    )
    runtime = build_runtime(config)
    await runtime.start()
    try:
        reader, writer = await asyncio.open_connection(host, port)
        frames: List[Frame] = []
        done = asyncio.Event()
        collector = asyncio.create_task(_collect_frames(reader, StreamDecoder(), frames, done))

        commands = [
            (0, build_command_frame(seq=0, command=MoveCommand(vx=0.3, vy=0.0, yaw=0.1))),
            (1, build_command_frame(seq=1, command=DiscreteCommand(CommandId.STAND))),
            (2, build_command_frame(seq=2, command=DiscreteCommand(CommandId.STOP))),
        ]

        for _, frame in commands:
            writer.write(encode_frame(frame))
            await writer.drain()
            await asyncio.sleep(0.02)

        await asyncio.sleep(0.3)
        done.set()
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass
        collector.cancel()
        try:
            await collector
        except asyncio.CancelledError:
            pass

        acks = [f for f in frames if f.frame_type == FrameType.ACK]
        states = [f for f in frames if f.frame_type == FrameType.STATE]
        ack_seqs = sorted({f.seq for f in acks})
        expected_seqs = {seq for seq, _ in commands}

        print(f"Received {len(acks)} ACK frame(s), seqs={ack_seqs}")
        print(f"Received {len(states)} STATE frame(s)")

        missing = expected_seqs - set(ack_seqs)
        if missing:
            print(f"FAIL: missing ACK for seqs {sorted(missing)}", file=sys.stderr)
            return 2
        if not states:
            print("FAIL: no STATE frames received within grace window", file=sys.stderr)
            return 3

        print("OK: TCP round-trip succeeded (ACK + STATE).")
        return 0
    finally:
        await runtime.stop()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9100)
    args = parser.parse_args()

    return asyncio.run(_run(args.host, args.port))


if __name__ == "__main__":
    raise SystemExit(main())
