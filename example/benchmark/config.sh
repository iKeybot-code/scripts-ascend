#!/bin/bash
# =============================================================================
# AISBench 评测参数配置文件
#
# 所有可调参数集中在此文件，按需修改后运行 run_bench.sh
# =============================================================================

# ---- vLLM 服务连接 (默认连接 minimaxm27 部署的 proxy) ----
export VLLM_HOST="${VLLM_HOST:-90.90.97.15}"
export VLLM_PORT="${VLLM_PORT:-8080}"

# ---- 模型配置 (默认 minimaxm27) ----
export MODEL_NAME="${MODEL_NAME:-minimaxm27}"
export MODEL_PATH="${MODEL_PATH:-/mnt/a800_weight/MiniMax-M2.7-w8a8-QuaRot}"

# ---- 推理参数 ----
export MAX_OUT_LEN="${MAX_OUT_LEN:-32768}"
export BATCH_SIZE="${BATCH_SIZE:-1}"
export TEMPERATURE="${TEMPERATURE:-0.0}"

# ---- 评测模式: all(精度+性能) / acc(仅精度) / perf(仅性能) ----
export EVAL_MODE="${EVAL_MODE:-all}"

# ---- 工作目录（存放评测结果） ----
export WORK_DIR="${WORK_DIR:-${SCRIPT_DIR:-./}/outputs}"

# ---- 额外 ais_bench 参数 ----
export AIS_BENCH_EXTRA_ARGS="${AIS_BENCH_EXTRA_ARGS:---dump-eval-details --merge-ds}"
