#!/bin/bash
# 在 Mac 上一键远程执行机器狗 do_action
#
# 用法：
#   ./run_action_on_dog.sh <action_id> [priority] [hold_time]
#
# 示例：
#   ./run_action_on_dog.sh 20609
#   ./run_action_on_dog.sh 20609 50 20
#
# 环境变量：
#   DOG_HOST   默认 root@10.10.10.10
#   DOG_PASS   默认 weilan.com
#
# 说明：
# - 脚本会先同步本地 dog_cmd.sh 到狗的 /tmp/
# - 默认会监听一次 /agent_skill/do_action/execute/result 并打印结果

set -euo pipefail

ACTION_ID="${1:-}"
PRIORITY="${2:-50}"
HOLD_TIME="${3:-20}"

DOG_HOST="${DOG_HOST:-root@10.10.10.10}"
DOG_PASS="${DOG_PASS:-weilan.com}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_DOG_CMD="$SCRIPT_DIR/dog_cmd.sh"

usage() {
  echo "用法: $0 <action_id> [priority] [hold_time]"
  echo "示例: $0 20609 50 20"
  exit 1
}

if [ -z "$ACTION_ID" ]; then
  usage
fi

case "$ACTION_ID" in
  ''|*[!0-9]*)
    echo "❌ action_id 必须是数字: $ACTION_ID"
    exit 1
    ;;
esac

if ! command -v sshpass >/dev/null 2>&1; then
  echo "❌ 缺少 sshpass，请先安装（macOS 可用: brew install hudochenkov/sshpass/sshpass）"
  exit 1
fi

if [ ! -f "$LOCAL_DOG_CMD" ]; then
  echo "❌ 未找到 $LOCAL_DOG_CMD"
  exit 1
fi

echo "📤 同步 dog_cmd.sh 到 ${DOG_HOST}:/tmp/dog_cmd.sh ..."
sshpass -p "$DOG_PASS" scp -o StrictHostKeyChecking=no "$LOCAL_DOG_CMD" "$DOG_HOST:/tmp/dog_cmd.sh"

echo "🚀 远程执行 action_id=$ACTION_ID (priority=$PRIORITY, hold_time=$HOLD_TIME) ..."
sshpass -p "$DOG_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=20 "$DOG_HOST" bash -s <<REMOTE
set +e
chmod +x /tmp/dog_cmd.sh
source /opt/ros/noetic/setup.bash
source /mnt/USERFS/app/nimgo/opt/nimgo/setup.bash --extend
source /mnt/USERFS/app/agent/opt/agent/setup.bash --extend

TMP=/tmp/action_${ACTION_ID}_from_mac_result.yaml
rm -f "\$TMP"
timeout 45 rostopic echo -n 1 /agent_skill/do_action/execute/result > "\$TMP" 2>&1 &
LISTEN_PID=\$!
sleep 1

bash /tmp/dog_cmd.sh action "$ACTION_ID" "$PRIORITY" "$HOLD_TIME"
wait \$LISTEN_PID 2>/dev/null

echo "----- execute/result -----"
if [ -s "\$TMP" ]; then
  cat "\$TMP"
else
  echo "NO_RESULT_CAPTURED"
fi
REMOTE

echo "✅ 完成"
