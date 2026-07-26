#!/bin/bash
# Start Decode engines on the current node.
#
# Usage:
#   CONFIGS_FILE=.../configs.sh bash start_decode.sh <node_index>
#
# Requires: CONFIGS_FILE

set -euo pipefail

COMMON_DIR_BOOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${COMMON_DIR_BOOT}/load_configs.sh"
# shellcheck disable=SC1091
source "${COMMON_DIR}/env_common.sh"
# shellcheck disable=SC1091
source "${COMMON_DIR}/kv_transfer_config.sh"

NODE_INDEX="${1:-0}"
resolve_node_meta decode "${NODE_INDEX}"

if is_kv_pool_enabled; then
    bash "${COMMON_DIR}/gen_mooncake_json.sh" \
        "${MOONCAKE_MASTER_IP}" \
        "${MOONCAKE_MASTER_PORT}" \
        "${MOONCAKE_CONFIG_PATH}" \
        "${MOONCAKE_GLOBAL_SEGMENT_SIZE}"
    export MOONCAKE_CONFIG_PATH
fi

set_network_env "${CUR_IP}" "${CUR_NIC}"
set_runtime_env

DP_RANK_START=$((NODE_INDEX * D_DP_SIZE_LOCAL))
# Properly join array with semicolons
_OLD_IFS="$IFS"
IFS=";"
VISIBLE_LIST="${D_VISIBLE_DEVICES_LIST[*]}"
IFS="$_OLD_IFS"

echo "[start_decode] node_index=${NODE_INDEX} ip=${CUR_IP} nic=${CUR_NIC}"
echo "[start_decode] connector=${PD_KV_CONNECTOR:-MooncakeConnectorV1} enable_kv_pool=${ENABLE_KV_POOL:-0}"
echo "[start_decode] dp_rank_start=${DP_RANK_START} dp_size=${D_DP_SIZE} local=${D_DP_SIZE_LOCAL}"

export CONFIGS_FILE
export CUR_IP CUR_NIC CUR_ROLE CUR_NODE_INDEX

python "${COMMON_DIR}/launch_online_dp.py" \
    --role decode \
    --dp-size "${D_DP_SIZE}" \
    --tp-size "${D_TP_SIZE}" \
    --dp-size-local "${D_DP_SIZE_LOCAL}" \
    --dp-rank-start "${DP_RANK_START}" \
    --dp-address "${D_DP_ADDRESS}" \
    --dp-rpc-port "${D_DP_RPC_PORT}" \
    --vllm-start-port "${D_VLLM_START_PORT}" \
    --kv-port-base "${D_KV_PORT_BASE}" \
    --visible-devices-list "${VISIBLE_LIST}" \
    --template "${COMMON_DIR}/run_dp_template.sh"
