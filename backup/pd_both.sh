
nic_name="enp194s0f0"      # 改成实际的网卡名
local_ip="90.90.97.42"     # 改成实际的 IP

export HCCL_OP_EXPANSION_MODE="AIV"

export HCCL_IF_IP=$local_ip
export GLOO_SOCKET_IFNAME=$nic_name
export TP_SOCKET_IFNAME=$nic_name
export HCCL_SOCKET_IFNAME=$nic_name

export HCCL_BUFFSIZE=1200
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export OMP_NUM_THREADS=1
export TASK_QUEUE_ENABLE=1

export VLLM_USE_V2_MODEL_RUNNER=1

unset http_proxy https_proxy

vllm serve /mnt/a800_weight/MiniMax-M2.7-w8a8-QuaRot \
    --safetensors-load-strategy 'prefetch' \
    --served-model-name "minimax" \
    --host 0.0.0.0 \
    --port 8000 \
    --trust-remote-code \
    --tensor-parallel-size 8 \
    --data-parallel-size 2 \
    --max-model-len 70000 \
    --max-num-seqs 128 \
    --max-num-batched-tokens 16384 \
    --gpu-memory-utilization 0.8 \
    --speculative_config '{"method": "eagle3", "model": "/mnt/a800_weight/MiniMax-M2.7-eagle-model-2", "num_speculative_tokens": 3}' \
    --compilation-config \
    '{
        "cudagraph_mode": "FULL_DECODE_ONLY"
    }' \
    --additional-config \
    '{
        "enable_npugraph_ex": true
    }'