# DeepSeek V3.1 2P1D PD分离 + MRV2 + KV池化 + Prefix Cache 部署报告

## 基本信息

| 项目 | 内容 |
|------|------|
| **日期** | 2026-07-27 |
| **模型** | DeepSeek-V3.1-Terminus-w4a8-mtp-QuaRot (w4a8量化, 685B参数, MoE) |
| **vllm版本** | v0.25.1 (commit 752a3a504) |
| **vllm-ascend版本** | main分支 (commit bbabae3f, 0.19.1rc2.dev1017) |
| **容器镜像** | quay.io/ascend/vllm-ascend:nightly-main-a3 |
| **特性** | ModelRunnerV2, PD分离(MooncakeConnectorV1), KV池化, Prefix Cache |
| **拓扑** | 2 Prefill + 1 Decode (2P1D) |

## 节点资源

| 节点 | IP | NPU | 最终分配 |
|------|-----|-----|----------|
| Node 29 | 90.90.97.29 | 16x Ascend910 | P0 (devices 0-7) + Mooncake Master |
| Node 37 | 90.90.97.37 | 16x Ascend910 | P1 (devices 0-7) + D0 (devices 8-15) |
| Node 42 | 90.90.97.42 | 16x Ascend910 | 未使用 (容器兼容性问题) |

> **注意**: Node 42的容器镜像 (dev-26.1.0.cann9.1.0.day20260720) 与Node 29/37不一致，存在C++层面 `std::logic_error: basic_string::_S_construct null not valid` 错误，未能定位根因。重装为nightly-main-a3后仍失败(可能是CANN/HCCL驱动兼容性)，最终改用Node 37运行Decode。

## 并行策略

| 角色 | DP(总) | DP(本地) | TP | 每节点卡数 | 跨节点DP通信 |
|------|--------|----------|-----|--------------|-------------|
| Prefill 0 | 2 | 1 | 8 | 8卡 | 是(enp194s0f0网卡) |
| Prefill 1 | 2 | 1 | 8 | 8卡 | 是(enp194s0f0网卡) |
| Decode 0 | 2 | 1 | 8 | 8卡/节点 | 是(enp194s0f0网卡) |

### 与原期望差异说明

| 参数 | 原期望 | 实际 | 原因 |
|------|--------|------|------|
| D_TP_SIZE | 1 | 8 | 685B w4a8模型~343GB, 单卡64GB无法容纳TP=1 |
| D_DP_SIZE | 32 | 2 | 16卡÷TP8=2组DP, 且跨节点 |
| P_每节点卡数 | 16 | 8 | P_DP_SIZE_LOCAL=1, TP=8=8卡 |

## 关键Bug修复

### Bug #1: run_dp_template.sh 跨节点Gloo通信失败

**文件**: `/mnt/a800_share/l00848175/scripts-ascend/example/common/run_dp_template.sh`  
**问题**: 第46行无条件设置 `export GLOO_SOCKET_IFNAME=lo`，导致跨节点DP时使用loopback而非实际网卡  
**症状**: `Gloo connectFullMesh failed with Connection refused, remote=[127.0.0.1]:32646`  
**修复**:
```bash
# 原代码 (已注释):
# export GLOO_SOCKET_IFNAME=lo

# 修复后: 仅在全部DP rank都在本节点时使用loopback
if [[ "${ROLE}" == "prefill" ]]; then
    if [[ "${P_DP_SIZE:-1}" == "${P_DP_SIZE_LOCAL:-1}" ]]; then
        export GLOO_SOCKET_IFNAME=lo
    fi
elif [[ "${ROLE}" == "decode" ]]; then
    if [[ "${D_DP_SIZE:-1}" == "${D_DP_SIZE_LOCAL:-1}" ]]; then
        export GLOO_SOCKET_IFNAME=lo
    fi
fi
```
**状态**: ✅ 已修复并验证，备份文件 `run_dp_template.sh.bak.*`

### Bug #2: hunyuan_vl_image.py transformers兼容性

**文件**: `/vllm-workspace/vllm/vllm/transformers_utils/processors/hunyuan_vl_image.py`  
**问题**: 第477行 `AutoImageProcessor.register("HunYuanVLImageProcessor", ...)` 对 transformers 5.13.0不兼容 (register方法期望class而非string)  
**症状**: `AttributeError: 'str' object has no attribute '__module__'` (仅Node 42出现, 因pip install更新了依赖)  
**修复**:
```python
# 原代码:
AutoImageProcessor.register("HunYuanVLImageProcessor", HunYuanVLImageProcessor)

# 修复后:
try:
    AutoImageProcessor.register("HunYuanVLImageProcessor", HunYuanVLImageProcessor)
except (AttributeError, TypeError):
    pass
```
**状态**: ⚠️ Node 42上已修复，但尚未提交到源码仓库

### Bug #3: Node 42 依赖版本不兼容

**问题**: 更新vllm到v0.25.1时，`pip install -e .` 升级了numpy 1.26.4→2.3.5、opentelemetry版本，破坏了兼容性  
**修复**: `pip install numpy==1.26.4` 降级  
**状态**: ✅ 已修复

### 未解决问题: Decode MRV2 profile_run崩溃

**问题**: Decode节点在MRV2的 `profile_run()` 阶段崩溃 (vllm_ascend/worker/v2/model_runner.py:166)  
**症状**: 所有TP worker同时报 `WorkerProc hit an exception`，发生在`determine_available_memory` → `profile_run`  
**影响**: Decode未能成功启动  
**可能原因**: MRV2在Decode模式下(`cudagraph_mode: FULL_DECODE_ONLY` + `enable_npugraph_ex`)的profile_run与Ascend NPU存在兼容性问题  
**建议**: 下一步需禁用MRV2测试(`VLLM_USE_V2_MODEL_RUNNER=0`)以隔离问题

## 已启用特性

| 特性 | 状态 | 配置位置 |
|------|------|----------|
| Model Runner V2 | ✅ Prefill成功 / ❌ Decode失败 | `VLLM_USE_V2_MODEL_RUNNER=1` |
| PD分离 | ✅ P节点通信正常 | `PD_KV_CONNECTOR=MooncakeConnectorV1` |
| KV池化 | ✅ Master启动成功 | `ENABLE_KV_POOL=1`, `KV_POOL_BACKEND=mooncake` |
| Prefix Cache | ✅ 已启用 | `--enable-prefix-caching` |
| Mooncake | ✅ Master运行在Node 29:50088 | `MOONCAKE_MASTER_IP=90.90.97.29` |

## 配置文件位置

| 文件 | 路径 |
|------|------|
| 测试配置 | `/mnt/a800_share/l00848175/workspace/tests/test_deepseek_v31_mrv2_pd_kvpool_pcache/configs.sh` |
| 公共脚本 | `/mnt/a800_share/l00848175/scripts-ascend/example/common/` |
| 模型权重 | `/mnt/a800_weight/DeepSeek-V3.1-Terminus-w4a8-mtp-QuaRot` |
| 报告(远程) | `/mnt/a800_share/l00848175/workspace/reports/deepseek_v31_2p1d_mrv2_report.md` |

## 完整操作指南

### 1. 环境准备

```bash
# 选择空闲节点 (优先Node 29, 37)
ssh root@90.90.97.29 "npu-smi info | grep 'No running' | wc -l"  # 期望: 8

# 如果容器不存在的节点, 拉取镜像并创建容器
docker pull quay.io/ascend/vllm-ascend:nightly-main-a3
bash /mnt/a800_share/l00848175/scripts-ascend/start_container.sh \
    quay.io/ascend/vllm-ascend:nightly-main-a3 vllm-0251
```

### 2. 版本确认

```bash
docker exec vllm-0251 bash -c '
    pip show vllm | grep Version      # 期望: 0.25.1+empty
    pip show vllm-ascend | grep Version  # 期望: 0.19.1rc2.dev1017+
    cd /vllm-workspace/vllm && git log --oneline -1  # 期望: 752a3a504
'
```

### 3. 更新共享盘脚本

```bash
cd /mnt/a800_share/l00848175/scripts-ascend
git remote set-url origin https://ghp_<token>@github.com/iKeybot-code/scripts-ascend.git
GIT_SSL_NO_VERIFY=1 git pull origin main
```

### 4. 创建测试目录

```bash
mkdir -p /mnt/a800_share/l00848175/workspace/tests
cp -r /mnt/a800_share/l00848175/scripts-ascend/example/pd_multi_nodes/ \
    /mnt/a800_share/l00848175/workspace/tests/test_deepseek_v31_mrv2_pd_kvpool_pcache/
```

### 5. 修改configs.sh

关键参数:
```bash
MODEL_PATH=/mnt/a800_weight/DeepSeek-V3.1-Terminus-w4a8-mtp-QuaRot
PREFILL_IPS=(90.90.97.29 90.90.97.37)
DECODE_IPS=(90.90.97.29 90.90.97.37)   # 跨节点Decode
P_DP_SIZE=2; P_TP_SIZE=8; P_DP_SIZE_LOCAL=1
D_DP_SIZE=2; D_TP_SIZE=8; D_DP_SIZE_LOCAL=1
P_VISIBLE_DEVICES_LIST=("0,1,2,3,4,5,6,7")
D_VISIBLE_DEVICES_LIST=("8,9,10,11,12,13,14,15")
```

### 6. 应用Bug修复

```bash
# Fix run_dp_template.sh (Gloo跨节点DP)
# 在 /mnt/a800_share/l00848175/scripts-ascend/example/common/run_dp_template.sh
# 将 "export GLOO_SOCKET_IFNAME=lo" 替换为条件判断 (参见Bug #1)

# Fix hunyuan_vl_image.py (如需)
# 在 /vllm-workspace/vllm/vllm/transformers_utils/processors/hunyuan_vl_image.py
# 将 line 477 的 AutoImageProcessor.register 包装为 try/except (参见Bug #2)
```

### 7. 启动服务

```bash
TEST_DIR=/mnt/a800_share/l00848175/workspace/tests/test_deepseek_v31_mrv2_pd_kvpool_pcache

# Master (Node 29)
ssh root@90.90.97.29 "docker exec vllm-0251 bash -c 'cd $TEST_DIR && bash run.sh mooncake_master'"

# Prefill 0 (Node 29) + Prefill 1 (Node 37) 同步启动
ssh root@90.90.97.29 "docker exec vllm-0251 bash -c 'cd $TEST_DIR && bash run.sh prefill 0'" &
ssh root@90.90.97.37 "docker exec vllm-0251 bash -c 'cd $TEST_DIR && bash run.sh prefill 1'" &

# 等待Prefill API就绪 (约10-15分钟)
curl http://90.90.97.29:13900/health
curl http://90.90.97.37:13900/health

# Decode 0 (Node 29) + Decode 1 (Node 37) 同步启动
ssh root@90.90.97.29 "docker exec vllm-0251 bash -c 'cd $TEST_DIR && bash run.sh decode 0'" &
ssh root@90.90.97.37 "docker exec vllm-0251 bash -c 'cd $TEST_DIR && bash run.sh decode 1'" &

# Proxy (Node 29)
ssh root@90.90.97.29 "docker exec vllm-0251 bash -c 'cd $TEST_DIR && bash run.sh proxy'"
```

### 8. 烟测

```bash
ssh root@90.90.97.29 "docker exec vllm-0251 bash -c 'cd $TEST_DIR && bash run.sh test'"
```

### 9. 停止服务

```bash
for ip in 90.90.97.29 90.90.97.37 90.90.97.42; do
    ssh root@$ip "
        docker stop vllm-0251 2>/dev/null
        fuser -k /dev/davinci* 2>/dev/null || true
    "
done
```

## 下一步

1. **隔离MRV2 Decode问题**: 使用 `VLLM_USE_V2_MODEL_RUNNER=0` 测试Decode是否正常
2. **Node 42兼容性**: 排查C++ `std::logic_error` 根因 (CANN驱动/CANN库版本对齐)
3. **AIME2025精度评测**: Decode正常后运行完整评测
4. **源码提交**: 将Bug修复提交到vllm和vllm-ascend对应分支
5. **脚本备份**: 将测试配置同步到 `/mnt/a800_share/l00848175/scripts-ascend/tests/`

---

*报告生成时间: 2026-07-27*  
*生成工具: Claude Code*
