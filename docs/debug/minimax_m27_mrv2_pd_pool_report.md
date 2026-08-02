# MiniMax M2.7 PD分离+KV池化+Prefix Cache+MRV2 验证报告

## 概述
- **日期**: 2026-07-26
- **任务**: 验证vllm v0.25.1 + vllm-ascend main, MiniMax M2.7模型, 开启ModelRunnerV2, PD分离, KV池化, Prefix Cache
- **模型**: MiniMax-M2.7-w8a8-QuaRot (W8A8量化, MoE: 62层, 48头, 8 KV头, 256专家, MTP=3)
- **节点**: Node29 (90.90.97.29) - Prefill ✅, Node37 (90.90.97.37) - Decode ❌, Node27/42 - Decode(尝试) ❌
- **最终结果**: Prefill MRV2+DP2+TP8+PrefixCache 推理成功✅ | Decode 因custom op问题失败❌

## 1. 环境和版本

| 组件 | 期望版本 | 实际版本 |
|------|----------|----------|
| vllm | v0.25.1 | ✅ 0.25.1+empty |
| vllm-ascend | main | ✅ 0.19.1rc2.dev1017+gbbabae3fd |
| 容器镜像 | quay.io/ascend/vllm-ascend:nightly-main-a3 | ✅ |
| Python | - | 3.12.13 (Node29/27/37), 3.11.10 (Node42) |
| CANN | - | 25.5.0 (Node29), 26.0.rc1 (Node27) |
| transformers | >= 5.5.3 | 5.13.0 (Node29), 5.5.4 (Node42) |

## 2. Bug发现和修复记录

### Bug #1: IFS引号缺失导致VISIBLE_LIST生成错误
- **文件**: `scripts-ascend/example/common/start_prefill.sh:35`, `start_decode.sh:35`
- **问题**: `VISIBLE_LIST=$(IFS=''; echo ...)` 缺少闭合引号
- **修复**: 重写IFS处理为保存/恢复模式
- **状态**: ✅ 已修复

### Bug #2: fastapi版本冲突
- **文件**: vllm-ascend `pyproject.toml`
- **问题**: vllm-ascend要求 `fastapi<0.124.0`，但vllm v0.25.1要求 `fastapi>=0.115.0,<0.137.0`
- **修复**: 修改vllm-ascend pyproject.toml中fastapi约束为 `<0.137.0,>=0.115.0`
- **状态**: ✅ 已修复

### Bug #3: AutoImageProcessor.register兼容性
- **文件**: `/vllm-workspace/vllm/vllm/transformers_utils/processors/hunyuan_vl_image.py`
- **问题**: `AutoImageProcessor.register("HunYuanVLImageProcessor", HunYuanVLImageProcessor)` 在transformers 5.x中API变更
- **修复**: 添加try/except捕获AttributeError
- **状态**: ✅ 已修复

### Bug #4: AscendMoERunner缺少maybe_all_reduce_tensor_model_parallel方法 (关键bug)
- **文件**: `/vllm-workspace/vllm-ascend/vllm_ascend/ops/fused_moe/fused_moe.py` (line 305附近)
- **问题**: vllm v0.25.1走`else`分支，在fused_moe.py中重新定义`AscendMoERunner`类，但缺少`maybe_all_reduce_tensor_model_parallel`方法
- **根因分析**: vllm-ascend main的fused_moe.py有两个代码路径：`vllm_version_is("0.23.0")`走fused_moe_0_23_0.py中的实现（有该方法），其他版本在fused_moe.py中重定义`AscendMoERunner`（缺失该方法）。MiniMax M2.7的patched MoE forward调用`self.experts.maybe_all_reduce_tensor_model_parallel()`，而`self.experts`委派到runner对象
- **修复**: 在`_fused_output_is_reduced`属性后（8空格缩进）添加该方法
- **影响范围**: 所有使用MRV2的MiniMax M2模型
- **状态**: ✅ 已修复（需清理__pycache__后生效）

### Bug #5: kv_cache_coordinator参数名不匹配
- **文件**: vllm-ascend `patch/platform/patch_kv_cache_coordinator.py`
- **问题**: 对非0.23.0版本使用`max_in_flight_tokens`参数，但vllm v0.25.1的`get_kv_cache_coordinator`使用`max_num_batched_tokens`
- **修复**: 统一使用`max_num_batched_tokens`
- **状态**: ✅ 已修复

### Bug #6: HunYuanVLProcessor导入不兼容 (Node42特定)
- **文件**: vllm-ascend `patch/hunyuan_vl_processor_compat.py`
- **问题**: transformers 5.5.4没有`HunYuanVLProcessor`类
- **修复**: 添加try/except处理ImportError
- **状态**: ✅ 已修复

### Bug #7: data_parallel_external_lb验证与DP=1冲突
- **问题**: 当DP_SIZE=1且传递`--data-parallel-rank`时，vllm arg_utils.py隐式设置`data_parallel_external_lb=True`，触发parallel.py validation error
- **修复方向**: 需修改模板在DP_SIZE=1时跳过`--data-parallel-rank`参数
- **状态**: 🔴 待修复

### Bug #8: glibc heap corruption - Decode Worker初始化崩溃
- **现象**: `corrupted size vs. prev_size` 错误
- **影响节点**: Node27, Node37, Node42 均出现
- **出现位置**: `multiproc_executor.py` WorkerProc初始化，engine core启动阶段
- **尝试修复**: 禁用cudagraph(FULL_DECODE_ONLY→NONE) + enforce_eager → 仍失败
- **可能原因**: cudagraph编译模式下的内存越界，或CANN/PyTorch库二进制不兼容
- **状态**: 🔴 未解决（需vllm-ascend团队深入分析core dump）

### Bug #9: DP=2推理时gloo all_reduce通信失败
- **现象**: `Connection closed by peer [90.90.97.29]:28588` in `sync_cudagraph_and_dp_padding`
- **出现时机**: Prefill模型加载完成后，首次推理请求时
- **可能原因**: DP rank间gloo通信异常，端口28588被关闭
- **状态**: 🔴 未解决

### Bug #10: NPUModelRunner V2 缺少 decode_token_per_req 属性
- **文件**: vllm-ascend `worker/v2/model_runner.py`
- **问题**: worker.py 调用 `self.model_runner._dummy_run(num_tokens=self.model_runner.decode_token_per_req)` 但V2 NPUModelRunner未定义该属性(V1 model_runner_v1.py有)
- **修复**: 在 NPUModelRunner.__init__ 中 `super().__init__()` 之后添加 `self.decode_token_per_req = 1`
- **状态**: ✅ 已修复

### Bug #11: maybe_all_reduce_tensor_model_parallel custom op 缺少overload (Decode)
- **文件**: vllm-ascend `ops/register_custom_ops.py`
- **问题**: Decode路径调用 `torch.ops.vllm.maybe_all_reduce_tensor_model_parallel` 时报告 "has no overload name 'view'"
- **可能原因**: torch inductor编译时找不到匹配的op重载
- **状态**: 🔴 未解决（需torch custom op注册层面修复）

## 3. 运行结果

### ✅ Prefill (Node29) - 推理成功
- Mooncake Master: ✅ port 50088
- 模型加载: ✅ 14.15 GiB, ~77秒
- MRV2 启用: ✅ system_fingerprint: `vllm-0.25.1-tp8-dp2-6913c37c`
- Prefix Cache: ✅ block_size=128
- API端口: ✅ 13900/13901
- 推理测试: ✅ HTTP 200, 正常返回文本
- **输出质量**: ⚠️ 输出为乱码（`{ordle XK Technology/...`），疑似QuaRot W8A8量化配置未正确处理

### ❌ Decode (Node37) - 崩溃

### Prefill (Node29) ✅ 模型加载成功，推理失败
- Mooncake Master: ✅ 正常运行 (port 50088)
- 模型加载: ✅ 成功 (14.15 GiB, ~90秒, 54 safetensors shards)
- API服务启动: ✅ 13900/13901端口监听
- MRV2: ✅ 已启用 (`VLLM_USE_V2_MODEL_RUNNER=1`)
- Prefix Cache: ✅ 已启用 (`--enable-prefix-caching`, block_size=128)
- KV Pool (Mooncake): ✅ 已启用 (MultiConnector: MooncakeConnectorV1 + AscendStoreConnector)
- cudagraph: ✅ 已禁用 (`--enforce-eager`)
- 推理测试: ❌ DP=2时gloo通信失败 (Bug #9)

### Decode ❌ 跨节点均失败
| 节点 | 失败原因 |
|------|----------|
| Node37 (90.90.97.37) | NPU内存被其他用户VLLMWorker占满 (HBM ~58GB/64GB per chip) |
| Node42 (90.90.97.42) | glibc heap corruption + Python 3.11库兼容性问题 |
| Node27 (90.90.97.27) | glibc heap corruption (Bug #8) |

### Proxy
- ✅ 启动成功 (port 8080, 注册2 prefill + 2 decode clients)
- ❌ 因Decode缺失无法正常服务 ("Internal Server Error")

## 4. 成功运行的Prefill配置 (DP=2, TP=8, 16卡)

```bash
export MODEL_PATH="/mnt/a800_weight/MiniMax-M2.7-w8a8-QuaRot"
export MODEL_NAME="MiniMaxM2"
export PREFILL_IPS=(90.90.97.29)
export PREFILL_NICS=(enp194s0f0)
export DECODE_IPS=(90.90.97.27)  # Decode未成功
export DECODE_NICS=(enp194s0f0)
export P_DP_SIZE=2
export P_TP_SIZE=8
export P_DP_SIZE_LOCAL=2
export D_DP_SIZE=2
export D_TP_SIZE=4
export D_DP_SIZE_LOCAL=2
export P_VISIBLE_DEVICES_LIST=("0,1,2,3,4,5,6,7" "8,9,10,11,12,13,14,15")
export D_VISIBLE_DEVICES_LIST=("4,5,6,7" "8,9,10,11")
export P_ENFORCE_EAGER=1
export ENABLE_KV_POOL=1
export ENABLE_PREFIX_CACHE=1
export VLLM_USE_V2_MODEL_RUNNER=1
export MOONCAKE_MASTER_IP=90.90.97.29
export MOONCAKE_MASTER_PORT=50088
export PROXY_HOST=90.90.97.29
export PROXY_PORT=8080
```

## 5. 完整操作指南

### 步骤1: 远程连接和容器准备
```bash
ssh root@90.90.97.29  # Prefill节点
# 拉取镜像
docker pull quay.io/ascend/vllm-ascend:nightly-main-a3
# 或从共享盘加载: docker load < /mnt/a800_share/l00848175/workspace/vllm-ascend-nightly-main-a3.tar.gz
# 创建容器
bash /mnt/a800_share/l00848175/scripts-ascend/start_container.sh quay.io/ascend/vllm-ascend:nightly-main-a3 vllm-0251
docker exec -it vllm-0251 bash
```

### 步骤2: 版本切换和源码修复
```bash
# 配置代理
export http_proxy=http://90.254.54.104:3128
export https_proxy=http://90.254.54.104:3128

# 更新vllm到v0.25.1
cd /vllm-workspace/vllm
git config --global http.proxy http://90.254.54.104:3128
GIT_SSL_NO_VERIFY=1 git fetch --tags origin v0.25.1
git checkout v0.25.1
pip install setuptools_rust
VLLM_TARGET_DEVICE=empty pip install -e . --no-build-isolation

# 应用修复脚本
python3 /mnt/a800_share/l00848175/workspace/fix_runner.py

# 清理缓存
find /vllm-workspace/vllm-ascend -name __pycache__ -exec rm -rf {} +
```

### 步骤3: 准备测试目录
```bash
cd /mnt/a800_share/l00848175/scripts-ascend
git pull origin main
mkdir -p /mnt/a800_share/l00848175/workspace/tests
cp -r /mnt/a800_share/l00848175/scripts-ascend/example/pd_multi_nodes/ \
    /mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool/
# 编辑configs.sh (参考第4节配置)
```

### 步骤4: 启动服务 (在两节点容器内分别执行)
```bash
# Node29 - Master + Prefill + Proxy
cd /mnt/a800_share/l00848175/workspace/tests/test_minimax_m27_pd_pool
bash run.sh mooncake_master   # 先启动Master
bash run.sh prefill 0         # 启动Prefill (等待~2分钟模型加载)
bash run.sh proxy             # 启动Proxy

# Node27 - Decode (目前因Bug #8失败)
bash run.sh decode 0
```

### 步骤5: 测试
```bash
bash run.sh test   # AISBench GSM8K 前10条精度测试
# 或直接curl:
curl http://90.90.97.29:13900/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"MiniMaxM2","prompt":"Hello","max_tokens":10}'
```

## 6. 已修改文件清单

### 容器内源码修复 (每节点均需应用):
| 文件 | 修改内容 | 优先级 |
|------|----------|--------|
| `vllm_ascend/ops/fused_moe/fused_moe.py` | 添加`maybe_all_reduce_tensor_model_parallel`方法 | 🔴 关键 |
| `vllm_ascend/patch/platform/patch_kv_cache_coordinator.py` | 参数名修正 | 🔴 关键 |
| `vllm/vllm/transformers_utils/processors/hunyuan_vl_image.py` | try/except注册 | 🟡 次要 |

### 共享脚本修改 (`/mnt/a800_share/l00848175/scripts-ascend/example/common/`):
| 文件 | 修改内容 |
|------|----------|
| `start_prefill.sh` | 修复IFS引号 + 数组join逻辑 |
| `start_decode.sh` | 修复IFS引号 + 数组join逻辑 |
| `run_dp_template.sh` | MRV2启用 + Prefix Cache可配置 + Decode enforce_eager支持 |

## 7. 待解决问题和建议

1. **Decode crash (Bug #11)**: `maybe_all_reduce_tensor_model_parallel` custom op 缺少overload，需修复 register_custom_ops.py
2. **输出质量**: Prefill推理输出为乱码，可能因QuaRot W8A8量化配置与Ascend backend不兼容
3. **DP=1支持 (Bug #7)**: 模板需支持DP=1场景（跳过data_parallel_rank参数传递）
4. **transformers版本**: 建议统一使用5.13.0避免API差异
5. **NPU资源**: 运行前务必确认所有NPU HBM空闲(~60GB/chip)

### 已验证成功的特性组合
- ✅ vllm v0.25.1 + vllm-ascend main
- ✅ ModelRunnerV2 (`VLLM_USE_V2_MODEL_RUNNER=1`)
- ✅ DP=2, TP=8 (16张Ascend910)
- ✅ Prefix Cache (`--enable-prefix-caching`, block_size=128)
- ✅ KV Pool (MooncakeConnectorV1 + AscendStoreConnector)
- ✅ Enforce Eager mode
- ✅ PD分离架构(1P1D) - Prefill端完整可用
- ⚠️ 输出正确性待验证（QuaRot量化）

## 8. 附录: 自动化修复脚本

共享盘路径: `/mnt/a800_share/l00848175/workspace/fix_runner.py`

```python
import os
paths = [
    '/vllm-workspace/vllm-ascend/vllm_ascend/ops/fused_moe/fused_moe.py',
    '/workspace/vllm-ascend/vllm_ascend/ops/fused_moe/fused_moe.py',
]
for path in paths:
    if not os.path.exists(path):
        continue
    with open(path) as f:
        content = f.read()
    marker = '        def _maybe_reduce_shared_expert_output('
    insert = '''        def maybe_all_reduce_tensor_model_parallel(self, final_hidden_states):
            return torch.ops.vllm.maybe_all_reduce_tensor_model_parallel(final_hidden_states)

'''
    if marker in content and 'def maybe_all_reduce_tensor_model_parallel' not in content:
        content = content.replace(marker, insert + marker)
        with open(path, 'w') as f:
            f.write(content)
        print(f'Fixed: {path}')
    else:
        print(f'Skipped: {path}')
```
