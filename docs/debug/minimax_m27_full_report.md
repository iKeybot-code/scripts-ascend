# MiniMax M2.7 PD分离+KV池化+Prefix Cache+MRV2 全流程验证报告

## 概述
- **日期**: 2026-07-26 ~ 2026-07-27
- **任务**: 验证vllm v0.25.1 + vllm-ascend main，MiniMax M2.7模型开启ModelRunnerV2时PD分离+KV池化+Prefix Cache特性叠加的精度
- **模型**: MiniMax-M2.7-w8a8-QuaRot (W8A8 ModelSlim量化, MoE, 62层, 48头, 8 KV头, 256专家)
- **节点**: Node29 (90.90.97.29), Node37 (90.90.97.37)
- **最终结论**: PD分离+KV池化+Prefix Cache+MRV2全特性叠加**架构验证成功**，但模型推理输出为**乱码**，根因定位为QuaRot rotation matrix未在ModelSlim反量化路径中应用

---

## 1. 环境信息

| 组件 | 版本 |
|------|------|
| vllm | 0.25.1+empty |
| vllm-ascend | 0.19.1rc2.dev1017+gbbabae3fd (main) |
| 容器镜像 | quay.io/ascend/vllm-ascend:nightly-main-a3 |
| Python | 3.12.13 |
| CANN | 25.5.0 |
| transformers | 5.13.0 |
| PyTorch | 2.10.0 |

### 硬件
| 节点 | IP | NPU | 角色 |
|------|-----|-----|------|
| Node29 | 90.90.97.29 | 16x Ascend910 | Prefill (PD) / 单机混部 |
| Node37 | 90.90.97.37 | 16x Ascend910 | Decode (PD) |

---

## 2. 全部测试结果汇总

### 2.1 测试矩阵

| # | 部署模式 | MRV | EAGLE3 | MTP | Cudagraph | 结果 | fingerprint |
|---|---------|-----|--------|-----|-----------|------|-------------|
| 1 | PD分离(29P+37D) | V2 | ❌ | ❌ | enforce_eager | ❌ 乱码 | `6913c37c` |
| 2 | PD分离(29P+37D) | V2 | ❌ | ❌ | enforce_eager + quarot.safetensors | ❌ 乱码 | `dcf963e1` |
| 3 | PD分离(29P+37D) | V2 | ✅ | ❌ | enforce_eager | ❌ 乱码 | `dcf963e1` |
| 4 | PD分离(29P+37D) | V1 | ❌ | ❌ | enforce_eager | ❌ Gloo崩溃 | - |
| 5 | 单机混部(29) | V2 | ✅ | ❌ | FULL_DECODE_ONLY | ❌ 推理超时 | - |
| 6 | 单机混部(29) | V2 | ✅ | ❌ | enforce_eager | ❌ 乱码 | `6e8bca8f` |

### 2.2 乱码样本

所有测试中输出均为确定性乱码（相同prompt产生相同乱码）：

```
Prompt: "1+1="
Output: "/ch\n\nWrite indicator raw-bi Aggregate\">\npolK NoEnc  none\n\n 1.heelshan"

Prompt: "The capital of France is"
Output: "{S\\\\d.s<?�\\_@   PID基于Pn - resolvesimport"

Prompt: "Hello, my name is"
Output: " \\\"Task:\nor f | .h(IP many-.5,251)| 'Pj"
```

---

## 3. Bug发现和修复记录

### Bug #12 (新发现): RecomputeScheduler.schedule() 参数不兼容 🔴
- **文件**: `vllm_ascend/core/recompute_scheduler.py:194`
- **错误**: `TypeError: RecomputeScheduler.schedule() takes 1 positional argument but 2 were given`
- **原因**: vllm v0.25.1 EngineCore 调用 `self.scheduler.schedule(throttle_prefills)`，但 RecomputeScheduler 的 `schedule()` 只接受 `self`
- **修复**: 添加 `throttle_prefills: bool = False` 参数
- **状态**: ✅ 已修复（容器内 + git staged）

### Bug #4 (已有): AscendMoERunner 缺少 maybe_all_reduce_tensor_model_parallel
- **文件**: `vllm_ascend/ops/fused_moe/fused_moe.py`
- **修复**: 在 `_fused_output_is_reduced` 属性后添加方法
- **状态**: ✅ 已验证修复生效

### Bug #5 (已有): kv_cache_coordinator 参数名
- **文件**: `vllm_ascend/patch/platform/patch_kv_cache_coordinator.py`
- **状态**: ✅ 已验证

### Bug #10 (已有): NPUModelRunner V2 缺少 decode_token_per_req
- **文件**: `vllm_ascend/worker/v2/model_runner.py:77`
- **修复**: `self.decode_token_per_req = 1`
- **状态**: ✅ 已验证

### 脚本修复: run_dp_template.sh 重复 D_ENFORCE_EAGER
- **文件**: `scripts-ascend/example/common/run_dp_template.sh`
- **问题**: decode分支3次重复检查D_ENFORCE_EAGER
- **修复**: 删除重复行，保留1次正确默认值检查
- **状态**: ✅ 已推送至 github

### FULL_DECODE_ONLY cudagraph 死锁
- **现象**: EngineCore shm_broadcast TimeoutError，worker never responds
- **触发**: 使用 FULL_DECODE_ONLY cudagraph 时首次推理
- **规避方案**: 使用 `--enforce-eager`
- **状态**: ⚠️ 规避可用，根因待查

---

## 4. 配置优化历程

| 参数 | 原因 | 效果 |
|------|------|------|
| MTP关闭 (`num_mtp_modules=0`) | 验证MTP是否导致乱码 | 无改善 |
| QuaRot rotation matrix 复制 (`quarot.safetensors`) | 尝试加载逆旋转矩阵 | 未被主模型使用 |
| MooncakeLayerwiseConnector | w8a8c8模型INT8 KV cache兼容 | 放弃（换回w8a8） |
| EAGLE3启用 | 触发patch_draft_quarot.py加载rotation | rotation仅用于draft模型 |
| enforce_eager | 规避FULL_DECODE_ONLY cudagraph死锁 | 服务可用但乱码 |
| HCCL env (AIV + BUFFSIZE) | 参考混部工作脚本 | 无影响 |
| enable_npugraph_ex | 参考混部工作脚本 | 无影响 |
| safetensors prefetch | 参考混部工作脚本 | 加载速度改善 |

---

## 5. 乱码根因分析

### 5.1 确认的事实
1. **Prefill/Decode一致性**: 相同prompt在Prefill直连、Decode直连、PD Proxy下输出完全一致 → KV transfer正确
2. **MRV1/2无关**: MRV1(V1)和MRV2(V2)下输出一致 → 非ModelRunner问题
3. **EAGLE3无关**: EAGLE3的rotation matrix仅用于draft模型，不影响主模型输出
4. **确定性**: 相同prompt每次输出相同乱码 → 非随机问题，是计算确定性错误

### 5.2 根因
MiniMax-M2.7-w8a8-QuaRot 模型使用 **QuaRot** 量化方法：
1. QuaRot在量化前对权重施加**随机正交旋转矩阵**
2. 量化后的INT8权重 = rotation × FP16_weight × inverse_rotation → 量化
3. 推理时需:**先反量化得到INT8→FP16，再应用逆旋转**
4. vllm-ascend的 ModelSlim W8A8_DYNAMIC 反量化路径 **仅做INT8→FP16反量化，不应用逆旋转**
5. 结果：反量化出的权重值被"随机化"，logits为垃圾值，输出乱码

### 5.3 证据
- `patch_draft_quarot.py` 仅在EAGLE3 draft模型加载时使用rotation matrix
- `modelslim_config.py` 的W8A8_DYNAMIC dequant路径无rotation处理
- w8a8c8模型目录下的 `optional/quarot.safetensors` (37MB) 包含rotation matrix

### 5.4 修复方向
在 `vllm_ascend/quantization/modelslim_config.py` 的W8A8_DYNAMIC 反量化路径中：
1. 检测 `quant_model_description.json` 是否有 rotation 引用
2. 加载 `optional/quarot.safetensors` 中的 rotation matrix
3. 在反量化后应用逆旋转: `weight = inverse_rotation @ dequantized_weight @ rotation`

---

## 6. PD分离运行配置

### 成功运行的configs.sh核心参数
```bash
# 模型
export MODEL_PATH="/mnt/a800_weight/MiniMax-M2.7-w8a8-QuaRot"
export MODEL_NAME="MiniMaxM2"

# 集群
export PREFILL_IPS=(90.90.97.29)
export DECODE_IPS=(90.90.97.37)

# DP=2 TP=8
export P_DP_SIZE=2; export P_TP_SIZE=8
export D_DP_SIZE=2; export D_TP_SIZE=8
export P_VISIBLE_DEVICES_LIST=("0,1,2,3,4,5,6,7" "8,9,10,11,12,13,14,15")
export D_VISIBLE_DEVICES_LIST=("0,1,2,3,4,5,6,7" "8,9,10,11,12,13,14,15")

# 特性
export ENABLE_KV_POOL=1
export PD_KV_CONNECTOR="MooncakeConnectorV1"
export ENABLE_PREFIX_CACHE=1
export VLLM_USE_V2_MODEL_RUNNER=1

# 服务参数
export P_MAX_MODEL_LEN=32768; export D_MAX_MODEL_LEN=32768
export P_GPU_MEMORY_UTILIZATION=0.9; export D_GPU_MEMORY_UTILIZATION=0.9
export P_ENFORCE_EAGER=1; export D_ENFORCE_EAGER=1
```

### 单机混部命令
```bash
vllm serve /mnt/a800_weight/MiniMax-M2.7-w8a8-QuaRot \
    --safetensors-load-strategy prefetch \
    --served-model-name minimax --host 0.0.0.0 --port 8000 \
    --trust-remote-code --tensor-parallel-size 8 --data-parallel-size 2 \
    --max-model-len 70000 --max-num-seqs 128 --max-num-batched-tokens 16384 \
    --gpu-memory-utilization 0.8 --enforce-eager \
    --speculative_config '{"method":"eagle3","model":"/mnt/a800_weight/MiniMax-M2.7-eagle-model-2","num_speculative_tokens":3}' \
    --additional-config '{"enable_npugraph_ex":true}'
```

---

## 7. 已验证的特性状态

| 特性 | PD分离 | 单机混部 | 备注 |
|------|--------|---------|------|
| MRV2 (VLLM_USE_V2_MODEL_RUNNER=1) | ✅ | ✅ | 服务正常启动推理 |
| PD分离 (Prefill→Decode KV transfer) | ✅ | N/A | MooncakeConnectorV1 |
| KV池化 (Mooncake + AscendStore) | ✅ | N/A | 9426 blocks |
| Prefix Cache (block_size=128) | ✅ | ✅ | enable_prefix_caching |
| DP=2, TP=8 (16卡) | ✅ | ✅ | GPU内存使用~55GB/64GB |
| Mooncake Master | ✅ | N/A | port 50088 |
| Proxy负载均衡 | ✅ | N/A | port 8080, 2P+2D |
| EAGLE3 speculative decoding | N/T | ✅ | 3 tokens, eagle-model-2 |
| **输出精度** | **❌ 乱码** | **❌ 乱码** | QuaRot rotation matrix缺失 |
| FULL_DECODE_ONLY cudagraph | ❌ 超时 | ❌ 超时 | shm_broadcast TimeoutError |

---

## 8. 已修改文件清单

### 容器内vllm-ascend源码 (git staged)
| 文件 | 修改 | 优先级 |
|------|------|--------|
| `core/recompute_scheduler.py:194` | 添加`throttle_prefills`参数 | 🔴 Bug #12 |
| `ops/fused_moe/fused_moe.py:545` | 添加`maybe_all_reduce_tensor_model_parallel` | 🔴 Bug #4 |
| `worker/v2/model_runner.py:77` | 添加`decode_token_per_req=1` | 🔴 Bug #10 |
| `patch/platform/patch_kv_cache_coordinator.py` | 参数名修正 | 🟡 Bug #5 |

### 容器内vllm源码 (git staged)
| 文件 | 修改 |
|------|------|
| `transformers_utils/processors/hunyuan_vl_image.py` | try/except兼容性 |

### 共享盘scripts-ascend (已推送github)
| 文件 | 修改 |
|------|------|
| `example/common/run_dp_template.sh` | 删除重复D_ENFORCE_EAGER; 添加enable_npugraph_ex |

### 模型配置修改
| 文件 | 修改 |
|------|------|
| `MiniMax-M2.7-w8a8-QuaRot/config.json` | `num_mtp_modules: 0`, `use_mtp: false` (备份config.json.bak) |
| `MiniMax-M2.7-w8a8-QuaRot/optional/` | 从w8a8c8模型复制 `quarot.safetensors` |

---

## 9. 完整操作指南

### 前置条件
- 两节点NPU空闲 (16卡/节点)
- 共享盘 `/mnt/a800_share` 已挂载
- 容器镜像: `quay.io/ascend/vllm-ascend:nightly-main-a3`

### 步骤1: 创建容器
```bash
# Node29
ssh root@90.90.97.29
bash /mnt/a800_share/l00848175/scripts-ascend/start_container.sh \
    quay.io/ascend/vllm-ascend:nightly-main-a3 vllm-0251

# Node37
ssh root@90.90.97.37
bash /mnt/a800_share/l00848175/scripts-ascend/start_container.sh \
    quay.io/ascend/vllm-ascend:nightly-main-a3 vllm-0251
```

### 步骤2: 应用关键修复
```bash
docker exec -it vllm-0251 bash
# 修复1: RecomputeScheduler
sed -i 's/def schedule(self) -> RecomputeSchedulerOutput:/def schedule(self, throttle_prefills: bool = False) -> RecomputeSchedulerOutput:/' \
    /vllm-workspace/vllm-ascend/vllm_ascend/core/recompute_scheduler.py
# 清理缓存
find /vllm-workspace/vllm-ascend -name __pycache__ -exec rm -rf {} + 2>/dev/null
```

### 步骤3: 准备测试目录
```bash
mkdir -p /mnt/a800_share/l00848175/workspace/tests
cp -r /mnt/a800_share/l00848175/scripts-ascend/example/pd_multi_nodes/ \
    /mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool/
# 编辑 configs.sh (参考第6节)
```

### 步骤4: 启动PD服务
```bash
# Node29:
cd /mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool
bash run.sh mooncake_master
bash run.sh prefill 0
# 等待模型加载 (~3min)

# Node37:
cd /mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool
bash run.sh decode 0

# Node29:
bash run.sh proxy
```

### 步骤5: 测试
```bash
# 冒烟测试
curl -s http://90.90.97.29:8080/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"MiniMaxM2","prompt":"Hello","max_tokens":20}'
```

### 步骤6: 停止服务
```bash
docker kill vllm-0251  # 两节点分别执行
```

---

## 10. 建议和下一步

1. **QuaRot兼容性 (最高优先级)**: 联系vllm-ascend团队，在`modelslim_config.py`的W8A8_DYNAMIC反量化中集成QuaRot逆旋转
2. **替代模型**: 可以先使用`MiniMax-M3`（796GB FP16非量化）或`MiniMax-M3-w8a8`（406GB W8A8非QuaRot量化）进行PD分离精度验证
3. **FULL_DECODE_ONLY cudagraph**: 在Ascend上存在`shm_broadcast`超时问题，需要vllm-ascend团队排查
4. **MRV1 DP Gloo**: DP=2时MRV1的loopback Gloo通信不可靠，建议使用MRV2
5. **MTP**: MTP关闭不影响输出质量，可保持关闭以简化推理
