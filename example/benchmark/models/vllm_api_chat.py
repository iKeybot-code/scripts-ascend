from ais_bench.benchmark.models import VLLMCustomAPIChat
from ais_bench.benchmark.utils.model_postprocessors import extract_non_reasoning_content

models = [
    dict(
        attr="service",
        type=VLLMCustomAPIChat,
        abbr="vllm-api-bench",
        path="PLACEHOLDER_PATH",
        model="PLACEHOLDER_MODEL",
        request_rate=0,
        retry=2,
        host_ip="127.0.0.1",
        host_port=8000,
        max_out_len=32768,
        batch_size=1,
        trust_remote_code=False,
        generation_kwargs=dict(
            temperature=0.0,
            top_k=10,
            top_p=0.95,
            seed=None,
            repetition_penalty=1.03,
        ),
        pred_postprocessor=dict(type=extract_non_reasoning_content),
    )
]

# host_ip/host_port/model/path/max_out_len/batch_size/temperature
# 由 run_bench.sh 运行时覆盖
