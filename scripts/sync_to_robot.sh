#!/usr/bin/env bash
# Mac -> 机器狗 单向同步脚本
#
# 用法：
#   ./scripts/sync_to_robot.sh                         # 默认同步到 robot-dog:/root/robot_factory
#   REMOTE=robot-dog DEST=/root/robot_factory ./scripts/sync_to_robot.sh
#   ./scripts/sync_to_robot.sh --dry-run               # 只预览，不真正同步
#
# 约束（见 AGENTS.md 第 2/7 条）：
#   - 只同步机器狗需要的 robot_server/、protocol/ 与 scripts/
#   - 不同步 Flutter / Dart / docs / .git 等
#   - 使用 --delete 保持远端与本地一致，避免老文件残留

set -euo pipefail

REMOTE="${REMOTE:-robot-dog}"
DEST="${DEST:-/root/robot_factory}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

RSYNC_OPTS=(
  -avz
  --delete
  --exclude='__pycache__/'
  --exclude='*.pyc'
  --exclude='*.pyo'
  --exclude='.pytest_cache/'
  --exclude='.mypy_cache/'
  --exclude='.ruff_cache/'
  --exclude='*.egg-info/'
  --exclude='.venv/'
  --exclude='venv/'
  --exclude='.git/'
  --exclude='.DS_Store'
  --exclude='build/'
  --exclude='dist/'
)

if [[ "${1:-}" == "--dry-run" ]]; then
  RSYNC_OPTS+=(--dry-run)
  echo "[dry-run] 仅预览，不会真正同步"
fi

SRC_PATHS=(robot_server protocol scripts)

for p in "${SRC_PATHS[@]}"; do
  if [[ ! -d "$p" ]]; then
    echo "跳过：$p 不存在"
    continue
  fi
done

echo "==> 目标: ${REMOTE}:${DEST}"
echo "==> 源:   ${SRC_PATHS[*]}"

ssh "$REMOTE" "mkdir -p '${DEST}'"

rsync "${RSYNC_OPTS[@]}" \
  "${SRC_PATHS[@]}" \
  "${REMOTE}:${DEST}/"

# 额外同步一键启动脚本和环境变量示例到机器狗根目录
# 使用独立一轮 rsync（不带 --delete），避免影响上面目录级同步的清理语义
EXTRA_FILES=(scripts/server_run.sh .env.example)
EXTRA_PRESENT=()
for f in "${EXTRA_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    EXTRA_PRESENT+=("$f")
  fi
done

if [[ ${#EXTRA_PRESENT[@]} -gt 0 ]]; then
  rsync -avz "${EXTRA_PRESENT[@]}" "${REMOTE}:${DEST}/"
  # server_run.sh 放到根目录后要可执行
  ssh "$REMOTE" "chmod +x '${DEST}/server_run.sh' 2>/dev/null || true"
fi

echo "==> 同步完成。"
echo "提示：登入机器狗后执行"
echo "  cd ${DEST}"
echo "  # 首次使用：cp .env.example .env，按需改 ROBOT_ID / BLE / TCP / ROS 等"
echo "  # systemd 部署参考：${DEST}/scripts/robot_server.service"
echo "  # 蓝牙异常恢复：sudo ${DEST}/scripts/recover_bluetooth.sh"
echo "  ./server_run.sh"
