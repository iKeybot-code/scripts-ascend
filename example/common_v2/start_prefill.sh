#!/bin/bash
# Start Prefill engines on the current machine (shared-dir safe).
#
# Usage:
#   bash run.sh prefill
#   bash run.sh prefill 1
#   bash run.sh prefill --node-ip 90.90.97.28
#
# Requires: CONFIGS_FILE
#
# xPxD note:
#   Device list / IP / nic / DP-TP-PP ranks are taken from IP-aligned arrays in
#   configs_*.sh. Same shared-dir scripts; minimal per-node selection via
#   node_index / --node-ip.

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
resolve_node_meta prefill "${SEL_NODE_INDEX:-auto}" "${SEL_NODE_IP:-}"
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

# Independent Prefill DP group per node (official DeepSeek 2P1D style):
#   each Prefill node: rank_start=0, dp_address=local IP, dp_size=P_DP_SIZE
# Shared global DP group (default MiniMax-style):
#   rank_start = node_index * local_dp, dp_address = P_DP_ADDRESS
if [[ "${P_INDEPENDENT_NODE_DP:-0}" == "1" ]]; then
    DP_RANK_START=0
    DP_ADDRESS="${CUR_IP}"
else
    DP_RANK_START=$((NODE_INDEX * P_DP_SIZE_LOCAL))
    DP_ADDRESS="${P_DP_ADDRESS}"
fi

VISIBLE_LIST="${CUR_VISIBLE_LIST:-}"
HTTP_PORT="${CUR_HTTP_PORT}"
KV_PORT_BASE="${CUR_KV_PORT_BASE}"

echo "[start_prefill] shared-script node_index=${NODE_INDEX} ip=${CUR_IP} nic=${CUR_NIC}"
echo "[start_prefill] connector=${PD_KV_CONNECTOR:-MooncakeConnectorV1} enable_kv_pool=${ENABLE_KV_POOL:-0}"
echo "[start_prefill] independent_node_dp=${P_INDEPENDENT_NODE_DP:-0}"
echo "[start_prefill] dp_rank_start=${DP_RANK_START} dp_size=${P_DP_SIZE} local=${P_DP_SIZE_LOCAL} tp=${P_TP_SIZE} pp=${P_PP_SIZE:-1}"
echo "[start_prefill] dp_address=${DP_ADDRESS} http=${HTTP_PORT} kv_base=${KV_PORT_BASE} visible=${VISIBLE_LIST:-auto}"
echo "[start_prefill] log_dir=${LOG_DIR}"

export CONFIGS_FILE
export CUR_IP CUR_NIC CUR_ROLE CUR_NODE_INDEX LOG_DIR

python "${COMMON_DIR}/launch_online_dp.py" \
    --role prefill \
    --dp-size "${P_DP_SIZE}" \
    --tp-size "${P_TP_SIZE}" \
    --pp-size "${P_PP_SIZE:-1}" \
    --dp-size-local "${P_DP_SIZE_LOCAL}" \
    --dp-rank-start "${DP_RANK_START}" \
    --dp-address "${DP_ADDRESS}" \
    --dp-rpc-port "${P_DP_RPC_PORT}" \
    --vllm-start-port "${HTTP_PORT}" \
    --kv-port-base "${KV_PORT_BASE}" \
    --visible-devices-list "${VISIBLE_LIST}" \
    --template "${COMMON_DIR}/run_dp_template.sh"
