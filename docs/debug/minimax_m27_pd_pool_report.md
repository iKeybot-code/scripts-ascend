# MiniMax-M2.7 PD分离+KV池化 搭建报告

> **日期**: 2026-07-25/26  
> **操作人**: l00848175  
> **环境**: Ascend A3 (2×16x Ascend910), HCE 3.0 / Ubuntu 24.04 aarch64

---

## 1. 概述

在双节点 Ascend 集群上搭建 MiniMax-M2.7 PD 分离+KV 池化 vLLM 推理服务。目标版本：vllm v0.25.1 + vllm-ascend main，开启 ModelRunnerV2 + prefix cache。

### 1.1 拓扑规划

| 角色 | 节点 | IP | NPU | 网卡 | TP |
|------|------|-----|-----|------|-----|
| Prefill (P) | k8s-node-15 | 90.90.97.15 | 16×Ascend910 | enp194s0f0 (data0:10.10.1.15) | 16 |
| Decode (D) | node-97-42 | 90.90.97.42 | 16×Ascend910 | enp194s0f0 (data0:10.10.1.42) | 16 |
| Master | 90.90.97.15 | - | - | - | - |
| Proxy | 90.90.97.15 | - | - | - | - |

### 1.2 模型信息

- **主模型**: `/mnt/a800_weight/MiniMax-M2.7-w8a8-QuaRot` (216GB, W8A8量化, 54 shards)
- **Eagle 投机模型**: `/mnt/a800_weight/MiniMax-M2.7-eagle-model-2` (2.5GB)
- **NFS 存储**: `10.10.0.11:/weight` 和 `10.10.0.11:/share` (两节点均通过 data0 网口可达)

---

## 2. 已完成的操作

### 2.1 环境准备 ✅

- SSH 免密互信：本地↔15, 本地↔42, 15↔42 均已配置
- 容器：两节点均创建 vllm-0251 (基于 2026-07-20 Ubuntu 镜像)
- Git proxy：HTTP_PROXY=http://90.254.58.25:3128，sslverify=false
- scripts-ascend：NFS 已同步最新 main 分支

### 2.2 工作目录 ✅

```
/mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool/
├── configs.sh              # MiniMax-M2.7 配置 (MRV2=1, PrefixCache=1)
├── run.sh                  # 统一入口 (mooncake_master|prefill|decode|proxy|test)
├── start_mooncake_master.sh
├── start_prefill.sh
├── start_decode.sh
├── start_proxy.sh
├── test_curl.sh
├── mooncake.json           # Master: 90.90.97.15:50088
├── common/                 # 公共脚本 (已修复)
│   ├── run_dp_template.sh  # MRV2 + prefix cache + DP=1 fix + MiniMax extras
│   ├── start_prefill.sh    # config_helpers 引用修复
│   ├── start_decode.sh     # 同上
│   └── ...
└── logs/
```

### 2.3 服务状态

| 组件 | 节点 | 状态 | 说明 |
|------|------|------|------|
| Mooncake Master | 97.15 | ✅ 已成功启动 | Port 50088 |
| Prefill (P) | 97.15 | ❌ 启动失败 | vllm-ascend 版本不兼容 |
| Decode (D) | 97.42 | ⏸️ 待P就绪 | - |
| Proxy | - | ⏸️ - | - |

---

## 3. Bug 分析与修复记录

### Bug #1: start_prefill.sh/start_decode.sh IFS 引号未闭合 🔴→🟢

**文件**: `scripts-ascend/example/common/start_prefill.sh` (line 35)

**现象**:
```bash
VISIBLE_LIST=$(IFS='; echo "${P_VISIBLE_DEVICES_LIST[*]}")
```
单引号在 `'` 处未闭合，bash 将后续内容解释为字面量字符串，导致 `unexpected EOF`。

**修复**: 简化为 `VISIBLE_LIST=$(echo "${P_VISIBLE_DEVICES_LIST[*]}")`

---

### Bug #2: config_helpers.sh 未 source 🔴→🟢

**现象**: `resolve_node_meta: command not found`

**根因**: `start_prefill.sh` 和 `start_decode.sh` 只用 source 了 `load_configs.sh`、`env_common.sh`、`kv_transfer_config.sh`，缺少 `config_helpers.sh`。

**修复**: 在 `kv_transfer_config.sh` source 后添加 `source "${COMMON_DIR}/config_helpers.sh"`

---

### Bug #3: vllm 0.25.1 DP=1 时 external_lb 校验冲突 🔴→🟢

**现象**:
```
Value error, data_parallel_external_lb can only be set when data_parallel_size > 1
```

**根因**: vllm 0.25.1 在 `data-parallel-size=1` 且传递了 `--data-parallel-address`/`--data-parallel-rpc-port` 时，会设置 `data_parallel_external_lb=True` 并触发 Pydantic 校验错误。

**修复**: 在 `run_dp_template.sh` 中添加条件判断，DP=1 时不传任何 DP 参数：
```bash
if [[ "${DP_SIZE}" -gt 1 ]]; then
    DP_ARGS=(--data-parallel-size "${DP_SIZE}" ...)
else
    DP_ARGS=()
fi
```

---

### Bug #4: entry.sh action 名称变更 🔴→🟢

**现象**: `[entry] unknown action: master`

**根因**: scripts-ascend 最新 main 分支将 action 从 `master` 改为 `mooncake_master`。

**修复**: 使用 `bash run.sh mooncake_master` 替代 `bash run.sh master`

---

### Bug #5: vllm-ascend 0.23.0rc2 与 vllm 0.25.1 深度不兼容 🔴 (未解决 - Blocker)

**现象 (链式崩溃)**:

1. **Import 失败 #1**: `vllm.tool_parsers.deepseekv4_tool_parser` 在 vllm 0.25.1 中被移除
   - 修复：注释 `patch/platform/__init__.py` 中的 deepseek_v4 导入
   
2. **Import 失败 #2**: `_compute_block_stats_kernel` 在 vllm 0.25.1 中不存在
   - vllm 0.25.1 将 spec_decode 函数全部重命名（如 `_compute_block_stats_kernel` → `_compute_local_logits_stats_kernel`）
   - vllm-ascend 的 `rejection_sampler_utils.py` 引用了旧 API

3. **V1 引擎崩溃**: `WorkerProc failed to start` + `Engine core initialization failed`
   - vllm 0.25.1 默认启用 V1 引擎，架构与 vllm 0.23.0 完全不同
   - vllm-ascend 0.23.0rc2 的 worker patch 无法适配 V1 引擎

4. **V0 引擎退避**: `VLLM_USE_V1=0` 尝试后仍有 spec_decode 导入错误

**结论**: vllm-ascend 0.23.0rc2（Docker 镜像预装版本）与 vllm 0.25.1 完全不兼容。**必须使用 vllm-ascend main 分支。**

---

### Bug #6: vllm-ascend main 编译失败 🔴 (未解决)

**现象**: `COMPILE_CUSTOM_KERNELS=1 pip install -e .` 在 aarch64 上编译时间长且可能 silent-fail

**已知问题**:
- `setuptools_rust` 缺失（已修复：`pip install setuptools_rust`）
- Ascend C 自定义算子编译耗时 10-30 分钟
- C 编译依赖特定 NPU 工具链版本

---

### Bug #7: Mooncake Master 端口冲突 🔴→🟢

**现象**: `bind port: 9003 error: Address already in use`

**修复**: `fuser -k 50088/tcp; fuser -k 9003/tcp` 清理残留进程

---

## 4. 配置变更汇总

### configs.sh 关键参数

```bash
# 模型
MODEL_PATH=/mnt/a800_weight/MiniMax-M2.7-w8a8-QuaRot
MODEL_NAME=minimax
EAGLE_MODEL_PATH=/mnt/a800_weight/MiniMax-M2.7-eagle-model-2

# 特性开关
ENABLE_KV_POOL=1              # KV 池化
VLLM_USE_V2_MODEL_RUNNER=1    # Model Runner V2
ENABLE_PREFIX_CACHING=1       # Prefix Cache

# 并行
P_TP_SIZE=16  D_TP_SIZE=16    # 大模型全卡 TP
P_DP_SIZE=1   D_DP_SIZE=1     # 单 DP

# MoE + 量化
--enable-expert-parallel
--quantization ascend

# Eagle 投机解码
--speculative_config '{"method":"eagle3","model":"...","num_speculative_tokens":1}'

# 长上下文
P_MAX_MODEL_LEN=200000
D_MAX_MODEL_LEN=200000
```

### run_dp_template.sh 关键修改

1. DP=1 条件逻辑（Bug #3 修复）
2. ENABLE_PREFIX_CACHING 控制 `--enable-prefix-caching` vs `--no-enable-prefix-caching`
3. VLLM_USE_V1=0（V0 引擎兼容降级）
4. MiniMax 扩展参数注入（P_EXTRA_SERVE_ARGS / D_EXTRA_SERVE_ARGS）

---

## 5. 完整操作指南

### 5.1 前置条件

```bash
# SSH 免密
ssh-keygen -t ed25519 -f ~/.ssh/id_rsa -N ""
ssh-copy-id root@90.90.97.15
ssh-copy-id root@90.90.97.42
```

### 5.2 创建容器

```bash
# 两节点均执行
docker run --name vllm-0251 --net=host --shm-size=500g \
  --device /dev/davinci0 ... --device /dev/davinci15 \
  --device /dev/davinci_manager --device /dev/devmm_svm --device /dev/hisi_hdc \
  -w /workspace -v /home:/home -v /mnt:/mnt \
  -v /usr/local/Ascend/driver/lib64/:/usr/local/Ascend/driver/lib64/ \
  -v /usr/local/Ascend/driver/version.info:/usr/local/Ascend/driver/version.info \
  -v /etc/ascend_install.info:/etc/ascend_install.info \
  -v /etc/hccn.conf:/etc/hccn.conf \
  -v /mnt/sfs_turbo/.cache:/root/.cache \
  -itd vllm-ascend:dev-26.1.0.day20260720-800I-A3-py311-Ubuntu24.04-lts-aarch64 bash
```

### 5.3 安装 vllm 0.25.1 + vllm-ascend main

```bash
docker exec vllm-0251 bash -c '
export https_proxy=http://90.254.58.25:3128
export http_proxy=http://90.254.58.25:3128

# 基础依赖
pip install setuptools_rust

# Clone vllm v0.25.1
cd /workspace
git clone --depth 1 --branch v0.25.1 https://github.com/vllm-project/vllm.git vllm-src
cd vllm-src
VLLM_TARGET_DEVICE=empty pip install -e . --no-build-isolation

# Clone vllm-ascend main (并编译 C 扩展)
cd /workspace
git clone --depth 1 --branch main https://github.com/vllm-project/vllm-ascend.git vllm-ascend-src
cd vllm-ascend-src
COMPILE_CUSTOM_KERNELS=1 pip install -e . --no-build-isolation
'
```

### 5.4 同步脚本与配置

```bash
# NFS 上更新
cd /mnt/a800_share/l00848175/scripts-ascend
git remote set-url origin https://TOKEN@github.com/iKeybot-code/scripts-ascend.git
git pull origin main

# 创建工作目录
cp -r scripts-ascend/example/pd_multi_nodes/ \
  /mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool/

# 修改 configs.sh（参见第 4 节）
# 修改 common/run_dp_template.sh（参见第 4 节）
```

### 5.5 启动服务

```bash
# 终端1 (97.15): Mooncake Master
docker exec vllm-0251 bash -c '
  cd /mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool
  bash run.sh mooncake_master
'

# 终端2 (97.15): Prefill
docker exec vllm-0251 bash -c '
  cd /mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool
  bash run.sh prefill 0
'

# 终端3 (97.42): Decode
docker exec vllm-0251 bash -c '
  cd /mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool
  bash run.sh decode 0
'

# 终端4 (97.15): Proxy
docker exec vllm-0251 bash -c '
  cd /mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool
  bash run.sh proxy
'

# 冒烟测试
docker exec vllm-0251 bash -c '
  cd /mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool
  bash run.sh test 1
'
```

### 5.6 AIME2025 精度测评

```bash
# 参考 /mnt/a800_share/l00848175/scripts-ascend/aisbench
# 使用 pd_gsm8k_acc_top10 配置文件
```

### 5.7 停止服务

```bash
# 97.15
docker exec vllm-0251 bash -c 'pkill -f mooncake_master; pkill -f launch_online_dp; pkill -f vllm'
# 97.42
docker exec vllm-0251 bash -c 'pkill -f launch_online_dp; pkill -f vllm'
```

---

## 6. 待解决事项

| 优先级 | 事项 | 阻塞原因 |
|--------|------|----------|
| **P0** | vllm-ascend main + C 扩展编译 | C 编译时间长且 silent-fail，需排查 NPU SDK 工具链 |
| P1 | Eagle 模型路径验证 | 需确认 /mnt/a800_weight/MiniMax-M2.7-eagle-model-2 兼容性 |
| P1 | D 节点 vllm-ascend 版本对齐 | 两节点 vllm-ascend 版本不一致可能导致 PD 通信异常 |
| P2 | AIME2025 精度测试 | 待服务启动后执行 |
| P3 | scripts-ascend 向官方提 MR | 修复 Bug #1, #2 等通用性问题 |

---

## 7. 附录

### 7.1 节点信息

| 属性 | 97.15 (P) | 97.42 (D) |
|------|-----------|-----------|
| OS | HCE 3.0 | Ubuntu 24.04 |
| 内核 | 6.6.0-72.0.0.76.hce3 | - |
| NPU | 16×Ascend910 | 16×Ascend910 |
| 存储网口 | data0.2000 (10.10.1.15) | data0.2000 (10.10.1.42) |
| Docker 镜像 | vllm-ascend:20260720-Ubuntu | vllm-ascend:20260720-cann9.1.0-Ubuntu |

### 7.2 容器内关键路径

| 路径 | 说明 |
|------|------|
| `/workspace/vllm-src/` | vllm v0.25.1 源码 |
| `/workspace/vllm-ascend-src/` | vllm-ascend main 源码 |
| `/mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool/` | 工作目录 |
| `/mnt/a800_share/l00848175/scripts-ascend/` | 样例脚本 |
| `/mnt/a800_weight/MiniMax-M2.7-w8a8-QuaRot/` | 模型权重 |

### 7.3 已修改的文件清单

| 文件 | 修改内容 |
|------|----------|
| `configs.sh` | MiniMax-M2.7 完整配置（MRV2, PrefixCache, TP16, MoE） |
| `common/run_dp_template.sh` | DP=1 fix, prefix cache toggle, MiniMax extras |
| `common/start_prefill.sh` | config_helpers source 修复, IFS 引号修复 |
| `common/start_decode.sh` | 同上 |
| `common/mooncake.json` | Master 地址 90.90.97.15:50088 |
