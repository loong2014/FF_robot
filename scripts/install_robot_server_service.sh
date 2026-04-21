#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SERVICE_TEMPLATE="${SCRIPT_DIR}/robot_server.service"
DROPIN_SRC="${SCRIPT_DIR}/bluetooth.service.d/robot-factory.conf"
UNIT_DEST="/etc/systemd/system/robot_server.service"
ENV_DEST="/etc/robot_factory/robot_server.env"
ENABLE_NOW=false

usage() {
    cat <<'EOF'
Usage: sudo ./scripts/install_robot_server_service.sh [options]

Options:
  --enable-now       Enable and start robot_server.service immediately
  --env-file PATH    Install/use this env file path (default: /etc/robot_factory/robot_server.env)
  --repo-root PATH   Render the systemd unit to this repo root (default: parent of scripts/)
  --unit-dest PATH   Install the systemd unit at this path (default: /etc/systemd/system/robot_server.service)
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --enable-now)
            ENABLE_NOW=true
            ;;
        --env-file)
            ENV_DEST="$2"
            shift
            ;;
        --repo-root)
            REPO_ROOT="$2"
            shift
            ;;
        --unit-dest)
            UNIT_DEST="$2"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root." >&2
    exit 1
fi

if [[ ! -d "${REPO_ROOT}" ]]; then
    echo "Repo root not found: ${REPO_ROOT}" >&2
    exit 1
fi

if [[ ! -f "${SERVICE_TEMPLATE}" ]]; then
    echo "Missing service template: ${SERVICE_TEMPLATE}" >&2
    exit 1
fi

if [[ ! -f "${DROPIN_SRC}" ]]; then
    echo "Missing bluetooth drop-in: ${DROPIN_SRC}" >&2
    exit 1
fi

echo "[install] repo root: ${REPO_ROOT}"
echo "[install] unit dest: ${UNIT_DEST}"
echo "[install] env dest: ${ENV_DEST}"

install -d "$(dirname "${UNIT_DEST}")"
install -d "$(dirname "${ENV_DEST}")"
install -d /etc/systemd/system/bluetooth.service.d
install -m 0644 "${DROPIN_SRC}" /etc/systemd/system/bluetooth.service.d/robot-factory.conf

if [[ ! -f "${ENV_DEST}" ]]; then
    if [[ -f "${REPO_ROOT}/.env" ]]; then
        install -m 0640 "${REPO_ROOT}/.env" "${ENV_DEST}"
        echo "[install] copied ${REPO_ROOT}/.env"
    elif [[ -f "${REPO_ROOT}/.env.example" ]]; then
        install -m 0640 "${REPO_ROOT}/.env.example" "${ENV_DEST}"
        echo "[install] copied ${REPO_ROOT}/.env.example"
    else
        echo "[install] warning: no .env or .env.example found; service will run with defaults" >&2
    fi
else
    echo "[install] keep existing env file"
fi

escaped_repo_root="$(printf '%s' "${REPO_ROOT}" | sed 's/[\/&]/\\&/g')"
escaped_env_dest="$(printf '%s' "${ENV_DEST}" | sed 's/[\/&]/\\&/g')"
tmp_unit="$(mktemp)"
trap 'rm -f "${tmp_unit}"' EXIT

sed \
    -e "s#/opt/robot_factory#${escaped_repo_root}#g" \
    -e "s#/etc/robot_factory/robot_server.env#${escaped_env_dest}#g" \
    "${SERVICE_TEMPLATE}" > "${tmp_unit}"

install -m 0644 "${tmp_unit}" "${UNIT_DEST}"

echo "[install] stop conflicting BLE services"
systemctl stop teleop_robot.service robot_ble_peripheral.service >/dev/null 2>&1 || true
systemctl disable teleop_robot.service robot_ble_peripheral.service >/dev/null 2>&1 || true

echo "[install] daemon-reload"
systemctl daemon-reload

unit_name="$(basename "${UNIT_DEST}")"
echo "[install] enable ${unit_name}"
systemctl enable "${unit_name}" >/dev/null

if [[ "${ENABLE_NOW}" == true ]]; then
    echo "[install] stop existing robot_server processes"
    while read -r pid; do
        if [[ -n "${pid}" ]]; then
            kill "${pid}" >/dev/null 2>&1 || true
        fi
    done < <(ps -ef | awk '/[p]ython3 -m robot_server.main/ {print $2}')

    echo "[install] restart bluetooth.service"
    systemctl restart bluetooth.service
    echo "[install] wait for org.bluez/hci0"
    for _ in $(seq 1 15); do
        if busctl tree org.bluez 2>/dev/null | grep -q '/org/bluez/hci0'; then
            break
        fi
        sleep 1
    done

    echo "[install] restart ${unit_name}"
    systemctl restart "${unit_name}"
    systemctl --no-pager -l status "${unit_name}" || true
fi

echo "[install] done"
