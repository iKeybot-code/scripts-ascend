export VLLM_RPC_TIMEOUT=3600000
export VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS=30000
export HCCL_EXEC_TIMEOUT=204
export HCCL_CONNECT_TIMEOUT=120

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
export HCCL_BUFFSIZE=256
export TASK_QUEUE_ENABLE=1
export HCCL_OP_EXPANSION_MODE="AIV"
export VLLM_TORCH_PROFILER_DIR="./vllm_profile"
export VLLM_TORCH_PROFILER_WITH_STACK=1
export VLLM_USE_V1=1
export ASCEND_RT_VISIBLE_DEVICES=$1
export ASCEND_BUFFER_POOL=4:8
export MOONCAKE_CONFIG_PATH="/mnt/a800_share/l00848175/workspace/tests/deepseek_v31_2p1d_mrv2/mooncake.json"
export HCCL_RDMA_TIMEOUT=17
export ASCEND_CONNECT_TIMEOUT=10000
export ASCEND_TRANSFER_TIMEOUT=10000
export LD_LIBRARY_PATH=/usr/local/Ascend/ascend-toolkit/latest/python/site-packages/mooncake:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/usr/local/Ascend/ascend-toolkit/latest/python/site-packages:$LD_LIBRARY_PATH
export PYTHONHASHSEED=0
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
	--max-num-batched-tokens 16384 \
	--max-num-seqs 8 \
	--enforce-eager \
	--trust-remote-code \
	--gpu-memory-utilization 0.9 \
	--quantization ascend \
	--enable-prefix-caching \
	--speculative-config '{"num_speculative_tokens": 1, "method": "mtp"}' \
	--additional-config '{"recompute_scheduler_enable":true}' \
	--kv-transfer-config \
	'{
    "kv_connector": "MultiConnector",
    "kv_role": "kv_producer",
    "kv_connector_extra_config": {
      "connectors": [
        {
          "kv_connector": "MooncakeConnectorV1",
          "kv_role": "kv_producer",
          "kv_port": "36000",
          "kv_connector_extra_config": {
            "prefill": {
              "dp_size": 2,
              "tp_size": 8
            },
            "decode": {
              "dp_size": 32,
              "tp_size": 1
            }
          }
        },
        {
          "kv_connector": "AscendStoreConnector",
          "kv_role": "kv_producer",
          "kv_connector_extra_config": {
            "lookup_rpc_port": "0",
            "backend": "mooncake"
          }
        }
      ]
    }
  }'
