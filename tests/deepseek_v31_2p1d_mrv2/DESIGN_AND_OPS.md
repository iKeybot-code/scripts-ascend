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
| 独立组件脚本 | `start_mooncake_master.sh`、`start_proxy.sh` |

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
```

生成规则（`common/kv_transfer_config.sh`）：

- `ENABLE_KV_POOL=0`：仅使用 `PD_KV_CONNECTOR`（PD 分离）
- `ENABLE_KV_POOL=1`：`MultiConnector` = `PD_KV_CONNECTOR` + `AscendStoreConnector(backend=mooncake)`
- Proxy：若 connector 名含 `Layerwise`，自动使用 layerwise proxy；否则使用普通 proxy
- `start_mooncake_master.sh`：仅在 `ENABLE_KV_POOL=1` 时真正启动；否则直接跳过

### 1.3 场景默认值

| 场景目录 | ENABLE_KV_POOL | 拓扑默认 |
|----------|----------------|----------|
| `pd_single_node` | `0` | 单机同 IP，P/D 各 1 rank |
| `pd_and_kvpool_single_node` | `1` | 单机同 IP，P/D 各 1 rank |
| `pd_multi_nodes` | `1` | 多机 IP 列表，可配多 rank |

三个场景共享同一套 `common` 启动逻辑，仅 `configs.sh` 不同。

### 1.4 架构

```text
                 configs.sh (场景差异)
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

启动顺序：

1. （可选）`start_mooncake_master.sh` —— 仅 KV 池化需要  
2. `start_prefill.sh <node_index>`  
3. `start_decode.sh <node_index>`  
4. `start_proxy.sh`  
5. `test_curl.sh`（AISBench GSM8K 前 10 条精度）

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
│   ├── run.sh
│   ├── start_*.sh / test_curl.sh                   # 薄封装 -> run.sh
│   └── mooncake.json                               # 预置模板（池化关闭时可忽略）
│
├── pd_and_kvpool_single_node/                      # 单节点 PD+KV池
│   ├── configs.sh                                  # ★ ENABLE_KV_POOL=1
│   ├── run.sh / start_*.sh / test_curl.sh
│   └── mooncake.json
│
└── pd_multi_nodes/                                 # 多节点 PD+KV池
    ├── DESIGN_AND_OPS.md                           # 本文件
    ├── configs.sh                                  # ★ 多机拓扑 + ENABLE_KV_POOL=1
    ├── run.sh / start_*.sh / test_curl.sh
    ├── mooncake.json
    └── logs/
```

### 2.1 已删除的冗余脚本

以下旧脚本能力已被当前体系完全覆盖，已删除：

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
KV_POOL_BACKEND=mooncake          # ENABLE_KV_POOL=1
MOONCAKE_MASTER_IP / PORT / GLOBAL_SEGMENT_SIZE
```

### 3.3 端口与并行

```bash
PROXY_PORT / P_VLLM_START_PORT / D_VLLM_START_PORT
P_KV_PORT_BASE / D_KV_PORT_BASE   # 建议避开 20000~(20000+NPU*1000)
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

bash start_prefill.sh 0      # 终端1
bash start_decode.sh 0       # 终端2
bash start_proxy.sh          # 终端3
bash test_curl.sh            # AISBench GSM8K 前10条精度
```

### 4.3 场景 B：单节点 PD + KV 池化

```bash
cd /mnt/a800_share/l00848175/scripts-ascend/example/pd_and_kvpool_single_node
# 编辑 configs.sh；确认 ENABLE_KV_POOL=1

bash start_mooncake_master.sh   # 终端1
bash start_prefill.sh 0         # 终端2
bash start_decode.sh 0          # 终端3
bash start_proxy.sh             # 终端4
bash test_curl.sh               # AISBench GSM8K 前10条精度
```

### 4.4 场景 C：多节点 PD + KV 池化

```bash
cd /mnt/a800_share/l00848175/scripts-ascend/example/pd_multi_nodes
# 编辑 configs.sh 中的 PREFILL_IPS/DECODE_IPS/NICS 等

# Master 节点
bash start_mooncake_master.sh

# Prefill 节点 i
bash start_prefill.sh <i>

# Decode 节点 j
bash start_decode.sh <j>

# Proxy 节点
bash start_proxy.sh
bash test_curl.sh               # AISBench GSM8K 前10条精度
```

也可用统一入口：

```bash
bash run.sh mooncake_master
bash run.sh prefill 0
bash run.sh decode 0
bash run.sh proxy
bash run.sh test
```

### 4.5 精度验证（AISBench GSM8K top10）

`test_curl.sh` 已改为调用 AISBench，对 Proxy 地址跑 **GSM8K 前 10 条**精度评测（对齐 aisbench smoke `accuracy_gsm8k` 的 `test_range='[0:10]'`）。

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
bash test_curl.sh
# 或
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

然后按场景 B 顺序启动（需先 `start_mooncake_master.sh`）。

**切换为 Layerwise connector：**

```bash
export PD_KV_CONNECTOR=MooncakeLayerwiseConnector
```

`start_proxy.sh` 会自动改用 `load_balance_proxy_layerwise_server_example.py`。

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
| `test_curl.sh`（GSM8K top10） | `aisbench/.../accuracy_gsm8k`（`test_range='[0:10]'`） |

---

## 6. 注意事项

1. **端口冲突**：AscendDirectTransport 占用 `[20000, 20000+NPU*1000)`，`kv_port` 建议 ≥ 28000（8 卡）或 ≥ 36000（16 卡）。
2. **PYTHONHASHSEED**：KV Pool 要求各节点一致，默认 `0`。
3. **global_segment_size**：建议按 1GB 对齐。
4. **共享目录优先**：确保容器内实际执行的是共享盘上的 `common`，避免节点本地旧副本。
5. **池化关闭时**：不必启动 `mooncake_master`；脚本会提示并跳过。
6. **硬件变量**：A2/A3 相关导出项可在 `env_common.sh` 中按需打开。
7. **AISBench**：需预先安装并准备 GSM8K 数据集；`test_curl.sh` 会向当前 Python 环境的 `ais_bench` 配置目录写入临时 case 文件。

---

## 7. 检查清单

- [ ] 已按场景修改对应 `configs.sh`
- [ ] `example/common` 已同步到 `/mnt/a800_share/.../common`
- [ ] 若 `ENABLE_KV_POOL=1`，已先启动 `mooncake_master`
- [ ] `PD_KV_CONNECTOR` 与 Proxy 实现匹配（Layerwise 自动处理）
- [ ] 多节点时 `node_index` 与 IP 列表一致
- [ ] 已安装 `ais_bench` 且 GSM8K 数据集就绪
- [ ] `test_curl.sh` 完成并输出 GSM8K top10 精度/summary
