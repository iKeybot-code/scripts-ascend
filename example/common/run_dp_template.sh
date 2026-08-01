#!/bin/bash
# Per-rank vLLM launch template (aligned with vllm-ascend external_online_dp).
#
# Args:
#   $1 ASCEND_RT_VISIBLE_DEVICES
#   $2 engine_port
#   $3 data_parallel_size
#   $4 data_parallel_rank
#   $5 data_parallel_address
#   $6 data_parallel_rpc_port
#   $7 tensor_parallel_size
#   $8 role: prefill|decode
#   $9 kv_port
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

mkdir -p "${LOG_DIR}"
rm -rf "${HOME}/ascend/log/"* 2>/dev/null || true


if [[ "${ROLE}" == "prefill" ]]; then
    KV_ROLE="kv_producer"
    MAX_NUM_SEQS="${P_MAX_NUM_SEQS}"
    MAX_MODEL_LEN="${P_MAX_MODEL_LEN}"
    MAX_NUM_BATCHED_TOKENS="${P_MAX_NUM_BATCHED_TOKENS}"
    GPU_MEM_UTIL="${P_GPU_MEMORY_UTILIZATION}"
    EXTRA_ARGS=(
        --additional-config '{"enable_cpu_binding":true,"enable_npugraph_ex": true,"enable_fused_mc2":0,"enable_prefill_mc2":0}'
    )
    if [[ "${P_ENFORCE_EAGER}" == "1" ]]; then
        EXTRA_ARGS+=(--enforce-eager)
    fi
    if [[ "${P_ASYNC_SCHEDULING:-0}" != "1" ]]; then
        EXTRA_ARGS+=(--no-async-scheduling)
    fi
elif [[ "${ROLE}" == "decode" ]]; then
    KV_ROLE="kv_consumer"
    MAX_NUM_SEQS="${D_MAX_NUM_SEQS}"
    MAX_MODEL_LEN="${D_MAX_MODEL_LEN}"
    MAX_NUM_BATCHED_TOKENS="${D_MAX_NUM_BATCHED_TOKENS}"
    GPU_MEM_UTIL="${D_GPU_MEMORY_UTILIZATION}"
    EXTRA_ARGS=(
        --compilation-config '{"cudagraph_mode":"FULL_DECODE_ONLY"}'
        --additional-config '{"recompute_scheduler_enable":true,"enable_cpu_binding":true,"enable_npugraph_ex": true}'
    )
    if [[ "${D_ENFORCE_EAGER:-1}" == "1" ]]; then
        EXTRA_ARGS+=(--enforce-eager)
    fi
    if [[ "${D_ASYNC_SCHEDULING}" == "1" ]]; then
        EXTRA_ARGS+=(--async-scheduling)
    fi
else
    echo "[run_dp_template] unknown role: ${ROLE}" >&2
    exit 1
fi

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

readarray -t EXTRA_ARGS < <(printf '%s\n' "${EXTRA_ARGS[@]}" | grep -v '^$')
  
KV_TRANSFER_CONFIG="$(build_kv_transfer_config "${KV_ROLE}" "${KV_PORT}")"

# ATTEMPTS_FILE="${COMMON_DIR}/attempts.txt"
# CURRENT_ATTEMPT=$(cat "${ATTEMPTS_FILE}" 2>/dev/null || echo 0)
# NEXT_ATTEMPT=$((CURRENT_ATTEMPT + 1))
# echo "${NEXT_ATTEMPT}" > "${ATTEMPTS_FILE}"
LOG_FILE="${LOG_DIR}/${ROLE}_rank${DP_RANK}_$(date '+%H%M%S').log"
echo "[run_dp_template] role=${ROLE} rank=${DP_RANK} port=${ENGINE_PORT} kv_port=${KV_PORT} ip=${LOCAL_IP}"
echo "[run_dp_template] pd_connector=${PD_KV_CONNECTOR:-MooncakeConnectorV1} enable_kv_pool=${ENABLE_KV_POOL:-0}"
echo "[run_dp_template] mrv2=${VLLM_USE_V2_MODEL_RUNNER} prefix_cache=${ENABLE_PREFIX_CACHE}"
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
