#!/bin/bash
# Usage: bash run.sh <mooncake_master|proxy|prefill|decode|test> [args...]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_FILE="${SCRIPT_DIR}/configs.sh"
# shellcheck disable=SC1091
source "${CONFIGS_FILE}"
exec bash "${COMMON_DIR}/entry.sh" "${CONFIGS_FILE}" "$@"
