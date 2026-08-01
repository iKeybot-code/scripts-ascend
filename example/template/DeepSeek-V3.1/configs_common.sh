#!/bin/bash
# =============================================================================
# DeepSeek-V3.1 shared topology / model / feature switches (common_v2)
#
# Shared-directory multi-machine:
#   Same scripts on every node. Differentiate via IP-aligned lists below, or:
#     bash run.sh prefill|decode [--node-index N | --node-ip IP]
#
# Default layout: 2P1D on 4x Atlas 800 A3 (official DeepSeek-V3.1 PD guide)
#   Prefill x2 : each node independent DP=2 TP=8 (16 NPUs/node)
#   Decode  x2 : global DP=32 TP=1, local_DP=16 (one DP group across 2 nodes)
# =============================================================================

_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export SHARED_COMMON_DIR="${SHARED_COMMON_DIR:-/mnt/a800_share/l00848175/scripts-ascend/example/common_v2}"
if [[ -z "${COMMON_DIR:-}" || ! -f "${COMMON_DIR}/config_helpers.sh" ]]; then
    if [[ -f "${SHARED_COMMON_DIR}/config_helpers.sh" ]]; then
        export COMMON_DIR="$(cd "${SHARED_COMMON_DIR}" && pwd)"
    elif [[ -f "${_THIS_DIR}/../../common_v2/config_helpers.sh" ]]; then
        export COMMON_DIR="$(cd "${_THIS_DIR}/../../common_v2" && pwd)"
    else
        echo "[configs_common] cannot locate common_v2/. Set COMMON_DIR or SHARED_COMMON_DIR." >&2
        return 1 2>/dev/null || exit 1
    fi
else
    export COMMON_DIR="$(cd "${COMMON_DIR}" && pwd)"
fi
# shellcheck disable=SC1091
source "${COMMON_DIR}/config_helpers.sh"

# =============================================================================
# ----- Model -----
export MODEL_PATH="${MODEL_PATH:-/mnt/a800_weight/DeepSeek-V3.1-w8a8-mtp-QuaRot}"
export MODEL_NAME="${MODEL_NAME:-deepseek_v3}"
export IS_QUANTIZATION=1

# ----- Feature switches (comment out to disable; keep only what you enable) -----
export ENABLE_KV_POOL=0
export ENABLE_EXPERT_PARALLEL=1
export PD_KV_CONNECTOR="${PD_KV_CONNECTOR:-MooncakeConnectorV1}"
# export ENABLE_PREFIX_CACHE=1
# export KV_POOL_BACKEND=mooncake
# export KV_LOAD_FAILURE_POLICY=recompute
# export KV_POOL_LOOKUP_RPC_PORT=0
# export VLLM_USE_V2_MODEL_RUNNER=1
# export ENABLE_FUSED_MC2=1
# export VLLM_SERVER_DEV_MODE=1
# export ENABLE_NPUGRAPH_EX=1
# export WEIGHT_NZ_MODE=1
# export ENABLE_REDUCE_SAMPLE=1
# export ENABLE_CPU_BINDING=1

# =============================================================================
# Machine inventory (INDEX-ALIGNED). Edit for your cluster.
# Index i always means the same physical machine across related arrays.
# =============================================================================

# Prefill machines: P0, P1
export PREFILL_IPS=("90.90.97.37" "90.90.97.38")
export PREFILL_NICS=(enp194s0f0 enp194s0f0)
# A3 16-NPU: two local DP ranks, each TP=8
export P_NODE_VISIBLE_DEVICES=(
    "0,1,2,3,4,5,6,7;8,9,10,11,12,13,14,15"
    "0,1,2,3,4,5,6,7;8,9,10,11,12,13,14,15"
)
export P_NODE_HTTP_PORT=()
export P_NODE_KV_PORT_BASE=(30000 30100)

# Decode machines: D0, D1 (one global DP group; D_DP_ADDRESS=D0)
export DECODE_IPS=("90.90.97.28" "90.90.97.29")
export DECODE_NICS=(enp194s0f0 enp194s0f0)
# Semicolon separates local DP ranks (TP=1 => one device id per rank)
export D_NODE_VISIBLE_DEVICES=(
    "0;1;2;3;4;5;6;7;8;9;10;11;12;13;14;15"
    "0;1;2;3;4;5;6;7;8;9;10;11;12;13;14;15"
)
export D_NODE_HTTP_PORT=()
export D_NODE_KV_PORT_BASE=(30200 30200)

export LOCAL_IPS=("${PREFILL_IPS[@]}" "${DECODE_IPS[@]}")
export NIC_NAMES=("${PREFILL_NICS[@]}" "${DECODE_NICS[@]}")

# ----- Parallelism (2P1D / official DeepSeek-V3.1 PD) -----
# Prefill: each node is an independent DP group
export P_INDEPENDENT_NODE_DP=1
export P_DP_SIZE=2
export P_TP_SIZE=8
export P_DP_SIZE_LOCAL=2
# Decode: one DP group across decode nodes
export D_DP_SIZE=32
export D_TP_SIZE=1
export D_DP_SIZE_LOCAL=16

# ----- Pipeline Parallel (optional; default 1 = disabled) -----
export P_PP_SIZE=1
# export P_PP_LAYER_PARTITION="31,30"
export D_PP_SIZE=1
# export D_PP_LAYER_PARTITION="31,30"

# Template devices (used only when P/D_NODE_VISIBLE_DEVICES empty)
export P_VISIBLE_DEVICES_LIST=("0,1,2,3,4,5,6,7" "8,9,10,11,12,13,14,15")
export D_VISIBLE_DEVICES_LIST=(
    "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "10" "11" "12" "13" "14" "15"
)

# ----- Ports / DP masters -----
export PROXY_HOST="${PROXY_HOST:-${PREFILL_IPS[0]}}"
export PROXY_PORT="${PROXY_PORT:-1999}"
export P_VLLM_START_PORT=7100
export D_VLLM_START_PORT=7100
export P_DP_ADDRESS="${P_DP_ADDRESS:-${PREFILL_IPS[0]}}"
export D_DP_ADDRESS="${D_DP_ADDRESS:-${DECODE_IPS[0]}}"
export P_DP_RPC_PORT=12321
export D_DP_RPC_PORT=12321
export P_KV_PORT_BASE=30000
export D_KV_PORT_BASE=30200

# ----- Mooncake master (only when ENABLE_KV_POOL=1) -----
export MOONCAKE_MASTER_IP="${MOONCAKE_MASTER_IP:-${PREFILL_IPS[0]}}"
export MOONCAKE_MASTER_PORT="${MOONCAKE_MASTER_PORT:-50088}"
export MOONCAKE_GLOBAL_SEGMENT_SIZE="${MOONCAKE_GLOBAL_SEGMENT_SIZE:-1GB}"
export MOONCAKE_EVICT_HIGH_WATERMARK="${MOONCAKE_EVICT_HIGH_WATERMARK:-0.95}"
export MOONCAKE_EVICT_RATIO="${MOONCAKE_EVICT_RATIO:-0.05}"
export MOONCAKE_KV_LEASE_TTL="${MOONCAKE_KV_LEASE_TTL:-11000}"
export MOONCAKE_CONFIG_PATH="${MOONCAKE_CONFIG_PATH:-${_THIS_DIR}/mooncake.json}"

# Per-machine log root on shared FS (final: <base>/<role><idx>_<ip>_YYMMDD/)
export LOG_DIR_BASE="${LOG_DIR_BASE:-${_THIS_DIR}/logs}"
export LOG_DIR="${LOG_DIR:-${LOG_DIR_BASE}}"

# ----- AISBench smoke -----
export AISBENCH_CASE_NAME="${AISBENCH_CASE_NAME:-pd_gsm8k_acc_top10}"
export AISBENCH_WORK_DIR="${AISBENCH_WORK_DIR:-${LOG_DIR_BASE}/aisbench_gsm8k}"
export AISBENCH_MAX_OUT_LEN="${AISBENCH_MAX_OUT_LEN:-512}"
export AISBENCH_BATCH_SIZE="${AISBENCH_BATCH_SIZE:-1}"
export GSM8K_TEST_RANGE="${GSM8K_TEST_RANGE:-[0:10]}"

# =============================================================================
# Shared KV-transfer JSON templates (placeholders filled by run_dp_template)
# Placeholders: __KV_ROLE__  __KV_PORT__  __ENGINE_ID__
# Selection: ENABLE_KV_POOL=0 -> PD ; =1 -> POOL
# =============================================================================
export KV_TRANSFER_CONFIG_PD=$(cat <<EOF
{"kv_connector": "${PD_KV_CONNECTOR}", "kv_role": "__KV_ROLE__", "kv_port": "__KV_PORT__", "engine_id": "__ENGINE_ID__", "kv_connector_extra_config": {"prefill": {"dp_size": ${P_DP_SIZE}, "tp_size": ${P_TP_SIZE}}, "decode": {"dp_size": ${D_DP_SIZE}, "tp_size": ${D_TP_SIZE}}}}
EOF
)

export KV_TRANSFER_CONFIG_POOL=$(cat <<EOF
{"kv_connector": "MultiConnector", "kv_role": "__KV_ROLE__", "kv_load_failure_policy": "${KV_LOAD_FAILURE_POLICY:-recompute}", "kv_connector_extra_config": {"connectors": [{"kv_connector": "${PD_KV_CONNECTOR}", "kv_role": "__KV_ROLE__", "kv_port": "__KV_PORT__", "kv_connector_extra_config": {"prefill": {"dp_size": ${P_DP_SIZE}, "tp_size": ${P_TP_SIZE}}, "decode": {"dp_size": ${D_DP_SIZE}, "tp_size": ${D_TP_SIZE}}}}, {"kv_connector": "AscendStoreConnector", "kv_role": "__KV_ROLE__", "kv_connector_extra_config": {"lookup_rpc_port": "${KV_POOL_LOOKUP_RPC_PORT:-0}", "backend": "${KV_POOL_BACKEND:-mooncake}"}}]}}
EOF
)
