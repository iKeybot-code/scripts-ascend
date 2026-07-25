from mmengine import read_base

with read_base():
    from .gsm8k_gen_0_shot_cot_str import gsm8k_datasets

# Evaluate only the first 10 GSM8K samples for a quick accuracy smoke.
gsm8k_datasets[0]["reader_cfg"]["test_range"] = "[0:10]"
