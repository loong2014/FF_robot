#!/usr/bin/env bash
set -euo pipefail

HOST="${HOST:-root@10.10.10.10}"
REMOTE_DIR="${REMOTE_DIR:-/mnt/USERFS/app/agent/opt/agent/lib/do_action/config/}"
# NOTE: dog behavior configs live under `.../do_dog_behavior/config/`
REMOTE_BEHAVIOR_DIR="${REMOTE_BEHAVIOR_DIR:-/mnt/USERFS/app/agent/opt/agent/lib/do_dog_behavior/config/}"
PASSWORD="${PASSWORD:-weilan.com}"
FACTORY_MODE="${FACTORY_MODE:-1}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="${LOCAL_DIR:-${SCRIPT_DIR}/do_action}"
LOCAL_BEHAVIOR_DIR="${LOCAL_BEHAVIOR_DIR:-${SCRIPT_DIR}/do_dog_behavior}"

JSON_FILE="${LOCAL_DIR}/ext_actions.json"
YAML_FILE="${LOCAL_DIR}/ext_actions.yaml"
BEHAVIOR_JSON_FILE="${LOCAL_BEHAVIOR_DIR}/dog_behaviors.json"
BEHAVIOR_YAML_FILE="${LOCAL_BEHAVIOR_DIR}/dog_behaviors.yaml"

SSH_OPTS=()
SCP_OPTS=()
if [[ "${FACTORY_MODE}" == "1" ]]; then
  SSH_OPTS+=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
  )
  SCP_OPTS+=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
  )
fi

run_ssh() {
  if command -v sshpass >/dev/null 2>&1; then
    sshpass -p "${PASSWORD}" ssh "${SSH_OPTS[@]}" "${HOST}" "$@"
  else
    ssh "${SSH_OPTS[@]}" "${HOST}" "$@"
  fi
}

run_scp() {
  if command -v sshpass >/dev/null 2>&1; then
    sshpass -p "${PASSWORD}" scp "${SCP_OPTS[@]}" "$@"
  else
    scp "${SCP_OPTS[@]}" "$@"
  fi
}

if [[ ! -f "${JSON_FILE}" ]]; then
  echo "ERROR: missing ${JSON_FILE}" >&2
  exit 1
fi
if [[ ! -f "${YAML_FILE}" ]]; then
  echo "ERROR: missing ${YAML_FILE}" >&2
  exit 1
fi
if [[ ! -f "${BEHAVIOR_JSON_FILE}" ]]; then
  echo "ERROR: missing ${BEHAVIOR_JSON_FILE}" >&2
  exit 1
fi
if [[ ! -f "${BEHAVIOR_YAML_FILE}" ]]; then
  echo "ERROR: missing ${BEHAVIOR_YAML_FILE}" >&2
  exit 1
fi

echo "Local:"
echo "  json: ${JSON_FILE}"
echo "  yaml: ${YAML_FILE}"
echo "  behavior_json: ${BEHAVIOR_JSON_FILE}"
echo "  behavior_yaml: ${BEHAVIOR_YAML_FILE}"
echo "Remote:"
echo "  host: ${HOST}"
echo "  do_action_dir     : ${REMOTE_DIR}"
echo "  do_dog_behavior_dir: ${REMOTE_BEHAVIOR_DIR}"
echo "Mode:"
echo "  factory_mode: ${FACTORY_MODE} (1=disable hostkey prompts)"
echo "  sshpass     : $(command -v sshpass >/dev/null 2>&1 && echo yes || echo no)"

echo "Checking remote directory exists."
run_ssh "test -d \"${REMOTE_DIR}\" && test -w \"${REMOTE_DIR}\""
run_ssh "test -d \"${REMOTE_BEHAVIOR_DIR}\" && test -w \"${REMOTE_BEHAVIOR_DIR}\""

echo "Uploading ext_actions.json / ext_actions.yaml ..."
run_scp "${JSON_FILE}" "${HOST}:${REMOTE_DIR}"
run_scp "${YAML_FILE}" "${HOST}:${REMOTE_DIR}"
echo "Uploading dog_behaviors.json / dog_behaviors.yaml ..."
run_scp "${BEHAVIOR_JSON_FILE}" "${HOST}:${REMOTE_BEHAVIOR_DIR}"
run_scp "${BEHAVIOR_YAML_FILE}" "${HOST}:${REMOTE_BEHAVIOR_DIR}"

echo "Verifying remote files."
run_ssh "ls -la \"${REMOTE_DIR}/ext_actions.json\" \"${REMOTE_DIR}/ext_actions.yaml\""
run_ssh "ls -la \"${REMOTE_BEHAVIOR_DIR}/dog_behaviors.json\" \"${REMOTE_BEHAVIOR_DIR}/dog_behaviors.yaml\""

echo "Done."

