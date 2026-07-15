#!/bin/bash

rm -rf ~/ascend/log/*
# =======================================================================
MODEL_PATH="/home/weight/Qwen3-8B"
MODEL_NAME="qwen3-8"
export ASCEND_RT_VISIBLE_DEVICES=15
# =======================================================================
export NODE_IP=90.90.97.27  # node ip
export NETWORK_CARD_NAME="enp194s0f0"  # network card name
# =======================================================================
export HCCL_IF_IP="${NODE_IP}"
export GLOO_SOCKET_IFNAME="${NETWORK_CARD_NAME}"
export TP_SOCKET_IFNAME="${NETWORK_CARD_NAME}"
export HCCL_SOCKET_IFNAME="${NETWORK_CARD_NAME}"
export HCCL_EXEC_TIMEOUT=600
export HCCL_CONNECT_TIMEOUT=360
export OMP_PROC_BIND=false
export OMP_NUM_THREADS=10
# export VLLM_USE_V2_MODEL_RUNNER=1

# =======================================================================

export HCCL_BUFFSIZE=1024
export HCCL_DETERMINISTIC=true

# export VLLM_USE_V1=1
# export VLLM_ASCEND_ENABLE_NZ=1
# export VLLM_ASCEND_ENABLE_FLASHCOMM1=1
# export HCCL_OP_EXPANSION_MODE="AIV"

# export LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libjemalloc.so.2:$LD_PRELOAD

export ASCEND_BUFFER_POOL=0:0
# export VLLM_TORCH_PROFILER_WITH_STACK=0
# export VLLM_TORCH_PROFILER_DIR="/home/z00931220/profile/p/"
# export VLLM_LOGGING_LEVEL="debug"

export MC_LOG_LEVEL=ERROR
# export VLLM_VERSION=0.18.0
# export VLLM_NIXL_ABORT_REQUEST_TIMEOUT=1
# export VLLM_MOONCAKE_ABORT_REQUEST_TIMEOUT=300000
# =======================================================================

vllm serve $MODEL_PATH \
  --served-model-name $MODEL_NAME \
  --host 0.0.0.0 \
  --port 13901 \
  --seed 1024 \
  --max-num-seqs 16 \
  --max-model-len 32768  \
  --max-num-batched-tokens 2048  \
  --trust-remote-code \
  --tensor-parallel-size 1 \
  --gpu-memory-utilization 0.9  \
  --no-enable-prefix-caching \
  --compilation-config '{"cudagraph_mode":"FULL_DECODE_ONLY"}' \
  --additional-config '{"recompute_scheduler_enable":true,"enable_cpu_binding":true}' \
  --async-scheduling \
  --kv-transfer-config \
  '{
        "kv_connector": "MooncakeConnector",
        "kv_role": "kv_consumer",
        "kv_port": "30901",
        "kv_connector_extra_config": {
            "prefill": {
                "dp_size": 1,
                "tp_size": 1
            },
            "decode": {
                "dp_size": 1,
                "tp_size": 1
            }
        }
    }'

# =======================================================================
#  --api-server-count 1 \
#  --data-parallel-size 4 \
#  --block-size 128 \
#  --quantization ascend \
#  --async-scheduling \
#  --enable-expert-parallel \
#  --distributed-executor-backend mp \
#  --additional-config '{"recompute_scheduler_enable":true}' \
#  --additional-config '{"enable_cpu_binding": true, "enable_shared_expert_dp": true, "enable_dsa_cp": true}' \
#  --speculative-config '{"num_speculative_tokens": 3, "method":"qwen3_5_mtp", "enforce_eager": true}' \
#  --model-loader-extra-config='{"enable_multithread_load": "true", "num_threads": 128}' \
#  --compilation-config '{"cudagraph_mode": "FULL_DECODE_ONLY"}' \

#  --safetensors-load-strategy 'prefetch' \
#  --tokenizer-mode deepseek_v4 \
#  --enable-auto-tool-choice \
#  --tool-call-parser deepseek_v4 \
#  --reasoning-parser deepseek_v4 \
# =======================================================================
