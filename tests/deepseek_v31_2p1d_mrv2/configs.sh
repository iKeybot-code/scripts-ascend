#!/bin/bash
# =============================================================================
# DeepSeek V3.1 PD multi-node config (2P1D + KV pool + MRV2 + prefix cache)
# Model: DeepSeek-V3.1-Terminus-w4a8-mtp-QuaRot
# Features: ModelRunnerV2, PD separation, MooncakeConnectorV1, KV pooling, prefix cache
# =============================================================================

_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate common/
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

# Enable MRV2 (Model Runner V2) and prefix cache
export VLLM_USE_V2_MODEL_RUNNER=1
export ENABLE_PREFIX_CACHE=1

# ----- Model -----
export MODEL_PATH="${MODEL_PATH:-/mnt/a800_weight/DeepSeek-V3.1-Terminus-w4a8-mtp-QuaRot}"
export MODEL_NAME="${MODEL_NAME:-deepseek_v31}"

# ----- Cluster topology (2P1D) -----
# Prefill nodes: Node 29 and Node 37
export PREFILL_IPS=(90.90.97.29 90.90.97.37)
export PREFILL_NICS=(enp194s0f0 enp194s0f0)
# Decode node: Node 42
export DECODE_IPS=(90.90.97.29 90.90.97.37)
export DECODE_NICS=(enp194s0f0 enp194s0f0)
export LOCAL_IPS=("${PREFILL_IPS[@]}" "${DECODE_IPS[@]}")
export NIC_NAMES=("${PREFILL_NICS[@]}" "${DECODE_NICS[@]}")

# ----- Parallelism -----
# P: DP=2 per node, TP=8 → 2×8=16 cards per P node
# Total P_DP_SIZE=4 (2 nodes × 2 DP per node), each uses TP=8
export P_DP_SIZE=2
export P_TP_SIZE=8
export P_DP_SIZE_LOCAL=1
# D: DP=16, TP=1 → 16×1=16 cards on single D node
# Note: Originally specified as DP=32, adjusted to 16 due to 16-card physical limit
export D_DP_SIZE=2
export D_TP_SIZE=8
export D_DP_SIZE_LOCAL=1
# Visible devices: all 16 cards
# P: 2 DP groups of 8 devices each
export P_VISIBLE_DEVICES_LIST=("0,1,2,3,4,5,6,7")
# D: 16 DP groups of 1 device each
export D_VISIBLE_DEVICES_LIST=("8,9,10,11,12,13,14,15")

# ----- Ports -----
export PROXY_HOST="${PROXY_HOST:-${PREFILL_IPS[0]}}"
export PROXY_PORT="${PROXY_PORT:-8080}"
export P_VLLM_START_PORT=13900
export D_VLLM_START_PORT=13901
export P_DP_ADDRESS="${P_DP_ADDRESS:-${PREFILL_IPS[0]}}"
export D_DP_ADDRESS="${D_DP_ADDRESS:-${DECODE_IPS[0]}}"
export P_DP_RPC_PORT=12321
export D_DP_RPC_PORT=12322
# KV ports above [20000, 20000+NPU*1000) range (AscendDirectTransport)
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
# Prefill settings (DeepSeek V3.1 160K context)
export P_MAX_NUM_SEQS=4
export P_MAX_MODEL_LEN=40000
export P_MAX_NUM_BATCHED_TOKENS=40000
export P_GPU_MEMORY_UTILIZATION=0.9
export P_ENFORCE_EAGER=1
# Decode settings
export D_MAX_NUM_SEQS=128
export D_MAX_MODEL_LEN=32768
export D_MAX_NUM_BATCHED_TOKENS=2048
export D_GPU_MEMORY_UTILIZATION=0.9
export D_ASYNC_SCHEDULING=1
export D_ENFORCE_EAGER=1
export LOG_DIR="${LOG_DIR:-${_THIS_DIR}/logs}"

# ----- AISBench smoke test (GSM8K top10 accuracy) -----
export AISBENCH_CASE_NAME="${AISBENCH_CASE_NAME:-pd_gsm8k_acc_top10}"
export AISBENCH_WORK_DIR="${AISBENCH_WORK_DIR:-${LOG_DIR}/aisbench_gsm8k}"
export AISBENCH_MAX_OUT_LEN="${AISBENCH_MAX_OUT_LEN:-512}"
export AISBENCH_BATCH_SIZE="${AISBENCH_BATCH_SIZE:-1}"
export GSM8K_TEST_RANGE="${GSM8K_TEST_RANGE:-[0:10]}"
