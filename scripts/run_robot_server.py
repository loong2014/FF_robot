"""Minimal robot_server runner.

Starts a :class:`RobotRuntime` using ``ServerConfig`` loaded from env vars
(see ``robot_server/robot_server/config.py``) so that testers can run the
core TCP / MQTT / ROS stack without writing Python.

默认模式是 BLE-only：``robot_server`` 进程内直接注册 BlueZ GATT peripheral。
需要旁路调试时，再显式打开 TCP / MQTT。

Typical usage::

    PYTHONPATH=protocol/python:robot_server \
    ROBOT_BLE_ENABLED=true ROBOT_TCP_ENABLED=false \
    python3 scripts/run_robot_server.py

Press Ctrl+C to stop cleanly.
"""

from __future__ import annotations

import asyncio
import logging
import signal

from robot_server import build_runtime, load_config_from_env


async def _run() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )
    config = load_config_from_env()
    runtime = build_runtime(config)

    logging.info(
        "Starting robot_server: tcp_enabled=%s ble_enabled=%s mqtt_enabled=%s ros_enabled=%s",
        config.tcp.enabled,
        config.ble.enabled,
        config.mqtt.enabled,
        config.ros.enabled,
    )
    await runtime.start()

    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop_event.set)
        except NotImplementedError:  # pragma: no cover - Windows
            signal.signal(sig, lambda *_: stop_event.set())

    try:
        await stop_event.wait()
    finally:
        logging.info("Stopping robot_server...")
        await runtime.stop()
        logging.info("robot_server stopped.")


def main() -> int:
    try:
        asyncio.run(_run())
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
