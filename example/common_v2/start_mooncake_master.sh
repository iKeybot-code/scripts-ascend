#!/bin/bash
# Start Mooncake master for KV pooling. Only needed when ENABLE_KV_POOL=1.
#
# Requires: CONFIGS_FILE

set -euo pipefail

COMMON_DIR_BOOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${COMMON_DIR_BOOT}/load_configs.sh"
# shellcheck disable=SC1091
source "${COMMON_DIR}/env_common.sh"
# shellcheck disable=SC1091
source "${COMMON_DIR}/kv_transfer_config.sh"

if ! is_kv_pool_enabled; then
    echo "[start_mooncake_master] ENABLE_KV_POOL=${ENABLE_KV_POOL:-0}, skip mooncake_master."
    echo "  Set ENABLE_KV_POOL=1 in configs.sh when KV pooling is required."
    exit 0
fi

mkdir -p "${LOG_DIR}"

bash "${COMMON_DIR}/gen_mooncake_json.sh" \
    "${MOONCAKE_MASTER_IP}" \
    "${MOONCAKE_MASTER_PORT}" \
    "${MOONCAKE_CONFIG_PATH}" \
    "${MOONCAKE_GLOBAL_SEGMENT_SIZE}"

if ! command -v mooncake_master >/dev/null 2>&1; then
    echo "[start_mooncake_master] mooncake_master not found in PATH" >&2
    exit 1
fi

LOG_FILE="${LOG_DIR}/mooncake_master_$(date '+%m%d%H%M%S').log"
echo "[start_mooncake_master] listen=${MOONCAKE_MASTER_IP}:${MOONCAKE_MASTER_PORT}"
echo "[start_mooncake_master] mooncake.json=${MOONCAKE_CONFIG_PATH}"
echo "[start_mooncake_master] log=${LOG_FILE}"

mooncake_master \
    --port "${MOONCAKE_MASTER_PORT}" \
    --eviction_high_watermark_ratio "${MOONCAKE_EVICT_HIGH_WATERMARK}" \
    --eviction_ratio "${MOONCAKE_EVICT_RATIO}" \
    --default_kv_lease_ttl "${MOONCAKE_KV_LEASE_TTL}" \
    2>&1 | tee "${LOG_FILE}"
