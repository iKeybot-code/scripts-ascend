#!/bin/bash
# DeepSeek-V3.1 PD sample entry (common_v2).
#
# Shared-directory multi-machine:
#   Same command on every node; machine identity comes from configs_* IP lists
#   or explicit --node-index / --node-ip.
#
#   bash run.sh topology
#   bash run.sh mooncake_master          # only if ENABLE_KV_POOL=1
#   bash run.sh prefill                  # loads configs_prefill.sh
#   bash run.sh prefill --node-ip x.x.x.x
#   bash run.sh decode                   # loads configs_decode.sh
#   bash run.sh proxy                    # loads configs_common.sh
#   bash run.sh test

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
    cat <<'EOF' >&2
Usage: bash run.sh <role> [args...]

Shared-dir multi-machine:
  - Use the SAME scripts on every node (shared mount).
  - Differentiate nodes via IP-aligned lists in configs_common.sh, and/or:
      bash run.sh prefill|decode [--node-index N | --node-ip IP]
      NODE_IP=<ip> bash run.sh prefill|decode

Roles:
  topology                 Print plan + validate IP-aligned topology
  mooncake_master          Start Mooncake master (KV pool)
  prefill [selector]       Start Prefill (configs_prefill.sh)
  decode  [selector]       Start Decode  (configs_decode.sh)
  proxy                    Start PD proxy
  test                     AISBench GSM8K top10

Examples:
  bash run.sh topology
  bash run.sh prefill
  bash run.sh prefill 1
  bash run.sh prefill --node-ip 90.90.97.37
  bash run.sh decode
  bash run.sh proxy
EOF
    exit 1
fi

ROLE="$1"
case "${ROLE}" in
    prefill|p|P)
        CONFIGS_FILE="${SCRIPT_DIR}/configs_prefill.sh"
        ;;
    decode|d|D)
        CONFIGS_FILE="${SCRIPT_DIR}/configs_decode.sh"
        ;;
    mooncake_master|proxy|test|curl|topology|topo|plan)
        CONFIGS_FILE="${SCRIPT_DIR}/configs_common.sh"
        ;;
    *)
        echo "[run.sh] unknown role: ${ROLE}" >&2
        echo "  expected: topology|mooncake_master|prefill|decode|proxy|test" >&2
        exit 1
        ;;
esac

# shellcheck disable=SC1091
source "${CONFIGS_FILE}"
exec bash "${COMMON_DIR}/entry.sh" "${CONFIGS_FILE}" "$@"
