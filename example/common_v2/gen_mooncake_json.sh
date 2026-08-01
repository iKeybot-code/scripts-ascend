#!/bin/bash
# Generate mooncake.json from master ip/port and segment size.
# Usage:
#   bash gen_mooncake_json.sh <master_ip> <master_port> <output_path> [global_segment_size]

set -euo pipefail

MASTER_IP="${1:?master_ip required}"
MASTER_PORT="${2:?master_port required}"
OUTPUT_PATH="${3:?output_path required}"
GLOBAL_SEGMENT_SIZE="${4:-1GB}"

mkdir -p "$(dirname "${OUTPUT_PATH}")"

cat > "${OUTPUT_PATH}" <<EOF
{
    "metadata_server": "P2PHANDSHAKE",
    "protocol": "ascend",
    "device_name": "",
    "master_server_address": "${MASTER_IP}:${MASTER_PORT}",
    "global_segment_size": "${GLOBAL_SEGMENT_SIZE}",
    "preferred_segment": false,
    "prefer_alloc_in_same_node": true
}
EOF

echo "[gen_mooncake_json] wrote ${OUTPUT_PATH}"
echo "[gen_mooncake_json] master_server_address=${MASTER_IP}:${MASTER_PORT}"
