#!/bin/bash
# Unified scenario entry (minimal args).
#
# Usage:
#   bash run.sh mooncake_master
#   bash run.sh prefill [node_index]
#   bash run.sh decode  [node_index]
#   bash run.sh proxy
#   bash run.sh test
#
# node_index defaults to 0 when omitted.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_FILE="${SCRIPT_DIR}/configs.sh"

if [[ $# -lt 1 ]]; then
    cat <<'EOF' >&2
Usage: bash run.sh <role> [args...]

Roles:
  mooncake_master          Start Mooncake master (KV pool)
  prefill [node_index]     Start Prefill on node (default node_index=0)
  decode  [node_index]     Start Decode on node (default node_index=0)
  proxy                    Start PD proxy
  test                     Run AISBench GSM8K top10 accuracy

Examples:
  bash run.sh mooncake_master
  bash run.sh prefill 0
  bash run.sh decode 0
  bash run.sh proxy
  bash run.sh test
EOF
    exit 1
fi

# shellcheck disable=SC1091
source "${CONFIGS_FILE}"
exec bash "${COMMON_DIR}/entry.sh" "${CONFIGS_FILE}" "$@"
