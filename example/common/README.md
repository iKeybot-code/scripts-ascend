# common

公共脚本目录。容器环境默认引用：

```text
/mnt/a800_share/l00848175/scripts-ascend/example/common/
```

请将本目录同步到上述共享路径。各场景目录只保留 `configs.sh` + `run.sh`，通过：

```bash
bash run.sh <mooncake_master|prefill|decode|proxy|test> [args...]
```

调用本目录实现。

## 主要文件

| 文件 | 作用 |
|------|------|
| `entry.sh` | 统一 action 分发：`mooncake_master/proxy/prefill/decode/test` |
| `launch_online_dp.py` / `run_dp_template.sh` | 对齐官方 external online DP |
| `kv_transfer_config.sh` | 按 `ENABLE_KV_POOL` / `PD_KV_CONNECTOR` 生成 KV 配置 |
| `start_*.sh` | 组件实现（由 `entry.sh` 调用，勿在场景目录重复） |
| `test_curl.sh` | AISBench GSM8K 前 10 条精度烟测（`run.sh test`） |
| `aisbench_configs/` | GSM8K top10 case 配置模板 |
| `load_balance_proxy_*.py` | PD Proxy（普通 / layerwise） |
| `gen_mooncake_json.sh` | 生成 mooncake.json |
| `env_common.sh` / `config_helpers.sh` | 环境与节点解析 |
