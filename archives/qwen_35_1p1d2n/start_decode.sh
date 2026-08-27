# 自动获取配置
nic_name=自动获取
local_ip=自动获取

export HCCL_IF_IP=$local_ip
export GLOO_SOCKET_IFNAME=$nic_name
export TP_SOCKET_IFNAME=$nic_name
export HCCL_SOCKET_IFNAME=$nic_name

# [Optional] jemalloc
# jemalloc is for better performance, if `libjemalloc.so` is installed on your machine, you can turn it on.
# export LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libjemalloc.so.2:$LD_PRELOAD

export HCCL_OP_EXPANSION_MODE="AIV"
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export OMP_PROC_BIND=false
export OMP_NUM_THREADS=1
export TASK_QUEUE_ENABLE=1
export LD_LIBRARY_PATH=/usr/local/Ascend/ascend-toolkit/latest/python/site-packages/mooncake:$LD_LIBRARY_PATH

export HCCL_BUFFSIZE=1024
export ASCEND_RT_VISIBLE_DEVICES=$1
export VLLM_USE_V2_MODEL_RUNNER=1

vllm serve /mnt/weight/Qwen3.5-27B-w8a8-org \
  --host 0.0.0.0 \
  --port $2 \
  --data-parallel-size $3 \
  --data-parallel-rank $4 \
  --data-parallel-address $5 \
  --data-parallel-rpc-port $6 \
  --tensor-parallel-size $7 \
  --seed 1024 \
  --quantization ascend \
  --served-model-name qwen3.5 \
  --trust-remote-code \
  --max-num-seqs 16 \
  --max-model-len 32768 \
  --max-num-batched-tokens 2048 \
  --enable-prefix-caching \
  --gpu-memory-utilization 0.91 \
  --compilation-config '{"cudagraph_mode":"FULL_DECODE_ONLY"}' \
  --additional-config '{"recompute_scheduler_enable":true,"enable_cpu_binding":true}' \
  --speculative-config '{"method": "qwen3_5_mtp", "num_speculative_tokens": 3, "enforce_eager": true}' \
  --kv-transfer-config \
  '{
      "kv_connector": "MooncakeConnectorV1",
      "kv_role": "kv_consumer",
      "kv_port": "37000",
      "kv_connector_extra_config": {
        "prefill": {
          "dp_size": 8,
          "tp_size": 2
        },
        "decode": {
          "dp_size": 8,
          "tp_size": 2
        }
      }
    }'
