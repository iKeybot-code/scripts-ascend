from mmengine import read_base

with read_base():
    from .aime2025_gen_0_shot_chat_prompt import aime2025_datasets

# Placeholder; test_range is set at runtime by test_aime2025.sh.

aime2025_datasets[0]["reader_cfg"]["test_range"] = "[0:30]"
