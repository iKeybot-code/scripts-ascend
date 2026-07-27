#!/bin/bash
# Unified scenario entry (minimal args).
#
# Usage:
#   bash run.sh topology
#   bash run.sh mooncake_master
#   bash run.sh prefill [node_index|auto]
#   bash run.sh decode  [node_index|auto]
#   bash run.sh proxy
#   bash run.sh test

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_FILE="${SCRIPT_DIR}/configs.sh"

if [[ $# -lt 1 ]]; then
    cat <<'EOF' >&2
Usage: bash run.sh <role> [args...]

Roles:
  topology                 Print launch plan / validate topology
  mooncake_master          Start Mooncake master (KV pool)
  prefill [node_index]     Start Prefill (default: auto-detect by local IP)
  decode  [node_index]     Start Decode  (default: auto-detect by local IP)
  proxy                    Start PD proxy
  test                     Run AISBench GSM8K top10 accuracy
EOF
    exit 1
fi

# shellcheck disable=SC1091
source "${CONFIGS_FILE}"
exec bash "${COMMON_DIR}/entry.sh" "${CONFIGS_FILE}" "$@"
