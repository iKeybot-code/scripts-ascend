#!/bin/bash
# Per-rank vLLM launch template (common_v2).
#
# Responsibility:
#   - validate launch args / required config exports
#   - select JSON config vars by feature switches
#   - assemble the final vllm command
#   - write the full command file next to the run log, then execute
#
# Args:
#   $1  ASCEND_RT_VISIBLE_DEVICES
#   $2  engine_port
#   $3  data_parallel_size
#   $4  data_parallel_rank
#   $5  data_parallel_address
#   $6  data_parallel_rpc_port
#   $7  tensor_parallel_size
#   $8  role: prefill|decode
#   $9  kv_port
#   $10 pipeline_parallel_size (optional, default 1)
#
# Requires: CONFIGS_FILE
# JSON exports (from configs_*): ADDITIONAL_CONFIG / SPECULATIVE_CONFIG /
#   COMPILATION_CONFIG / KV_TRANSFER_CONFIG_{PD,POOL}

set -euo pipefail
unset ftp_proxy
unset https_proxy
unset http_proxy

COMMON_DIR_BOOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${COMMON_DIR_BOOT}/load_configs.sh"
# shellcheck disable=SC1091
source "${COMMON_DIR}/env_common.sh"
# shellcheck disable=SC1091
source "${COMMON_DIR}/kv_transfer_config.sh"

VISIBLE_DEVICES="${1:?visible devices required}"
ENGINE_PORT="${2:?engine port required}"
DP_SIZE="${3:?dp size required}"
DP_RANK="${4:?dp rank required}"
DP_ADDRESS="${5:?dp address required}"
DP_RPC_PORT="${6:?dp rpc port required}"
TP_SIZE="${7:?tp size required}"
ROLE="${8:?role required}"
KV_PORT="${9:?kv port required}"
PP_SIZE="${10:-1}"

LOCAL_IP="${CUR_IP:-${HCCL_IF_IP:-}}"
NIC_NAME="${CUR_NIC:-${GLOO_SOCKET_IFNAME:-}}"
if [[ -z "${LOCAL_IP}" || -z "${NIC_NAME}" ]]; then
    echo "[run_dp_template] CUR_IP/CUR_NIC not set. Call via start_prefill/start_decode." >&2
    exit 1
fi

set_network_env "${LOCAL_IP}" "${NIC_NAME}"
set_runtime_env

# Use loopback only when all DP ranks are local to this node
if [[ "${ROLE}" == "prefill" ]]; then
    if [[ "${P_DP_SIZE:-1}" == "${P_DP_SIZE_LOCAL:-1}" && "${P_INDEPENDENT_NODE_DP:-0}" != "1" ]]; then
        export GLOO_SOCKET_IFNAME=lo
    elif [[ "${P_INDEPENDENT_NODE_DP:-0}" == "1" && "${P_DP_SIZE_LOCAL:-1}" == "${P_DP_SIZE:-1}" ]]; then
        export GLOO_SOCKET_IFNAME=lo
    fi
elif [[ "${ROLE}" == "decode" ]]; then
    if [[ "${D_DP_SIZE:-1}" == "${D_DP_SIZE_LOCAL:-1}" ]]; then
        export GLOO_SOCKET_IFNAME=lo
    fi
fi

export ASCEND_RT_VISIBLE_DEVICES="${VISIBLE_DEVICES}"
if is_kv_pool_enabled; then
    export MOONCAKE_CONFIG_PATH
fi

# Export PP layer partition env var for vllm (from configs)
if [[ "${ROLE}" == "prefill" && -n "${P_PP_LAYER_PARTITION:-}" ]]; then
    export VLLM_PP_LAYER_PARTITION="${P_PP_LAYER_PARTITION}"
elif [[ "${ROLE}" == "decode" && -n "${D_PP_LAYER_PARTITION:-}" ]]; then
    export VLLM_PP_LAYER_PARTITION="${D_PP_LAYER_PARTITION}"
fi

mkdir -p "${LOG_DIR}"
rm -rf "${HOME}/ascend/log/"* 2>/dev/null || true

# =============================================================================
# Per-role scalar defaults + flag judgments (no JSON building here)
# =============================================================================
EXTRA_ARGS=()
if [[ "${ROLE}" == "prefill" ]]; then
    KV_ROLE="kv_producer"
    MAX_NUM_SEQS="${P_MAX_NUM_SEQS:?P_MAX_NUM_SEQS required}"
    MAX_MODEL_LEN="${P_MAX_MODEL_LEN:?P_MAX_MODEL_LEN required}"
    MAX_NUM_BATCHED_TOKENS="${P_MAX_NUM_BATCHED_TOKENS:?P_MAX_NUM_BATCHED_TOKENS required}"
    GPU_MEM_UTIL="${P_GPU_MEMORY_UTILIZATION:?P_GPU_MEMORY_UTILIZATION required}"
    [[ "${P_ENFORCE_EAGER:-0}" == "1" ]] && EXTRA_ARGS+=(--enforce-eager)
    [[ "${P_ASYNC_SCHEDULING:-0}" != "1" ]] && EXTRA_ARGS+=(--no-async-scheduling)
elif [[ "${ROLE}" == "decode" ]]; then
    KV_ROLE="kv_consumer"
    MAX_NUM_SEQS="${D_MAX_NUM_SEQS:?D_MAX_NUM_SEQS required}"
    MAX_MODEL_LEN="${D_MAX_MODEL_LEN:?D_MAX_MODEL_LEN required}"
    MAX_NUM_BATCHED_TOKENS="${D_MAX_NUM_BATCHED_TOKENS:?D_MAX_NUM_BATCHED_TOKENS required}"
    GPU_MEM_UTIL="${D_GPU_MEMORY_UTILIZATION:?D_GPU_MEMORY_UTILIZATION required}"
    [[ "${D_ENFORCE_EAGER:-0}" == "1" ]] && EXTRA_ARGS+=(--enforce-eager)
    # Official DeepSeek-V3.1 PD decode config does NOT use async scheduling.
    # D_ASYNC_SCHEDULING=0 (default) => pass --no-async-scheduling explicitly,
    # otherwise vllm auto-enables async scheduling and desyncs DP ranks.
    [[ "${D_ASYNC_SCHEDULING:-0}" != "1" ]] && EXTRA_ARGS+=(--no-async-scheduling)
else
    echo "[run_dp_template] unknown role: ${ROLE}" >&2
    exit 1
fi

[[ "${PP_SIZE}" -gt 1 ]] && EXTRA_ARGS+=(--pipeline-parallel-size "${PP_SIZE}")

# ---- JSON configs: use exported vars; select KV by feature switch ----
if [[ -n "${COMPILATION_CONFIG:-}" ]]; then
    EXTRA_ARGS+=(--compilation-config "${COMPILATION_CONFIG}")
fi
if [[ -n "${ADDITIONAL_CONFIG:-}" ]]; then
    EXTRA_ARGS+=(--additional-config "${ADDITIONAL_CONFIG}")
fi
if [[ -n "${SPECULATIVE_CONFIG:-}" ]]; then
    EXTRA_ARGS+=(--speculative_config "${SPECULATIVE_CONFIG}")
fi

if [[ "${ENABLE_PREFIX_CACHE:-0}" == "1" ]]; then
    EXTRA_ARGS+=(--enable-prefix-caching)
else
    EXTRA_ARGS+=(--no-enable-prefix-caching)
fi
[[ "${ENABLE_EXPERT_PARALLEL:-0}" == "1" ]] && EXTRA_ARGS+=(--enable-expert-parallel)
[[ "${IS_QUANTIZATION:-0}" == "1" ]] && EXTRA_ARGS+=(--quantization ascend)

KV_TRANSFER_CONFIG="$(build_kv_transfer_config "${KV_ROLE}" "${KV_PORT}")"

# ---- Log + full command file under the same redirect directory ----
STAMP="$(date '+%H%M%S')"
LOG_FILE="${LOG_DIR}/${ROLE}_rank${DP_RANK}_${STAMP}.log"
CMD_FILE="${LOG_DIR}/${ROLE}_rank${DP_RANK}_${STAMP}.cmd"

CMD=(
    vllm serve "${MODEL_PATH}"
    --served-model-name "${MODEL_NAME}"
    --host 0.0.0.0
    --port "${ENGINE_PORT}"
    --seed 1024
    --trust-remote-code
    --data-parallel-size "${DP_SIZE}"
    --data-parallel-rank "${DP_RANK}"
    --data-parallel-address "${DP_ADDRESS}"
    --data-parallel-rpc-port "${DP_RPC_PORT}"
    --tensor-parallel-size "${TP_SIZE}"
    --max-num-seqs "${MAX_NUM_SEQS}"
    --max-model-len "${MAX_MODEL_LEN}"
    --max-num-batched-tokens "${MAX_NUM_BATCHED_TOKENS}"
    --gpu-memory-utilization "${GPU_MEM_UTIL}"
    "${EXTRA_ARGS[@]}"
    --kv-transfer-config "${KV_TRANSFER_CONFIG}"
)

# Persist a replayable command file (env + argv) beside the run log
{
    echo "#!/bin/bash"
    echo "# Auto-generated by common_v2/run_dp_template.sh"
    echo "# role=${ROLE} rank=${DP_RANK} ip=${LOCAL_IP} nic=${NIC_NAME}"
    echo "# generated_at=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "set -euo pipefail"
    echo
    echo "export ASCEND_RT_VISIBLE_DEVICES=$(printf '%q' "${ASCEND_RT_VISIBLE_DEVICES}")"
    echo "export HCCL_IF_IP=$(printf '%q' "${HCCL_IF_IP:-}")"
    echo "export GLOO_SOCKET_IFNAME=$(printf '%q' "${GLOO_SOCKET_IFNAME:-}")"
    echo "export TP_SOCKET_IFNAME=$(printf '%q' "${TP_SOCKET_IFNAME:-}")"
    echo "export HCCL_SOCKET_IFNAME=$(printf '%q' "${HCCL_SOCKET_IFNAME:-}")"
    if [[ -n "${VLLM_PP_LAYER_PARTITION:-}" ]]; then
        echo "export VLLM_PP_LAYER_PARTITION=$(printf '%q' "${VLLM_PP_LAYER_PARTITION}")"
    fi
    if is_kv_pool_enabled && [[ -n "${MOONCAKE_CONFIG_PATH:-}" ]]; then
        echo "export MOONCAKE_CONFIG_PATH=$(printf '%q' "${MOONCAKE_CONFIG_PATH}")"
    fi
    echo "export VLLM_ASCEND_ENABLE_FLASHCOMM1=$(printf '%q' "${VLLM_ASCEND_ENABLE_FLASHCOMM1:-0}")"
    echo "export VLLM_ASCEND_ENABLE_FUSED_MC2=$(printf '%q' "${VLLM_ASCEND_ENABLE_FUSED_MC2:-0}")"
    echo
    echo "PYTHONUNBUFFERED=1 \\"
    # Pretty-print argv one flag/value pair style for readability
    local_i=0
    for local_arg in "${CMD[@]}"; do
        local_i=$((local_i + 1))
        if [[ ${local_i} -eq ${#CMD[@]} ]]; then
            printf '  %q\n' "${local_arg}"
        else
            printf '  %q \\\n' "${local_arg}"
        fi
    done
} > "${CMD_FILE}"
chmod +x "${CMD_FILE}" 2>/dev/null || true

echo "[run_dp_template] role=${ROLE} rank=${DP_RANK} port=${ENGINE_PORT} kv_port=${KV_PORT} ip=${LOCAL_IP}"
echo "[run_dp_template] pd_connector=${PD_KV_CONNECTOR:-MooncakeConnectorV1} enable_kv_pool=${ENABLE_KV_POOL:-0}"
echo "[run_dp_template] tp=${TP_SIZE} pp=${PP_SIZE} dp=${DP_SIZE} dp_address=${DP_ADDRESS}"
echo "[run_dp_template] log=${LOG_FILE}"
echo "[run_dp_template] cmd=${CMD_FILE}"

PYTHONUNBUFFERED=1 "${CMD[@]}" 2>&1 | tee "${LOG_FILE}"
