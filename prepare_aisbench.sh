cd /workspace
if [ -d aisbench/.git ]; then
  cd aisbench && git fetch --all && git pull --ff-only
else
  git clone https://github.com/AISBench/benchmark.git aisbench
  cd aisbench
fi

pip install -e .

# AIME2025 数据路径（评测脚本硬性检查）
mkdir -p ais_bench/datasets/aime2025
# 将数据放到：
#   /workspace/aisbench/ais_bench/datasets/aime2025/aime2025.jsonl
wc -l /workspace/aisbench/ais_bench/datasets/aime2025/aime2025.jsonl
# 历史环境为 30 条

python3 -c "import ais_bench; print(ais_bench.__file__)"
