# MiniMax-M2.7 (w8a8 QuaRot) 评测报告

**日期**: 2026-07-29  
**模型**: MiniMax-M2.7 w8a8 QuaRot (Ascend量化)  
**硬件**: Ascend910 NPU (aarch64), 2机8卡配置  
**评测者**: l00848175  

---

## 一、评测环境

### 1.1 服务器配置

| 角色 | IP地址 | 硬件 |
|------|--------|------|
| Prefill节点 | 90.90.97.37 | Ascend910 NPU × 8 |
| Decode节点 | 90.90.97.42 | Ascend910 NPU × 8 |

### 1.2 软件环境

- **推理框架**: vLLM (Ascend版本) `vllm-ascend`
- **容器**: `vllm-lkl` (Docker)
- **量化方案**: w8a8 QuaRot
- **模型路径**: `/mnt/a800_weight/MiniMax-M2.7-w8a8-QuaRot`
- **数据集路径**: `/mnt/a800_share/xuchi/datasets/aime2025/aime2025.jsonl`

### 1.3 原始架构: PD分离 (Prefill-Decode Separation)

原始计划使用vLLM PD分离架构进行评测，拓扑结构为 **2P1D**（2 Prefill + 1 Decode）：

- **Tensor Parallel (TP)**: 8 (per node)
- **Data Parallel (DP)**: 2 (prefill nodes)
- **Expert Parallel (EP)**: 启用
- **KV Cache传输**: MooncakeConnectorV1 (PF→D via RDMA)
- **负载均衡**: HTTP Proxy (`load_balance_proxy_server_example.py`, port 8080)
- **Prefill特殊配置**: `build_prefill_request` 设置 `max_tokens=1` + `kv_transfer_params`

---

## 二、评测过程中的问题与解决

### 2.1 问题1: Decode节点 MoE通讯崩溃

**现象**: Decode节点在首次推理时崩溃，报错 `TypeError: '>' not supported between instances of 'NoneType' and 'int'`

**根因**: `vllm_ascend/ascend_forward_context.py` 中全局变量 `mc2_tokens_capacity` 初始值为 `None`，但在 `select_moe_comm_method` 函数中直接与整数比较。

**修复**: 在 `ascend_forward_context.py` 中添加三处空值保护：
- `select_moe_comm_method`: 当 `mc2_tokens_capacity is None` 时回退到 `ALLTOALL`
- `_select_a3_moe_comm_method`: 添加 `mc2_tokens_capacity is None` 守卫
- `_select_a2_moe_comm_method`: 添加 `mc2_tokens_capacity is None` 守卫  
- `_select_a5_moe_comm_method`: 添加 `mc2_tokens_capacity is None` 守卫

**补丁文件**: `D:\workspace\codes\.agents\patch_mc2.py`, `patch_mc2_v2.py`

### 2.2 问题2: Prefill节点 NPU Vector Core Exception

**现象**: Prefill节点在运行MoE AllGather通讯时触发NPU内核级错误：
```
Vector Core Exception: DDR address of MTE instruction out of range
Stream timeout: 507035
```

**根因**: w8a8量化 + MoE AllGather 路径存在NPU内核级bug，属于Ascend驱动/算子层问题，无法在应用层修复。

**尝试的修复方案**（均失败）:
1. 禁用 FUSED_MC2 和 PREFILL_MC2 (`enable_fused_mc2=0, enable_prefill_mc2=0`)
2. NPU重置 (`npu-smi set -t reset`)

### 2.3 最终解决方案: 独立vLLM模式

由于PD分离的Prefill节点NPU内核问题无法解决，采用**绕过方案**：

在Decode节点 (90.90.97.42) 上直接启动**独立vLLM实例**（不使用PD分离）：

```bash
vllm serve /mnt/a800_weight/MiniMax-M2.7-w8a8-QuaRot \
  --served-model-name minimaxm27 \
  --host 0.0.0.0 --port 9999 \
  --trust-remote-code \
  --quantization ascend \
  --tensor-parallel-size 8 \
  --max-model-len 4096 \
  --max-num-batched-tokens 4096 \
  --gpu-memory-utilization 0.8 \
  --enforce-eager \
  --no-enable-prefix-caching
```

- 生成速度: ~5.7 tokens/s
- API端点: `http://127.0.0.1:9999/v1/chat/completions`

---

## 三、操作步骤

### 3.1 GSM8K 冒烟测试 (10题)

**步骤**:

1. SSH连接到Decode节点:
   ```bash
   ssh root@90.90.97.42
   ```

2. 进入容器:
   ```bash
   docker exec -it vllm-lkl bash
   ```

3. 创建评测脚本 `run_gsm8k_test.py`（见附件 `D:\workspace\codes\.agents\run_eval_standalone_v2.py`）

4. 执行测试:
   ```bash
   python /tmp/run_gsm8k_test.py
   ```

5. 结果保存至 `/tmp/gsm8k_eval_standalone.json`

**脚本核心逻辑**:
- 加载GSM8K数据（前10题）
- 使用OpenAI客户端连接 `http://127.0.0.1:9999/v1`
- Prompt模板: `"Question: {question}\nLet's think step by step\nAnswer:"`
- 参数: `max_tokens=512, temperature=0.0, ignore_eos=False`
- 使用 `\boxed{}` 正则提取答案，与ground truth对比

### 3.2 AIME2025 评测 (30题)

**步骤**:

1. SSH连接到Decode节点:
   ```bash
   ssh root@90.90.97.42
   ```

2. 将评测脚本拷贝到容器:
   ```bash
   docker cp /tmp/run_aime_v3.py vllm-lkl:/tmp/
   ```

3. 执行评测:
   ```bash
   docker exec vllm-lkl python -u /tmp/run_aime_v3.py
   ```

4. 结果保存至容器内 `/tmp/aime2025_eval_v3.json`

**评测脚本核心逻辑** (`D:\workspace\codes\.agents\run_aime_v3.py`):
- 加载AIME2025数据集（30题，来源: `/mnt/a800_share/xuchi/datasets/aime2025/aime2025.jsonl`）
- 使用OpenAI客户端连接独立vLLM (`http://127.0.0.1:9999/v1`)
- Prompt模板: `"Question: {question}\n\nPlease solve this problem step by step, and end your response with the final answer in the format: \\boxed{answer}\n\nSolution:"`
- 参数: `max_tokens=2048, temperature=0.0, ignore_eos=False`
- 答案提取策略:
  1. 优先匹配 `\boxed{...}` 中的数字
  2. 匹配 "answer is X", "= X", "final answer: X" 等模式
  3. 提取文本中最后一个数字（AIME答案均为0-999的整数）
  4. 返回最后一行文本

**v1-v2版本迭代**:
- v1: `max_tokens=512`, GSM8K风格prompt，结果全部截断 (0/30)
- v2: `max_tokens=1024`, 添加 `\boxed{}` prompt，结果大部分截断 (1/17后终止)
- v3: `max_tokens=2048`, 改进prompt和答案提取，当前运行版本

### 3.3 操作时间线

| 时间 | 操作 | 结果 |
|------|------|------|
| 阶段1 | 启动PD分离架构（2P1D） | Prefill/Decode/Proxy启动 |
| 阶段2 | 首次推理尝试 | Decode崩溃 (mc2_tokens_capacity) |
| 阶段3 | 打补丁修复mc2问题 | Decode恢复正常 |
| 阶段4 | 再次尝试推理 | Prefill NPU Vector Core Exception |
| 阶段5 | 尝试禁用MC2、重置NPU | 问题未解决 |
| 阶段6 | 启动独立vLLM (TP=8) | 成功，端口9999 |
| 阶段7 | GSM8K 10题冒烟测试 | 9/10 (90%) |
| 阶段8 | AIME2025 v1 (512 tokens) | 全部截断，0/30 |
| 阶段9 | AIME2025 v2 (1024 tokens) | 大部分截断，终止 |
| 阶段10 | AIME2025 v3 (2048 tokens) | 完成，5/30 (16.67%) |

---

## 四、评测结果

### 4.1 GSM8K 冒烟测试结果

| 指标 | 数值 |
|------|------|
| 总题数 | 10 |
| 正确数 | 9 |
| 准确率 | **90.00%** |
| 失败原因 | 第5题输出截断（达到max_tokens=512限制） |

**结论**: GSM8K测试通过。w8a8量化模型在基础数学推理任务上表现良好。

### 4.2 AIME2025 评测结果

| 指标 | 数值 |
|------|------|
| 总题数 | 30 |
| 正确数 | 5 |
| 准确率 | **16.67%** |
| 平均推理时间 | ~354s/题 |
| 总耗时 | ~177分钟 (~3小时) |
| 最大输出tokens | 2048 |

**每题详细结果**:

| 题号 | GT | Pred | 结果 | 题目概要 |
|------|-----|------|------|------|
| Q1 | 70 | 70 | ✅ | 整数进制b>9使17_b整除97_b的和 |
| Q2 | 588 | 288 | ❌ | 三角形内点反射面积 |
| Q3 | 16 | 16 | ✅ | 冰淇淋口味选择方案数 |
| Q4 | 117 | 4 | ❌ | 12x²-xy-6y²=0的整数解数 |
| Q5 | 279 | 4 | ❌ | 1-8排列能被22整除的个数 |
| Q6 | 504 | 504 | ✅ | 等腰梯形内切圆r²+s² |
| Q7 | 821 | 6 | ❌ | 12字母配对最后单词含G的概率 |
| Q8 | 77 | 23 | ❌ | 复数方程\ |25+20i-z\ |=5有唯一解k的和 |
| Q9 | 62 | 3 | ❌ | 抛物线旋转60°交点坐标 |
| Q10 | 81 | 1 | ❌ | 3×9数独网格填充方案数 |
| Q11 | 259 | 0 | ❌ | 分段线性周期函数与抛物线交点 |
| Q12 | 510 | 2 | ❌ | 平面x+y+z=75上不等式区域面积 |
| Q13 | 204 | 27 | ❌ | 圆盘画线段的交点期望数 |
| Q14 | 60 | 169 | ❌ | 五边形内点使距离和最小 |
| Q15 | 735 | 1 | ❌ | a³+b³+c³被3⁷整除的有序三元组数 |
| Q16 | 468 | 468 | ✅ | 共线6点+外点G，三角形BGE面积 |
| Q17 | 49 | 49 | ✅ | n+2整除3(n+3)(n²+9)的n之和 |
| Q18 | 82 | 12 | ❌ | 2×2网格边红蓝染色方案数 |
| Q19 | 106 | 93 | ❌ | 对数乘积化简m+n |
| Q20 | 336° | 1 | ❌ | 三角形中点与外接圆交点弧长 |
| Q21 | 293 | 9 | ❌ | 两相切圆内接矩形面积 |
| Q22 | 237 | 4 | ❌ | 2025因子子集的LCM概率 |
| Q23 | 610 | 1 | ❌ | 硬币贪心算法非最优的N |
| Q24 | 149 | 2 | ❌ | sin(7π·sin(5x))=0的解数n+t |
| Q25 | 907 | 3 | ❌ | 16椅8人不邻坐的方案数 |
| Q26 | 113 | 8 | ❌ | 正24边形顶点12条等长线段配对 |
| Q27 | 19 | 2 | ❌ | 11边形面积/周长约束求边长 |
| Q28 | 248 | 2025 | ❌ | 迭代数列x_{k+1}=(x_k+1/x_k-1)/3 |
| Q29 | 104 | 0 | ❌ | 直角三角形内BKLC四边形面积 |
| Q30 | 240 | 3 | ❌ | 函数f(x)三个k使最小值在两点取得 |

**答对的5题**: Q1(70), Q3(16), Q6(504), Q16(468), Q17(49)

**正确答案解析特点**: 5道正确题中，有3道在响应中明确输出了`\boxed{答案}`格式（如Q17输出`\boxed{49}`），2道通过数字提取获得。所有正确题的响应的finish_reason均为`length`（达到max_tokens截断）或`stop`（自然停止）。

---

## 五、结论与建议

### 5.1 GSM8K
- ✅ w8a8 QuaRot量化MiniMax-M2.7在GSM8K基础数学推理上达到**90.00%**准确率（9/10），冒烟测试通过
- ⚠️ 单个截断案例可通过增加max_tokens解决

### 5.2 AIME2025
- ⚠️ w8a8量化模型在AIME2025竞赛级数学推理上准确率仅**16.67%**（5/30）
- 📊 模型能正确解决部分AIME级别问题（涉及数论、几何、代数等），但对大多数问题推理失败
- 🔍 错误模式：模型通常输出推理过程中的中间数字而非最终答案，或计算错误导致最终答案偏离
- 💡 所有回答均为截断状态（finish_reason=length），说明2048 tokens仍不足以让模型完成完整推理
- 📝 建议后续评测：(1) 使用未量化模型对比；(2) 增加max_tokens到4096；(3) 使用few-shot prompting

### 5.3 PD分离架构
- ❌ vLLM PD分离 + w8a8量化 + MoE AllGather 在当前NPU驱动版本上存在内核级bug
- 🔧 需要Ascend驱动团队修复Vector Core Exception (DDR地址越界)问题
- ✅ `mc2_tokens_capacity` 空值bug已定位并修复（补丁已应用在`ascend_forward_context.py`）

### 5.4 独立vLLM模式
- ✅ 独立vLLM (TP=8) 在Decode节点上稳定运行，无NPU崩溃
- ⚠️ 推理速度较慢（~5.7 tok/s），30题AIME耗时约3小时（vs PD分离预期<1小时）
- ⚠️ 损失了PD分离的性能优势（prefill计算卸载、DP并行）
- 💡 独立模式适合功能验证和小规模评测，不适合大规模吞吐场景
