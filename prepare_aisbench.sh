WORK_SPACE="/mnt/a800_share/l00848175/workspace"
BENCH_MARK="benchmark"
if [ -d "${BENCH_MARK}"/.git ]; then
  cd "${BENCH_MARK}" && git fetch --all && git pull --ff-only
else
  git clone https://github.com/AISBench/benchmark.git "${BENCH_MARK}"
  cd "${BENCH_MARK}"
fi

# 从源码安装 AISBench
pip3 install -e ./ --use-pep517
# 安装额外的 AISBench 依赖
pip3 install -r requirements/api.txt
pip3 install -r requirements/extra.txt

# AIME2025 数据路径（评测脚本硬性检查）
mkdir -p "${BENCH_MARK}"/datasets/aime2025
# 将数据放到：
#   /"${WORK_SPACE}"/"${BENCH_MARK}"/ais_bench/datasets/aime2025/aime2025.jsonl
wc -l /"${WORK_SPACE}"/"${BENCH_MARK}"/ais_bench/datasets/aime2025/aime2025.jsonl
# 历史环境为 30 条

python3 -c "import ais_bench; print(ais_bench.__file__)"
