from __future__ import annotations

import asyncio
import logging
import os
import signal

from .app import build_runtime
from .config import load_config_from_env


def _configure_logging() -> None:
    level_name = os.getenv("ROBOT_LOG_LEVEL", "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)-5s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )


async def _run() -> None:
    config = load_config_from_env()
    runtime = build_runtime(config)

    stop_event = asyncio.Event()

    def _request_stop() -> None:
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _request_stop)
        except NotImplementedError:
            pass

    await runtime.start()
    try:
        await stop_event.wait()
    finally:
        await runtime.stop()


def main() -> None:
    _configure_logging()
    asyncio.run(_run())


if __name__ == "__main__":
    main()
