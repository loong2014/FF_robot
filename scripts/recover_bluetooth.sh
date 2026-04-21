#!/bin/bash
set -euo pipefail

RESTART_ROBOT_SERVER=auto
case "${1:-}" in
    --restart-server)
        RESTART_ROBOT_SERVER=always
        ;;
    --no-server-restart)
        RESTART_ROBOT_SERVER=never
        ;;
    "")
        ;;
    *)
        echo "Usage: $0 [--restart-server|--no-server-restart]" >&2
        exit 2
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DROPIN_SRC="${SCRIPT_DIR}/bluetooth.service.d/robot-factory.conf"
DROPIN_DEST="/etc/systemd/system/bluetooth.service.d/robot-factory.conf"

echo "[recover] install bluetooth.service drop-in"
install -d /etc/systemd/system/bluetooth.service.d
/bin/cp "${DROPIN_SRC}" "${DROPIN_DEST}"

echo "[recover] normalize /etc/bluetooth/main.conf"
python3 <<'PY'
from pathlib import Path

p = Path("/etc/bluetooth/main.conf")
lines = p.read_text().splitlines()


def find_section(name: str):
    marker = f"[{name}]"
    for index, line in enumerate(lines):
        if line.strip() == marker:
            return index
    return None


normalized = []
seen_rsd = False
for line in lines:
    if line.strip().startswith("ReverseServiceDiscovery"):
        if not seen_rsd:
            normalized.append("ReverseServiceDiscovery = false")
            seen_rsd = True
        continue
    normalized.append(line)
lines = normalized

general_index = find_section("General")
if not seen_rsd:
    if general_index is None:
        lines = ["[General]", "ReverseServiceDiscovery = false", ""] + lines
    else:
        lines.insert(general_index + 1, "ReverseServiceDiscovery = false")

gatt_index = find_section("GATT")
if gatt_index is None:
    if lines and lines[-1] != "":
        lines.append("")
    lines.extend(["[GATT]", "Cache = no"])
else:
    section_end = len(lines)
    for index in range(gatt_index + 1, len(lines)):
        if lines[index].startswith("["):
            section_end = index
            break

    cache_line = None
    index = gatt_index + 1
    while index < section_end:
        if lines[index].strip().startswith("Cache"):
            if cache_line is None:
                lines[index] = "Cache = no"
                cache_line = index
                index += 1
                continue
            lines.pop(index)
            section_end -= 1
            continue
        index += 1

    if cache_line is None:
        lines.insert(gatt_index + 1, "Cache = no")

p.write_text("\n".join(lines).rstrip() + "\n")
PY

echo "[recover] stop robot_server (in-process BLE owner)"
systemctl stop robot_server.service || true

echo "[recover] stop legacy standalone BLE app if present"
systemctl stop robot_ble_peripheral.service || true

echo "[recover] stop vendor teleop BLE service"
systemctl stop teleop_robot.service || true

echo "[recover] stop bluetooth.service"
timeout 20 systemctl stop bluetooth.service || true

echo "[recover] run vendor bt teardown"
/bin/bash /etc/xinit/xbtex || true

echo "[recover] run vendor bt bring-up"
/bin/bash /etc/xinit/xbt_46212

echo "[recover] daemon-reload"
systemctl daemon-reload

echo "[recover] start bluetooth.service"
systemctl start bluetooth.service

echo "[recover] wait for org.bluez/hci0"
for _ in $(seq 1 15); do
    if busctl tree org.bluez 2>/dev/null | grep -q '/org/bluez/hci0'; then
        break
    fi
    sleep 1
done

restart_robot_server=false
case "$RESTART_ROBOT_SERVER" in
    always)
        restart_robot_server=true
        ;;
    never)
        restart_robot_server=false
        ;;
    auto)
        if systemctl is-enabled --quiet robot_server.service; then
            restart_robot_server=true
        fi
        ;;
esac

if [[ "$restart_robot_server" == true ]]; then
    echo "[recover] restart robot_server"
    systemctl restart robot_server.service || true
    sleep 2
else
    echo "[recover] skip robot_server restart (unit disabled or --no-server-restart)"
fi

echo "[recover] bluetoothctl list"
bluetoothctl list || true

echo "[recover] bluetoothctl show"
bluetoothctl show || true

echo "[recover] busctl tree"
busctl tree org.bluez || true

echo "[recover] bluetooth.service status"
systemctl status bluetooth.service --no-pager -l || true

echo "[recover] robot_server status"
systemctl status robot_server.service --no-pager -l || true
