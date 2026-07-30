#!/bin/bash
# Shared-directory multi-machine entry.
# Same command on every node; machine identity comes from configs.sh IP lists
# or explicit --node-index / --node-ip.
#
#   bash run.sh topology
#   bash run.sh mooncake_master
#   bash run.sh prefill                  # auto by local IP
#   bash run.sh prefill --node-ip x.x.x.x
#   bash run.sh decode
#   bash run.sh proxy
#   bash run.sh test

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_FILE="${SCRIPT_DIR}/configs.sh"

if [[ $# -lt 1 ]]; then
    cat <<'EOF' >&2
Usage: bash run.sh <role> [args...]

Shared-dir multi-machine:
  - Use the SAME configs.sh/run.sh on every node (shared mount).
  - Differentiate nodes via IP-aligned lists in configs.sh, and/or:
      bash run.sh prefill|decode [--node-index N | --node-ip IP]
      NODE_IP=<ip> bash run.sh prefill|decode

Roles:
  topology                 Print plan + validate IP-aligned topology
  mooncake_master          Start Mooncake master (KV pool)
  prefill [selector]       Start Prefill on this machine
  decode  [selector]       Start Decode on this machine
  proxy                    Start PD proxy
  test                     AISBench GSM8K top10

Examples:
  bash run.sh topology
  bash run.sh prefill
  bash run.sh prefill 1
  bash run.sh prefill --node-ip 90.90.97.28
  bash run.sh decode
  bash run.sh proxy
EOF
    exit 1
fi

# shellcheck disable=SC1091
source "${CONFIGS_FILE}"
exec bash "${COMMON_DIR}/entry.sh" "${CONFIGS_FILE}" "$@"
