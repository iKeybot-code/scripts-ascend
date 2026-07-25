#!/bin/bash
# Start PD load-balance proxy.
# Auto-selects layerwise / non-layerwise implementation by PD_KV_CONNECTOR.
#
# Requires: CONFIGS_FILE

set -euo pipefail

COMMON_DIR_BOOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${COMMON_DIR_BOOT}/load_configs.sh"
# shellcheck disable=SC1091
source "${COMMON_DIR}/kv_transfer_config.sh"

if is_layerwise_connector; then
    PROXY_PY="${COMMON_DIR}/load_balance_proxy_layerwise_server_example.py"
    PROXY_KIND="layerwise"
else
    PROXY_PY="${COMMON_DIR}/load_balance_proxy_server_example.py"
    PROXY_KIND="non-layerwise"
fi

if [[ ! -f "${PROXY_PY}" ]]; then
    echo "[start_proxy] missing proxy script: ${PROXY_PY}" >&2
    exit 1
fi

PREFILLER_HOSTS=()
PREFILLER_PORTS=()
for ip in "${PREFILL_IPS[@]}"; do
    for ((i = 0; i < P_DP_SIZE_LOCAL; i++)); do
        PREFILLER_HOSTS+=("${ip}")
        PREFILLER_PORTS+=("$((P_VLLM_START_PORT + i))")
    done
done

DECODER_HOSTS=()
DECODER_PORTS=()
for ip in "${DECODE_IPS[@]}"; do
    for ((i = 0; i < D_DP_SIZE_LOCAL; i++)); do
        DECODER_HOSTS+=("${ip}")
        DECODER_PORTS+=("$((D_VLLM_START_PORT + i))")
    done
done

mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/proxy_$(date '+%m%d%H%M%S').log"

echo "[start_proxy] kind=${PROXY_KIND} connector=${PD_KV_CONNECTOR:-MooncakeConnectorV1}"
echo "[start_proxy] host=${PROXY_HOST} port=${PROXY_PORT}"
echo "[start_proxy] prefiller_hosts=${PREFILLER_HOSTS[*]}"
echo "[start_proxy] prefiller_ports=${PREFILLER_PORTS[*]}"
echo "[start_proxy] decoder_hosts=${DECODER_HOSTS[*]}"
echo "[start_proxy] decoder_ports=${DECODER_PORTS[*]}"
echo "[start_proxy] log=${LOG_FILE}"

python "${PROXY_PY}" \
    --host "${PROXY_HOST}" \
    --port "${PROXY_PORT}" \
    --prefiller-hosts "${PREFILLER_HOSTS[@]}" \
    --prefiller-ports "${PREFILLER_PORTS[@]}" \
    --decoder-hosts "${DECODER_HOSTS[@]}" \
    --decoder-ports "${DECODER_PORTS[@]}" \
    2>&1 | tee "${LOG_FILE}"
