#!/bin/bash
# Build --kv-transfer-config JSON from scenario settings.
# Requires configs.sh already sourced:
#   ENABLE_KV_POOL, PD_KV_CONNECTOR, KV_POOL_BACKEND, KV_LOAD_FAILURE_POLICY,
#   P_DP_SIZE, P_TP_SIZE, D_DP_SIZE, D_TP_SIZE
#
# Usage:
#   build_kv_transfer_config <kv_role> <kv_port>
#   -> prints JSON to stdout

build_kv_transfer_config() {
    local kv_role="${1:?kv_role required}"
    local kv_port="${2:?kv_port required}"
    local engine_id="${2:?kv_port required}"
    local pd_connector="${PD_KV_CONNECTOR:-MooncakeConnectorV1}"
    local enable_pool="${ENABLE_KV_POOL:-0}"
    local pool_backend="${KV_POOL_BACKEND:-mooncake}"
    local load_policy="${KV_LOAD_FAILURE_POLICY:-recompute}"
    local lookup_port="${KV_POOL_LOOKUP_RPC_PORT:-0}"

    local engine_id="0"

    case "$kv_role" in
        kv_producer|prefill)
            engine_id="1"
            ;;
        kv_consumer|decode)
            engine_id="2"
            ;;
        *)
            engine_id="${DP_RANK}"
            ;;
    esac

    local pd_block
    pd_block=$(cat <<EOF
{
  "kv_connector": "${pd_connector}",
  "kv_role": "${kv_role}",
  "kv_port": "${kv_port}",
  "engine_id": "${engine_id}",
  "kv_connector_extra_config": {
    "prefill": {
      "dp_size": ${P_DP_SIZE},
      "tp_size": ${P_TP_SIZE}
    },
    "decode": {
      "dp_size": ${D_DP_SIZE},
      "tp_size": ${D_TP_SIZE}
    }
  }
}
EOF
)

    if [[ "${enable_pool}" == "1" || "${enable_pool}" == "true" || "${enable_pool}" == "yes" ]]; then
        cat <<EOF
{
  "kv_connector": "MultiConnector",
  "kv_role": "${kv_role}",
  "kv_load_failure_policy": "${load_policy}",
  "kv_connector_extra_config": {
    "connectors": [
      ${pd_block},
      {
        "kv_connector": "AscendStoreConnector",
        "kv_role": "${kv_role}",
        "kv_connector_extra_config": {
          "lookup_rpc_port": "${lookup_port}",
          "backend": "${pool_backend}"
        }
      }
    ]
  }
}
EOF
    else
        echo "${pd_block}"
    fi
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
