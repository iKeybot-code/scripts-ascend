unset ftp_proxy
unset https_proxy
unset http_proxy

export HCCL_IF_IP=141.61.81.142

ifname="enp48s3u1u2"

export GLOO_SOCKET_IFNAME=${ifname}
export TP_SOCKET_IFNAME=${ifname}
export HCCL_SOCKET_IFNAME=${ifname}
echo $HCCL_SOCKET_IFNAME
export HCCL_BUFFSIZE=1200
export HCCL_OP_EXPANSION_MODE="AIV"
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
export VLLM_ASCEND_ENABLE_FLASHCOMM1=1
#export VLLM_ASCEND_ENABLE_FLASHCOMM1=0
export VLLM_ASCEND_ENABLE_FUSED_MC2=1

export OMP_NUM_THREADS=1
echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
sysctl -w vm.swappiness=0
sysctl -w kernel.numa_balancing=0
sysctl kernel.sched_migration_cost_ns=50000
export LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libjemalloc.so.2:$LD_PRELOAD
export LD_LIBRARY_PATH=/usr/local/Ascend/ascend-toolkit/latest/python/site-packages/mooncake:$LD_LIBRARY_PATH

export TASK_QUEUE_ENABLE=1
#export DYNAMIC_EPLB="true"
#"eplb_config": {"dynamic_eplb": true, "expert_heat_collection_interval": 600, "algorithm_execution_interval": 50, "eplb_policy_type": 2, "num_redundant_experts": 16},
export ASCEND_RT_VISIBLE_DEVICES=$1

vllm serve /mnt/share/weight/MiniMax-M2.7-w8a8-QuaRot \
    --host 0.0.0.0 \
    --port $2 \
    --data-parallel-size $3 \
    --data-parallel-rank $4 \
    --data-parallel-address $5 \
    --data-parallel-rpc-port $6 \
    --tensor-parallel-size $7 \
    --enable-expert-parallel \
    --served-model-name minimax \
    --max-model-len 135000 \
    --max-num-batched-tokens 32768 \
    --max-num-seqs 64 \
    --trust-remote-code \
    --gpu-memory-utilization 0.92 \
    --quantization ascend \
    --speculative_config '{"enforce_eager": false, "method": "eagle3", "model": "/mnt/share/weight/MiniMax-M2.7-eagle-model-2", "num_speculative_tokens": 3}' \
    --async-scheduling \
    --no-enable-prefix-caching \
    --compilation-config '{"cudagraph_mode":"FULL_DECODE_ONLY"}' \
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
        "kv_role": "kv_consumer",
        "kv_port": "60800",
        "engine_id": "1",
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