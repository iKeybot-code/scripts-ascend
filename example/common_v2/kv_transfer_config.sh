#!/bin/bash
# Select --kv-transfer-config JSON from configs exports.
#
# Configs should export one or both of:
#   KV_TRANSFER_CONFIG_PD    # ENABLE_KV_POOL=0
#   KV_TRANSFER_CONFIG_POOL  # ENABLE_KV_POOL=1
# Or a final:
#   KV_TRANSFER_CONFIG       # used as-is if already set
#
# Placeholders substituted at launch time:
#   __KV_ROLE__  __KV_PORT__  __ENGINE_ID__
#
# Usage:
#   build_kv_transfer_config <kv_role> <kv_port>
#   -> prints JSON to stdout

_substitute_kv_placeholders() {
    local json="$1"
    local kv_role="$2"
    local kv_port="$3"
    local engine_id="$4"
    json="${json//__KV_ROLE__/${kv_role}}"
    json="${json//__KV_PORT__/${kv_port}}"
    json="${json//__ENGINE_ID__/${engine_id}}"
    # Also accept ${KV_ROLE} style if someone prefers shell-like tokens in files
    json="${json//\$\{KV_ROLE\}/${kv_role}}"
    json="${json//\$\{KV_PORT\}/${kv_port}}"
    json="${json//\$\{ENGINE_ID\}/${engine_id}}"
    printf '%s' "${json}"
}

build_kv_transfer_config() {
    local kv_role="${1:?kv_role required}"
    local kv_port="${2:?kv_port required}"
    local engine_id="0"
    local enable_pool="${ENABLE_KV_POOL:-0}"
    local raw=""

    case "${kv_role}" in
        kv_producer|prefill) engine_id="1" ;;
        kv_consumer|decode)  engine_id="2" ;;
        *) engine_id="${DP_RANK:-0}" ;;
    esac

    if [[ -n "${KV_TRANSFER_CONFIG:-}" ]]; then
        raw="${KV_TRANSFER_CONFIG}"
    elif [[ "${enable_pool}" == "1" || "${enable_pool}" == "true" || "${enable_pool}" == "yes" ]]; then
        raw="${KV_TRANSFER_CONFIG_POOL:-}"
        if [[ -z "${raw}" ]]; then
            echo "[kv_transfer_config] ENABLE_KV_POOL=1 but KV_TRANSFER_CONFIG_POOL is empty" >&2
            return 1
        fi
    else
        raw="${KV_TRANSFER_CONFIG_PD:-}"
        if [[ -z "${raw}" ]]; then
            echo "[kv_transfer_config] KV_TRANSFER_CONFIG_PD is empty" >&2
            return 1
        fi
    fi

    _substitute_kv_placeholders "${raw}" "${kv_role}" "${kv_port}" "${engine_id}"
    echo
}

is_kv_pool_enabled() {
    case "${ENABLE_KV_POOL:-0}" in
        1|true|yes|YES|TRUE) return 0 ;;
        *) return 1 ;;
    esac
}

is_layerwise_connector() {
    case "${PD_KV_CONNECTOR:-MooncakeConnectorV1}" in
        *Layerwise*|*layerwise*) return 0 ;;
        *) return 1 ;;
    esac
}
