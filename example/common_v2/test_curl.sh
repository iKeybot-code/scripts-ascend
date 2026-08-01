#!/bin/bash
# Run AISBench GSM8K accuracy on the first 10 samples via the PD proxy.
#
# Usage:
#   CONFIGS_FILE=.../configs.sh bash test_curl.sh
#
# Requires:
#   - CONFIGS_FILE
#   - ais_bench installed and on PATH
#   - GSM8K dataset available at ais_bench/datasets/gsm8k (relative to aisbench root)

set -euo pipefail

COMMON_DIR_BOOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${COMMON_DIR_BOOT}/load_configs.sh"

CASE_NAME="${AISBENCH_CASE_NAME:-pd_gsm8k_acc_top10}"
MAX_OUT_LEN="${AISBENCH_MAX_OUT_LEN:-512}"
BATCH_SIZE="${AISBENCH_BATCH_SIZE:-1}"
TEST_RANGE="${GSM8K_TEST_RANGE:-[0:10]}"
WORK_DIR="${AISBENCH_WORK_DIR:-${LOG_DIR}/aisbench_gsm8k}"
CFG_SRC_DIR="${COMMON_DIR}/aisbench_configs"

if ! command -v ais_bench >/dev/null 2>&1; then
    echo "[test_aisbench] ais_bench not found in PATH. Install AISBench first." >&2
    exit 1
fi

AIS_BENCH_CONFIGS_DIR="$(
    python - <<'PY'
import os
import ais_bench.benchmark
print(os.path.join(os.path.dirname(ais_bench.benchmark.__file__), "configs"))
PY
)"

if [[ ! -d "${AIS_BENCH_CONFIGS_DIR}" ]]; then
    echo "[test_aisbench] cannot resolve ais_bench configs dir: ${AIS_BENCH_CONFIGS_DIR}" >&2
    exit 1
fi

if [[ ! -f "${CFG_SRC_DIR}/datasets/gsm8k/${CASE_NAME}.py" || ! -f "${CFG_SRC_DIR}/models/vllm_api/${CASE_NAME}.py" ]]; then
    echo "[test_aisbench] missing case configs under ${CFG_SRC_DIR}" >&2
    exit 1
fi

mkdir -p "${WORK_DIR}"
mkdir -p "${AIS_BENCH_CONFIGS_DIR}/datasets/gsm8k"
mkdir -p "${AIS_BENCH_CONFIGS_DIR}/models/vllm_api"

echo "[test_aisbench] install case configs -> ${AIS_BENCH_CONFIGS_DIR}"
cp -f "${CFG_SRC_DIR}/datasets/gsm8k/${CASE_NAME}.py" \
    "${AIS_BENCH_CONFIGS_DIR}/datasets/gsm8k/${CASE_NAME}.py"
cp -f "${CFG_SRC_DIR}/models/vllm_api/${CASE_NAME}.py" \
    "${AIS_BENCH_CONFIGS_DIR}/models/vllm_api/${CASE_NAME}.py"

DATASET_CFG="${AIS_BENCH_CONFIGS_DIR}/datasets/gsm8k/${CASE_NAME}.py"
MODEL_CFG="${AIS_BENCH_CONFIGS_DIR}/models/vllm_api/${CASE_NAME}.py"

# Override runtime fields from scenario configs.
{
    echo ""
    echo "gsm8k_datasets[0]['reader_cfg']['test_range'] = '${TEST_RANGE}'"
} >> "${DATASET_CFG}"

{
    echo ""
    echo "models[0]['host_ip'] = '${PROXY_HOST}'"
    echo "models[0]['host_port'] = ${PROXY_PORT}"
    echo "models[0]['model'] = '${MODEL_NAME}'"
    echo "models[0]['path'] = '${MODEL_PATH}'"
    echo "models[0]['max_out_len'] = ${MAX_OUT_LEN}"
    echo "models[0]['batch_size'] = ${BATCH_SIZE}"
} >> "${MODEL_CFG}"

LOG_FILE="${WORK_DIR}/aisbench_${CASE_NAME}_$(date '+%m%d%H%M%S').log"
echo "[test_aisbench] target=http://${PROXY_HOST}:${PROXY_PORT} model=${MODEL_NAME}"
echo "[test_aisbench] case=${CASE_NAME} test_range=${TEST_RANGE}"
echo "[test_aisbench] work_dir=${WORK_DIR}"
echo "[test_aisbench] log=${LOG_FILE}"

set -o pipefail
ais_bench \
    --models "${CASE_NAME}" \
    --datasets "${CASE_NAME}" \
    --work-dir "${WORK_DIR}" \
    2>&1 | tee "${LOG_FILE}"

# Parse exp folder from log (ais_bench prints: Current exp folder: ...)
EXP_DIR="$(
    grep -E 'Current exp folder:' "${LOG_FILE}" | tail -n 1 | awk -F': ' '{print $NF}' | tr -d '\r' || true
)"
if [[ -z "${EXP_DIR}" || ! -d "${EXP_DIR}" ]]; then
    EXP_DIR="$(ls -1dt "${WORK_DIR}"/*/ 2>/dev/null | head -n 1 || true)"
fi

LATEST_SUMMARY=""
LATEST_RESULT=""
if [[ -n "${EXP_DIR}" && -d "${EXP_DIR}" ]]; then
    LATEST_SUMMARY="$(ls -1t "${EXP_DIR}"/summary/summary_*.csv 2>/dev/null | head -n 1 || true)"
    LATEST_RESULT="$(ls -1t "${EXP_DIR}"/results/*/*.json 2>/dev/null | head -n 1 || true)"
fi

echo
echo "========== AISBench GSM8K top10 finished =========="
echo "[test_aisbench] exp_dir=${EXP_DIR:-N/A}"
if [[ -n "${LATEST_SUMMARY}" ]]; then
    echo "[test_aisbench] summary: ${LATEST_SUMMARY}"
    cat "${LATEST_SUMMARY}"
fi
if [[ -n "${LATEST_RESULT}" ]]; then
    echo "[test_aisbench] result: ${LATEST_RESULT}"
    python - <<PY
import json
from pathlib import Path
path = Path(r"""${LATEST_RESULT}""")
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"[test_aisbench] failed to read result json: {exc}")
    raise SystemExit(0)

def dump_scores(obj, prefix=""):
    if isinstance(obj, dict):
        for k, v in obj.items():
            key = f"{prefix}{k}" if not prefix else f"{prefix}.{k}"
            if isinstance(v, (int, float, str)) and any(
                x in str(k).lower() for x in ("acc", "score", "exact", "accuracy")
            ):
                print(f"[test_aisbench] {key} = {v}")
            elif isinstance(v, (dict, list)):
                dump_scores(v, key)
    elif isinstance(obj, list):
        for i, item in enumerate(obj[:5]):
            dump_scores(item, f"{prefix}[{i}]")

dump_scores(data)
print("[test_aisbench] done")
PY
fi
echo "==================================================="
