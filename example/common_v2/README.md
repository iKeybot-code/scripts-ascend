# common_v2

公共脚本目录（v2）。相对 `common` 的主要差异：

1. 场景侧将配置拆成 `configs_common.sh` / `configs_prefill.sh` / `configs_decode.sh`
2. JSON 类参数（`additional-config` / `speculative_config` / `compilation-config` / `kv-transfer-config`）由 configs 用普通 `export` 承载
3. `run_dp_template.sh` 只做开关判断与命令拼接，并在日志目录写入完整 `.cmd` 文件
4. 按 `ENABLE_KV_POOL` 在 `KV_TRANSFER_CONFIG_PD` / `KV_TRANSFER_CONFIG_POOL` 间选择

容器默认共享路径：

```text
/mnt/a800_share/l00848175/scripts-ascend/example/common_v2/
```

```bash
bash run.sh <mooncake_master|prefill|decode|proxy|test|topology> [args...]
```

## 主要文件

| 文件 | 作用 |
|------|------|
| `entry.sh` | 统一 action 分发 |
| `config_helpers.sh` | 节点解析 / IP 自动识别 / 拓扑校验 |
| `launch_online_dp.py` / `run_dp_template.sh` | online DP 拉起；模板只拼命令并落盘 `.cmd` |
| `kv_transfer_config.sh` | 按 `ENABLE_KV_POOL` 选择并替换占位符 |
| `start_*.sh` | 组件实现 |
| `load_balance_proxy_*.py` | PD Proxy |

## 共享目录多机

所有节点执行同一份脚本；用 configs 的 IP 对齐列表区分机器，或传 `--node-ip` / `--node-index`。

xPxD 布局下需在 configs 中维护：设备可见列表、IP、nicname、DP/TP/PP 与 rank 起止。
