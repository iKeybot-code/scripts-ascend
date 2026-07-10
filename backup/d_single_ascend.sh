# echo "export TE_PARALLEL_COMPILER=1"
# export TE_PARALLEL_COMPILER=1
# # 规避方案：同上，直接改tbe的代码，减少进程数
# echo "sed -i '174a\        cann_kb_process_num = 1' /usr/local/Ascend/ascend-toolkit/latest/python/site-packages/tbe/common/repository_manager/route.py"
# sed -i '174a\        cann_kb_process_num = 1' /usr/local/Ascend/ascend-toolkit/latest/python/site-packages/tbe/common/repository_manager/route.py

unset ftp_proxy
unset https_proxy
unset http_proxy
#!/bin/bash
rm -rf ~/ascend/log/*
#export HCCL_OP_RETRY_ENABLE="L0:0, L1:0, L2:0"
export VLLM_NIXL_ABORT_REQUEST_TIMEOUT=30000
export HCCL_EXEC_TIMEOUT=600
export HCCL_CONNECT_TIMEOUT=360

IP_ADDRESS="90.90.97.28"
NETWORK_CARD_NAME="enp194s0f0"

export HCCL_IF_IP=$IP_ADDRESS
export GLOO_SOCKET_IFNAME=$NETWORK_CARD_NAME
export TP_SOCKET_IFNAME=$NETWORK_CARD_NAME
export HCCL_SOCKET_IFNAME=$NETWORK_CARD_NAME

export VLLM_USE_V1=1
export HCCL_BUFFSIZE=1024
export LD_LIBRARY_PATH=/usr/local/Ascend/ascend-toolkit/latest/python/site-packages/mooncake:$LD_LIBRARY_PATH
export PYTORCH_NPU_ALLOC_CONF="expandable_segments:True"
export VLLM_TORCH_PROFILER_WITH_STACK=0
export HCCL_DETERMINISTIC=true
export TASK_QUEUE_ENABLE=1
export VLLM_ASCEND_ENABLE_NZ=1
# export HCCL_OP_EXPANSION_MODE="AIV"
export OMP_NUM_THREADS=10
export OMP_PROC_BIND=false

export ASCEND_BUFFER_POOL=0:0
export VLLM_TORCH_PROFILER_DIR="/home/z00931220/profile/d/"
# export VLLM_LOGGING_LEVEL="debug"
# vllm serve /mnt/weight/Qwen3-235B-A22B-W8A8 \
export MC_LOG_LEVEL=ERROR
# export VLLM_VERSION=0.18.0
# export ASCEND_RT_VISIBLE_DEVICES=12,13,14,15 #8,9,10,11,12,13,14,15

# export ASCEND_RT_VISIBLE_DEVICES=8,9,10,11,12,13,14,15
export ASCEND_RT_VISIBLE_DEVICES=2,3
# export ASCEND_RT_VISIBLE_DEVICES=10,11
# vllm serve /mnt/nfs/weight/Qwen3-30B-A3B-Instruct-2507 \
# vllm serve /home/weight/Qwen3-8B \
# vllm serve /home/weight/Qwen3-30B-A3B-Instruct-2507 \
# vllm serve /home/weight/qwen-next \
vllm serve /home/weight/Qwen3.5-35B-A3B-w8a8-org \
  --host 0.0.0.0 \
  --port 40060 \
  --no-enable-prefix-caching \
  --data-parallel-size 2 \
  --tensor-parallel-size 1 \
  --seed 1024 \
  --served-model-name qwen \
  --distributed-executor-backend mp \
  --max-model-len 65536 \
  --max-num-batched-tokens 65536 \
  --trust-remote-code \
  --max-num_seqs 64 \
  --gpu-memory-utilization 0.9 \
  --enable-expert-parallel \
  --quantization ascend \
  --no-disable-hybrid-kv-cache-manager \
  --additional-config '{"recompute_scheduler_enable":true}' \
  --compilation-config '{"cudagraph_mode": "FULL_DECODE_ONLY","cudagraph_capture_sizes":[2,4,8,16,24,32,40,42,48,60,72,80]}' \
  --speculative-config '{"num_speculative_tokens": 3, "method":"qwen3_5_mtp", "enforce_eager": true}' \
  --kv-transfer-config \
  '{"kv_connector": "MooncakeConnectorV1",
  "kv_buffer_device": "npu",
  "kv_role": "kv_consumer",
  "kv_port": "31445",
  "engine_id": "1",
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

