#!/usr/bin/env python3
from __future__ import annotations

import os
import socket
import sys


def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name)
    if raw is None or not raw.strip():
        return default
    return float(raw)


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None or not raw.strip():
        return default
    return int(raw)


def main() -> int:
    payload = sys.stdin.buffer.read()
    if not payload:
        print("empty payload", file=sys.stderr)
        return 1

    host = os.getenv("ROBOT_BLE_BRIDGE_HOST", "127.0.0.1").strip() or "127.0.0.1"
    port = _env_int("ROBOT_BLE_BRIDGE_PORT", 9000)
    connect_timeout = _env_float("ROBOT_BLE_BRIDGE_CONNECT_TIMEOUT_SEC", 3.0)
    read_timeout = _env_float("ROBOT_BLE_BRIDGE_READ_TIMEOUT_SEC", 0.5)

    try:
        with socket.create_connection((host, port), timeout=connect_timeout) as sock:
            sock.sendall(payload)
            try:
                sock.shutdown(socket.SHUT_WR)
            except OSError:
                pass

            if read_timeout > 0:
                sock.settimeout(read_timeout)
                try:
                    ack = sock.recv(4096)
                except socket.timeout:
                    ack = b""
            else:
                ack = b""
    except OSError as exc:
        print(f"tcp bridge failed: {exc}", file=sys.stderr)
        return 1

    if ack:
        print(f"ack_hex={ack.hex()}")
    else:
        print("forwarded")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
