# PD / KV Pool 样例工程设计与操作指南

> 覆盖目录：  
> - `example/common`（公共能力）  
> - `example/pd_single_node`（单节点 PD，默认关 KV 池化）  
> - `example/pd_and_kvpool_single_node`（单节点 PD + KV 池化）  
> - `example/pd_multi_nodes`（多节点 PD + KV 池化）

---

## 1. 设计概览

### 1.1 目标

| 目标 | 实现 |
|------|------|
| 统一配置入口 | 每个场景只改自己的 `configs.sh` |
| 可选 KV 池化 | `ENABLE_KV_POOL=0/1` |
| 可切换 PD connector | `PD_KV_CONNECTOR=MooncakeConnectorV1` / `MooncakeLayerwiseConnector` |
| 公共脚本共享 | `example/common`，容器默认引用共享盘路径 |
| 官方运行形态 | `launch_online_dp.py` + `run_dp_template.sh` |
| 统一场景入口 | 各样例目录仅保留 `run.sh` + `configs.sh` |

### 1.2 能力开关

在任意场景的 `configs.sh` 中：

```bash
# KV 池化开关
export ENABLE_KV_POOL=0   # 或 1

# PD 传输 connector（可改）
export PD_KV_CONNECTOR=MooncakeConnectorV1
# export PD_KV_CONNECTOR=MooncakeLayerwiseConnector

# 仅 ENABLE_KV_POOL=1 时生效
export KV_POOL_BACKEND=mooncake
export KV_LOAD_FAILURE_POLICY=recompute

# 引擎级开关（env vars）
export ENABLE_FLASHCOMM1=0       # VLLM_ASCEND_ENABLE_FLASHCOMM1
export ENABLE_FUSED_MC2=0        # VLLM_ASCEND_ENABLE_FUSED_MC2
export VLLM_SERVER_DEV_MODE=0

# additional-config 布尔开关（由 run_dp_template.sh 动态拼装 JSON）
export ENABLE_REDUCE_SAMPLE=0
export ENABLE_CPU_BINDING=1
export ENABLE_NPUGRAPH_EX=0      # ascend_compilation_config.enable_npugraph_ex
export WEIGHT_NZ_MODE=0
export P_RECOMPUTE_SCHEDULER=0   # Prefill recompute_scheduler_enable
export D_RECOMPUTE_SCHEDULER=1   # Decode recompute_scheduler_enable

# 投机解码
export SPECULATIVE_METHOD=""                    # e.g. "eagle3"
export SPECULATIVE_MODEL_PATH=""                # eagle 模型路径
export P_SPECULATIVE_TOKENS=1                   # Prefill draft tokens
export D_SPECULATIVE_TOKENS=3                   # Decode draft tokens

# 编译配置
export P_CUDAGRAPH_MODE=""                      # e.g. "FULL_DECODE_ONLY"
export D_CUDAGRAPH_MODE=""                      # e.g. "FULL_DECODE_ONLY"

# Pipeline Parallel（可选，默认 1 = 关闭）
export P_PP_SIZE=1
export P_PP_LAYER_PARTITION=""                  # e.g. "32,30"
export D_PP_SIZE=1
export D_PP_LAYER_PARTITION=""                  # e.g. "32,30"
```

生成规则（`common/kv_transfer_config.sh` + `common/run_dp_template.sh`）：

- `ENABLE_KV_POOL=0`：仅使用 `PD_KV_CONNECTOR`（PD 分离）
- `ENABLE_KV_POOL=1`：`MultiConnector` = `PD_KV_CONNECTOR` + `AscendStoreConnector(backend=mooncake)`
- `PP_SIZE > 1` 时：`--pipeline-parallel-size` 加入 vllm 命令行，`VLLM_PP_LAYER_PARTITION` 环境变量导出，`kv_connector_extra_config` 自动包含 `pp_size` / `pp_layer_partition`
- `additional-config`：根据上述布尔开关**动态构建** JSON（非硬编码），仅非默认值才包含
- `speculative_config`：仅在 `SPECULATIVE_METHOD` 和 `SPECULATIVE_MODEL_PATH` 均非空时生成
- `compilation-config`：仅在 `P/D_CUDAGRAPH_MODE` 非空时生成
- Proxy：若 connector 名含 `Layerwise`，自动使用 layerwise proxy；否则使用普通 proxy
- `bash run.sh mooncake_master`：仅在 `ENABLE_KV_POOL=1` 时真正启动；否则直接跳过

### 1.3 场景默认值

| 场景目录 | ENABLE_KV_POOL | 拓扑默认 |
|----------|----------------|----------|
| `pd_single_node` | `0` | 单机同 IP，P/D 各 1 rank |
| `pd_and_kvpool_single_node` | `1` | 单机同 IP，P/D 各 1 rank |
| `pd_multi_nodes` | `1` | 默认四机 2P1D：P=`DP2 TP8`，D=`DP32 TP1`（两机拼一组） |

三个场景共享同一套 `common` 启动逻辑，仅 `configs.sh` 不同。

### 1.4 架构

```text
                 configs.sh (场景差异)
                        │
                        ▼
                   run.sh <role>
                        │
                        ▼
              common/entry.sh / start_*.sh
                        │
        ┌───────────────┼────────────────┐
        ▼               ▼                ▼
 mooncake_master   Prefill/Decode     PD Proxy
 (可选, KV池化)   launch_online_dp   (自动选实现)
                        │
                        ▼
                 run_dp_template.sh
              (按开关拼 kv-transfer-config)
```

### 1.5 共享目录同脚本多机运行（重要）

脚本放在共享盘，**每台机器执行同一份 `configs.sh` / `run.sh`，不要按机器复制多份脚本**。

机器差异只通过下面两种方式区分：

1. **`configs.sh` 中与机器 IP 下标对齐的参数列表**（主方式）  
   - `PREFILL_IPS[i]` / `PREFILL_NICS[i]`  
   - `DECODE_IPS[j]` / `DECODE_NICS[j]`  
   - 可选：`P_NODE_VISIBLE_DEVICES[i]`、`P_NODE_HTTP_PORT[i]`、`P_NODE_KV_PORT_BASE[i]`（Decode 同理）
2. **启动传参 / 环境变量**（辅助）  
   - `bash run.sh prefill`：按本机 IP 自动匹配列表下标  
   - `bash run.sh prefill 1` 或 `--node-index 1`  
   - `bash run.sh prefill --node-ip 90.90.97.28` 或 `NODE_IP=...`

日志默认写到共享盘下的**分机目录**：`${LOG_DIR_BASE}/<role><idx>_<ip>/`，避免多机互相覆盖。

```bash
# 所有机器都 cd 到同一共享路径
cd /mnt/a800_share/l00848175/scripts-ascend/example/pd_multi_nodes
bash run.sh topology

# P0 / P1 / D0 / D1 各自执行对应 role（命令可完全相同）
bash run.sh prefill    # 在 Prefill 机器上
bash run.sh decode     # 在 Decode 机器上
```

---

## 2. 文件结构

```text
scripts-ascend/example/
├── common/                                         # 公共脚本（同步到共享盘）
│   ├── README.md
│   ├── entry.sh                                    # 统一 action 入口
│   ├── load_configs.sh
│   ├── config_helpers.sh
│   ├── env_common.sh
│   ├── kv_transfer_config.sh                       # ENABLE_KV_POOL / connector
│   ├── gen_mooncake_json.sh
│   ├── launch_online_dp.py
│   ├── run_dp_template.sh
│   ├── start_mooncake_master.sh
│   ├── start_prefill.sh
│   ├── start_decode.sh
│   ├── start_proxy.sh
│   ├── test_curl.sh                                # AISBench GSM8K top10 精度烟测
│   ├── aisbench_configs/
│   │   ├── datasets/gsm8k/pd_gsm8k_acc_top10.py
│   │   └── models/vllm_api/pd_gsm8k_acc_top10.py
│   ├── load_balance_proxy_server_example.py
│   └── load_balance_proxy_layerwise_server_example.py
│
├── pd_single_node/                                 # 单节点 PD
│   ├── configs.sh                                  # ★ ENABLE_KV_POOL=0
│   ├── run.sh                                      # ★ 唯一入口
│   └── mooncake.json                               # 预置模板（池化关闭时可忽略）
│
├── pd_and_kvpool_single_node/                      # 单节点 PD+KV池
│   ├── configs.sh                                  # ★ ENABLE_KV_POOL=1
│   ├── run.sh                                      # ★ 唯一入口
│   └── mooncake.json
│
└── pd_multi_nodes/                                 # 多节点 PD+KV池
    ├── DESIGN_AND_OPS.md                           # 本文件
    ├── configs.sh                                  # ★ 多机拓扑 + ENABLE_KV_POOL=1
    ├── run.sh                                      # ★ 唯一入口
    ├── mooncake.json
    └── logs/
```

### 2.1 已删除的冗余脚本

以下旧脚本能力已被当前体系完全覆盖，已删除：

- 各样例目录下的 `start_prefill.sh` / `start_decode.sh` / `start_proxy.sh` / `start_mooncake_master.sh` / `test_curl.sh`（统一为 `run.sh <role>`）
- `pd_single_node/run_disaggregation_single_node_{p,d,Proxy}.sh`
- `pd_single_node/load_balance_proxy_server_example.py`
- `pd_and_kvpool_single_node/run_disaggregation_single_node_{p,d,Proxy}.sh`
- `pd_and_kvpool_single_node/load_balance_proxy_server_example.py`
- `pd_multi_nodes/launch_online_dp.py`、`run_dp_template.sh`（上移到 `common/`）
- `example/configs/kv_transfer_config_{p,d}.json`（改为运行时生成）

---

## 3. 配置说明（`configs.sh`）

### 3.1 必改项

```bash
MODEL_PATH=...
MODEL_NAME=...
PREFILL_IPS=(...)
PREFILL_NICS=(...)
DECODE_IPS=(...)
DECODE_NICS=(...)
P_VISIBLE_DEVICES_LIST=(...)
D_VISIBLE_DEVICES_LIST=(...)
```

### 3.2 功能开关

```bash
ENABLE_KV_POOL=0|1
PD_KV_CONNECTOR=MooncakeConnectorV1|MooncakeLayerwiseConnector
KV_POOL_BACKEND=mooncake                    # ENABLE_KV_POOL=1
MOONCAKE_MASTER_IP / PORT / GLOBAL_SEGMENT_SIZE

# 引擎级开关
ENABLE_FLASHCOMM1=0|1                       # VLLM_ASCEND_ENABLE_FLASHCOMM1
ENABLE_FUSED_MC2=0|1                        # VLLM_ASCEND_ENABLE_FUSED_MC2
VLLM_SERVER_DEV_MODE=0|1

# additional-config 动态开关（由 run_dp_template.sh 拼装 JSON）
ENABLE_REDUCE_SAMPLE=0|1                    # additional-config: enable_reduce_sample
ENABLE_CPU_BINDING=0|1                      # additional-config: enable_cpu_binding
ENABLE_NPUGRAPH_EX=0|1                      # additional-config: ascend_compilation_config.enable_npugraph_ex
WEIGHT_NZ_MODE=0|1                          # additional-config: weight_nz_mode
P_RECOMPUTE_SCHEDULER=0|1                   # Prefill: recompute_scheduler_enable
D_RECOMPUTE_SCHEDULER=0|1                   # Decode: recompute_scheduler_enable
```

### 3.3 投机解码

```bash
SPECULATIVE_METHOD=""                       # e.g. "eagle3"（空 = 关闭投机解码）
SPECULATIVE_MODEL_PATH=""                   # eagle 模型路径
P_SPECULATIVE_TOKENS=1                      # Prefill 端 draft token 数
D_SPECULATIVE_TOKENS=3                      # Decode 端 draft token 数
```

> 仅当 `SPECULATIVE_METHOD` 和 `SPECULATIVE_MODEL_PATH` 均非空且 `*_SPECULATIVE_TOKENS > 0` 时，才会生成 `--speculative_config` JSON。

### 3.4 编译配置

```bash
P_CUDAGRAPH_MODE=""                         # Prefill: e.g. "" 或 "FULL_DECODE_ONLY"
D_CUDAGRAPH_MODE=""                         # Decode: e.g. "FULL_DECODE_ONLY"
```

> 仅在非空时生成 `--compilation-config '{"cudagraph_mode":"<value>"}'`。

### 3.5 Pipeline Parallel

```bash
P_PP_SIZE=1                                 # Prefill pipeline parallel size（默认 1 = 关闭）
P_PP_LAYER_PARTITION=""                     # e.g. "32,30"
D_PP_SIZE=1                                 # Decode pipeline parallel size
D_PP_LAYER_PARTITION=""                     # e.g. "32,30"
```

> `PP_SIZE > 1` 时：
> - 自动添加 `--pipeline-parallel-size` 到 vllm 命令行
> - 导出 `VLLM_PP_LAYER_PARTITION` 环境变量
> - `kv_connector_extra_config` 自动包含 `pp_size` / `pp_layer_partition`
>
> 注意：PP 需要 `VISIBLE_DEVICES` 覆盖 TP × PP 张卡（e.g. TP=8, PP=2 → 16 张卡/rank）。

### 3.6 端口与并行

```bash
PROXY_PORT / P_VLLM_START_PORT / D_VLLM_START_PORT
P_KV_PORT_BASE / D_KV_PORT_BASE             # 建议避开 20000~(20000+NPU*1000)
P_DP_SIZE / P_DP_SIZE_LOCAL / P_TP_SIZE
D_DP_SIZE / D_DP_SIZE_LOCAL / D_TP_SIZE
```

公共目录约定：

```bash
SHARED_COMMON_DIR=/mnt/a800_share/l00848175/scripts-ascend/example/common
```

若共享目录不存在，自动回退到仓库内 `example/common`。

---

## 4. 操作指南

### 4.1 同步到共享盘

```bash
rsync -av scripts-ascend/example/common/ \
  /mnt/a800_share/l00848175/scripts-ascend/example/common/
rsync -av scripts-ascend/example/pd_single_node/ \
  /mnt/a800_share/l00848175/scripts-ascend/example/pd_single_node/
rsync -av scripts-ascend/example/pd_and_kvpool_single_node/ \
  /mnt/a800_share/l00848175/scripts-ascend/example/pd_and_kvpool_single_node/
rsync -av scripts-ascend/example/pd_multi_nodes/ \
  /mnt/a800_share/l00848175/scripts-ascend/example/pd_multi_nodes/
```

### 4.2 场景 A：单节点 PD（无池化）

```bash
cd /mnt/a800_share/l00848175/scripts-ascend/example/pd_single_node
# 编辑 configs.sh：IP/NIC/模型；确认 ENABLE_KV_POOL=0

bash run.sh prefill 0   # 终端1
bash run.sh decode 0    # 终端2
bash run.sh proxy       # 终端3
bash run.sh test        # AISBench GSM8K 前10条精度
```

### 4.3 场景 B：单节点 PD + KV 池化

```bash
cd /mnt/a800_share/l00848175/scripts-ascend/example/pd_and_kvpool_single_node
# 编辑 configs.sh；确认 ENABLE_KV_POOL=1

bash run.sh mooncake_master   # 终端1
bash run.sh prefill 0         # 终端2
bash run.sh decode 0          # 终端3
bash run.sh proxy             # 终端4
bash run.sh test              # AISBench GSM8K 前10条精度
```

### 4.4 场景 C：四机 2P1D（共享目录同脚本）

`pd_multi_nodes/configs.sh` 默认拓扑：

| 角色 | 机器数 | 并行 | 每机 local DP | 卡数/机（自动分配） |
|------|--------|------|---------------|---------------------|
| Prefill | 2 | DP2 TP8 | 1 | 8（`0-7`） |
| Decode | 2 | DP32 TP1 | 16 | 16（`0-15`，两机共一组 DP） |

**先只改一份共享 `configs.sh`（IP 对齐列表）：**

```bash
PREFILL_IPS=(P0_IP P1_IP)
PREFILL_NICS=(nic0 nic1)
DECODE_IPS=(D0_IP D1_IP)
DECODE_NICS=(nic0 nic1)
# 可选按机差异（下标与 IPS 对齐）
# P_NODE_VISIBLE_DEVICES=("0,1,2,3,4,5,6,7" "0,1,2,3,4,5,6,7")
# P_NODE_HTTP_PORT=(7100 7100)
# P_NODE_KV_PORT_BASE=(36000 36100)
```

**各机进入同一共享目录执行（命令可相同，靠本机 IP 匹配）：**

```bash
cd /mnt/a800_share/l00848175/scripts-ascend/example/pd_multi_nodes
bash run.sh topology

# P0
bash run.sh mooncake_master
bash run.sh prefill
bash run.sh proxy

# P1
bash run.sh prefill

# D0 / D1
bash run.sh decode

bash run.sh test
```

自动识别失败时显式指定：

```bash
bash run.sh prefill --node-ip 90.90.97.28
bash run.sh decode --node-index 1
NODE_IP=90.90.97.30 bash run.sh decode
```

### 4.5 精度验证（AISBench GSM8K top10）

`bash run.sh test` 调用 AISBench，对 Proxy 地址跑 **GSM8K 前 10 条**精度评测（对齐 aisbench smoke `accuracy_gsm8k` 的 `test_range='[0:10]'`）。

**前置条件：**

1. 容器内已安装 `ais_bench`，且命令可用：`ais_bench --help`
2. GSM8K 数据集已放到 aisbench 约定路径（相对源码根）：

```bash
# 数据集默认路径
<aisbench_root>/ais_bench/datasets/gsm8k
```

3. PD 服务与 Proxy 已拉起，`configs.sh` 中 `PROXY_HOST` / `PROXY_PORT` / `MODEL_NAME` 正确

**执行：**

```bash
bash run.sh test
```

**脚本行为：**

1. 将 `common/aisbench_configs/` 下 case 配置安装到当前 `ais_bench` 包的 `configs/`  
2. 写入运行时字段：`host_ip/host_port/model/path/max_out_len/batch_size/test_range`  
3. 执行：

```bash
ais_bench --models pd_gsm8k_acc_top10 --datasets pd_gsm8k_acc_top10 --work-dir <AISBENCH_WORK_DIR>
```

4. 在终端打印 summary，并尽量解析 accuracy 指标  
5. 完整日志：`${LOG_DIR}/aisbench_gsm8k/aisbench_pd_gsm8k_acc_top10_*.log`

**可在 `configs.sh` 调整的参数：**

```bash
export AISBENCH_CASE_NAME=pd_gsm8k_acc_top10
export AISBENCH_WORK_DIR=${LOG_DIR}/aisbench_gsm8k
export AISBENCH_MAX_OUT_LEN=512
export AISBENCH_BATCH_SIZE=1
export GSM8K_TEST_RANGE='[0:10]'   # 可改为 [0:50] 等
```

### 4.6 切换 connector / 开关池化示例

**在 `pd_single_node` 临时打开 KV 池化：**

```bash
# configs.sh
export ENABLE_KV_POOL=1
export PD_KV_CONNECTOR=MooncakeConnectorV1
```

然后按场景 B 顺序启动（需先 `bash run.sh mooncake_master`）。

**切换为 Layerwise connector：**

```bash
export PD_KV_CONNECTOR=MooncakeLayerwiseConnector
```

`bash run.sh proxy` 会自动改用 `load_balance_proxy_layerwise_server_example.py`。

---

## 5. 与官方文档/脚本对应关系

| 本工程 | 官方参考 |
|--------|----------|
| `common/launch_online_dp.py` | `vllm-ascend/examples/external_online_dp/launch_online_dp.py` |
| `common/run_dp_template.sh` | `external_online_dp/run_dp_template.sh` + multi-node PD 参数 |
| `ENABLE_KV_POOL=1` 的 MultiConnector | `user_guide/feature_guide/kv_pool.md` |
| `ENABLE_KV_POOL=0` 的单 connector | `pd_disaggregation_mooncake_*` |
| Proxy 自动选择 | `disaggregated_prefill_v1/load_balance_proxy_*.py` |
| `mooncake_master` | kv_pool / pd_colocated 文档 |
| `bash run.sh test`（GSM8K top10） | `aisbench/.../accuracy_gsm8k`（`test_range='[0:10]'`） |

---

## 6. 注意事项

1. **端口冲突**：AscendDirectTransport 占用 `[20000, 20000+NPU*1000)`，`kv_port` 建议 ≥ 28000（8 卡）或 ≥ 36000（16 卡）。
2. **PYTHONHASHSEED**：KV Pool 要求各节点一致，默认 `0`。
3. **global_segment_size**：建议按 1GB 对齐。
4. **共享目录优先**：确保容器内实际执行的是共享盘上的 `common`，避免节点本地旧副本。
5. **池化关闭时**：不必启动 `mooncake_master`；脚本会提示并跳过。
6. **硬件变量**：A2/A3 相关导出项可在 `env_common.sh` 中按需打开。
7. **AISBench**：需预先安装并准备 GSM8K 数据集；`bash run.sh test` 会向当前 Python 环境的 `ais_bench` 配置目录写入临时 case 文件。
8. **PP 适配**：启用 PP 时需确保 `VISIBLE_DEVICES_LIST` 每 rank 覆盖 TP×PP 张卡。`P_PP_LAYER_PARTITION` 需与模型层数匹配（MiniMax-M2.7 共 62 层 → `"32,30"` 表示 PP0 取 32 层、PP1 取 30 层）。
9. **additional-config 动态拼装**：不再硬编码 JSON，而是通过 configs.sh 中的布尔开关控制。只有非默认值的字段才会出现在最终 JSON 中，避免冗余配置。

---
## 7. backup 脚本参数对照

`backup/` 目录中的旧版脚本参数与新 `configs.sh` 体系的对应关系：

| backup 脚本参数 | configs.sh 对应变量 | 说明 |
|----------------|---------------------|------|
| `VLLM_ASCEND_ENABLE_FLASHCOMM1=1` | `ENABLE_FLASHCOMM1=1` | 同时控制 env var 和 additional-config |
| `VLLM_ASCEND_ENABLE_FUSED_MC2=1` | `ENABLE_FUSED_MC2=1` | 同时控制 env var 和 additional-config |
| `VLLM_PP_LAYER_PARTITION="32,30"` | `P_PP_LAYER_PARTITION="32,30"` | env + kv_connector_extra_config |
| `VLLM_SERVER_DEV_MODE=1` | `VLLM_SERVER_DEV_MODE=1` | env var |
| `--pipeline-parallel-size 2` | `P_PP_SIZE=2` | vllm arg |
| `--compilation-config '{"cudagraph_mode":"FULL_DECODE_ONLY"}'` | `D_CUDAGRAPH_MODE="FULL_DECODE_ONLY"` | 动态生成 |
| `--speculative_config '{"method":"eagle3",...}'` | `SPECULATIVE_METHOD="eagle3"` + `SPECULATIVE_MODEL_PATH=...` + `*_SPECULATIVE_TOKENS` | 动态生成 |
| `--additional-config '{...}'` | 各 `ENABLE_*` / `WEIGHT_*` / `*_RECOMPUTE_SCHEDULER` 布尔开关 | 动态拼装 |
| `--enable-prefix-caching` / `--no-enable-prefix-caching` | `ENABLE_PREFIX_CACHE=1/0` | 已有 |
| `--enable-expert-parallel` | `ENABLE_EXPERT_PARALLEL=1/0` | 已有 |

---
## 8. 检查清单

- [ ] 已按场景修改对应 `configs.sh`
- [ ] `example/common` 已同步到 `/mnt/a800_share/.../common`
- [ ] 若 `ENABLE_KV_POOL=1`，已先执行 `bash run.sh mooncake_master`
- [ ] `PD_KV_CONNECTOR` 与 Proxy 实现匹配（Layerwise 自动处理）
- [ ] 多节点时 `node_index` 与 IP 列表一致
- [ ] 已安装 `ais_bench` 且 GSM8K 数据集就绪
- [ ] `bash run.sh test` 完成并输出 GSM8K top10 精度/summary
