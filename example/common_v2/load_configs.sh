#!/bin/bash
# Source scenario configs. Requires CONFIGS_FILE.
#
# Usage:
#   export CONFIGS_FILE=/path/to/scenario/configs.sh
#   source /path/to/common/load_configs.sh

if [[ -z "${CONFIGS_FILE:-}" ]]; then
    echo "[load_configs] CONFIGS_FILE is not set" >&2
    return 1 2>/dev/null || exit 1
fi

if [[ ! -f "${CONFIGS_FILE}" ]]; then
    echo "[load_configs] configs not found: ${CONFIGS_FILE}" >&2
    return 1 2>/dev/null || exit 1
fi

# shellcheck disable=SC1090
source "${CONFIGS_FILE}"

if [[ -z "${COMMON_DIR:-}" ]]; then
    echo "[load_configs] COMMON_DIR missing after sourcing configs" >&2
    return 1 2>/dev/null || exit 1
fi
