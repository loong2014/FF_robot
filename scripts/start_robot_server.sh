#!/usr/bin/env bash
# robot_server 启动包装脚本
#
# 设计目标：
#   1. 为 systemd / 手动启动提供统一入口；
#   2. source 正确的 ROS1 Noetic 环境；
#   3. 可选激活 venv；
#   4. 加载 .env，但不覆盖 shell 中显式传入的 ROBOT_*；
#   5. 自动把系统 dist-packages 并入 PYTHONPATH，复用 rospy 等系统包；
#   6. BLE 启用时复用系统 bluetooth.service；脚本本身不主动拉起服务，
#      但会提示明显的前置条件错误。

# 不开 -u。ROS setup.bash / venv activate / 用户 .env 可能依赖未定义变量。
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${ROBOT_FACTORY_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
cd "${REPO_ROOT}"

# ---------------------------------------------------------------------------
# 1) ROS1 Noetic
# ---------------------------------------------------------------------------
if [[ -z "${ROS_DISTRO:-}" && -f /opt/ros/noetic/setup.bash ]]; then
    # shellcheck disable=SC1091
    source /opt/ros/noetic/setup.bash
fi

# ---------------------------------------------------------------------------
# 2) venv
# ---------------------------------------------------------------------------
VENV_DIR="${ROBOT_FACTORY_VENV:-}"
if [[ -z "$VENV_DIR" ]]; then
    for candidate in "$REPO_ROOT/.venv" "$REPO_ROOT/venv"; do
        if [[ -f "$candidate/bin/activate" ]]; then
            VENV_DIR="$candidate"
            break
        fi
    done
fi
if [[ -n "$VENV_DIR" && -f "$VENV_DIR/bin/activate" ]]; then
    echo "[start_robot_server] activate venv: $VENV_DIR" >&2
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
fi

# ---------------------------------------------------------------------------
# 3) .env
# ---------------------------------------------------------------------------
ENV_FILE="${ROBOT_FACTORY_ENV_FILE:-}"
if [[ -z "$ENV_FILE" ]]; then
    for candidate in /etc/robot_factory/robot_server.env "${REPO_ROOT}/.env"; do
        if [[ -f "$candidate" ]]; then
            ENV_FILE="$candidate"
            break
        fi
    done
fi

if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
    echo "[start_robot_server] loading env: $ENV_FILE" >&2
    while IFS= read -r _line; do
        case "$_line" in
            ''|\#*) continue ;;
        esac
        _line="${_line#export }"
        _key="${_line%%=*}"
        _val="${_line#*=}"
        if ! [[ "$_key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            continue
        fi
        if [[ -n "${!_key+x}" && -n "${!_key}" ]]; then
            continue
        fi
        if [[ "${_val}" =~ ^\"(.*)\"$ || "${_val}" =~ ^\'(.*)\'$ ]]; then
            _val="${BASH_REMATCH[1]}"
        fi
        export "$_key=$_val"
    done < "$ENV_FILE"
    unset _line _key _val
else
    echo "[start_robot_server] no env file found, using shell env + defaults" >&2
fi

# ---------------------------------------------------------------------------
# 4) PYTHONPATH
# ---------------------------------------------------------------------------
EXTRA_PATH="${REPO_ROOT}/protocol/python:${REPO_ROOT}/robot_server"
for sys_site in /usr/lib/python3/dist-packages /usr/local/lib/python3/dist-packages; do
    if [[ -d "$sys_site" ]]; then
        EXTRA_PATH="${EXTRA_PATH}:${sys_site}"
    fi
done
export PYTHONPATH="${EXTRA_PATH}${PYTHONPATH:+:$PYTHONPATH}"

# ---------------------------------------------------------------------------
# 5) runtime prerequisites
# ---------------------------------------------------------------------------
_ble_enabled="${ROBOT_BLE_ENABLED:-true}"
case "${_ble_enabled,,}" in
    1|true|yes|on) _ble_enabled=true ;;
    *) _ble_enabled=false ;;
esac

if [[ "$_ble_enabled" == true && "$(uname -s)" == "Linux" ]]; then
    if command -v systemctl >/dev/null 2>&1; then
        if ! systemctl is-active --quiet bluetooth.service; then
            echo "[start_robot_server] warning: bluetooth.service is not active; in-process BLE registration may fail" >&2
        fi
        if systemctl is-active --quiet teleop_robot.service; then
            echo "[start_robot_server] warning: teleop_robot.service is still active and may conflict with robot_server BLE" >&2
        fi
    fi
fi
unset _ble_enabled

# ---------------------------------------------------------------------------
# 6) start
# ---------------------------------------------------------------------------
PYTHON_BIN="${ROBOT_FACTORY_PYTHON:-python3}"
echo "[start_robot_server] PYTHONPATH=$PYTHONPATH" >&2
echo "[start_robot_server] starting: $PYTHON_BIN -m robot_server.main $*" >&2
exec "$PYTHON_BIN" -m robot_server.main "$@"
