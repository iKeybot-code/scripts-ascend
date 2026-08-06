# DeepSeek-V3.1 vLLM Ascend PD 分离、池化 Prefix Cache 与 GPQA 评测任务报告

## 1. 任务概览

- 执行日期：2026-08-06
- Windows 工作区：`D:\OneBox\codes`
- 远端环境：`root@192.168.13.165`
- 容器：`vllm-lkl`
- 模型：`/mnt/weight/DeepSeek-V3.1-w4a8-mtp-QuaRot`
- 服务模型名：`deepseek_v3`
- 部署形态：1P1D，Prefill/Decode 各 TP=8、EP 开启，Mooncake KV 传输，Prefill 同时启用 HBM APC 与 AscendStore/Mooncake KVPool
- 最终状态：服务功能验证、Prefix 命中性能评测和 GPQA-Diamond 全量精度评测均完成；任务启动的相关进程已停止

## 2. 代码仓与版本

| 仓库/工具 | 分支 | 提交 |
|---|---|---|
| Windows `vllm` | `releases/v0.26.0` | `568afb3a13806beb53bb2e6bd518269357b237c0` |
| Windows `vllm-ascend` | `main` | `4f3e2cb7b1ab306f0d5fb0d83707cda8e3038eaa` |
| Windows `scripts-ascend` | `main` | `df6a14a09ec58c5dd885fafcc7bb2d3edcce4c1a` |
| 远端 `aisbench_auto_tools_prefix` | `main` | `5acd8e5532a7c9ea48e10e14ee84f777a57c3db5` |
| 远端 `AISBench/benchmark` | 当前检出版本 | `3fd27b4a5fd022fcb5484fb084307f49955491ba` |

Windows 仓库中的改动尚未提交。用户已有的 `pyrightconfig.json` 和两份设计文档保持未跟踪状态，任务没有覆盖或删除它们。

## 3. 操作过程

### 3.1 环境与代码准备

1. 检查 Windows 本地三个仓库的分支、提交和工作树状态。
2. 将 `vllm` 切至 `releases/v0.26.0`，将 `vllm-ascend`、`scripts-ascend` 保持在 `main`，同步对应最新代码。
3. 使用 SSH 公钥登录远端，进入 `vllm-lkl` 容器。
4. 检查模型路径、NPU 可见设备、网卡地址、Mooncake 配置和原始启动脚本。
5. 修正 1P1D 参数、网络参数、模型路径、DP/TP 参数、KV connector JSON 及 proxy 地址。
6. 启动顺序为 Mooncake master → Prefill → Decode → proxy；启动后检查健康接口和日志。
7. 通过 proxy 的 `/v1/chat/completions` 发起功能请求，响应成功；Decode 日志确认 KV 传输成功。

### 3.2 本地同步内容

远端最终配置已同步到 Windows：

- `vllm-ascend/vllm_ascend/worker/v2/model_runner.py`
- `scripts-ascend/archives/deepseek_v31_1p1d_pool_apc/start_prefill.sh`
- `scripts-ascend/archives/deepseek_v31_1p1d_pool_apc/start_decode.sh`
- `scripts-ascend/archives/deepseek_v31_1p1d_pool_apc/start_proxy.sh`
- `scripts-ascend/archives/deepseek_v31_1p1d_pool_apc/mooncake.json`
- `scripts-ascend/archives/deepseek_v31_1p1d_pool_apc/eval/prefix_config.py`
- `scripts-ascend/archives/deepseek_v31_1p1d_pool_apc/eval/deepseek_v31_pd_gpqa.py`

对本地 Python 热修执行了 `python -m py_compile`，并对 `vllm-ascend`、`scripts-ascend` 执行了 `git diff --check`，均通过。

## 4. 最终启动配置

### 4.1 Mooncake master

- 监听端口：`50088`
- 管理端口：`9003`
- master 地址：`178.27.4.165:50088`
- 协议：`ascend`
- global segment：`5GB`
- 配置文件：`/mnt/share/l00848175/scripts-ascend/example/template/mooncake.json`

### 4.2 Prefill

- 端口：`8000`
- NPU：`0,1,2,3,4,5,6,7`
- DP/TP：`DP=1`、`TP=8`
- Expert Parallel：开启
- `max-model-len=65536`
- `max-num-batched-tokens=16384`
- `max-num-seqs=8`
- HBM Prefix Cache：开启
- speculative decoding：MTP，1 token
- KV connector：`MultiConnector`
  - `MooncakeConnectorV1`，producer，端口 `36000`
  - `AscendStoreConnector`，producer，backend=`mooncake`
- KV load failure policy：`recompute`
- 完整脚本：`scripts-ascend/archives/deepseek_v31_1p1d_pool_apc/start_prefill.sh`

### 4.3 Decode

- 端口：`8001`
- NPU：`8,9,10,11,12,13,14,15`
- DP/TP：`DP=1`、`TP=8`
- Expert Parallel：开启
- `max-model-len=65536`
- `max-num-batched-tokens=256`
- `max-num-seqs=28`
- 本地 Prefix Cache：关闭
- speculative decoding：MTP，1 token
- scheduler：`recompute_scheduler_enable=true`
- KV connector：`MooncakeConnectorV1`，consumer，端口 `37000`
- 完整脚本：`scripts-ascend/archives/deepseek_v31_1p1d_pool_apc/start_decode.sh`

### 4.4 Proxy

- 监听端口：`9000`
- Prefill 后端：`192.168.13.165:8000`
- Decode 后端：`192.168.13.165:8001`
- 完整脚本：`scripts-ascend/archives/deepseek_v31_1p1d_pool_apc/start_proxy.sh`

## 5. 异常处理

### 5.1 MRV2 Decode 启动异常

#### 现象

Prefill 可以启动，而启用了 MRV2、MoE、PD Decode consumer 和 recompute scheduler 的 Decode 在加载模型/MoE dispatcher 阶段失败。最终异常来自：

```python
def get_potential_max_tokens() -> int:
    assert _potential_max_tokens is not None
    return _potential_max_tokens
```

原始失败日志后来被成功重启时的 `tee decode.log` 覆盖；上述断言位置、调用链以及补丁后成功启动共同确认了根因。

#### 调用链

```text
NPUWorker.init_device()
  -> MRV2 NPUModelRunner.__init__()
  -> load_model()
  -> DeepSeek MoE 层创建 token dispatcher
  -> should_skip_allreduce_across_dp_group(vllm_config)
  -> needs_mc2(get_potential_max_tokens())
  -> assert _potential_max_tokens is not None
```

相关代码：

- MRV2 选择：`vllm_ascend/worker/worker.py`
- MoE dispatcher：`vllm_ascend/ops/fused_moe/token_dispatcher.py`
- PD/MC2 判断及缓存值：`vllm_ascend/utils.py`
- 修复位置：`vllm_ascend/worker/v2/model_runner.py`

#### 根因

旧版 Ascend `NPUModelRunner` 会在初始化时调用：

```python
set_potential_max_tokens(vllm_config)
```

MRV2 实现遗漏了这一步。DeepSeek-V3.1 是 MoE 模型；Decode 又是 KV consumer，因此 `should_skip_allreduce_across_dp_group()` 不会提前返回，而会读取尚未初始化的全局缓存值，触发断言。

普通非 PD 场景没有 `kv_transfer_config`，PD Prefill 是 producer，两者都会在 `is_kv_consumer` 检查处提前返回，所以过去没有暴露该错误。未启用 MRV2 时走旧 runner，旧 runner 已有初始化，同样不会触发。

#### 解决方案

在 MRV2 runner 的基础类初始化完成后、模型加载前补齐同等初始化：

```python
from vllm_ascend.utils import enable_sp, set_potential_max_tokens

with torch_cuda_wrapper():
    super().__init__(vllm_config, device)
    set_potential_max_tokens(vllm_config)
```

这样可以使用已经规范化的 scheduler、compilation 和 speculative config 计算 decode 潜在最大 token 数，并在 MoE dispatcher 读取前完成缓存。

#### 影响评估

- setter 幂等，重复调用会直接返回。
- 只做配置算术和进程内缓存，不修改请求 token、权重、KV cache 或调度上限。
- 该值用于 MC2 通信方法判断、是否跳过 DP all-reduce、`global_bs` 和部分静态 exchange buffer 容量。
- Prefill/非 PD 路径即便初始化该值，大多数情况下不会读取，功能影响可忽略。
- 理论边界：模块全局缓存只设置一次；如果未来在同一 worker 进程内用不同配置反复创建 engine，需要考虑重置。当前一进程一 engine 的生命周期不受影响。

### 5.2 Prefix 工具依赖异常

首次 Prefix 评测中，AISBench 缺少 `tabulate` 等依赖。外层工具仍以 0 退出并生成 `99999` 等占位指标，因此该轮被明确判定为无效，没有计入报告。

处理方式：

1. 在容器内建立带 system site packages 的独立 venv。
2. 安装 AISBench 及运行期依赖，包括 `tabulate`、`jieba`、`h5py`、datasets、mmengine-lite 等。
3. 使用新的输出目录 `outputs_valid`、固定 seed=2 重新运行。
4. 以成功请求数、AISBench 性能表和 Prometheus counter 增量共同确认有效性。

## 6. Prefix Cache 性能评测

### 6.1 配置

- 工具：`rayn-zzz/aisbench_auto_tools_prefix`
- dataset type：`prefix_cache`
- 输入长度：2048
- 输出长度：32
- 请求数：8
- 并发：1
- request rate：0（尽快发送）
- 重复前缀比例：0.5
- prefix 数量：1
- seed：2
- proxy：`192.168.13.165:9000`
- POD：`192.168.13.165:8000`、`192.168.13.165:8001`

执行命令：

```bash
python3 aisbench_test.py \
  --input_len 2048 --output_len 32 --data_num 8 \
  --concurrency 1 --request_rate 0 \
  --dataset_type prefix_cache --repeat_rate 0.5 \
  --prefix_num 1 --prefix_test --dp 1 --npu_num 16 --seed 2
```

### 6.2 命中结果

| 阶段/指标 | HBM | KVPool / external |
|---|---:|---:|
| Prefix 预热阶段 | 0/1028，0.00% | 1028/2056，50.00% |
| 8 请求全量阶段 | 7168/16418，43.66% | 17442/25668，67.95% |

说明：以上为工具输出的 `ALL_PODS` Prometheus counter 增量；HBM 对应本地 APC counter，KVPool/external 对应 external prefix cache/connector counter。计数单位是 token，不是请求。

### 6.3 性能指标

| 指标 | 结果 |
|---|---:|
| 成功/失败请求 | 8 / 0 |
| Benchmark Duration | 134064.7794 ms（约 134.06 s） |
| 平均 TTFT | 12227.9 ms |
| TTFT P90 | 16363.4 ms |
| 平均 TPOT | 146.1 ms |
| TPOT P90 | 157.1 ms |
| 平均 E2EL | 16757.2 ms |
| E2EL P90 | 20947.9 ms |
| Request Throughput | 0.0597 req/s |
| 输入 token | 16418 |
| 输出 token | 256 |
| Input Token Throughput | 122.4632 token/s |
| Output Token Throughput | 1.9095 token/s |
| Total Token Throughput | 124.3727 token/s |

## 7. GPQA-Diamond 精度评测

### 7.1 配置

- 工具：`AISBench/benchmark`
- 数据集：GPQA-Diamond，198 题
- metric：accuracy，即 Pass@1
- prompt：官方 `gpqa_gen_0_shot_cot_chat_prompt`
- 方式：0-shot CoT
- temperature：0
- 最大输出长度：8192
- 并发：8
- warmup：0
- 请求失败：0

### 7.2 最终结果

| 指标 | 结果 |
|---|---:|
| Pass@1 / accuracy | **76.77%** |
| 精确 accuracy | 76.76767676767676% |
| 正确 | 152 |
| 错误 | 46 |
| 总题数 | 198 |
| 答案/请求失败 | 0 |
| API inference elapsed | 6768.98 s（1 h 52 min 48.98 s） |
| 并发摊销平均耗时 | 34.19 s/case |

验证方式：最终预测 JSONL 为 198 行；结果 JSON 含 198 条 details；其中 152 条 `correct=true`，46 条为 false；`152 / 198 = 76.767676...%`，与 AISBench summary 的 76.77 一致。

## 8. 结果日志与产物

所有远端时间为容器/服务器记录时间（UTC）。

| 内容 | 路径 | 大小 |
|---|---|---:|
| Prefill 日志 | `/mnt/share/l00848175/deepseek_v31_1p1d_pool_apc/prefill.log` | 637881 B |
| Decode 日志 | `/mnt/share/l00848175/deepseek_v31_1p1d_pool_apc/decode.log` | 1136360 B |
| Proxy 日志 | `/mnt/share/l00848175/deepseek_v31_1p1d_pool_apc/proxy.log` | 16756 B |
| Prefix 有效评测日志 | `/mnt/share/l00848175/eval_results/prefix/run_hbm.log` | 59824 B |
| Prefix AISBench 输出 | `/mnt/share/l00848175/eval_results/prefix/outputs_valid` | 目录 |
| GPQA 主日志 | `/mnt/share/l00848175/eval_results/gpqa_full.log` | 2193340 B |
| GPQA 逐题预测 | `/mnt/share/l00848175/eval_results/gpqa_full/20260806_101408/predictions/deepseek-v31-pd/GPQA_diamond.jsonl` | 198 行 |
| GPQA 评分明细 | `/mnt/share/l00848175/eval_results/gpqa_full/20260806_101408/results/deepseek-v31-pd/GPQA_diamond.json` | 1231839 B |
| GPQA 汇总 | `/mnt/share/l00848175/eval_results/gpqa_full/20260806_101408/summary/summary_20260806_101408.csv` | 83 B |

## 9. 清理结果

任务结束后按依赖逆序检查并停止相关进程：proxy → Prefill/Decode → Mooncake master。

实际盘点时：

- Prefix/GPQA 评测进程已经正常结束。
- Prefill 和 Decode 已退出，端口 `8000`、`8001` 已释放。
- 精确终止本次 proxy 进程树：容器 PID `25402/25409/25410`。
- 精确终止本次 Mooncake master：宿主机 PID `898963`。
- 再次检查确认 `8000`、`8001`、`9000`、`50088`、`9003` 均无本任务监听进程。
- 容器 `vllm-lkl` 保留运行，没有停止或删除；远端日志、数据集、venv、工具仓和评测产物均保留，可复查和复现。

## 10. 结论

本次成功构建并验证了 DeepSeek-V3.1 Ascend 1P1D 部署：Prefill 使用 HBM APC 与 AscendStore/Mooncake KVPool，Decode 通过 Mooncake 接收 KV，并经 proxy 对外服务。MRV2 在 MoE PD Decode consumer 路径上的初始化遗漏得到定位和最小修复。有效 Prefix 测试得到 HBM 43.66%、KVPool/external 67.95% 的 token 命中率；GPQA-Diamond 198 题 Pass@1 为 76.77%，无请求失败。任务相关运行进程已经停止，代码、脚本、配置、日志和结果均已保留。
