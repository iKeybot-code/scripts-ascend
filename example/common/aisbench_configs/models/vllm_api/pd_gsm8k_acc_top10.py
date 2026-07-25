from mmengine import read_base

with read_base():
    from .vllm_api_general_chat import models

# Defaults; host/port/model/path are appended by test_curl.sh at runtime.
models[0]["model"] = "qwen3"
models[0]["max_out_len"] = 512
models[0]["batch_size"] = 1
models[0]["generation_kwargs"] = dict(
    temperature=0.0,
    ignore_eos=False,
)
