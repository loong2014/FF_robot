#!/usr/bin/env bash
# Compatibility wrapper.
#
# 支持两种运行方式：
#   1. 仓库内：scripts/server_run.sh
#   2. sync_to_robot.sh 复制到仓库根后的 ./server_run.sh
#
# 真正的实现统一收口到 scripts/start_robot_server.sh，避免 systemd 路径与
# 手动启动路径分叉。

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/scripts/start_robot_server.sh" ]]; then
    REPO_ROOT="${ROBOT_FACTORY_ROOT:-$SCRIPT_DIR}"
else
    REPO_ROOT="${ROBOT_FACTORY_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
fi

exec "${REPO_ROOT}/scripts/start_robot_server.sh" "$@"
