#!/bin/bash
set -euo pipefail
export PATH="/usr/local/python3.12.13/bin:${PATH}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python /mnt/share/l00848175/scripts-ascend/example/common/load_balance_proxy_server_example.py \
  --host 0.0.0.0 --port "${1:-9000}" \
  --prefiller-hosts 192.168.13.165 --prefiller-ports 8000 \
  --decoder-hosts 192.168.13.165 --decoder-ports 8001 \
  2>&1 | tee "${SCRIPT_DIR}/proxy.log"
