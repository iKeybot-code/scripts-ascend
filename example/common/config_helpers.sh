#!/bin/bash
# Shared helpers used by scenario configs.sh files.

bootstrap_common_dir() {
    local example_dir="$1"
    export SHARED_COMMON_DIR="${SHARED_COMMON_DIR:-/mnt/a800_share/l00848175/scripts-ascend/example/common}"
    if [[ -d "${SHARED_COMMON_DIR}" ]]; then
        export COMMON_DIR="${SHARED_COMMON_DIR}"
    else
        export COMMON_DIR="${example_dir}/common"
    fi
}

resolve_node_meta() {
    local role="$1"
    local node_index="${2:-0}"
    local ip nic count

    case "${role}" in
        prefill|p|P)
            count=${#PREFILL_IPS[@]}
            ip="${PREFILL_IPS[${node_index}]:-}"
            nic="${PREFILL_NICS[${node_index}]:-}"
            role="prefill"
            ;;
        decode|d|D)
            count=${#DECODE_IPS[@]}
            ip="${DECODE_IPS[${node_index}]:-}"
            nic="${DECODE_NICS[${node_index}]:-}"
            role="decode"
            ;;
        *)
            echo "[configs] unknown role: ${role}" >&2
            return 1
            ;;
    esac

    if [[ -z "${ip}" || -z "${nic}" ]] || (( node_index < 0 || node_index >= count )); then
        echo "[configs] node_index ${node_index} out of range for ${role}" >&2
        return 1
    fi

    export CUR_ROLE="${role}"
    export CUR_NODE_INDEX="${node_index}"
    export CUR_IP="${ip}"
    export CUR_NIC="${nic}"
}
