#!/usr/bin/env bash
# 文件保存即同步（Mac 专用，依赖 fswatch）
#
# 用法：
#   brew install fswatch   # 首次使用需要安装
#   ./scripts/watch_and_sync_to_robot.sh
#
# 原理：监视 robot_server/ 与 protocol/ 的变更，去抖后调用 sync_to_robot.sh

set -euo pipefail

if ! command -v fswatch >/dev/null 2>&1; then
  echo "未检测到 fswatch。请先安装：" >&2
  echo "  brew install fswatch" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SYNC="${REPO_ROOT}/scripts/sync_to_robot.sh"
WATCH_PATHS=(robot_server protocol)

echo "==> 开始监视: ${WATCH_PATHS[*]}"
echo "==> 目标: ${REMOTE:-robot-dog}:${DEST:-/root/robot_factory}"
echo "==> Ctrl+C 退出"

"$SYNC"

fswatch -o \
  --latency 0.5 \
  --exclude '/\.git/' \
  --exclude '/__pycache__/' \
  --exclude '\.pyc$' \
  "${WATCH_PATHS[@]}" \
  | while read -r _; do
      echo "[$(date +%H:%M:%S)] 检测到变更，同步中..."
      if "$SYNC"; then
        echo "[$(date +%H:%M:%S)] 同步完成"
      else
        echo "[$(date +%H:%M:%S)] 同步失败，继续监视" >&2
      fi
    done
