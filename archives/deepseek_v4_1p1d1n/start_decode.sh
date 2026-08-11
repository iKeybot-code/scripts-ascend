#!/bin/bash
set -euo pipefail

export VLLM_RPC_TIMEOUT=3600000
export VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS=6000
export HCCL_EXEC_TIMEOUT=3600
export HCCL_CONNECT_TIMEOUT=1800
export HCCL_IF_IP=178.27.4.165
export GLOO_SOCKET_IFNAME=data0.173
export TP_SOCKET_IFNAME=data0.173
export HCCL_SOCKET_IFNAME=data0.173
export OMP_PROC_BIND=false
export OMP_NUM_THREADS=10
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export VLLM_ASCEND_ENABLE_MLAPO=1
export HCCL_BUFFSIZE=1200
export TASK_QUEUE_ENABLE=1
export HCCL_OP_EXPANSION_MODE="AIV"
export VLLM_USE_V1=1
export ASCEND_RT_VISIBLE_DEVICES="${1:-8,9,10,11,12,13,14,15}"
export ASCEND_BUFFER_POOL=4:8
export MOONCAKE_CONFIG_PATH="/mnt/share/l00848175/scripts-ascend/example/template/mooncake.json"
export HCCL_RDMA_TIMEOUT=17
export ASCEND_CONNECT_TIMEOUT=10000
export ASCEND_TRANSFER_TIMEOUT=10000
export LD_LIBRARY_PATH=/usr/local/Ascend/ascend-toolkit/latest/python/site-packages/mooncake:/usr/local/Ascend/ascend-toolkit/latest/python/site-packages/vllm:${LD_LIBRARY_PATH:-}
export PYTHONPATH=${PYTHONPATH:-}:/usr/local/Ascend/ascend-toolkit/latest/python/site-packages/vllm
export PATH="/usr/local/python3.12.13/bin:${PATH}"
export PYTHONHASHSEED=0
export VLLM_USE_V2_MODEL_RUNNER=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
vllm serve /mnt/share/weight/dsk-v3.1-w4a4_mlp-w8a8c8_attn-0618-full \
  --host 0.0.0.0 \
  --port "${2:-8001}" \
  --data-parallel-size 1 \
  --tensor-parallel-size 8 \
  --enable-expert-parallel \
  --seed 1024 \
  --served-model-name dsv4 \
  --max-model-len 65536 \
  --max-num-batched-tokens 256 \
  --max-num-seqs 28 \
  --enforce-eager \
  --trust-remote-code \
  --gpu-memory-utilization 0.92 \
  --quantization ascend \
  --no-enable-prefix-caching \
  --speculative-config '{
    "num_speculative_tokens": 1,
    "method": "mtp"
  }' \
  --additional-config '{
    "scheduler_config": {
      "recompute_scheduler_enable": true
    }
  }' \
  --kv-transfer-config '{
    "kv_connector": "MooncakeConnectorV1",
    "kv_role": "kv_consumer",
    "kv_port": "37000",
    "kv_connector_extra_config": {
      "prefill": {
        "dp_size": 1,
        "tp_size": 8
      },
      "decode": {
        "dp_size": 1,
        "tp_size": 8
      }
    }
  }' \
  2>&1 | tee "${SCRIPT_DIR}/decode.log"
