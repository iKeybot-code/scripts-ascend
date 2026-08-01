#!/bin/bash
# =============================================================================
# DeepSeek-V3.1 Prefill role config (common_v2)
# Sourced by: bash run.sh prefill [...]
# =============================================================================

_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_THIS_DIR}/configs_common.sh"

# ----- Prefill serve knobs -----
export P_MAX_NUM_SEQS=8
export P_MAX_MODEL_LEN=65536
export P_MAX_NUM_BATCHED_TOKENS=16384
export P_GPU_MEMORY_UTILIZATION=0.9
export P_ENFORCE_EAGER=1
# export P_ASYNC_SCHEDULING=1
export P_ASYNC_SCHEDULING=0

# Prefill engine env switches (plain export; comment to leave default/off)
export ENABLE_FLASHCOMM1=1
# export ENABLE_FUSED_MC2=1
# export VLLM_SERVER_DEV_MODE=1

# =============================================================================
# JSON configs as standalone exports (run_dp_template only selects / appends)
# Comment out a whole export to omit that CLI flag.
# =============================================================================

# --additional-config
export ADDITIONAL_CONFIG='{"recompute_scheduler_enable": true}'
# export ADDITIONAL_CONFIG='{"recompute_scheduler_enable": true, "enable_flashcomm1": true}'

# --speculative_config
export SPECULATIVE_CONFIG='{"num_speculative_tokens": 1, "method": "mtp"}'
# export SPECULATIVE_CONFIG='{"enforce_eager": false, "method": "mtp", "num_speculative_tokens": 1}'

# --compilation-config (usually off for Prefill + enforce-eager)
# export COMPILATION_CONFIG='{"cudagraph_mode": "FULL_DECODE_ONLY"}'

# KV transfer JSON selection is owned by ENABLE_KV_POOL in configs_common.sh:
#   0 -> KV_TRANSFER_CONFIG_PD
#   1 -> KV_TRANSFER_CONFIG_POOL
# Optional override (skips switch selection if set):
# export KV_TRANSFER_CONFIG="${KV_TRANSFER_CONFIG_PD}"
