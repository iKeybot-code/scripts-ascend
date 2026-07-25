#!/bin/bash
# Unified entry for all PD scenarios.
#
# Usage:
#   bash entry.sh <configs.sh> <action> [args...]
#
# Actions:
#   mooncake_master | proxy | prefill | decode | test

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <configs.sh> <mooncake_master|proxy|prefill|decode|test> [args...]" >&2
    exit 1
fi

CONFIGS_ARG="$1"
shift
ACTION="$1"
shift || true

if [[ "${CONFIGS_ARG}" != /* ]]; then
    CONFIGS_ARG="$(cd "$(dirname "${CONFIGS_ARG}")" && pwd)/$(basename "${CONFIGS_ARG}")"
fi
export CONFIGS_FILE="${CONFIGS_ARG}"

# Bootstrap COMMON_DIR (prefer shared mount) before sourcing full configs.
_ENTRY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_COMMON_DIR="${SHARED_COMMON_DIR:-/mnt/a800_share/l00848175/scripts-ascend/example/common}"
if [[ -d "${SHARED_COMMON_DIR}" ]]; then
    COMMON_BOOT="${SHARED_COMMON_DIR}"
else
    COMMON_BOOT="${_ENTRY_DIR}"
fi

# shellcheck disable=SC1091
source "${COMMON_BOOT}/load_configs.sh"

case "${ACTION}" in
    mooncake_master)
        exec bash "${COMMON_DIR}/start_mooncake_master.sh" "$@"
        ;;
    proxy)
        exec bash "${COMMON_DIR}/start_proxy.sh" "$@"
        ;;
    prefill|p)
        exec bash "${COMMON_DIR}/start_prefill.sh" "$@"
        ;;
    decode|d)
        exec bash "${COMMON_DIR}/start_decode.sh" "$@"
        ;;
    test|curl)
        exec bash "${COMMON_DIR}/test_curl.sh" "$@"
        ;;
    *)
        echo "[entry] unknown action: ${ACTION}" >&2
        echo "  expected: mooncake_master|proxy|prefill|decode|test" >&2
        exit 1
        ;;
esac
