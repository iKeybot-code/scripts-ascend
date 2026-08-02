# MiniMax M2.7 PD分离 AIME2025 精度测评报告

## 测试环境

| 项目 | 详情 |
|------|------|
| 日期 | 2026-07-27 |
| 模型 | MiniMax-M2.7-w8a8-QuaRot |
| vllm 版本 | fe784ff22 (main) |
| vllm-ascend 版本 | ae2397f2d (main) |
| Docker 镜像 | vllm-ascend:dev-26.1.0.cann9.1.0.day20260717-800I-A3-py311-Ubuntu24.04-lts-aarch64 |

## 集群拓扑

| 角色 | 节点 | IP | NPU |
|------|------|-----|-----|
| Prefill | Node 15 | 90.90.97.15 | 16 cards (0-15) |
| Decode | Node 37 | 90.90.97.37 | 16 cards (0-15) |

## 并行策略

| 参数 | Prefill | Decode |
|------|---------|--------|
| DP | 2 | 2 |
| TP | 8 | 8 |
| DP Local | 2 | 2 |
| 每节点卡数 | 16 | 16 |

## 特性开关

| 特性 | 状态 | 说明 |
|------|------|------|
| Model Runner V2 (MRV2) | ✅ 启用 | VLLM_USE_V2_MODEL_RUNNER=1 |
| PD 分离 | ✅ 启用 | 1P1D 跨节点 (Node15 + Node37) |
| KV 池化 | ✅ 启用 | MooncakeConnectorV1 |
| Prefix Cache | ✅ 启用 | --enable-prefix-caching |

## Bug 分析与修复记录

### Bug 1: Docker 容器线程创建失败 (Node 37)

**现象**: Node 37 容器无法创建线程，Python `threading.Thread.start()` 抛出 `RuntimeError: can't start new thread`

**根因**: Docker 20.10.8 默认 seccomp 配置阻止了 `clone()` 系统调用

**修复**:
```bash
docker run --security-opt seccomp=unconfined ...
```

**影响文件**: `/mnt/a800_share/l00848175/scripts-ascend/start_container.sh`

### Bug 2: OpenTelemetry SDK 导入时线程创建失败 (Node 37)

**现象**: `vllm serve` 启动时在导入 OpenTelemetry SDK 阶段崩溃，`Resource.create()` 调用 ThreadPoolExecutor 时失败

**根因**: Bug 1 的连锁反应 - seccomp 阻止线程创建

**修复**: 设置 `OTEL_SDK_DISABLED=true` 环境变量

### Bug 3: MRV2 版本检测失败

**现象**: Decode 启动时警告 `VLLM_USE_V2_MODEL_RUNNER is not supported on vllm 0.23.0; falling back to v1 model runner`

**根因**: Node 37 容器重建后，容器内旧版 vllm 0.23.0 (Docker 镜像内置版本) 覆盖了从 Node 15 复制的 editable install。`vllm.__version__` 返回 `0.23.0` 而非预期的 `0.23.1rc1.dev1220+gfe784ff22`

**修复**:
```bash
# 删除旧版 vllm 包，建立到 NFS 共享源的软链接
rm -rf /usr/local/python3.11.10/lib/python3.11/site-packages/vllm
ln -sf /mnt/a800_share/xuchi/Tasks/A00302/vllm/vllm /usr/local/python3.11.10/lib/python3.11/site-packages/vllm
```

### Bug 4: vllm 与 vllm-ascend API 不匹配

**现象**: 
- `AttributeError: module 'vllm.v1.engine.utils' has no attribute 'get_physical_gpu_ids_for_local_dp_rank'`
- `ModuleNotFoundError: No module named 'vllm.tool_parsers.deepseekv4_tool_parser'`

**根因**: 容器内置 vllm 0.23.0 缺少 vllm-ascend main 分支所需的 API

**修复**: 与 Bug 3 相同，通过软链接使用 NFS 共享源上的最新 vllm 代码

### Bug 5: vllm 包元数据缺失

**现象**: `importlib.metadata.PackageNotFoundError: No package metadata was found for vllm`

**根因**: 删除 site-packages 中旧版 vllm 时同时删除了 dist-info 元数据目录

**修复**: 从 Node 15 复制完整的 `vllm-*.dist-info` 目录

### Bug 6: msgspec 序列化不匹配导致 Decode 崩溃

**现象**: Decode 引擎运行一段时间后崩溃:
```
msgspec.ValidationError: Expected `object | null`, got `array` - at `$[1][0][8]`
corrupted size vs. prev_size
```

**根因**: vllm EngineCore 与 API Server 之间的序列化 schema 不一致。尽管代码源一致（NFS 共享），但 Python 字节码缓存 (`.pyc`) 可能残留旧版本，导致 schema 定义不同步

**修复建议**: 
1. 清除所有 `__pycache__` 目录
2. 确保两节点完全使用相同的 Python 环境

### Bug 7: NFS 共享存储导致 pip install -e 挂起

**现象**: Node 37 上 `pip install -e /path/on/nfs` 在 "Preparing editable metadata" 阶段无限挂起

**根因**: NFS 文件系统性能问题，setuptools-scm 在构建时 I/O 极慢

**修复**: 使用软链接方式替代 editable install，绕过 pip 构建步骤

## 运行结果

### 服务启动

| 组件 | 节点 | 状态 |
|------|------|------|
| Mooncake Master | Node 15 | ✅ 正常 (端口 50088) |
| Prefill (Rank 0) | Node 15 | ✅ 正常 (端口 13900) |
| Prefill (Rank 1) | Node 15 | ✅ 正常 (端口 13901) |
| Decode (Rank 0) | Node 37 | ⚠️ 不稳定 (端口 13901) |
| Decode (Rank 1) | Node 37 | ⚠️ 不稳定 (端口 13902) |
| Proxy | Node 15 | ✅ 正常 (端口 8080) |

### GSM8K 冒烟测试

- **状态**: 失败 (数据集文件缺失)
- **原因**: `ais_bench/datasets/gsm8k` 目录为空

### AIME2025 精度测评

- **状态**: 未完成
- **原因**: Decode 引擎稳定性问题导致推理失败
- **推理阶段**: Warmup 阶段失败 (289秒后返回格式错误)
- **根因**: Bug 6 — Decode 引擎在接收到推理请求后因 msgspec 序列化错误崩溃

## 完整操作指南

### 1. 前置准备

```bash
# 设置代理 (如需下载数据集)
export PROXY_IP=90.254.54.104
export http_proxy=http://${PROXY_IP}:3128
export https_proxy=${http_proxy}
```

### 2. 节点 NPU 检查

```bash
for ip in 15 37; do
  ssh root@90.90.97.$ip 'npu-smi info'
done
```

### 3. 启动容器 (使用 seccomp=unconfined)

```bash
# Node 15 (Prefill)
ssh root@90.90.97.15
docker stop vllm-lkl-minimax; docker rm vllm-lkl-minimax
docker run -d --name vllm-lkl-minimax --net=host --shm-size=500g \
  --security-opt seccomp=unconfined \
  --device /dev/davinci0 ... --device /dev/davinci15 \
  --device /dev/davinci_manager --device /dev/devmm_svm --device /dev/hisi_hdc \
  -w /workspace \
  -v /home:/home -v /data:/data -v /mnt:/mnt \
  -v /usr/local/dcmi:/usr/local/dcmi \
  -v /usr/local/Ascend/driver/tools/hccn_tool:/usr/local/Ascend/driver/tools/hccn_tool \
  -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
  -v /usr/local/Ascend/driver/lib64/:/usr/local/Ascend/driver/lib64/ \
  -v /usr/local/Ascend/driver/version.info:/usr/local/Ascend/driver/version.info \
  -v /etc/ascend_install.info:/etc/ascend_install.info \
  -v /etc/hccn.conf:/etc/hccn.conf \
  -v /mnt/sfs_turbo/.cache:/root/.cache \
  vllm-ascend:dev-26.1.0.cann9.1.0.day20260717-800I-A3-py311-Ubuntu24.04-lts-aarch64 \
  sleep infinity

# Node 37 (Decode) - 同理
ssh root@90.90.97.37
# 同上命令
```

### 4. 配置 vllm/vllm-ascend (两个节点均需执行)

```bash
docker exec vllm-lkl-minimax bash -c '
# 删除旧版包
rm -rf /usr/local/python3.11.10/lib/python3.11/site-packages/vllm
rm -rf /usr/local/python3.11.10/lib/python3.11/site-packages/vllm-*.dist-info
rm -rf /usr/local/python3.11.10/lib/python3.11/site-packages/vllm_ascend
rm -rf /usr/local/python3.11.10/lib/python3.11/site-packages/vllm_ascend-*.dist-info
# 建立软链接到 NFS 共享源码
ln -sf /mnt/a800_share/xuchi/Tasks/A00302/vllm/vllm /usr/local/python3.11.10/lib/python3.11/site-packages/vllm
ln -sf /mnt/a800_share/xuchi/Tasks/A00302/vllm-ascend/vllm_ascend /usr/local/python3.11.10/lib/python3.11/site-packages/vllm_ascend
ln -sf /mnt/a800_share/xuchi/Tasks/A00302/vllm /workspace/vllm
# 恢复元数据 (从备份)
cd /usr/local/python3.11.10/lib/python3.11/site-packages
tar xzf /mnt/a800_share/l00848175/workspace/vllm_dist_info.tgz
tar xzf /mnt/a800_share/l00848175/workspace/vllm_ascend_meta.tgz
'
```

### 5. 准备数据集

```bash
# 在容器内下载 AIME2025
docker exec -e http_proxy=http://90.254.54.104:3128 \
  -e https_proxy=http://90.254.54.104:3128 \
  vllm-lkl-minimax python3 -c '
import os
d = "/usr/local/python3.11.10/lib/python3.11/site-packages/ais_bench/datasets/aime2025"
os.makedirs(d, exist_ok=True)
from datasets import load_dataset, concatenate_datasets
ds1 = load_dataset("opencompass/AIME2025", "AIME2025-I", trust_remote_code=True, split="test")
ds2 = load_dataset("opencompass/AIME2025", "AIME2025-II", trust_remote_code=True, split="test")
ds = concatenate_datasets([ds1, ds2])
ds.to_json(os.path.join(d, "aime2025.jsonl"), orient="records", lines=True, force_ascii=False)
print(f"Downloaded {len(ds)} problems")
'
```

### 6. 创建工作目录和配置

```bash
mkdir -p /mnt/a800_share/l00848175/workspace/tests
cp -r /mnt/a800_share/l00848175/scripts-ascend/example/pd_multi_nodes \
  /mnt/a800_share/l00848175/workspace/tests/test_MiniMax-M2.7_MRV2_PD_KV_PrefixCache
# 编辑 configs.sh (配置已在上文详述)
```

### 7. 启动服务 (按顺序)

```bash
# 步骤 1: Node 15 - Mooncake Master
docker exec vllm-lkl-minimax bash -c \
  'cd /path/to/test_dir && nohup bash run.sh mooncake_master > logs/mm.log 2>&1 &'

# 步骤 2: Node 15 - Prefill
docker exec vllm-lkl-minimax bash -c \
  'cd /path/to/test_dir && nohup bash run.sh prefill 0 > logs/prefill.log 2>&1 &'

# 步骤 3: Node 37 - Decode (需 OTEL_SDK_DISABLED=true)
docker exec -e OTEL_SDK_DISABLED=true vllm-lkl-minimax bash -c \
  'cd /path/to/test_dir && nohup bash run.sh decode 0 > logs/decode.log 2>&1 &'

# 步骤 4: Node 15 - Proxy
docker exec vllm-lkl-minimax bash -c \
  'cd /path/to/test_dir && nohup bash run.sh proxy > logs/proxy.log 2>&1 &'

# 步骤 5: 运行评估
docker exec vllm-lkl-minimax bash /path/to/run_aime2025.sh
```

### 8. 停止服务

```bash
# Node 15
docker exec vllm-lkl-minimax bash -c 'pkill -9 -f vllm; pkill -9 -f mooncake'
# Node 37
docker exec vllm-lkl-minimax bash -c 'pkill -9 -f vllm'
```

## 待解决问题

1. **Decode 引擎稳定性**: msgspec 序列化错误 + heap corruption，需进一步排查 Python 字节码缓存或 NPU 驱动兼容性
2. **AIME2025 评测未完成**: 因 Decode 不稳定，完整精度评测未能执行
3. **`pip install -e` on NFS**: 建议在 Dockerfile 中预安装 vllm/vllm-ascend，避免运行时从 NFS editable install

## 配置参考

### configs.sh 关键配置

```bash
export MODEL_PATH=/mnt/a800_weight/MiniMax-M2.7-w8a8-QuaRot
export MODEL_NAME=MiniMax-M2.7-w8a8-QuaRot
export PREFILL_IPS=(90.90.97.15)
export DECODE_IPS=(90.90.97.37)
export P_DP_SIZE=2; export P_TP_SIZE=8; export P_DP_SIZE_LOCAL=2
export D_DP_SIZE=2; export D_TP_SIZE=8; export D_DP_SIZE_LOCAL=2
export P_VISIBLE_DEVICES_LIST=("0,1,2,3,4,5,6,7" "8,9,10,11,12,13,14,15")
export D_VISIBLE_DEVICES_LIST=("0,1,2,3,4,5,6,7" "8,9,10,11,12,13,14,15")
export ENABLE_KV_POOL=1
export PD_KV_CONNECTOR=MooncakeConnectorV1
export P_MAX_MODEL_LEN=131072
export D_MAX_MODEL_LEN=131072
# VLLM_USE_V2_MODEL_RUNNER=1 (default in run_dp_template.sh)
# ENABLE_PREFIX_CACHE=1 (default in run_dp_template.sh)
```
