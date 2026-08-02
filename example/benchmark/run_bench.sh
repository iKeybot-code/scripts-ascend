#!/bin/bash
# =============================================================================
# AISBench 统一评测入口脚本
#
# 用法:
#   bash run_bench.sh <数据集名> [选项]
#
# 支持的数据集: ceval | mmlu | gpqa | math500 | livecodebench | aime2024 | gsm8k | aime2026
#
# 选项:
#   -n, --num <N>        评测数据条数 (默认: 全部)
#   -m, --mode <MODE>    评测模式: all | acc | perf (默认: all)
#   -w, --work-dir <DIR> 结果输出目录 (默认: ./outputs)
#   -c, --config <FILE>  指定参数配置文件 (默认: 同级目录下的 config.sh)
#   --host <IP>          vLLM 服务 IP (覆盖 config.sh)
#   --port <PORT>        vLLM 服务端口 (覆盖 config.sh)
#   --model <NAME>       模型名称 (覆盖 config.sh)
#   --model-path <PATH>  模型路径 (覆盖 config.sh)
#   --max-out-len <N>    最大输出长度 (覆盖 config.sh)
#   --batch-size <N>     批次大小 (覆盖 config.sh)
#   --temperature <T>    推理温度 (覆盖 config.sh)
#   --extra-args <ARGS>  额外 ais_bench 参数 (覆盖 config.sh)
#   --list               列出所有支持的数据集及说明
#   --check              检查环境（ais_bench 是否安装、数据集是否存在）
#   -h, --help           显示帮助信息
#
# 示例:
#   bash run_bench.sh gsm8k -n 10                    # GSM8K 取前 10 条跑精度
#   bash run_bench.sh mmlu -m perf -n 100            # MMLU 取前 100 条跑性能
#   bash run_bench.sh ceval --host 192.168.1.1       # 指定 vLLM 地址
#   bash run_bench.sh math500 -n 50 -m acc           # MATH-500 取前 50 条跑精度
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- 数据集定义 ----
declare -A DATASET_TABLE=(
    ["ceval"]="C-Eval|ceval"
    ["mmlu"]="MMLU|mmlu"
    ["gpqa"]="GPQA|gpqa"
    ["math500"]="MATH-500|math500"
    ["livecodebench"]="LiveCodeBench|livecodebench"
    ["aime2024"]="AIME 2024|aime2024"
    ["gsm8k"]="GSM8K|gsm8k"
    ["aime2026"]="AIME 2026|aime2026"
)

# ---- 帮助信息 ----
print_help() {
    head -30 "${BASH_SOURCE[0]}" | sed -n '/^# =/,/^# ===/p' | grep '^#' | sed 's/^# \{0,1\}//'
    echo ""
    echo "支持的数据集:"
    for ds in "${!DATASET_TABLE[@]}"; do
        IFS='|' read -r label config_key <<< "${DATASET_TABLE[$ds]}"
        printf "  %-16s %s\n" "${ds}" "${label}"
    done
}

# ---- 列出数据集 ----
list_datasets() {
    echo "支持的数据集:"
    echo ""
    printf "  %-16s %-12s %s\n" "KEY" "LABEL" "DESCRIPTION"
    printf "  %-16s %-12s %s\n" "---" "-----" "-----------"
    for ds in "${!DATASET_TABLE[@]}"; do
        IFS='|' read -r label config_key <<< "${DATASET_TABLE[$ds]}"
        printf "  %-16s %-12s %s\n" "${ds}" "${label}" ""
    done
}

# ---- 环境检查 ----
check_env() {
    local errors=0

    echo "========== 环境检查 =========="

    # 检查 ais_bench
    if command -v ais_bench >/dev/null 2>&1; then
        echo "[OK] ais_bench 已安装: $(which ais_bench)"
    else
        echo "[FAIL] ais_bench 未安装。请执行: pip install -e ./ --use-pep517 (在 AISBench 仓库根目录)"
        ((errors++))
    fi

    # 检查 AISBench 数据集
    if command -v python >/dev/null 2>&1; then
        AIS_DATASETS_DIR="$(
            python -c "
import os
import ais_bench.benchmark
print(os.path.join(os.path.dirname(ais_bench.benchmark.__file__), '..', '..', 'datasets'))
" 2>/dev/null || echo ""
        )"
        if [[ -n "${AIS_DATASETS_DIR}" && -d "${AIS_DATASETS_DIR}" ]]; then
            echo "[OK] AISBench datasets 目录: ${AIS_DATASETS_DIR}"
            echo ""
            echo "各数据集下载状态:"
            for ds in "${!DATASET_TABLE[@]}"; do
                IFS='|' read -r label config_key <<< "${DATASET_TABLE[$ds]}"
                if [[ -d "${AIS_DATASETS_DIR}/${config_key}" ]] || ls "${AIS_DATASETS_DIR}/${config_key}"* >/dev/null 2>&1; then
                    echo "  [OK] ${label}"
                else
                    echo "  [MISS] ${label}"
                fi
            done
        else
            echo "[WARN] 无法确定 AISBench datasets 目录。请确认 AISBench 已正确安装。"
        fi
    fi

    # 检查 vLLM 服务连通性
    if command -v curl >/dev/null 2>&1; then
        if curl -s --max-time 3 "http://${VLLM_HOST}:${VLLM_PORT}/health" >/dev/null 2>&1; then
            echo "[OK] vLLM 服务可访问: http://${VLLM_HOST}:${VLLM_PORT}"
        else
            echo "[WARN] vLLM 服务不可访问: http://${VLLM_HOST}:${VLLM_PORT}"
        fi
    fi

    echo "==============================="
    return ${errors}
}

# ---- 解析命令行参数 ----
DATASET=""
NUM_SAMPLES=""
CONFIG_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_help
            exit 0
            ;;
        --list)
            list_datasets
            exit 0
            ;;
        --check)
            # 先尝试加载 config.sh
            _cfg="${SCRIPT_DIR}/config.sh"
            if [[ -f "${_cfg}" ]]; then
                # shellcheck disable=SC1090
                source "${_cfg}"
            fi
            check_env
            exit $?
            ;;
        -n|--num)
            NUM_SAMPLES="$2"
            shift 2
            ;;
        -m|--mode)
            EVAL_MODE="$2"
            shift 2
            ;;
        -w|--work-dir)
            WORK_DIR="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --host)
            VLLM_HOST="$2"
            shift 2
            ;;
        --port)
            VLLM_PORT="$2"
            shift 2
            ;;
        --model)
            MODEL_NAME="$2"
            shift 2
            ;;
        --model-path)
            MODEL_PATH="$2"
            shift 2
            ;;
        --max-out-len)
            MAX_OUT_LEN="$2"
            shift 2
            ;;
        --batch-size)
            BATCH_SIZE="$2"
            shift 2
            ;;
        --temperature)
            TEMPERATURE="$2"
            shift 2
            ;;
        --extra-args)
            AIS_BENCH_EXTRA_ARGS="$2"
            shift 2
            ;;
        -*)
            echo "[ERROR] 未知选项: $1" >&2
            print_help
            exit 1
            ;;
        *)
            DATASET="$1"
            shift
            ;;
    esac
done

# ---- 加载配置文件 ----
if [[ -n "${CONFIG_FILE}" ]]; then
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "[ERROR] 配置文件不存在: ${CONFIG_FILE}" >&2
        exit 1
    fi
    # shellcheck disable=SC1090
    source "${CONFIG_FILE}"
else
    if [[ -f "${SCRIPT_DIR}/config.sh" ]]; then
        # shellcheck disable=SC1090
        source "${SCRIPT_DIR}/config.sh"
    fi
fi

# 应用默认值
VLLM_HOST="${VLLM_HOST:-127.0.0.1}"
VLLM_PORT="${VLLM_PORT:-8000}"
MODEL_NAME="${MODEL_NAME:-Qwen/Qwen2.5-0.5B-Instruct}"
MODEL_PATH="${MODEL_PATH:-Qwen/Qwen2.5-0.5B-Instruct}"
MAX_OUT_LEN="${MAX_OUT_LEN:-32768}"
BATCH_SIZE="${BATCH_SIZE:-1}"
TEMPERATURE="${TEMPERATURE:-0.0}"
EVAL_MODE="${EVAL_MODE:-all}"
WORK_DIR="${WORK_DIR:-${SCRIPT_DIR}/outputs}"
AIS_BENCH_EXTRA_ARGS="${AIS_BENCH_EXTRA_ARGS:---dump-eval-details --merge-ds}"

# ---- 校验数据集 ----
if [[ -z "${DATASET}" ]]; then
    echo "[ERROR] 请指定数据集名称" >&2
    echo "" >&2
    list_datasets >&2
    exit 1
fi

if [[ -z "${DATASET_TABLE[${DATASET}]+_}" ]]; then
    echo "[ERROR] 未知数据集: ${DATASET}" >&2
    echo "  支持的数据集: ${!DATASET_TABLE[*]}" >&2
    exit 1
fi

IFS='|' read -r DS_LABEL DS_CONFIG_KEY <<< "${DATASET_TABLE[${DATASET}]}"

# ---- 校验模式 ----
case "${EVAL_MODE}" in
    all|acc|perf) ;;
    *)
        echo "[ERROR] 无效的评测模式: ${EVAL_MODE}，可选: all | acc | perf" >&2
        exit 1
        ;;
esac

# ---- 检查 ais_bench ----
if ! command -v ais_bench >/dev/null 2>&1; then
    echo "[ERROR] ais_bench 未找到。请先安装 AISBench。" >&2
    exit 1
fi

# ---- 解析 AISBench configs 目录 ----
AIS_BENCH_CONFIGS_DIR="$(
    python - <<'PY'
import os
import ais_bench.benchmark
print(os.path.join(os.path.dirname(ais_bench.benchmark.__file__), "configs"))
PY
)"

if [[ ! -d "${AIS_BENCH_CONFIGS_DIR}" ]]; then
    echo "[ERROR] 无法解析 AISBench configs 目录: ${AIS_BENCH_CONFIGS_DIR}" >&2
    exit 1
fi

# ---- 检查本地配置文件 ----
CUSTOM_DATASET_CFG="${SCRIPT_DIR}/datasets/${DS_CONFIG_KEY}.py"
CUSTOM_MODEL_CFG="${SCRIPT_DIR}/models/vllm_api_chat.py"

if [[ ! -f "${CUSTOM_DATASET_CFG}" ]]; then
    echo "[ERROR] 数据集配置文件不存在: ${CUSTOM_DATASET_CFG}" >&2
    exit 1
fi
if [[ ! -f "${CUSTOM_MODEL_CFG}" ]]; then
    echo "[ERROR] 模型配置文件不存在: ${CUSTOM_MODEL_CFG}" >&2
    exit 1
fi

# ---- 计算配置 key ----
# 使用 HOST_PORT 拼接生成唯一 key，避免覆盖 ais_bench 内置配置
CASE_KEY="bench_${DS_CONFIG_KEY}"
MODEL_CASE_KEY="bench_vllm_api_chat"

# ---- 安装配置文件到 AISBench configs 目录 ----
TARGET_DATASET_DIR="${AIS_BENCH_CONFIGS_DIR}/datasets/${DS_CONFIG_KEY}"
TARGET_MODEL_DIR="${AIS_BENCH_CONFIGS_DIR}/models/vllm_api"

mkdir -p "${TARGET_DATASET_DIR}"
mkdir -p "${TARGET_MODEL_DIR}"

cp -f "${CUSTOM_DATASET_CFG}" "${TARGET_DATASET_DIR}/${CASE_KEY}.py"
cp -f "${CUSTOM_MODEL_CFG}" "${TARGET_MODEL_DIR}/${MODEL_CASE_KEY}.py"

# ---- 运行时覆盖参数 ----
# 数据集: 追加 test_range
if [[ -n "${NUM_SAMPLES}" ]]; then
    echo "" >> "${TARGET_DATASET_DIR}/${CASE_KEY}.py"
    echo "# 由 run_bench.sh 自动生成" >> "${TARGET_DATASET_DIR}/${CASE_KEY}.py"
    echo "${DS_CONFIG_KEY}_datasets[0]['reader_cfg']['test_range'] = '[0:${NUM_SAMPLES}]'" >> "${TARGET_DATASET_DIR}/${CASE_KEY}.py"
fi

# 模型: 追加运行时参数
{
    echo ""
    echo "# 由 run_bench.sh 自动生成"
    echo "models[0]['host_ip'] = '${VLLM_HOST}'"
    echo "models[0]['host_port'] = ${VLLM_PORT}"
    echo "models[0]['model'] = '${MODEL_NAME}'"
    echo "models[0]['path'] = '${MODEL_PATH}'"
    echo "models[0]['max_out_len'] = ${MAX_OUT_LEN}"
    echo "models[0]['batch_size'] = ${BATCH_SIZE}"
    echo "models[0]['stream'] = True"
    echo "models[0]['retry'] = 3"
    echo "models[0]['request_rate'] = 1"
    echo "models[0]['generation_kwargs']['temperature'] = ${TEMPERATURE}"
} >> "${TARGET_MODEL_DIR}/${MODEL_CASE_KEY}.py"

# ---- 创建工作目录 ----
mkdir -p "${WORK_DIR}"

# ---- 构建 ais_bench 命令 ----
AIS_CMD=("ais_bench")
AIS_CMD+=("--models" "${MODEL_CASE_KEY}")
AIS_CMD+=("--datasets" "${CASE_KEY}")
AIS_CMD+=("--work-dir" "${WORK_DIR}")

# 模式参数
case "${EVAL_MODE}" in
    all)
        AIS_CMD+=("--mode" "all")
        ;;
    acc)
        AIS_CMD+=("--mode" "all")
        ;;
    perf)
        AIS_CMD+=("--summarizer" "default_perf")
        AIS_CMD+=("--mode" "perf")
        ;;
esac

# 额外参数
if [[ -n "${AIS_BENCH_EXTRA_ARGS}" ]]; then
    # shellcheck disable=SC2206
    AIS_CMD+=(${AIS_BENCH_EXTRA_ARGS})
fi

# ---- 打印信息 ----
echo "================================================"
echo "  AISBench 评测"
echo "================================================"
echo "  数据集    : ${DS_LABEL} (${DATASET})"
echo "  评测模式  : ${EVAL_MODE}"
if [[ -n "${NUM_SAMPLES}" ]]; then
    echo "  数据条数  : 前 ${NUM_SAMPLES} 条"
else
    echo "  数据条数  : 全部"
fi
echo "  vLLM 地址 : http://${VLLM_HOST}:${VLLM_PORT}"
echo "  模型      : ${MODEL_NAME}"
echo "  max_out_len: ${MAX_OUT_LEN}"
echo "  batch_size : ${BATCH_SIZE}"
echo "  temperature: ${TEMPERATURE}"
echo "  结果目录  : ${WORK_DIR}"
echo "================================================"
echo ""
echo "[run_bench] 执行: ${AIS_CMD[*]}"
echo ""

# ---- 执行评测 ----
LOG_FILE="${WORK_DIR}/bench_${DATASET}_$(date '+%Y%m%d_%H%M%S').log"

set -o pipefail
"${AIS_CMD[@]}" 2>&1 | tee "${LOG_FILE}"
EXIT_CODE=${PIPESTATUS[0]}

# ---- 解析结果 ----
EXP_DIR="$(
    grep -E 'Current exp folder:' "${LOG_FILE}" | tail -n 1 | awk -F': ' '{print $NF}' | tr -d '\r' || true
)"
if [[ -z "${EXP_DIR}" || ! -d "${EXP_DIR}" ]]; then
    EXP_DIR="$(ls -1dt "${WORK_DIR}"/*/ 2>/dev/null | head -n 1 || true)"
fi

echo ""
echo "================================================"
echo "  评测完成 (exit=${EXIT_CODE})"
echo "================================================"
echo "  日志文件  : ${LOG_FILE}"

if [[ -n "${EXP_DIR}" && -d "${EXP_DIR}" ]]; then
    echo "  实验目录  : ${EXP_DIR}"

    # 精度结果
    if [[ "${EVAL_MODE}" != "perf" ]]; then
        LATEST_SUMMARY="$(ls -1t "${EXP_DIR}"/summary/summary_*.csv 2>/dev/null | head -n 1 || true)"
        if [[ -n "${LATEST_SUMMARY}" ]]; then
            echo "  精度摘要  : ${LATEST_SUMMARY}"
            echo "  ----------"
            cat "${LATEST_SUMMARY}"
        fi
    fi

    # 性能结果
    if [[ "${EVAL_MODE}" != "acc" ]]; then
        LATEST_PERF="$(ls -1t "${EXP_DIR}"/performances/*/*.csv 2>/dev/null | head -n 1 || true)"
        if [[ -n "${LATEST_PERF}" ]]; then
            echo "  性能结果  : ${LATEST_PERF}"
        fi
    fi
fi

echo "================================================"
exit ${EXIT_CODE}
