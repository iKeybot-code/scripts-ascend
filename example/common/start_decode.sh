#!/bin/bash
# Start Decode engines on the current machine (shared-dir safe).
#
# Usage:
#   bash run.sh decode
#   bash run.sh decode 1
#   bash run.sh decode --node-ip 90.90.97.30
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

parse_role_args "$@" || exit $?
validate_pd_topology || exit 1
resolve_node_meta decode "${SEL_NODE_INDEX:-auto}" "${SEL_NODE_IP:-}"
NODE_INDEX="${CUR_NODE_INDEX}"
setup_node_log_dir

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
VISIBLE_LIST="${CUR_VISIBLE_LIST:-}"
HTTP_PORT="${CUR_HTTP_PORT}"
KV_PORT_BASE="${CUR_KV_PORT_BASE}"

echo "[start_decode] shared-script node_index=${NODE_INDEX} ip=${CUR_IP} nic=${CUR_NIC}"
echo "[start_decode] connector=${PD_KV_CONNECTOR:-MooncakeConnectorV1} enable_kv_pool=${ENABLE_KV_POOL:-0}"
echo "[start_decode] dp_rank_start=${DP_RANK_START} dp_size=${D_DP_SIZE} local=${D_DP_SIZE_LOCAL} tp=${D_TP_SIZE}"
echo "[start_decode] dp_address=${D_DP_ADDRESS} http=${HTTP_PORT} kv_base=${KV_PORT_BASE} visible=${VISIBLE_LIST:-auto}"
echo "[start_decode] log_dir=${LOG_DIR}"

export CONFIGS_FILE
export CUR_IP CUR_NIC CUR_ROLE CUR_NODE_INDEX LOG_DIR

python "${COMMON_DIR}/launch_online_dp.py" \
    --role decode \
    --dp-size "${D_DP_SIZE}" \
    --tp-size "${D_TP_SIZE}" \
    --dp-size-local "${D_DP_SIZE_LOCAL}" \
    --dp-rank-start "${DP_RANK_START}" \
    --dp-address "${D_DP_ADDRESS}" \
    --dp-rpc-port "${D_DP_RPC_PORT}" \
    --vllm-start-port "${HTTP_PORT}" \
    --kv-port-base "${KV_PORT_BASE}" \
    --visible-devices-list "${VISIBLE_LIST}" \
    --template "${COMMON_DIR}/run_dp_template.sh"
