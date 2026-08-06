export VLLM_RPC_TIMEOUT=3600000
export VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS=6000
export HCCL_EXEC_TIMEOUT=3600
export HCCL_CONNECT_TIMEOUT=1800

# 自动获取配置
nic_name=自动获取
local_ip=自动获取

# 以下环境变量无需修改
export HCCL_IF_IP=$local_ip
export GLOO_SOCKET_IFNAME=$nic_name
export TP_SOCKET_IFNAME=$nic_name
export HCCL_SOCKET_IFNAME=$nic_name
export OMP_PROC_BIND=false
export OMP_NUM_THREADS=10
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export VLLM_ASCEND_ENABLE_MLAPO=1
export HCCL_BUFFSIZE=1200
export TASK_QUEUE_ENABLE=1
export HCCL_OP_EXPANSION_MODE="AIV"
export VLLM_TORCH_PROFILER_DIR="./vllm_profile"
export VLLM_TORCH_PROFILER_WITH_STACK=1
export VLLM_USE_V1=1
export ASCEND_RT_VISIBLE_DEVICES=$1
export ASCEND_BUFFER_POOL=4:8
export LD_LIBRARY_PATH=/usr/local/Ascend/ascend-toolkit/latest/python/site-packages/mooncake:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/usr/local/Ascend/ascend-toolkit/latest/python/site-packages/vllm:$LD_LIBRARY_PATH
export PYTHONPATH=$PYTHONPATH:/usr/local/Ascend/ascend-toolkit/latest/python/site-packages/vllm
export PATH="/usr/local/python3.12.13/bin:$PATH"
export VLLM_USE_V2_MODEL_RUNNER=1

# vllm起服务配置
vllm serve /mnt/a800_weight/DeepSeek-V3.1-Terminus-w4a8-mtp-QuaRot \
  --host 0.0.0.0 \
  --port $2 \
  --data-parallel-size $3 \
  --data-parallel-rank $4 \
  --data-parallel-address $5 \
  --data-parallel-rpc-port $6 \
  --tensor-parallel-size $7 \
  --enable-expert-parallel \
  --seed 1024 \
  --served-model-name deepseek_v3 \
  --max-model-len 65536 \
  --max-num-batched-tokens 256 \
  --max-num-seqs 28 \
  --trust-remote-code \
  --gpu-memory-utilization 0.92 \
  --quantization ascend \
  --no-enable-prefix-caching \
  --speculative-config '{"num_speculative_tokens": 1, "method": "mtp"}' \
  --compilation-config '{"cudagraph_mode": "FULL_DECODE_ONLY"}' \
  --additional-config '{"recompute_scheduler_enable":true, "multistream_overlap_shared_expert": true, "finegrained_tp_config": {"lmhead_tensor_parallel_size":16}}' \
  --kv-transfer-config \
  '{
    "kv_connector": "MooncakeConnectorV1",
    "kv_role": "kv_consumer",
    "kv_port": "37000",
    "kv_connector_extra_config": {
      "prefill": {
        "dp_size": 2,
        "tp_size": 8
      },
      "decode": {
        "dp_size": 2,
        "tp_size": 8
      }
    }
  }'
