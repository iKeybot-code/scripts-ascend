from mmengine import read_base

with read_base():
    from .vllm_api_general_chat import models

# Defaults; host/port/model/path are appended by test_aime2025.sh at runtime.
models[0]["model"] = "minimax-m27-pd"
models[0]["max_out_len"] = 32768
models[0]["batch_size"] = 1
models[0]["generation_kwargs"] = dict(
    temperature=0.0,
    ignore_eos=False,
)
