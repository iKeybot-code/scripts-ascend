curl http://90.90.97.28:8080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{
        "model": "qwen36",
        "messages": [
            {"role": "user", "content": "Who are you?"}
        ],
        "max_tokens": 100,
        "temperature": 1.0,
        "top_p": 0.95
    }'



curl http://90.90.97.28:8080/v1/completions \
    -H "Content-Type: application/json" \
    -d '{
        "model": "qwen36",
        "prompt": "Who are you?",
        "max_completion_tokens": 100,
        "temperature": 0
    }'