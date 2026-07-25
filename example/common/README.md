# common

公共脚本目录。容器环境默认引用：

```text
/mnt/a800_share/l00848175/scripts-ascend/example/common/
```

请将本目录同步到上述共享路径。各场景目录（`pd_single_node` / `pd_and_kvpool_single_node` / `pd_multi_nodes`）只保留 `configs.sh` 与薄封装入口，实际逻辑均在此目录执行。

## 主要文件

| 文件 | 作用 |
|------|------|
| `entry.sh` | 统一入口：`master/proxy/prefill/decode/test` |
| `launch_online_dp.py` / `run_dp_template.sh` | 对齐官方 external online DP |
| `kv_transfer_config.sh` | 按 `ENABLE_KV_POOL` / `PD_KV_CONNECTOR` 生成 KV 配置 |
| `start_*.sh` / `test_curl.sh` | 组件启动与验证 |
| `load_balance_proxy_*.py` | PD Proxy（普通 / layerwise） |
| `gen_mooncake_json.sh` | 生成 mooncake.json |
| `env_common.sh` / `config_helpers.sh` | 环境与节点解析 |
