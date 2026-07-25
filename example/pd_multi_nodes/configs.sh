#!/bin/bash
# =============================================================================
# PD multi-node sample (KV pool enabled by default).
# Edit THIS FILE for IPs / NICs / ports / model / connector / pool.
# =============================================================================

_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate common/ (priority):
#   1) COMMON_DIR
#   2) SHARED_COMMON_DIR (default shared mount)
#   3) <scenario>/../common
#   4) <scenario>/common
export SHARED_COMMON_DIR="${SHARED_COMMON_DIR:-/mnt/a800_share/l00848175/scripts-ascend/example/common}"
if [[ -z "${COMMON_DIR:-}" || ! -f "${COMMON_DIR}/config_helpers.sh" ]]; then
    if [[ -f "${SHARED_COMMON_DIR}/config_helpers.sh" ]]; then
        export COMMON_DIR="$(cd "${SHARED_COMMON_DIR}" && pwd)"
    elif [[ -f "${_THIS_DIR}/../common/config_helpers.sh" ]]; then
        export COMMON_DIR="$(cd "${_THIS_DIR}/../common" && pwd)"
    elif [[ -f "${_THIS_DIR}/common/config_helpers.sh" ]]; then
        export COMMON_DIR="$(cd "${_THIS_DIR}/common" && pwd)"
    else
        echo "[configs] cannot locate common/. Set COMMON_DIR or SHARED_COMMON_DIR." >&2
        return 1 2>/dev/null || exit 1
    fi
else
    export COMMON_DIR="$(cd "${COMMON_DIR}" && pwd)"
fi
# shellcheck disable=SC1091
source "${COMMON_DIR}/config_helpers.sh"

# ----- Feature switches -----
export ENABLE_KV_POOL=1
export PD_KV_CONNECTOR="${PD_KV_CONNECTOR:-MooncakeConnectorV1}"
export KV_POOL_BACKEND="${KV_POOL_BACKEND:-mooncake}"
export KV_LOAD_FAILURE_POLICY="${KV_LOAD_FAILURE_POLICY:-recompute}"
export KV_POOL_LOOKUP_RPC_PORT="${KV_POOL_LOOKUP_RPC_PORT:-0}"

# ----- Model -----
export MODEL_PATH="${MODEL_PATH:-/home/weight/Qwen3-8B}"
export MODEL_NAME="${MODEL_NAME:-qwen3}"

# ----- Cluster topology (index-aligned) -----
export PREFILL_IPS=(90.90.97.27 90.90.97.28)
export PREFILL_NICS=(enp194s0f0 enp194s0f0)
export DECODE_IPS=(90.90.97.29 90.90.97.30)
export DECODE_NICS=(enp194s0f0 enp194s0f0)
export LOCAL_IPS=("${PREFILL_IPS[@]}" "${DECODE_IPS[@]}")
export NIC_NAMES=("${PREFILL_NICS[@]}" "${DECODE_NICS[@]}")

# ----- Parallelism -----
export P_DP_SIZE=2
export P_TP_SIZE=1
export P_DP_SIZE_LOCAL=1
export D_DP_SIZE=2
export D_TP_SIZE=1
export D_DP_SIZE_LOCAL=1
export P_VISIBLE_DEVICES_LIST=("14")
export D_VISIBLE_DEVICES_LIST=("15")

# ----- Ports -----
export PROXY_HOST="${PROXY_HOST:-${PREFILL_IPS[0]}}"
export PROXY_PORT="${PROXY_PORT:-8080}"
export P_VLLM_START_PORT=13900
export D_VLLM_START_PORT=13901
export P_DP_ADDRESS="${P_DP_ADDRESS:-${PREFILL_IPS[0]}}"
export D_DP_ADDRESS="${D_DP_ADDRESS:-${DECODE_IPS[0]}}"
export P_DP_RPC_PORT=12321
export D_DP_RPC_PORT=12322
export P_KV_PORT_BASE=36000
export D_KV_PORT_BASE=37000

# ----- Mooncake master -----
export MOONCAKE_MASTER_IP="${MOONCAKE_MASTER_IP:-${PREFILL_IPS[0]}}"
export MOONCAKE_MASTER_PORT="${MOONCAKE_MASTER_PORT:-50088}"
export MOONCAKE_GLOBAL_SEGMENT_SIZE="${MOONCAKE_GLOBAL_SEGMENT_SIZE:-1GB}"
export MOONCAKE_EVICT_HIGH_WATERMARK="${MOONCAKE_EVICT_HIGH_WATERMARK:-0.95}"
export MOONCAKE_EVICT_RATIO="${MOONCAKE_EVICT_RATIO:-0.05}"
export MOONCAKE_KV_LEASE_TTL="${MOONCAKE_KV_LEASE_TTL:-11000}"
export MOONCAKE_CONFIG_PATH="${MOONCAKE_CONFIG_PATH:-${_THIS_DIR}/mooncake.json}"

# ----- Serve knobs -----
export P_MAX_NUM_SEQS=4
export P_MAX_MODEL_LEN=40000
export P_MAX_NUM_BATCHED_TOKENS=40000
export P_GPU_MEMORY_UTILIZATION=0.9
export P_ENFORCE_EAGER=1
export D_MAX_NUM_SEQS=16
export D_MAX_MODEL_LEN=32768
export D_MAX_NUM_BATCHED_TOKENS=2048
export D_GPU_MEMORY_UTILIZATION=0.9
export D_ASYNC_SCHEDULING=1
export LOG_DIR="${LOG_DIR:-${_THIS_DIR}/logs}"
