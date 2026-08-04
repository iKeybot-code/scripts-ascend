#!/bin/bash
# Shared Ascend / HCCL / Mooncake environment helpers.
# Intended location (container shared mount):
#   /mnt/a800_share/l00848175/scripts-ascend/example/common_v2/env_common.sh

set_network_env() {
    local local_ip="$1"
    local nic_name="$2"

    if [[ -z "${local_ip}" || -z "${nic_name}" ]]; then
        echo "[env_common] local_ip and nic_name are required" >&2
        return 1
    fi

    export HCCL_IF_IP="${local_ip}"
    export GLOO_SOCKET_IFNAME="${nic_name}"
    export TP_SOCKET_IFNAME="${nic_name}"
    export HCCL_SOCKET_IFNAME="${nic_name}"
}

set_runtime_env() {
    # HCCL_EXEC_TIMEOUT raised (1800s) to tolerate cross-node decode startup
    # skew: node .48 model-loads ~3min later than .44, so first-inference
    # AllGather would otherwise hit the 600s default timeout and kill rank0.
    export HCCL_EXEC_TIMEOUT="${HCCL_EXEC_TIMEOUT:-1800}"
    export HCCL_CONNECT_TIMEOUT="${HCCL_CONNECT_TIMEOUT:-360}"
    export HCCL_BUFFSIZE="${HCCL_BUFFSIZE:-1024}"
    export HCCL_DETERMINISTIC="${HCCL_DETERMINISTIC:-true}"
    export OMP_PROC_BIND="${OMP_PROC_BIND:-false}"
    export OMP_NUM_THREADS="${OMP_NUM_THREADS:-10}"
    export HCCL_OP_EXPANSION_MODE="AIV"
    export PYTORCH_NPU_ALLOC_CONF="${PYTORCH_NPU_ALLOC_CONF:-expandable_segments:True}"
    export TASK_QUEUE_ENABLE="${TASK_QUEUE_ENABLE:-1}"
    export MC_LOG_LEVEL="${MC_LOG_LEVEL:-ERROR}"
    export PYTHONHASHSEED="${PYTHONHASHSEED:-0}"
    # Official DeepSeek-V3.1 PD guide values: tolerate NPU graph compile + slow
    # DP-rank model startup on first inference (sample_tokens RPC used to time
    # out at the 300s default, crashing decode workers).
    export VLLM_RPC_TIMEOUT="${VLLM_RPC_TIMEOUT:-3600000}"
    export VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS="${VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS:-30000}"
    export ASCEND_BUFFER_POOL="${ASCEND_BUFFER_POOL:-0:0}"
    export ASCEND_CONNECT_TIMEOUT="${ASCEND_CONNECT_TIMEOUT:-10000}"
    export ASCEND_TRANSFER_TIMEOUT="${ASCEND_TRANSFER_TIMEOUT:-10000}"
    export HCCL_RDMA_TIMEOUT="${HCCL_RDMA_TIMEOUT:-17}"

    # FlashComm1 / Fused MC2 (configs.sh: ENABLE_FLASHCOMM1 / ENABLE_FUSED_MC2)
    export VLLM_ASCEND_ENABLE_FLASHCOMM1="${ENABLE_FLASHCOMM1:-0}"
    export VLLM_ASCEND_ENABLE_FUSED_MC2="${ENABLE_FUSED_MC2:-0}"

    # VLLM dev mode (configs.sh: VLLM_SERVER_DEV_MODE)
    if [[ "${VLLM_SERVER_DEV_MODE:-0}" == "1" ]]; then
        export VLLM_SERVER_DEV_MODE=1
    fi

    # LD_PRELOAD libjemalloc to avoid Mooncake glibc heap corruption
    # ("corrupted size vs. prev_size") under high-concurrency KV pool access.
    if [[ -z "${LD_PRELOAD:-}" ]]; then
        for _je in /usr/lib/aarch64-linux-gnu/libjemalloc.so.2 \
            /usr/lib/x86_64-linux-gnu/libjemalloc.so.2 \
            /lib/aarch64-linux-gnu/libjemalloc.so.2 /lib64/libjemalloc.so.2; do
            if [[ -f "${_je}" ]]; then
                export LD_PRELOAD="${_je}"
                break
            fi
        done
    fi

    # Optional hardware knobs (uncomment in configs.sh as needed)
    # export ASCEND_ENABLE_USE_FABRIC_MEM=1          # A3 recommended
    # export HCCL_INTRA_ROCE_ENABLE=1                # A2
    # export ACL_OP_INIT_MODE=1                      # A3
}

resolve_common_dir() {
    # Prefer shared mount; fall back to repo-local example/common_v2.
    local shared_dir="${SHARED_COMMON_DIR:-/mnt/a800_share/l00848175/scripts-ascend/example/common_v2}"
    if [[ -d "${shared_dir}" ]]; then
        echo "${shared_dir}"
        return 0
    fi

    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "${here}"
}
