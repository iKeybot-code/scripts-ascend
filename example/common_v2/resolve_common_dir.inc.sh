#!/bin/bash
# Resolve COMMON_DIR for a scenario directory.
# Intended to be inlined/copied OR sourced when already reachable.
#
# Priority:
#   1) COMMON_DIR (explicit export)
#   2) SHARED_COMMON_DIR (default shared mount)
#   3) <scenario>/../common   (original example layout)
#   4) <scenario>/common      (scenario + common copied as a pair)

resolve_common_dir() {
    local scenario_dir="${1:?scenario dir required}"
    local shared_default="/mnt/a800_share/l00848175/scripts-ascend/example/common_v2"
    export SHARED_COMMON_DIR="${SHARED_COMMON_DIR:-${shared_default}}"

    if [[ -n "${COMMON_DIR:-}" && -d "${COMMON_DIR}" && -f "${COMMON_DIR}/config_helpers.sh" ]]; then
        export COMMON_DIR="$(cd "${COMMON_DIR}" && pwd)"
        return 0
    fi

    if [[ -d "${SHARED_COMMON_DIR}" && -f "${SHARED_COMMON_DIR}/config_helpers.sh" ]]; then
        export COMMON_DIR="$(cd "${SHARED_COMMON_DIR}" && pwd)"
        return 0
    fi

    if [[ -f "${scenario_dir}/../common_v2/config_helpers.sh" ]]; then
        export COMMON_DIR="$(cd "${scenario_dir}/../common_v2" && pwd)"
        return 0
    fi

    if [[ -f "${scenario_dir}/../../common_v2/config_helpers.sh" ]]; then
        export COMMON_DIR="$(cd "${scenario_dir}/../../common_v2" && pwd)"
        return 0
    fi

    if [[ -f "${scenario_dir}/common_v2/config_helpers.sh" ]]; then
        export COMMON_DIR="$(cd "${scenario_dir}/common_v2" && pwd)"
        return 0
    fi

    echo "[resolve_common_dir] cannot locate common_v2/" >&2
    echo "  Options:" >&2
    echo "    export COMMON_DIR=/path/to/common_v2" >&2
    echo "    export SHARED_COMMON_DIR=/path/to/common_v2" >&2
    echo "    keep ../common_v2 next to the scenario" >&2
    return 1
}
