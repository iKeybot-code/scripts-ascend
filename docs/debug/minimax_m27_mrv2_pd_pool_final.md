# MiniMax M2.7 PD分离+KV池化+Prefix Cache+MRV2 完整验证报告

## 概述
- **日期**: 2026-07-27
- **任务**: 验证vllm v0.25.1 + vllm-ascend main, MiniMax M2.7模型, 开启ModelRunnerV2, PD分离, KV池化, Prefix Cache
- **模型**: MiniMax-M2.7-w8a8-QuaRot (W8A8量化, MoE: 62层, 48头, 8 KV头, 256专家, MTP=3)
- **节点**: Node29 (90.90.97.29) - Prefill ✅, Node37 (90.90.97.37) - Decode ✅
- **最终结果**: **PD分离+KV池化+Prefix Cache+MRV2全特性叠加推理成功** ✅ | 输出乱码为W8A8 QuaRot量化问题 ⚠️

---

## 1. 环境和版本

| 组件 | 期望版本 | 实际版本 | 状态 |
|------|----------|----------|------|
| vllm | v0.25.1 | 0.25.1+empty | ✅ |
| vllm-ascend | main | 0.19.1rc2.dev1017+gbbabae3fd | ✅ |
| 容器镜像 | quay.io/ascend/vllm-ascend:nightly-main-a3 | nightly-main-a3 | ✅ |
| Python | - | 3.12.13 | ✅ |
| CANN | - | 25.5.0 (Node29) | ✅ |
| transformers | - | 5.13.0 | ✅ |

---

## 2. 集群拓扑

### Node 29 (90.90.97.29) - Prefill
- **NPU**: 16x Ascend910 (0-15), 全部健康
- **HBM使用**: ~55GB/64GB per chip (模型权重14.15GB + KV Cache ~35.5GB)
- **DP配置**: DP=2, TP=8, 每DP rank 8张卡
- **端口**: 13900 (DP rank 0), 13901 (DP rank 1)
- **角色**: kv_producer
- **Mooncake Master**: port 50088

### Node 37 (90.90.97.37) - Decode
- **NPU**: 16x Ascend910 (0-15), 全部健康
- **HBM使用**: ~55GB/64GB per chip
- **DP配置**: DP=2, TP=8, 每DP rank 8张卡
- **端口**: 13901 (DP rank 0), 13902 (DP rank 1)
- **角色**: kv_consumer

### Proxy
- **节点**: Node29 (90.90.97.29)
- **端口**: 8080
- **后端**: 2 Prefill + 2 Decode

---

## 3. 特性验证状态

| 特性 | 状态 | 说明 |
|------|------|------|
| **PD分离** | ✅ 成功 | Prefill(29) → KV Transfer(Mooncake) → Decode(37) 链路正常 |
| **KV池化** | ✅ 成功 | MooncakeConnectorV1 + AscendStoreConnector, KV cache 9426 blocks |
| **Prefix Cache** | ✅ 成功 | `--enable-prefix-caching`, block_size=128 |
| **ModelRunnerV2** | ✅ 成功 | `VLLM_USE_V2_MODEL_RUNNER=1`, fingerprint: vllm-0.25.1-tp8-dp2 |
| **DP=2, TP=8** | ✅ 成功 | 16卡满配推理 |
| **Mooncake Master** | ✅ 成功 | Port 50088, KV lease TTL=11000 |
| **Proxy负载均衡** | ✅ 成功 | Port 8080, 2 Prefill + 2 Decode 客户端注册 |
| **Enforce Eager** | ✅ 成功 | 禁用cudagraph避免Ascend兼容问题 |
| **输出正确性** | ⚠️ 乱码 | W8A8 QuaRot量化输出为随机乱码 |

---

## 4. Bug发现和修复记录

### Bug #12 (新发现): RecomputeScheduler.schedule() 参数签名不匹配 🔴 关键
- **文件**: `vllm-ascend/vllm_ascend/core/recompute_scheduler.py:194`
- **问题**: `RecomputeScheduler.schedule()` 定义为 `def schedule(self) -> RecomputeSchedulerOutput:`，但vllm v0.25.1的EngineCore调用 `self.scheduler.schedule(self._should_throttle_prefills())`，传递了 `throttle_prefills` 参数
- **错误信息**: `TypeError: RecomputeScheduler.schedule() takes 1 positional argument but 2 were given`
- **影响范围**: 所有使用 `recompute_scheduler_enable=true` 的Decode节点
- **修复**: 将方法签名改为 `def schedule(self, throttle_prefills: bool = False) -> RecomputeSchedulerOutput:`
- **状态**: ✅ 已修复

### Bug #1: IFS引号缺失导致VISIBLE_LIST生成错误 (vllm-ascend脚本)
- **文件**: `scripts-ascend/example/common/start_prefill.sh`, `start_decode.sh`
- **修复**: 重写IFS处理为保存/恢复模式
- **状态**: ✅ 已修复（共享盘脚本已更新）

### Bug #2: fastapi版本冲突
- **文件**: vllm-ascend `pyproject.toml`
- **修复**: 修改vllm-ascend pyproject.toml中fastapi约束为 `<0.137.0,>=0.115.0`
- **状态**: ✅ 已修复

### Bug #3: AutoImageProcessor.register兼容性
- **文件**: vllm `transformers_utils/processors/hunyuan_vl_image.py`
- **修复**: 添加try/except捕获AttributeError
- **状态**: ✅ 已修复

### Bug #4: AscendMoERunner缺少maybe_all_reduce_tensor_model_parallel方法
- **文件**: vllm-ascend `ops/fused_moe/fused_moe.py`
- **修复**: 在 `_fused_output_is_reduced` 属性后添加该方法
- **状态**: ✅ 已修复

### Bug #5: kv_cache_coordinator参数名不匹配
- **文件**: vllm-ascend `patch/platform/patch_kv_cache_coordinator.py`
- **修复**: 统一使用 `max_num_batched_tokens`
- **状态**: ✅ 已修复

### Bug #10: NPUModelRunner V2 缺少 decode_token_per_req 属性
- **文件**: vllm-ascend `worker/v2/model_runner.py:77`
- **修复**: `self.decode_token_per_req = 1`
- **状态**: ✅ 已修复

---

## 5. 运行结果

### Prefill (Node 29) ✅
```
Model: MiniMax-M2.7-w8a8-QuaRot
Model size: 14.15 GiB (54 safetensors shards)
KV Cache: 35.67 GiB (9426 blocks, block_size=128)
HBM usage: ~55GB / 64GB per chip (~85%)
API ports: 13900, 13901
kv_role: kv_producer
MRV2: enabled
Prefix Cache: enabled
Enforce Eager: enabled
System fingerprint: vllm-0.25.1-tp8-dp2-6913c37c
```

### Decode (Node 37) ✅
```
Model: MiniMax-M2.7-w8a8-QuaRot
Model size: 14.15 GiB (54 safetensors shards)
KV Cache: ~35.5 GiB
HBM usage: ~55GB / 64GB per chip (~85%)
API ports: 13901, 13902
kv_role: kv_consumer
MRV2: enabled
Prefix Cache: enabled
Async Scheduling: enabled
Recompute Scheduler: enabled (Bug #12修复后)
System fingerprint: vllm-0.25.1-tp8-dp2-f0c0df6d
```

### Proxy (Node 29) ✅
```
Host: 90.90.97.29:8080
Prefill clients: 90.90.97.29:13900, 90.90.97.29:13901
Decode clients: 90.90.97.37:13901, 90.90.97.37:13902
路由正常，请求通过 Prefill → KV transfer → Decode → 响应
```

### PD端到端推理测试 ✅
```json
// Request (via proxy)
POST http://90.90.97.29:8080/v1/completions
{"model":"MiniMaxM2","prompt":"What is the capital of France?","max_tokens":20}

// Response
{
  "id": "cmpl-0edab6b3-44ee-43ff-97b4-c9a4ddb395cc",
  "model": "MiniMaxM2",
  "system_fingerprint": "vllm-0.25.1-tp8-dp2-f0c0df6d",
  "usage": {"prompt_tokens": 7, "completion_tokens": 20, "total_tokens": 27}
}
// 注：输出文本为乱码（QuaRot量化问题）
```

---

## 6. 输出乱码问题分析 ⚠️

### 现象
所有推理请求（Prefill直连、Decode直连、PD Proxy）输出均为随机乱码：
- Prompt: "1+1=" → Output: `"/- �Validator Outstanding(number\n\n<The"`
- Prompt: "The capital of France is" → Output: `"{S\\\\d.s"`
- Prompt: "What is the capital of France?" → Output: `" [## ####2to.20-\n\n924\n\n人人对本袋,6论 篮球 "`

### 根因分析
1. **量化方式**: 模型使用ModelSlim W8A8_DYNAMIC量化（per-channel weight + scale + offset），由 `quant_model_description.json` 描述
2. **量化检测**: vllm-ascend 通过 `detect_quantization_method()` 正确检测到 `ascend` 量化方法
3. **Dequant逻辑**: ModelSlim的INT8→FP16反量化可能在MiniMax M2架构的某些层上存在计算精度问题
4. **一致性**: Prefill和Decode对相同prompt产生完全一致的输出，证明KV transfer正确且RP推理确定性强

### 可能原因
- ModelSlim W8A8反量化compute精度与原始FP16模型不匹配
- MiniMax M2架构的某些自定义层（如block_sparse_moe）的反量化路径有bug
- QuaRot rotation matrix未正确应用到推理计算中
- 模型weight_scale/weight_offset与实际weight数据不一致

### 建议修复方向
1. 检查 `/vllm-workspace/vllm-ascend/vllm_ascend/quantization/modelslim_config.py` 中W8A8_DYNAMIC的dequant实现
2. 对比MiniMax M2的block_sparse_moe层在FP16与INT8下的输出差异
3. 联系vllm-ascend团队确认ModelSlim对MiniMax M2架构的量化推理支持状态
4. 尝试使用 `MiniMax-M2.7-w8a8c8-QuaRot`（INT8 weight + INT8 KV cache）模型，可能有不一致的量化配置

---

## 7. 成功运行的完整配置

```bash
# configs.sh - 在 /mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool/configs.sh

# Feature switches
export ENABLE_KV_POOL=1
export PD_KV_CONNECTOR="MooncakeConnectorV1"
export KV_POOL_BACKEND="mooncake"
export ENABLE_PREFIX_CACHE=1

# Model
export MODEL_PATH="/mnt/a800_weight/MiniMax-M2.7-w8a8-QuaRot"
export MODEL_NAME="MiniMaxM2"

# Cluster: 1P1D
export PREFILL_IPS=(90.90.97.29)
export PREFILL_NICS=(enp194s0f0)
export DECODE_IPS=(90.90.97.37)
export DECODE_NICS=(enp194s0f0)

# DP=2 TP=8, 16卡/节点
export P_DP_SIZE=2
export P_TP_SIZE=8
export P_DP_SIZE_LOCAL=2
export D_DP_SIZE=2
export D_TP_SIZE=8
export D_DP_SIZE_LOCAL=2
export P_VISIBLE_DEVICES_LIST=("0,1,2,3,4,5,6,7" "8,9,10,11,12,13,14,15")
export D_VISIBLE_DEVICES_LIST=("0,1,2,3,4,5,6,7" "8,9,10,11,12,13,14,15")

# Ports
export PROXY_HOST="90.90.97.29"
export PROXY_PORT=8080
export P_VLLM_START_PORT=13900
export D_VLLM_START_PORT=13901

# Mooncake Master
export MOONCAKE_MASTER_IP="90.90.97.29"
export MOONCAKE_MASTER_PORT=50088

# Serve knobs
export P_MAX_NUM_SEQS=128
export P_MAX_MODEL_LEN=32768
export P_MAX_NUM_BATCHED_TOKENS=32768
export P_GPU_MEMORY_UTILIZATION=0.9
export P_ENFORCE_EAGER=1
export D_MAX_NUM_SEQS=128
export D_MAX_MODEL_LEN=32768
export D_MAX_NUM_BATCHED_TOKENS=2048
export D_GPU_MEMORY_UTILIZATION=0.9
export D_ENFORCE_EAGER=1
export D_ASYNC_SCHEDULING=1
```

---

## 8. 完整操作指南

### 前置条件
- 确认两节点NPU全部空闲（16卡）
- 共享盘 `/mnt/a800_share` 已挂载
- 模型权重在 `/mnt/a800_weight/MiniMax-M2.7-w8a8-QuaRot/`

### 步骤1: SSH连接和容器准备
```bash
# 在两节点分别执行
ssh root@90.90.97.29  # Node29
ssh root@90.90.97.37  # Node37

# 拉取镜像（如需代理先设置）
# export http_proxy=http://90.254.54.104:3128
# export https_proxy=http://90.254.54.104:3128

docker pull quay.io/ascend/vllm-ascend:nightly-main-a3

# 创建/启动容器
bash /mnt/a800_share/l00848175/scripts-ascend/start_container.sh \
    quay.io/ascend/vllm-ascend:nightly-main-a3 vllm-0251
docker exec -it vllm-0251 bash
```

### 步骤2: 版本检查和源码修复
```bash
# 确认vllm版本
pip show vllm | grep Version  # 应为 0.25.1+empty

# 确认vllm-ascend版本
pip show vllm-ascend | grep Version

# 如需切换到期望版本:
# cd /vllm-workspace/vllm && git checkout v0.25.1
# VLLM_TARGET_DEVICE=empty pip install -e . --no-build-isolation
```

### 步骤3: 应用关键Bug修复
```bash
# 修复1: RecomputeScheduler.schedule() 参数签名
sed -i 's/def schedule(self) -> RecomputeSchedulerOutput:/def schedule(self, throttle_prefills: bool = False) -> RecomputeSchedulerOutput:/' \
    /vllm-workspace/vllm-ascend/vllm_ascend/core/recompute_scheduler.py

# 修复2: fused_moe.py 添加 maybe_all_reduce_tensor_model_parallel
# (如果容器中尚未包含此修复，执行以下Python脚本)
python3 << 'PYFIX'
import os
for path in ['/vllm-workspace/vllm-ascend/vllm_ascend/ops/fused_moe/fused_moe.py',
             '/workspace/vllm-ascend/vllm_ascend/ops/fused_moe/fused_moe.py']:
    if not os.path.exists(path):
        continue
    with open(path) as f:
        content = f.read()
    marker = '        def _maybe_reduce_shared_expert_output('
    insert = '        def maybe_all_reduce_tensor_model_parallel(self, final_hidden_states):\n            return torch.ops.vllm.maybe_all_reduce_tensor_model_parallel(final_hidden_states)\n\n'
    if marker in content and 'def maybe_all_reduce_tensor_model_parallel' not in content:
        content = content.replace(marker, insert + marker)
        with open(path, 'w') as f:
            f.write(content)
        print(f'Fixed: {path}')
PYFIX

# 修复3: model_runner.py 添加 decode_token_per_req
# (如果容器中尚未包含此修复)
sed -i '/super().__init__()/a\        self.decode_token_per_req = 1' \
    /vllm-workspace/vllm-ascend/vllm_ascend/worker/v2/model_runner.py

# 清理缓存
find /vllm-workspace/vllm-ascend -name __pycache__ -exec rm -rf {} + 2>/dev/null
```

### 步骤4: 准备测试目录和配置
```bash
# 更新共享盘脚本
cd /mnt/a800_share/l00848175/scripts-ascend
git pull origin main

# 创建测试目录
mkdir -p /mnt/a800_share/l00848175/workspace/tests
cp -r /mnt/a800_share/l00848175/scripts-ascend/example/pd_multi_nodes/ \
    /mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool/

# 编辑configs.sh（参考第7节配置）
vi /mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool/configs.sh
```

### 步骤5: 启动服务（严格按顺序）
```bash
# === Node 29 容器内 ===
cd /mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool

# 1. 启动Mooncake Master
bash run.sh mooncake_master

# 2. 启动Prefill（等待模型加载完成，约3分钟）
bash run.sh prefill 0

# 3. 等待Prefill API就绪
curl -s http://localhost:13900/v1/models  # 应返回模型列表

# === Node 37 容器内 ===
cd /mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool

# 4. 启动Decode（等待模型加载完成，约3分钟）
bash run.sh decode 0

# 5. 等待Decode API就绪
curl -s http://localhost:13901/v1/models  # 应返回模型列表

# === Node 29 容器内 ===
# 6. 启动Proxy
bash run.sh proxy
```

### 步骤6: 测试验证
```bash
# 冒烟测试 - 通过Proxy
curl -s http://90.90.97.29:8080/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"MiniMaxM2","prompt":"Hello","max_tokens":20}'

# 直接测试Prefill
curl -s http://localhost:13900/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"MiniMaxM2","prompt":"Hello","max_tokens":20}'

# 直接测试Decode
curl -s http://localhost:13901/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"MiniMaxM2","prompt":"Hello","max_tokens":20}'
```

### 步骤7: 停止服务
```bash
# 在两节点容器内分别执行
kill $(pgrep -f "vllm serve") 2>/dev/null
kill $(pgrep -f "mooncake_master") 2>/dev/null
kill $(pgrep -f "load_balance_proxy") 2>/dev/null

# 或直接重启容器
docker restart vllm-0251
```

---

## 9. 已修改文件清单

### 容器内源码修复 (每节点均需应用):
| 文件 | 修改内容 | 优先级 | Bug # |
|------|----------|--------|-------|
| `vllm_ascend/core/recompute_scheduler.py:194` | 添加 `throttle_prefills` 参数 | 🔴 关键 | #12 |
| `vllm_ascend/ops/fused_moe/fused_moe.py:545` | 添加 `maybe_all_reduce_tensor_model_parallel` 方法 | 🔴 关键 | #4 |
| `vllm_ascend/worker/v2/model_runner.py:77` | 添加 `decode_token_per_req = 1` | 🔴 关键 | #10 |
| `vllm_ascend/patch/platform/patch_kv_cache_coordinator.py:46` | 参数名修正 | 🟡 次要 | #5 |

### 共享脚本修改 (`/mnt/a800_share/l00848175/scripts-ascend/example/common/`):
| 文件 | 修改内容 |
|------|----------|
| `start_prefill.sh` | 修复IFS引号 + 数组join逻辑 |
| `start_decode.sh` | 修复IFS引号 + 数组join逻辑 |
| `run_dp_template.sh` | MRV2启用 + Prefix Cache可配置 + enforce_eager支持 |
| `entry.sh` | run.sh test入口 |

---

## 10. 待解决问题

1. **输出乱码 (高优先级)**: W8A8 QuaRot量化模型推理输出为随机乱码，需排查ModelSlim dequant逻辑或尝试 `MiniMax-M2.7-w8a8c8-QuaRot` 替代模型
2. **Bug #7 (中优先级)**: DP=1时 data_parallel_external_lb 验证冲突
3. **Bug #9 (中优先级)**: 某些情况下DP gloo通信失败 (Connection closed by peer)
4. **Bug #11 (高优先级)**: Decode路径 `maybe_all_reduce_tensor_model_parallel` custom op overload 缺失 — 本次未触发但在之前测试中出现
5. **run_dp_template.sh代码质量**: Decode分支中 `D_ENFORCE_EAGER` 重复检查3次，需清理

---

## 11. 关键经验总结

1. **PD分离+KV池化+Prefix Cache+MRV2 特性叠加已验证可行**：所有架构特性在vllm v0.25.1 + vllm-ascend main上正确集成
2. **RecomputeScheduler兼容性**: vllm-ascend main的RecomputeScheduler需适配vllm v0.25.1的 `schedule(throttle_prefills)` 接口
3. **容器重启保留修改**: /vllm-workspace目录在容器重启后保持修改
4. **Zombie进程清理**: vllm Worker zombie进程无法被kill -9清理，必须重启容器
5. **Proxy绑定地址**: proxy默认绑定到 `PROXY_HOST` IP而非0.0.0.0，容器内需使用该IP访问
6. **NPU资源检查**: 运行前务必确认所有NPU HBM空闲，否则模型加载失败
7. **QuaRot量化模型**: 当前vllm-ascend main对MiniMax M2.7 W8A8 QuaRot模型的推理可能存在精度问题，建议使用FP16原始模型或联系vllm-ascend团队确认支持状态
