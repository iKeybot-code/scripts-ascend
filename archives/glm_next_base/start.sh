#!/bin/sh

# Reduce memory fragmentation and avoid out-of-memory errors.
export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True

export HCCL_OP_EXPANSION_MODE="AIV"
export HCCL_BUFFSIZE=1024
export OMP_NUM_THREADS=1
export TASK_QUEUE_ENABLE=1
echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
sysctl -w vm.swappiness=0
sysctl -w kernel.numa_balancing=0
sysctl kernel.sched_migration_cost_ns=50000
#export LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libjemalloc.so.2:$LD_PRELOAD

export PYTHONHASHSEED=0
export MMC_LOCAL_CONFIG_PATH=/usr/local/python3.11.10/lib/python3.11/site-packages/memcache_hybrid/config/mmc-local.conf
KV_CONFIG='{
  "kv_connector": "AscendStoreConnector",
  "kv_role": "kv_both",
  "kv_connector_extra_config": {
     "backend": "memcache",
     "lookup_rpc_port": "0"
  }
}'

vllm serve /home/wyzhou/dummy_weight \
	--host 0.0.0.0 \
	--port 8000 \
	--data-parallel-size 1 \
	--tensor-parallel-size 16 \
	--enable-expert-parallel \
	--seed 1024 \
	--load-format dummy \
	--dtype bfloat16 \
	--served-model-name glm \
	--max-num-seqs 128 \
	--max-model-len 16400 \
	--enforce_eager \
	--max-num-batched-tokens 8192 \
	--trust-remote-code \
	--gpu-memory-utilization 0.90 \
	--profiler-config '{"profiler": "torch", "torch_profiler_dir": "/home/l00622059/profiling", "torch_profiler_with_stack": false}' \
	--enable-prefix-caching \
	--kv-transfer-config "$KV_CONFIG"
