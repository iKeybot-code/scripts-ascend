#!/bin/bash
# Shared helpers for multi-node PD on a shared filesystem.
#
# Design:
# - The same configs.sh / run.sh are used on every machine (shared mount).
# - Machine differences come from:
#     1) IP-aligned arrays in configs.sh (IPS/NICS/devices/ports)
#     2) CLI/env selectors: node_index / --node-ip / NODE_IP
# - Default: auto-select node by matching local IPs to PREFILL_IPS/DECODE_IPS.

list_local_ips() {
    local ips=""
    if command -v hostname >/dev/null 2>&1; then
        ips="$(hostname -I 2>/dev/null || true)"
    fi
    if [[ -z "${ips}" ]] && command -v ip >/dev/null 2>&1; then
        ips="$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | tr '\n' ' ')"
    fi
    # Optional explicit override used as a candidate match source.
    if [[ -n "${NODE_IP:-}" ]]; then
        ips="${NODE_IP} ${ips}"
    fi
    echo "${ips}"
}

find_index_in_list() {
    # find_index_in_list <needle> <elem0> <elem1> ...
    local needle="$1"
    shift
    local i=0
    local elem
    for elem in "$@"; do
        if [[ "${elem}" == "${needle}" ]]; then
            echo "${i}"
            return 0
        fi
        i=$((i + 1))
    done
    return 1
}

detect_node_index_by_ip() {
    # Usage: detect_node_index_by_ip prefill|decode [explicit_ip]
    local role="$1"
    local explicit_ip="${2:-}"
    local -a ips=()
    local i ip local_ips

    case "${role}" in
        prefill|p|P) ips=("${PREFILL_IPS[@]}") ;;
        decode|d|D) ips=("${DECODE_IPS[@]}") ;;
        *)
            echo "[configs] unknown role for detect: ${role}" >&2
            return 1
            ;;
    esac

    if [[ -n "${explicit_ip}" ]]; then
        if idx="$(find_index_in_list "${explicit_ip}" "${ips[@]}")"; then
            echo "${idx}"
            return 0
        fi
        echo "[configs] --node-ip/${NODE_IP} '${explicit_ip}' not found in ${role} IPS: ${ips[*]}" >&2
        return 1
    fi

    local_ips="$(list_local_ips)"
    for i in "${!ips[@]}"; do
        ip="${ips[$i]}"
        if [[ -n "${ip}" && " ${local_ips} " == *" ${ip} "* ]]; then
            echo "${i}"
            return 0
        fi
    done
    return 1
}

# Parse role CLI args into SEL_NODE_INDEX / SEL_NODE_IP.
# Accepts:
#   [node_index|auto]
#   --node-index N | -n N
#   --node-ip IP
# Env fallbacks: NODE_INDEX, NODE_IP
parse_role_args() {
    SEL_NODE_INDEX="${NODE_INDEX:-}"
    SEL_NODE_IP="${NODE_IP:-}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --node-ip)
                [[ $# -ge 2 ]] || { echo "[args] --node-ip needs a value" >&2; return 1; }
                SEL_NODE_IP="$2"
                shift 2
                ;;
            --node-index|--index|-n)
                [[ $# -ge 2 ]] || { echo "[args] $1 needs a value" >&2; return 1; }
                SEL_NODE_INDEX="$2"
                shift 2
                ;;
            auto)
                SEL_NODE_INDEX="auto"
                shift
                ;;
            -h|--help)
                cat <<'EOF' >&2
Node selector (shared-dir multi-machine):
  bash run.sh prefill                  # auto by local IP vs PREFILL_IPS
  bash run.sh prefill 1                # explicit node_index
  bash run.sh prefill --node-index 1
  bash run.sh prefill --node-ip 90.90.97.28
  NODE_IP=90.90.97.28 bash run.sh prefill
EOF
                return 2
                ;;
            *)
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    SEL_NODE_INDEX="$1"
                    shift
                else
                    echo "[args] unknown argument: $1" >&2
                    return 1
                fi
                ;;
        esac
    done
}

resolve_node_meta() {
    local role="$1"
    local node_index="${2:-}"
    local explicit_ip="${3:-}"
    local ip nic count

    case "${role}" in
        prefill|p|P)
            count=${#PREFILL_IPS[@]}
            role="prefill"
            ;;
        decode|d|D)
            count=${#DECODE_IPS[@]}
            role="decode"
            ;;
        *)
            echo "[configs] unknown role: ${role}" >&2
            return 1
            ;;
    esac

    # Priority: explicit index > explicit IP > auto local IP
    if [[ -n "${node_index}" && "${node_index}" != "auto" ]]; then
        :
    elif [[ -n "${explicit_ip}" ]]; then
        if ! node_index="$(detect_node_index_by_ip "${role}" "${explicit_ip}")"; then
            return 1
        fi
        echo "[configs] selected ${role} node_index=${node_index} by node_ip=${explicit_ip}" >&2
    else
        if ! node_index="$(detect_node_index_by_ip "${role}")"; then
            echo "[configs] cannot auto-detect ${role} node_index from local IP." >&2
            echo "  local_ips: $(list_local_ips)" >&2
            if [[ "${role}" == "prefill" ]]; then
                echo "  configured PREFILL_IPS: ${PREFILL_IPS[*]}" >&2
            else
                echo "  configured DECODE_IPS: ${DECODE_IPS[*]}" >&2
            fi
            echo "  Use: bash run.sh ${role} <node_index>  OR  --node-ip <ip>" >&2
            return 1
        fi
        echo "[configs] auto node_index=${node_index} for role=${role} (shared-dir / same script)" >&2
    fi

    if [[ "${role}" == "prefill" ]]; then
        ip="${PREFILL_IPS[${node_index}]:-}"
        nic="${PREFILL_NICS[${node_index}]:-}"
    else
        ip="${DECODE_IPS[${node_index}]:-}"
        nic="${DECODE_NICS[${node_index}]:-}"
    fi

    if [[ -z "${ip}" || -z "${nic}" ]] || (( node_index < 0 || node_index >= count )); then
        echo "[configs] node_index ${node_index} out of range for ${role} (count=${count})" >&2
        return 1
    fi

    export CUR_ROLE="${role}"
    export CUR_NODE_INDEX="${node_index}"
    export CUR_IP="${ip}"
    export CUR_NIC="${nic}"

    # Per-node optional overrides (index-aligned with *_IPS). Empty => global default / auto.
    P_NODE_VISIBLE_DEVICES=("${P_NODE_VISIBLE_DEVICES[@]+"${P_NODE_VISIBLE_DEVICES[@]}"}")
    D_NODE_VISIBLE_DEVICES=("${D_NODE_VISIBLE_DEVICES[@]+"${D_NODE_VISIBLE_DEVICES[@]}"}")
    P_NODE_HTTP_PORT=("${P_NODE_HTTP_PORT[@]+"${P_NODE_HTTP_PORT[@]}"}")
    D_NODE_HTTP_PORT=("${D_NODE_HTTP_PORT[@]+"${D_NODE_HTTP_PORT[@]}"}")
    P_NODE_KV_PORT_BASE=("${P_NODE_KV_PORT_BASE[@]+"${P_NODE_KV_PORT_BASE[@]}"}")
    D_NODE_KV_PORT_BASE=("${D_NODE_KV_PORT_BASE[@]+"${D_NODE_KV_PORT_BASE[@]}"}")
    P_VISIBLE_DEVICES_LIST=("${P_VISIBLE_DEVICES_LIST[@]+"${P_VISIBLE_DEVICES_LIST[@]}"}")
    D_VISIBLE_DEVICES_LIST=("${D_VISIBLE_DEVICES_LIST[@]+"${D_VISIBLE_DEVICES_LIST[@]}"}")

    if [[ "${role}" == "prefill" ]]; then
        export CUR_HTTP_PORT="${P_NODE_HTTP_PORT[${node_index}]:-${P_VLLM_START_PORT}}"
        export CUR_KV_PORT_BASE="${P_NODE_KV_PORT_BASE[${node_index}]:-${P_KV_PORT_BASE}}"
        if (( ${#P_NODE_VISIBLE_DEVICES[@]} > 0 )); then
            export CUR_VISIBLE_LIST="${P_NODE_VISIBLE_DEVICES[${node_index}]:-}"
        elif (( ${#P_VISIBLE_DEVICES_LIST[@]} > 0 )); then
            local _old="$IFS"
            IFS=";"
            export CUR_VISIBLE_LIST="${P_VISIBLE_DEVICES_LIST[*]}"
            IFS="${_old}"
        else
            export CUR_VISIBLE_LIST=""
        fi
    else
        export CUR_HTTP_PORT="${D_NODE_HTTP_PORT[${node_index}]:-${D_VLLM_START_PORT}}"
        export CUR_KV_PORT_BASE="${D_NODE_KV_PORT_BASE[${node_index}]:-${D_KV_PORT_BASE}}"
        if (( ${#D_NODE_VISIBLE_DEVICES[@]} > 0 )); then
            export CUR_VISIBLE_LIST="${D_NODE_VISIBLE_DEVICES[${node_index}]:-}"
        elif (( ${#D_VISIBLE_DEVICES_LIST[@]} > 0 )); then
            local _old="$IFS"
            IFS=";"
            export CUR_VISIBLE_LIST="${D_VISIBLE_DEVICES_LIST[*]}"
            IFS="${_old}"
        else
            export CUR_VISIBLE_LIST=""
        fi
    fi
}

setup_node_log_dir() {
    # Keep logs separated per machine when scripts live on a shared filesystem.
    local base="${LOG_DIR_BASE:-${LOG_DIR:-./logs}}"
    local host_tag
    host_tag="$(hostname 2>/dev/null || echo host)"
    export LOG_DIR="${base}/${CUR_ROLE:-node}${CUR_NODE_INDEX:-X}_${CUR_IP:-${host_tag}}_$(date '+%y%m%d')"
    mkdir -p "${LOG_DIR}"
}

validate_pd_topology() {
    # Tolerate unset optional per-node arrays under `set -u`.
    P_NODE_VISIBLE_DEVICES=("${P_NODE_VISIBLE_DEVICES[@]+"${P_NODE_VISIBLE_DEVICES[@]}"}")
    D_NODE_VISIBLE_DEVICES=("${D_NODE_VISIBLE_DEVICES[@]+"${D_NODE_VISIBLE_DEVICES[@]}"}")
    P_NODE_HTTP_PORT=("${P_NODE_HTTP_PORT[@]+"${P_NODE_HTTP_PORT[@]}"}")
    D_NODE_HTTP_PORT=("${D_NODE_HTTP_PORT[@]+"${D_NODE_HTTP_PORT[@]}"}")
    P_NODE_KV_PORT_BASE=("${P_NODE_KV_PORT_BASE[@]+"${P_NODE_KV_PORT_BASE[@]}"}")
    D_NODE_KV_PORT_BASE=("${D_NODE_KV_PORT_BASE[@]+"${D_NODE_KV_PORT_BASE[@]}"}")
    P_VISIBLE_DEVICES_LIST=("${P_VISIBLE_DEVICES_LIST[@]+"${P_VISIBLE_DEVICES_LIST[@]}"}")
    D_VISIBLE_DEVICES_LIST=("${D_VISIBLE_DEVICES_LIST[@]+"${D_VISIBLE_DEVICES_LIST[@]}"}")

    local p_nodes=${#PREFILL_IPS[@]}
    local d_nodes=${#DECODE_IPS[@]}
    local p_nics=${#PREFILL_NICS[@]}
    local d_nics=${#DECODE_NICS[@]}
    local ok=0

    if (( p_nodes < 1 || d_nodes < 1 )); then
        echo "[topology] PREFILL_IPS/DECODE_IPS must be non-empty" >&2
        ok=1
    fi
    if (( p_nodes != p_nics || d_nodes != d_nics )); then
        echo "[topology] IPS/NICS length mismatch (P:${p_nodes}/${p_nics}, D:${d_nodes}/${d_nics})" >&2
        ok=1
    fi

    local expect_p=$((p_nodes * P_DP_SIZE_LOCAL))
    local expect_d=$((d_nodes * D_DP_SIZE_LOCAL))
    if (( P_DP_SIZE != expect_p )); then
        echo "[topology] P_DP_SIZE(${P_DP_SIZE}) != #P_nodes(${p_nodes}) * P_DP_SIZE_LOCAL(${P_DP_SIZE_LOCAL}) = ${expect_p}" >&2
        ok=1
    fi
    if (( D_DP_SIZE != expect_d )); then
        echo "[topology] D_DP_SIZE(${D_DP_SIZE}) != #D_nodes(${d_nodes}) * D_DP_SIZE_LOCAL(${D_DP_SIZE_LOCAL}) = ${expect_d}" >&2
        ok=1
    fi

    if (( ${#P_VISIBLE_DEVICES_LIST[@]} > 0 && ${#P_VISIBLE_DEVICES_LIST[@]} != P_DP_SIZE_LOCAL )); then
        echo "[topology] P_VISIBLE_DEVICES_LIST length must be 0(auto) or P_DP_SIZE_LOCAL(${P_DP_SIZE_LOCAL})" >&2
        ok=1
    fi
    if (( ${#D_VISIBLE_DEVICES_LIST[@]} > 0 && ${#D_VISIBLE_DEVICES_LIST[@]} != D_DP_SIZE_LOCAL )); then
        echo "[topology] D_VISIBLE_DEVICES_LIST length must be 0(auto) or D_DP_SIZE_LOCAL(${D_DP_SIZE_LOCAL})" >&2
        ok=1
    fi
    if (( ${#P_NODE_VISIBLE_DEVICES[@]} > 0 && ${#P_NODE_VISIBLE_DEVICES[@]} != p_nodes )); then
        echo "[topology] P_NODE_VISIBLE_DEVICES length must be 0 or #PREFILL_IPS(${p_nodes})" >&2
        ok=1
    fi
    if (( ${#D_NODE_VISIBLE_DEVICES[@]} > 0 && ${#D_NODE_VISIBLE_DEVICES[@]} != d_nodes )); then
        echo "[topology] D_NODE_VISIBLE_DEVICES length must be 0 or #DECODE_IPS(${d_nodes})" >&2
        ok=1
    fi
    if (( ${#P_NODE_HTTP_PORT[@]} > 0 && ${#P_NODE_HTTP_PORT[@]} != p_nodes )); then
        echo "[topology] P_NODE_HTTP_PORT length must be 0 or #PREFILL_IPS(${p_nodes})" >&2
        ok=1
    fi
    if (( ${#D_NODE_HTTP_PORT[@]} > 0 && ${#D_NODE_HTTP_PORT[@]} != d_nodes )); then
        echo "[topology] D_NODE_HTTP_PORT length must be 0 or #DECODE_IPS(${d_nodes})" >&2
        ok=1
    fi
    if (( ${#P_NODE_KV_PORT_BASE[@]} > 0 && ${#P_NODE_KV_PORT_BASE[@]} != p_nodes )); then
        echo "[topology] P_NODE_KV_PORT_BASE length must be 0 or #PREFILL_IPS(${p_nodes})" >&2
        ok=1
    fi
    if (( ${#D_NODE_KV_PORT_BASE[@]} > 0 && ${#D_NODE_KV_PORT_BASE[@]} != d_nodes )); then
        echo "[topology] D_NODE_KV_PORT_BASE length must be 0 or #DECODE_IPS(${d_nodes})" >&2
        ok=1
    fi

    return "${ok}"
}

print_pd_topology() {
    local i
    local local_ips
    local_ips="$(list_local_ips)"
    echo "========== PD Topology (shared-dir same script) =========="
    echo "Model: ${MODEL_NAME} (${MODEL_PATH})"
    echo "KV pool: ${ENABLE_KV_POOL:-0}  connector: ${PD_KV_CONNECTOR:-MooncakeConnectorV1}"
    echo "This host IPs: ${local_ips}"
    echo
    echo "How to differentiate machines:"
    echo "  1) Edit IP-aligned lists in configs.sh (IPS/NICS/devices/ports)"
    echo "  2) Or pass: bash run.sh prefill|decode [--node-index N | --node-ip IP]"
    echo
    echo "Prefill: nodes=${#PREFILL_IPS[@]}  DP=${P_DP_SIZE}  TP=${P_TP_SIZE}  local_DP=${P_DP_SIZE_LOCAL}"
    echo "  dp_address=${P_DP_ADDRESS}  rpc=${P_DP_RPC_PORT}  http_base=${P_VLLM_START_PORT}  kv_base=${P_KV_PORT_BASE}"
    for i in "${!PREFILL_IPS[@]}"; do
        echo "  [P${i}] ip=${PREFILL_IPS[$i]} nic=${PREFILL_NICS[$i]}"
        echo "         ranks $((i * P_DP_SIZE_LOCAL))..$((i * P_DP_SIZE_LOCAL + P_DP_SIZE_LOCAL - 1))"
        echo "         on that machine: bash run.sh prefill"
        echo "         or: bash run.sh prefill ${i}   /   bash run.sh prefill --node-ip ${PREFILL_IPS[$i]}"
        if (( ${#P_NODE_VISIBLE_DEVICES[@]} > 0 )); then
            echo "         devices: ${P_NODE_VISIBLE_DEVICES[$i]}"
        fi
    done
    echo
    echo "Decode: nodes=${#DECODE_IPS[@]}  DP=${D_DP_SIZE}  TP=${D_TP_SIZE}  local_DP=${D_DP_SIZE_LOCAL}"
    echo "  dp_address=${D_DP_ADDRESS}  rpc=${D_DP_RPC_PORT}  http_base=${D_VLLM_START_PORT}  kv_base=${D_KV_PORT_BASE}"
    for i in "${!DECODE_IPS[@]}"; do
        echo "  [D${i}] ip=${DECODE_IPS[$i]} nic=${DECODE_NICS[$i]}"
        echo "         ranks $((i * D_DP_SIZE_LOCAL))..$((i * D_DP_SIZE_LOCAL + D_DP_SIZE_LOCAL - 1))"
        echo "         on that machine: bash run.sh decode"
        echo "         or: bash run.sh decode ${i}   /   bash run.sh decode --node-ip ${DECODE_IPS[$i]}"
        if (( ${#D_NODE_VISIBLE_DEVICES[@]} > 0 )); then
            echo "         devices: ${D_NODE_VISIBLE_DEVICES[$i]}"
        fi
    done
    echo
    echo "Mooncake master: ${MOONCAKE_MASTER_IP}:${MOONCAKE_MASTER_PORT}  -> bash run.sh mooncake_master"
    echo "Proxy: ${PROXY_HOST}:${PROXY_PORT}  -> bash run.sh proxy"
    echo "Test: bash run.sh test"
    echo "Logs: \${LOG_DIR_BASE}/<role><idx>_<ip>/  (per-machine, safe on shared FS)"
    echo "==========================================================="
    validate_pd_topology || true
}
