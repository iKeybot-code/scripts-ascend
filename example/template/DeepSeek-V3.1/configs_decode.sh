#!/bin/bash
# =============================================================================
# DeepSeek-V3.1 Decode role config (common_v2)
# Sourced by: bash run.sh decode [...]
# =============================================================================

_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_THIS_DIR}/configs_common.sh"

# ----- Decode serve knobs -----
export D_MAX_NUM_SEQS=28
export D_MAX_MODEL_LEN=65536
export D_MAX_NUM_BATCHED_TOKENS=256
export D_GPU_MEMORY_UTILIZATION=0.92
export D_ENFORCE_EAGER=1
# export D_ENFORCE_EAGER=0
export D_ASYNC_SCHEDULING=1

# Decode engine env switches (plain export; comment to leave default/off)
# export ENABLE_FLASHCOMM1=1
# export ENABLE_FUSED_MC2=1
# export VLLM_ASCEND_ENABLE_MLAPO=1
# export VLLM_SERVER_DEV_MODE=1

# =============================================================================
# JSON configs as standalone exports (run_dp_template only selects / appends)
# Comment out a whole export to omit that CLI flag.
# =============================================================================

# --additional-config
export ADDITIONAL_CONFIG='{"recompute_scheduler_enable": true, "multistream_overlap_shared_expert": true, "finegrained_tp_config": {"lmhead_tensor_parallel_size": 16}}'
# export ADDITIONAL_CONFIG='{"recompute_scheduler_enable": true}'

# --speculative_config
export SPECULATIVE_CONFIG='{"num_speculative_tokens": 1, "method": "mtp", "enforce_eager": true}'

# --compilation-config
export COMPILATION_CONFIG='{"cudagraph_mode": "FULL_DECODE_ONLY"}'
# export COMPILATION_CONFIG='{"cudagraph_mode": "PIECEWISE"}'

# KV transfer JSON selection is owned by ENABLE_KV_POOL in configs_common.sh:
#   0 -> KV_TRANSFER_CONFIG_PD
#   1 -> KV_TRANSFER_CONFIG_POOL
# Optional override (skips switch selection if set):
# export KV_TRANSFER_CONFIG="${KV_TRANSFER_CONFIG_PD}"
