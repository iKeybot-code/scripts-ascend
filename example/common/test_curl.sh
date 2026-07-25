#!/bin/bash
# Quick connectivity test against the PD proxy.
#
# Usage:
#   CONFIGS_FILE=.../configs.sh bash test_curl.sh 1|2
#
# Requires: CONFIGS_FILE

set -euo pipefail

COMMON_DIR_BOOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${COMMON_DIR_BOOT}/load_configs.sh"

HOST="${PROXY_HOST}"
PORT="${PROXY_PORT}"

if [[ $# -lt 1 ]]; then
    echo "Usage:"
    echo "  $0 1 : test /v1/chat/completions"
    echo "  $0 2 : test /v1/completions"
    exit 1
fi

case "$1" in
    1)
        echo "curl: /v1/chat/completions -> http://${HOST}:${PORT}"
        curl -sS "http://${HOST}:${PORT}/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d '{
                "model": "'"${MODEL_NAME}"'",
                "messages": [
                    {"role": "user", "content": "Who are you?"}
                ],
                "max_tokens": 100,
                "temperature": 1.0,
                "top_p": 0.95
            }'
        echo
        ;;
    2)
        echo "curl: /v1/completions -> http://${HOST}:${PORT}"
        curl -sS "http://${HOST}:${PORT}/v1/completions" \
            -H "Content-Type: application/json" \
            -d '{
                "model": "'"${MODEL_NAME}"'",
                "prompt": "Who are you?",
                "max_completion_tokens": 100,
                "temperature": 0
            }'
        echo
        ;;
    *)
        echo "Invalid arg '$1'. Use 1 or 2."
        exit 1
        ;;
esac
