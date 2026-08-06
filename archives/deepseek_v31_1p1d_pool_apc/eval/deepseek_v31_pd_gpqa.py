from ais_bench.benchmark.models import VLLMCustomAPIChat
from ais_bench.benchmark.utils.postprocess.model_postprocessors import extract_non_reasoning_content

models = [
    dict(
        attr="service",
        type=VLLMCustomAPIChat,
        abbr="deepseek-v31-pd",
        path="/mnt/weight/DeepSeek-V3.1-w4a8-mtp-QuaRot",
        model="deepseek_v3",
        stream=False,
        request_rate=0,
        use_timestamp=False,
        retry=2,
        api_key="",
        host_ip="192.168.13.165",
        host_port=9000,
        url="",
        max_out_len=8192,
        batch_size=8,
        trust_remote_code=True,
        generation_kwargs=dict(temperature=0.0, ignore_eos=False),
        pred_postprocessor=dict(type=extract_non_reasoning_content),
    )
]
