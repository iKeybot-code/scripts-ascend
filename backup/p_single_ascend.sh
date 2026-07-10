unset ftp_proxy
unset https_proxy
unset http_proxy
#!/bin/bash
rm -rf ~/ascend/log/*
# export VLLM_NIXL_ABORT_REQUEST_TIMEOUT=1
export HCCL_EXEC_TIMEOUT=600
export HCCL_CONNECT_TIMEOUT=360
# export HCCL_EXEC_TIMEOUT=204
# export HCCL_CONNECT_TIMEOUT=120


IP_ADDRESS="90.90.97.28"
NETWORK_CARD_NAME="enp194s0f0"

export HCCL_IF_IP=$IP_ADDRESS
export GLOO_SOCKET_IFNAME=$NETWORK_CARD_NAME
export TP_SOCKET_IFNAME=$NETWORK_CARD_NAME
export HCCL_SOCKET_IFNAME=$NETWORK_CARD_NAME

export VLLM_USE_V1=1
export HCCL_BUFFSIZE=1024
export PYTORCH_NPU_ALLOC_CONF="expandable_segments:True"
export VLLM_TORCH_PROFILER_WITH_STACK=0
export TASK_QUEUE_ENABLE=1
export VLLM_ASCEND_ENABLE_NZ=1
# export HCCL_OP_EXPANSION_MODE="AIV"
export HCCL_DETERMINISTIC=true
export OMP_NUM_THREADS=10
export OMP_PROC_BIND=false

export ASCEND_BUFFER_POOL=0:0
export VLLM_TORCH_PROFILER_DIR="/home/z00931220/profile/p/"
# export VLLM_LOGGING_LEVEL="debug"
# vllm serve /mnt/weight/Qwen3-235B-A22B-W8A8 \
export MC_LOG_LEVEL=ERROR
# export VLLM_VERSION=0.18.0
# export ASCEND_RT_VISIBLE_DEVICES=8,9,10,11 #0,1,2,3,4,5,6,7
# export ASCEND_RT_VISIBLE_DEVICES=0,1
export ASCEND_RT_VISIBLE_DEVICES=0,1

export VLLM_MOONCAKE_ABORT_REQUEST_TIMEOUT=300000
vllm serve /home/weight/Qwen3.5-35B-A3B-w8a8-org \
  --host 0.0.0.0 \
  --port 40070 \
  --no-enable-prefix-caching \
  --data-parallel-size 2 \
  --tensor-parallel-size 1 \
  --seed 1024 \
  --max-num-seqs 32 \
  --distributed-executor-backend mp \
  --served-model-name qwen \
  --max-model-len 65536 \
  --max-num-batched-tokens 65536 \
  --trust-remote-code \
  --gpu-memory-utilization 0.9 \
  --enable-expert-parallel \
  --no-disable-hybrid-kv-cache-manager \
  --enforce-eager \
  --additional-config '{"recompute_scheduler_enable":true}' \
  --speculative-config '{"num_speculative_tokens": 3, "method":"qwen3_5_mtp", "enforce_eager": true}' \
  --kv-transfer-config \
  '{"kv_connector": "MooncakeConnectorV1",
  "kv_role": "kv_producer",
  "kv_port": "31245",
  "engine_id": "0",
  "kv_connector_extra_config": {
       "prefill": {
         "dp_size": 2,
         "tp_size": 1
       },
       "decode": {
         "dp_size": 2,
         "tp_size": 1
       }
      }
   }' \



