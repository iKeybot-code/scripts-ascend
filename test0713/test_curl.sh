#!/bin/bash

HOST="90.90.97.27"
PORT="8080"
MODEL_NAME="qwen3-8"

# 检查是否输入了参数
if [ -z "$1" ]; then
    echo "使用错误！请传入数字参数："
    echo "  $0 1 : 测试 chat/completions 接口"
    echo "  $0 2 : 测试 completions 接口"
    exit 1
fi

# 根据传入的参数决定执行哪一条 curl
case "$1" in
    1)
        echo "curl: /v1/chat/completions ..."
        curl http://${HOST}:${PORT}/v1/chat/completions \
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
        ;;
    2)
        echo "curl: /v1/completions ..."
        curl http://${HOST}:${PORT}/v1/completions \
            -H "Content-Type: application/json" \
            -d '{
                "model": "'"${MODEL_NAME}"'",
                "prompt": "Who are you?",
                "max_completion_tokens": 100,
                "temperature": 0
            }'
        ;;
    *)
        echo "错误: 无效参数 '$1'。只能输入 1 或 2。"
        exit 1
        ;;
esac