"""MQTT end-to-end smoke test.

Spins up ``RobotRuntime`` with the MQTT router enabled (BLE / TCP / ROS
disabled), then opens a second paho-mqtt client that plays the role of
the mobile SDK:

1. Subscribes to ``robot/{id}/state``.
2. Publishes MOVE / STAND / STOP frames on ``robot/{id}/control``.
3. Waits for ACK frames (seq 0/1/2) and at least one STATE frame.

**Requires a local broker** (mosquitto / emqx / etc.) reachable at
``--host:--port``. If no broker is running, the script exits with a
clear "please start a broker" message instead of hanging.

Run from the repo root::

    PYTHONPATH=protocol/python:robot_server \\
        python3 scripts/mqtt_smoke.py --host 127.0.0.1 --port 1883

Exits 0 on success, non-zero on any assertion failure.
"""

from __future__ import annotations

import argparse
import asyncio
import socket
import sys
from typing import List, Optional, Set

import paho.mqtt.client as mqtt  # type: ignore[import-not-found]

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

from robot_server import build_runtime
from robot_server.config import (
    BLEConfig,
    MQTTConfig,
    ROSConfig,
    ServerConfig,
    TCPConfig,
)


def _broker_reachable(host: str, port: int, timeout: float = 1.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


async def _run(host: str, port: int, robot_id: str) -> int:
    if not _broker_reachable(host, port):
        print(
            f"FAIL: cannot reach MQTT broker at {host}:{port}. "
            "Please start mosquitto / emqx locally first (e.g. "
            "`docker run -it --rm -p 1883:1883 eclipse-mosquitto`).",
            file=sys.stderr,
        )
        return 10

    config = ServerConfig(
        ble=BLEConfig(enabled=False),
        tcp=TCPConfig(enabled=False),
        mqtt=MQTTConfig(enabled=True, host=host, port=port, robot_id=robot_id, qos=1),
        ros=ROSConfig(enabled=False),
        state_hz=20,
    )
    runtime = build_runtime(config)
    await runtime.start()

    try:
        collected: List[Frame] = []
        ack_seqs: Set[int] = set()
        state_seen = asyncio.Event()
        ack_all = asyncio.Event()
        loop = asyncio.get_running_loop()
        decoder = StreamDecoder()

        client = mqtt.Client(
            client_id=f"mqtt-smoke-{robot_id}",
            protocol=mqtt.MQTTv311,
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
        )

        def on_connect(client: mqtt.Client, userdata: object, flags: object, reason_code: int, properties: object = None) -> None:
            client.subscribe(f"robot/{robot_id}/state", qos=1)

        def on_message(client: mqtt.Client, userdata: object, message: mqtt.MQTTMessage) -> None:
            for frame in decoder.feed(bytes(message.payload)):
                collected.append(frame)
                if frame.frame_type == FrameType.ACK:
                    ack_seqs.add(frame.seq)
                    if ack_seqs >= {0, 1, 2}:
                        loop.call_soon_threadsafe(ack_all.set)
                elif frame.frame_type == FrameType.STATE:
                    loop.call_soon_threadsafe(state_seen.set)

        client.on_connect = on_connect
        client.on_message = on_message
        client.connect(host, port, 30)
        client.loop_start()

        try:
            # Give both router and smoke client time to subscribe.
            await asyncio.sleep(0.5)

            for seq, command in (
                (0, MoveCommand(vx=0.3, vy=0.0, yaw=0.1)),
                (1, DiscreteCommand(CommandId.STAND)),
                (2, DiscreteCommand(CommandId.STOP)),
            ):
                payload = encode_frame(build_command_frame(seq=seq, command=command))
                client.publish(f"robot/{robot_id}/control", payload, qos=1)
                await asyncio.sleep(0.05)

            try:
                await asyncio.wait_for(ack_all.wait(), timeout=3.0)
            except asyncio.TimeoutError:
                print(
                    f"FAIL: timed out waiting for ACKs, got seqs={sorted(ack_seqs)}",
                    file=sys.stderr,
                )
                return 2
            try:
                await asyncio.wait_for(state_seen.wait(), timeout=2.0)
            except asyncio.TimeoutError:
                print("FAIL: no STATE frame received within grace window", file=sys.stderr)
                return 3
        finally:
            client.loop_stop()
            client.disconnect()

        print(
            f"OK: MQTT round-trip succeeded (acks={sorted(ack_seqs)}, "
            f"state_frames={sum(1 for f in collected if f.frame_type == FrameType.STATE)})."
        )
        return 0
    finally:
        await runtime.stop()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=1883)
    parser.add_argument("--robot-id", default="dog-smoke")
    args = parser.parse_args()

    return asyncio.run(_run(args.host, args.port, args.robot_id))


if __name__ == "__main__":
    raise SystemExit(main())
