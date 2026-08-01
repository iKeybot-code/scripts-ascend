#!/bin/bash
# =============================================================================
# PD multi-node sample: 4-machine 2P1D (shared-directory same script)
#
# Same configs.sh + run.sh is executed on every machine from the shared mount.
# Machine differences MUST come from:
#   A) IP-aligned parameter lists below (index i <-> machine i)
#   B) CLI/env selectors:
#        bash run.sh prefill|decode                 # auto by local IP
#        bash run.sh prefill 1                      # explicit index
#        bash run.sh prefill --node-ip 90.90.97.28  # explicit IP
#        NODE_IP=90.90.97.28 bash run.sh prefill
#
# Topology:
#   Prefill x2 : global DP=2, TP=8, each node local_DP=1
#   Decode  x2 : global DP=32, TP=1, each node local_DP=16 (ONE DP group)
# =============================================================================

_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_WORK_SPACE="${_THIS_DIR}/../.."

export SHARED_COMMON_DIR="${SHARED_COMMON_DIR:-/mnt/a800_share/l00848175/scripts-ascend/example/common}"
if [[ -z "${COMMON_DIR:-}" || ! -f "${COMMON_DIR}/config_helpers.sh" ]]; then
    if [[ -f "${SHARED_COMMON_DIR}/config_helpers.sh" ]]; then
        export COMMON_DIR="$(cd "${SHARED_COMMON_DIR}" && pwd)"
    elif [[ -f "${_WORK_SPACE}/../common/config_helpers.sh" ]]; then
        export COMMON_DIR="$(cd "${_WORK_SPACE}/../common" && pwd)"
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


# =============================================================================
# ----- Model -----
export MODEL_PATH="${MODEL_PATH:-/mnt/a800_weight/MiniMax-M2.7-w8a8-QuaRot}"
export MODEL_NAME="${MODEL_NAME:-minimaxm27}"
export IS_QUANTIZATION=1

# ----- Feature switches -----
export ENABLE_KV_POOL=1
export ENABLE_PREFIX_CACHE=1
export ENABLE_EXPERT_PARALLEL=1
export PD_KV_CONNECTOR="${PD_KV_CONNECTOR:-MooncakeConnectorV1}"
export KV_POOL_BACKEND="${KV_POOL_BACKEND:-mooncake}"
export KV_LOAD_FAILURE_POLICY="${KV_LOAD_FAILURE_POLICY:-recompute}"
export KV_POOL_LOOKUP_RPC_PORT="${KV_POOL_LOOKUP_RPC_PORT:-0}"
export VLLM_USE_V2_MODEL_RUNNER=1

# ----- Optional engine-level switches (env vars) -----
export ENABLE_FLASHCOMM1="${ENABLE_FLASHCOMM1:-0}"        # VLLM_ASCEND_ENABLE_FLASHCOMM1
export ENABLE_FUSED_MC2="${ENABLE_FUSED_MC2:-0}"          # VLLM_ASCEND_ENABLE_FUSED_MC2
export VLLM_SERVER_DEV_MODE="${VLLM_SERVER_DEV_MODE:-0}"

# ----- Additional-config booleans (dynamically built by run_dp_template.sh) -----
export ENABLE_REDUCE_SAMPLE="${ENABLE_REDUCE_SAMPLE:-0}"
export ENABLE_CPU_BINDING="${ENABLE_CPU_BINDING:-1}"
export ENABLE_NPUGRAPH_EX="${ENABLE_NPUGRAPH_EX:-0}"
export WEIGHT_NZ_MODE="${WEIGHT_NZ_MODE:-0}"
export P_RECOMPUTE_SCHEDULER="${P_RECOMPUTE_SCHEDULER:-0}"
export D_RECOMPUTE_SCHEDULER="${D_RECOMPUTE_SCHEDULER:-1}"

# ----- Speculative decoding -----
export SPECULATIVE_METHOD="${SPECULATIVE_METHOD:-}"                       # e.g. "eagle3"
export SPECULATIVE_MODEL_PATH="${SPECULATIVE_MODEL_PATH:-}"               # eagle model path
export P_SPECULATIVE_TOKENS="${P_SPECULATIVE_TOKENS:-1}"                  # Prefill draft tokens
export D_SPECULATIVE_TOKENS="${D_SPECULATIVE_TOKENS:-3}"                  # Decode draft tokens

# ----- Compilation config -----
export P_CUDAGRAPH_MODE="${P_CUDAGRAPH_MODE:-}"                           # e.g. "" or "FULL_DECODE_ONLY"
export D_CUDAGRAPH_MODE="${D_CUDAGRAPH_MODE:-}"                           # e.g. "FULL_DECODE_ONLY"
# =============================================================================



# =============================================================================
# Machine inventory (INDEX-ALIGNED). Edit these lists for your cluster.
# Index i always means the same physical machine across related arrays.
# =============================================================================

# Prefill machines: P0, P1
export PREFILL_IPS=("90.90.97.37")
export PREFILL_NICS=(enp194s0f0)
# Optional per-P-node overrides (length 0 = use global defaults / auto devices)
# Example (local_DP=1): one device group string per node
# export P_NODE_VISIBLE_DEVICES=("0,1,2,3,4,5,6,7" "0,1,2,3,4,5,6,7")
# Example (local_DP=2): semicolon separates local ranks on that node
# export P_NODE_VISIBLE_DEVICES=("0,1,2,3,4,5,6,7;8,9,10,11,12,13,14,15" "...")
export P_NODE_VISIBLE_DEVICES=("0,1,2,3,4,5,6,7;8,9,10,11,12,13,14,15")
export P_NODE_HTTP_PORT=()          # e.g. (7100 7100)
export P_NODE_KV_PORT_BASE=()       # e.g. (36000 36100)

# Decode machines: D0, D1 (join one DP group via D_DP_ADDRESS=D0)
export DECODE_IPS=("90.90.97.28")
export DECODE_NICS=(enp194s0f0)
export D_NODE_VISIBLE_DEVICES=("0,1,2,3,4,5,6,7;8,9,10,11,12,13,14,15")
export D_NODE_HTTP_PORT=()
export D_NODE_KV_PORT_BASE=()

export LOCAL_IPS=("${PREFILL_IPS[@]}" "${DECODE_IPS[@]}")
export NIC_NAMES=("${PREFILL_NICS[@]}" "${DECODE_NICS[@]}")

# ----- Parallelism (1P1D) -----
export P_DP_SIZE=2
export P_TP_SIZE=8
export P_DP_SIZE_LOCAL=2
export D_DP_SIZE=2
export D_TP_SIZE=8
export D_DP_SIZE_LOCAL=2

# ----- Pipeline Parallel (optional, both default to 1 = disabled) -----
export P_PP_SIZE="${P_PP_SIZE:-1}"
export P_PP_LAYER_PARTITION="${P_PP_LAYER_PARTITION:-}"                   # e.g. "32,30"
export D_PP_SIZE="${D_PP_SIZE:-1}"
export D_PP_LAYER_PARTITION="${D_PP_LAYER_PARTITION:-}"                   # e.g. "32,30"

# Template devices for ALL nodes of a role (used only when P/D_NODE_VISIBLE_DEVICES empty).
# Length must be 0(auto) or *_DP_SIZE_LOCAL.
export P_VISIBLE_DEVICES_LIST=("0,1,2,3,4,5,6,7" "8,9,10,11,12,13,14,15")
export D_VISIBLE_DEVICES_LIST=("0,1,2,3,4,5,6,7" "8,9,10,11,12,13,14,15")

# ----- Ports / DP masters -----
export PROXY_HOST="${PROXY_HOST:-${PREFILL_IPS[0]}}"
export PROXY_PORT="${PROXY_PORT:-8080}"
export P_VLLM_START_PORT=7100
export D_VLLM_START_PORT=7100
export P_DP_ADDRESS="${P_DP_ADDRESS:-${PREFILL_IPS[0]}}"
export D_DP_ADDRESS="${D_DP_ADDRESS:-${DECODE_IPS[0]}}"
export P_DP_RPC_PORT=12321
export D_DP_RPC_PORT=12321
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
export P_MAX_NUM_SEQS=256
export P_MAX_MODEL_LEN=135000 
export P_MAX_NUM_BATCHED_TOKENS=32768
export P_GPU_MEMORY_UTILIZATION=0.9
export P_ENFORCE_EAGER=1
export P_ASYNC_SCHEDULING="${P_ASYNC_SCHEDULING:-0}"
export D_MAX_NUM_SEQS=256
export D_MAX_MODEL_LEN=135000 
export D_MAX_NUM_BATCHED_TOKENS=32768
export D_GPU_MEMORY_UTILIZATION=0.92
export D_ASYNC_SCHEDULING=1
export D_ENFORCE_EAGER="${D_ENFORCE_EAGER:-1}"

# Per-machine log root on shared FS (final path: <base>/<role><idx>_<ip>/)
export LOG_DIR_BASE="${LOG_DIR_BASE:-${_THIS_DIR}/logs}"
export LOG_DIR="${LOG_DIR:-${LOG_DIR_BASE}}"

# ----- AISBench smoke -----
export AISBENCH_CASE_NAME="${AISBENCH_CASE_NAME:-pd_gsm8k_acc_top10}"
export AISBENCH_WORK_DIR="${AISBENCH_WORK_DIR:-${LOG_DIR_BASE}/aisbench_gsm8k}"
export AISBENCH_MAX_OUT_LEN="${AISBENCH_MAX_OUT_LEN:-512}"
export AISBENCH_BATCH_SIZE="${AISBENCH_BATCH_SIZE:-1}"
export GSM8K_TEST_RANGE="${GSM8K_TEST_RANGE:-[0:10]}"
