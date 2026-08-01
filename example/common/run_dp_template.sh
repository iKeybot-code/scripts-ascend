#!/bin/bash
# Per-rank vLLM launch template (aligned with vllm-ascend external_online_dp).
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
    if [[ "${P_DP_SIZE:-1}" == "${P_DP_SIZE_LOCAL:-1}" ]]; then
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

# Export PP layer partition env var for vllm (from configs.sh)
if [[ "${ROLE}" == "prefill" && -n "${P_PP_LAYER_PARTITION:-}" ]]; then
    export VLLM_PP_LAYER_PARTITION="${P_PP_LAYER_PARTITION}"
elif [[ "${ROLE}" == "decode" && -n "${D_PP_LAYER_PARTITION:-}" ]]; then
    export VLLM_PP_LAYER_PARTITION="${D_PP_LAYER_PARTITION}"
fi

mkdir -p "${LOG_DIR}"
rm -rf "${HOME}/ascend/log/"* 2>/dev/null || true


# =============================================================================
# build_additional_config: dynamically build --additional-config JSON
# =============================================================================
build_additional_config() {
    local role="$1"
    local parts=()

    # ---- Common booleans from configs.sh ----
    [[ "${ENABLE_CPU_BINDING:-1}" == "1" ]] && parts+=('"enable_cpu_binding": true')
    [[ "${ENABLE_REDUCE_SAMPLE:-0}" == "1" ]] && parts+=('"enable_reduce_sample": true')
    [[ "${ENABLE_FLASHCOMM1:-0}" == "1" ]] && parts+=('"enable_flashcomm1": true')
    [[ "${ENABLE_FUSED_MC2:-0}" == "1" ]] && parts+=('"enable_fused_mc2": true')
    [[ "${WEIGHT_NZ_MODE:-0}" == "1" ]] && parts+=('"weight_nz_mode": true')
    [[ "${ENABLE_SHARED_EXPERT_DP:-0}" == "1" ]] && parts+=('"enable_shared_expert_dp": true')

    # ---- Role-specific ----
    if [[ "${role}" == "prefill" ]]; then
        [[ "${P_RECOMPUTE_SCHEDULER:-0}" == "1" ]] && parts+=('"recompute_scheduler_enable": true')
        # Prefill: when enforce_eager=1, disable fused_mc2 and prefill_mc2
        if [[ "${P_ENFORCE_EAGER:-1}" == "1" ]]; then
            parts+=('"enable_fused_mc2": 0')
            parts+=('"enable_prefill_mc2": 0')
        fi
    elif [[ "${role}" == "decode" ]]; then
        [[ "${D_RECOMPUTE_SCHEDULER:-1}" == "1" ]] && parts+=('"recompute_scheduler_enable": true')
        [[ "${D_MULTISTREAM_OVERLAP:-0}" == "1" ]] && parts+=('"multistream_overlap_shared_expert": true')
        # Finegrained TP config for decode (e.g. lmhead_tensor_parallel_size=16)
        if [[ -n "${D_FINEGRAINED_TP_CONFIG:-}" ]]; then
            parts+=("\"finegrained_tp_config\": ${D_FINEGRAINED_TP_CONFIG}")
        fi
    fi

    # ---- NPU graph ex (optional) ----
    if [[ "${ENABLE_NPUGRAPH_EX:-0}" == "1" ]]; then
        parts+=('"ascend_compilation_config": {"enable_npugraph_ex": true}')
    fi

    # ---- Extra additional config parts (for model-specific overrides) ----
    if [[ -n "${EXTRA_ADDITIONAL_CONFIG_PARTS:-}" ]]; then
        local extra_part
        IFS='|' read -ra extra_arr <<< "${EXTRA_ADDITIONAL_CONFIG_PARTS}"
        for extra_part in "${extra_arr[@]}"; do
            [[ -n "${extra_part}" ]] && parts+=("${extra_part}")
        done
    fi

    if [[ ${#parts[@]} -eq 0 ]]; then
        return 1
    fi

    local config="{"
    local delim=""
    local part
    for part in "${parts[@]}"; do
        config+="${delim}${part}"
        delim=","
    done
    config+="}"
    echo "${config}"
}


# =============================================================================
# build_speculative_config: dynamically build --speculative_config JSON
# =============================================================================
build_speculative_config() {
    local role="$1"
    if [[ -z "${SPECULATIVE_METHOD:-}" || -z "${SPECULATIVE_MODEL_PATH:-}" ]]; then
        return 1
    fi

    local tokens
    if [[ "${role}" == "prefill" ]]; then
        tokens="${P_SPECULATIVE_TOKENS:-1}"
    else
        tokens="${D_SPECULATIVE_TOKENS:-3}"
    fi

    if [[ "${tokens}" == "0" || -z "${tokens}" ]]; then
        return 1
    fi

    cat <<INNEREOF
{"enforce_eager": false, "method": "${SPECULATIVE_METHOD}", "model": "${SPECULATIVE_MODEL_PATH}", "num_speculative_tokens": ${tokens}}
INNEREOF
}


# =============================================================================
# build_compilation_config
# =============================================================================
build_compilation_config() {
    local role="$1"
    local mode=""
    if [[ "${role}" == "prefill" ]]; then
        mode="${P_CUDAGRAPH_MODE:-}"
    else
        mode="${D_CUDAGRAPH_MODE:-}"
    fi
    if [[ -z "${mode}" ]]; then
        return 1
    fi
    echo "{\"cudagraph_mode\":\"${mode}\"}"
}


# =============================================================================
# Per-role defaults
# =============================================================================
if [[ "${ROLE}" == "prefill" ]]; then
    KV_ROLE="kv_producer"
    MAX_NUM_SEQS="${P_MAX_NUM_SEQS}"
    MAX_MODEL_LEN="${P_MAX_MODEL_LEN}"
    MAX_NUM_BATCHED_TOKENS="${P_MAX_NUM_BATCHED_TOKENS}"
    GPU_MEM_UTIL="${P_GPU_MEMORY_UTILIZATION}"
    EXTRA_ARGS=()
    if [[ "${P_ENFORCE_EAGER}" == "1" ]]; then
        EXTRA_ARGS+=(--enforce-eager)
    fi
    if [[ "${P_ASYNC_SCHEDULING:-0}" != "1" ]]; then
        EXTRA_ARGS+=(--no-async-scheduling)
    fi
    if [[ "${PP_SIZE}" -gt 1 ]]; then
        EXTRA_ARGS+=(--pipeline-parallel-size "${PP_SIZE}")
    fi
elif [[ "${ROLE}" == "decode" ]]; then
    KV_ROLE="kv_consumer"
    MAX_NUM_SEQS="${D_MAX_NUM_SEQS}"
    MAX_MODEL_LEN="${D_MAX_MODEL_LEN}"
    MAX_NUM_BATCHED_TOKENS="${D_MAX_NUM_BATCHED_TOKENS}"
    GPU_MEM_UTIL="${D_GPU_MEMORY_UTILIZATION}"
    EXTRA_ARGS=()
    if [[ "${D_ENFORCE_EAGER:-1}" == "1" ]]; then
        EXTRA_ARGS+=(--enforce-eager)
    fi
    if [[ "${D_ASYNC_SCHEDULING}" == "1" ]]; then
        EXTRA_ARGS+=(--async-scheduling)
    fi
    if [[ "${PP_SIZE}" -gt 1 ]]; then
        EXTRA_ARGS+=(--pipeline-parallel-size "${PP_SIZE}")
    fi
else
    echo "[run_dp_template] unknown role: ${ROLE}" >&2
    exit 1
fi

# ---- Compilation config ----
COMPILATION_JSON="$(build_compilation_config "${ROLE}" || true)"
if [[ -n "${COMPILATION_JSON}" ]]; then
    EXTRA_ARGS+=(--compilation-config "${COMPILATION_JSON}")
fi

# ---- Additional config (dynamic via configs.sh flags) ----
ADDITIONAL_JSON="$(build_additional_config "${ROLE}" || true)"
if [[ -n "${ADDITIONAL_JSON}" ]]; then
    EXTRA_ARGS+=(--additional-config "${ADDITIONAL_JSON}")
fi

# ---- Shared switches (prefix cache / expert parallel / quantization) ----
if [[ "${ENABLE_PREFIX_CACHE:-0}" == "1" ]]; then
    EXTRA_ARGS+=(--enable-prefix-caching)
else
    EXTRA_ARGS+=(--no-enable-prefix-caching)
fi
if [[ "${ENABLE_EXPERT_PARALLEL:-0}" == "1" ]]; then
    EXTRA_ARGS+=(--enable-expert-parallel)
fi
if [[ "${IS_QUANTIZATION:-0}" == "1" ]]; then
    EXTRA_ARGS+=(--quantization ascend)
fi

# ---- Speculative decoding ----
SPEC_JSON="$(build_speculative_config "${ROLE}" || true)"
if [[ -n "${SPEC_JSON}" ]]; then
    EXTRA_ARGS+=(--speculative_config "${SPEC_JSON}")
fi

# ---- KV transfer config ----
KV_TRANSFER_CONFIG="$(build_kv_transfer_config "${KV_ROLE}" "${KV_PORT}")"

# ---- Log ----
LOG_FILE="${LOG_DIR}/${ROLE}_rank${DP_RANK}_$(date '+%H%M%S').log"
echo "[run_dp_template] role=${ROLE} rank=${DP_RANK} port=${ENGINE_PORT} kv_port=${KV_PORT} ip=${LOCAL_IP}"
echo "[run_dp_template] pd_connector=${PD_KV_CONNECTOR:-MooncakeConnectorV1} enable_kv_pool=${ENABLE_KV_POOL:-0}"
echo "[run_dp_template] mrv2=${VLLM_USE_V2_MODEL_RUNNER:-0} prefix_cache=${ENABLE_PREFIX_CACHE:-0}"
echo "[run_dp_template] flashcomm1=${ENABLE_FLASHCOMM1:-0} fused_mc2=${ENABLE_FUSED_MC2:-0}"
echo "[run_dp_template] tp=${TP_SIZE} pp=${PP_SIZE} dp=${DP_SIZE}"
echo "[run_dp_template] speculative=${SPECULATIVE_METHOD:-none}"
echo "[run_dp_template] log=${LOG_FILE}"

PYTHONUNBUFFERED=1 vllm serve "${MODEL_PATH}" \
    --served-model-name "${MODEL_NAME}" \
    --host 0.0.0.0 \
    --port "${ENGINE_PORT}" \
    --seed 1024 \
    --trust-remote-code \
    --data-parallel-size "${DP_SIZE}" \
    --data-parallel-rank "${DP_RANK}" \
    --data-parallel-address "${DP_ADDRESS}" \
    --data-parallel-rpc-port "${DP_RPC_PORT}" \
    --tensor-parallel-size "${TP_SIZE}" \
    --max-num-seqs "${MAX_NUM_SEQS}" \
    --max-model-len "${MAX_MODEL_LEN}" \
    --max-num-batched-tokens "${MAX_NUM_BATCHED_TOKENS}" \
    --gpu-memory-utilization "${GPU_MEM_UTIL}" \
    "${EXTRA_ARGS[@]}" \
    --kv-transfer-config "${KV_TRANSFER_CONFIG}" \
    2>&1 | tee "${LOG_FILE}"
