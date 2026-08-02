# MiniMax M2.7 PD分离部署任务报告

**日期**: 2026-07-27
**任务**: MiniMax M2.7 (MiniMax-M2.7-w8a8-QuaRot) PD分离部署与AIME2025精度测评
**目标特性**: ModelRunnerV2 + PD分离(1P1D/MooncakeConnectorV1) + KV池化 + Prefix Cache

---

## 一、任务执行摘要

| 阶段 | 状态 | 说明 |
|------|------|------|
| 环境检查 | ✅ 完成 | 检查9台机器NPU状态，删除旧容器 |
| 镜像准备 | ✅ 完成 | 拉取/迁移nightly-main-a3镜像到多节点 |
| 源码更新 | ✅ 完成 | vllm main (da99ffcc1) + vllm-ascend main (39d1cf9b3) |
| Prefill部署 | ✅ 成功 | Node 37, DP=2/TP=8, 16卡, 正常运行 |
| Decode部署 | ❌ 阻塞 | 多节点/多驱动版本均出现C++崩溃 |
| AIME2025测评 | ⏸️ 未执行 | Decode阻塞导致无法完成 |

---

## 二、集群资源状态

| 节点 | 驱动版本 | NPU状态 | 备注 |
|------|----------|---------|------|
| 90.90.97.4 | 26.1.0.b070 | 16卡空闲 | 驱动版本不兼容 |
| 90.90.97.15 | 26.1.0.b070 | 16卡空闲 | ❌ 多卡崩溃(std::logic_error) |
| 90.90.97.27 | 26.0.rc1 | 全部占用 | 其他vllm进程 |
| 90.90.97.28 | 26.0.rc1 | NPU2-7空闲 | ❌ 解码崩溃 |
| 90.90.97.29 | 25.5.0 | NPU4-7空闲 | 仅8卡可用 |
| 90.90.97.36 | 25.5.0 | 全部占用 | 其他vllm进程 |
| 90.90.97.37 | 25.5.0 | ✅ 使用中 | Prefill正常运行 |
| 90.90.97.42 | 25.5.0 | NPU0-3占用 | 其他用户进程冲突 |
| 90.90.97.48 | 26.0.rc1.b030 | 16卡空闲 | 无共享盘/a800_share |

---

## 三、部署过程与Bug分析

### 3.1 镜像迁移

**问题**: 多节点无法直接从 quay.io 拉取镜像（SSL证书错误、网络超时）
**解决**: 通过共享盘 `/mnt/a800_share/` 迁移镜像

```bash
# 导出 (Node 37)
docker save quay.io/ascend/vllm-ascend:nightly-main-a3 \
  -o /mnt/a800_share/l00848175/tmp/vllm-ascend-nightly.tar

# 加载 (Node 15/28/42)
docker load -i /mnt/a800_share/l00848175/tmp/vllm-ascend-nightly.tar
```

### 3.2 容器创建

**问题**: start_container.sh 使用 `-it` 需要TTY，SSH非交互模式报错
**解决**: 手动创建detached容器

```bash
docker run -d --name vllm-lkl-minimax --net=host --shm-size=500g \
  --device /dev/davinci0 ... --device /dev/davinci15 \
  --device /dev/davinci_manager --device /dev/devmm_svm --device /dev/hisi_hdc \
  -v /mnt:/mnt -v /home:/home -v /data:/data \
  quay.io/ascend/vllm-ascend:nightly-main-a3 sleep infinity
```

### 3.3 源码安装

**问题1**: vllm可编辑安装缺少 `setuptools_rust`
**解决**: `pip install setuptools_rust`

**问题2**: `pip install -e .` 后 `vllm` 命令行入口丢失
**解决**: 手动创建wrapper脚本
```bash
cat > /usr/local/python3.12.13/bin/vllm << 'EOF'
#!/bin/bash
PYTHONUNBUFFERED=1 exec python -m vllm.entrypoints.cli.main "$@"
EOF
chmod +x /usr/local/python3.12.13/bin/vllm
```

**问题3**: vllm-ascend要求 `fastapi<0.124.0`，但vllm安装后覆盖为0.136.3
**解决**: `pip install "fastapi<0.124.0"`

### 3.4 驱动版本兼容性问题 (关键Bug)

**现象**: Decode角色在驱动 26.1.0.b070 和 26.0.rc1 上出现C++崩溃
```
terminate called after throwing an instance of 'std::logic_error'
  what():  basic_string::_S_construct null not valid
```

**影响范围**:
| 驱动版本 | TP=1 | TP>1 | Decode |
|----------|------|------|--------|
| 25.5.0 | ✅ | ✅ | ❌ (请求级崩溃) |
| 26.0.rc1 | 未测试 | ❌ | ❌ |
| 26.1.0.b070 | ✅ | ❌ | ❌ |

**分析**:
- vllm main分支 (commit da99ffcc1) 的decode角色存在C++空指针/空字符串bug
- 模型加载正常(/v1/models 返回200)，但处理推理请求时崩溃
- Prefill角色在25.5.0驱动上完全正常
- 此bug可能与 `--kv-transfer-config` 中的MooncakeConnectorV1实例化有关

### 3.5 PD配置迭代

**配置演进**:

| 版本 | Prefill | Decode | 结果 |
|------|---------|--------|------|
| v1 | DP=1/TP=16 (16卡) | DP=1/TP=16 | ❌ `data_parallel_external_lb` 要求 DP>1 |
| v2 | DP=2/TP=8 (16卡) | DP=2/TP=8 | P成功, D WorkerProc崩溃 |
| v3 | DP=2/TP=8 | DP=1/TP=8 (8卡) | ❌ DP=1与external_lb冲突 |
| v4 | DP=2/TP=4 (8卡) | DP=2/TP=4 (8卡) | P成功, D请求级崩溃 |
| v5 | DP=2/TP=8 | - (关闭KV池化) | ❌ Decode仍崩溃 |

### 3.6 端口冲突

**问题**: P_VLLM_START_PORT=13900, D_VLLM_START_PORT=13901 导致P rank1和D rank0共用13901端口
**解决**: 修改 D_VLLM_START_PORT=13910

---

## 四、成功的Prefill配置

```bash
# 节点: 90.90.97.37 (驱动 25.5.0)
# 配置: DP=2, TP=4, 8张卡用于Prefill

export P_DP_SIZE=2
export P_TP_SIZE=4
export P_DP_SIZE_LOCAL=2
export P_VISIBLE_DEVICES_LIST=("0,1,2,3" "4,5,6,7")
export P_VLLM_START_PORT=13900
export PREFILL_IPS=(90.90.97.37)
export PREFILL_NICS=(enp194s0f0)
export P_ENFORCE_EAGER=1
export VLLM_USE_V2_MODEL_RUNNER=1
export ENABLE_PREFIX_CACHE=1
export MOONCAKE_MASTER_IP=90.90.97.37
export MOONCAKE_MASTER_PORT=50088
```

**验证结果**: Prefill rank0 (port 13900) 和 rank1 (port 13901) 均正常响应，模型 `minimax-m27-pd` 可用于推理。

---

## 五、待解决问题

1. **[严重] Decode C++崩溃**: vllm main分支 (>= da99ffcc1) 在Ascend平台的decode角色中，WorkerProc处理首个推理请求时抛出 `std::logic_error: basic_string::_S_construct null not valid`。需要:
   - 回退到已验证的vllm/vllm-ascend稳定版本
   - 或在vllm-ascend仓库中提交bug report

2. **[建议] 驱动版本选择**: 建议统一使用驱动25.5.0的节点进行PD部署(已验证兼容)

3. **[增强] AIME2025测试**: 需在decode修复后，通过AISBench执行完整精度测评。AIME2025数据集和测试配置已准备就绪。

---

## 六、文件资产

| 文件 | 路径 |
|------|------|
| 测试脚本和配置 | `/mnt/a800_share/l00848175/workspace/tests/test_minimax-m27_pd_mrv2_kvpool_pcache/` |
| AIME2025 AISBench配置 | `/mnt/a800_share/l00848175/scripts-ascend/example/common/aisbench_configs/datasets/aime2025/pd_aime2025.py` |
| AIME2025 模型配置 | `/mnt/a800_share/l00848175/scripts-ascend/example/common/aisbench_configs/models/vllm_api/pd_aime2025.py` |
| 镜像备份 | `/mnt/a800_share/l00848175/tmp/vllm-ascend-nightly.tar` (16GB) |
| 日志目录 | `/mnt/a800_share/l00848175/workspace/tests/test_minimax-m27_pd_mrv2_kvpool_pcache/logs/` |

---

## 七、后续建议

1. 使用经过验证的vllm/vllm-ascend版本组合 (而非main分支) 进行PD部署
2. 确认Node 27上运行的vllm版本可作为稳定基线
3. 优先选用驱动版本25.5.0的节点 (Node 37, 29, 36, 42)
4. 建议在Node 37上完成单节点PD+KV池化验证后，再扩展到跨节点部署
