unset ftp_proxy
unset https_proxy
unset http_proxy

export HCCL_IF_IP=141.61.81.24

ifname="enp48s3u1u2"

export GLOO_SOCKET_IFNAME=${ifname}
export TP_SOCKET_IFNAME=${ifname}
export HCCL_SOCKET_IFNAME=${ifname}

export HCCL_BUFFSIZE=1200
export HCCL_OP_EXPANSION_MODE="AIV"
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True

export OMP_NUM_THREADS=1
echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
sysctl -w vm.swappiness=0
sysctl -w kernel.numa_balancing=0
sysctl kernel.sched_migration_cost_ns=50000
export LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libjemalloc.so.2:$LD_PRELOAD
export LD_LIBRARY_PATH=/usr/local/Ascend/ascend-toolkit/latest/python/site-packages/mooncake:$LD_LIBRARY_PATH
export VLLM_SERVER_DEV_MODE=1

export TASK_QUEUE_ENABLE=1
export VLLM_ASCEND_ENABLE_FLASHCOMM1=1
export VLLM_ASCEND_ENABLE_FUSED_MC2=1
export VLLM_PP_LAYER_PARTITION="32,30"
# export ASCEND_RT_VISIBLE_DEVICES=$1
#"pp_layer_partition": "32,30"
vllm serve /mnt/share/weight/MiniMax-M2.7-w8a8-QuaRot \
    --host 0.0.0.0 \
    --port 8000 \
    --data-parallel-size 1 \
    --pipeline-parallel-size 2 \
    --master-addr 141.61.81.24 \
    --master-port 7060 \
    --nnodes 1 \
    --node-rank 0 \
    --tensor-parallel-size 8 \
    --enable-expert-parallel \
    --served-model-name minimax \
    --max-model-len 135000 \
    --max-num-batched-tokens 32768 \
    --max-num-seqs 128 \
    --trust-remote-code \
    --gpu-memory-utilization 0.9 \
    --quantization ascend \
    --enforce-eager \
    --enable-prefix-caching \
    --speculative_config '{"method": "eagle3", "model": "/mnt/share/weight/MiniMax-M2.7-eagle-model-2", "num_speculative_tokens": 1}' \
    --additional-config '{
        "recompute_scheduler_enable": true,
        "enable_reduce_sample": true,
        "enable_cpu_binding": true,
        "ascend_compilation_config":{"enable_npugraph_ex": true},
        "enable_fused_mc2": true,
        "enable_flashcomm1": true,
        "weight_nz_mode": true
    }' \
    --kv-transfer-config \
        '{"kv_connector": "MooncakeConnectorV1",
        "kv_role": "kv_producer",
        "kv_port": "51000",
        "engine_id": "2",
        "kv_connector_extra_config": {
             "prefill": {
                    "dp_size": 1,
                    "tp_size": 8,
                    "pp_size": 2,
                    "pp_layer_partition": "32,30"
             },
             "decode": {
                    "dp_size": 2,
                    "tp_size": 8
             }
        }
        }'