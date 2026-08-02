#!/usr/bin/env python3
"""Monitor AISBench AIME2026 eval and report per-question accuracy."""
import glob
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

BASE = "/mnt/a800_share/l00848175/workspace/tests/minimax_m27_1p1d_mrv2"
RUN_TAG = os.environ.get("AIME_RUN_TAG", "aime2026_aisbench_v6")
FINAL_GLOB = f"{BASE}/outputs/{RUN_TAG}/*/predictions/vllm-api-bench/aime2026.jsonl"
TMP_GLOB = f"{BASE}/outputs/{RUN_TAG}/*/predictions/vllm-api-bench/tmp/*.jsonl"
DATASET = "/mnt/a800_share/l00848175/workspace/benchmark/ais_bench/datasets/aime2026/aime2026.jsonl"
PROGRESS_LOG = f"{BASE}/logs/{RUN_TAG}_progress.log"
EVAL_LOG = f"{BASE}/logs/{RUN_TAG}.log"
PROXY_HEALTH = "http://90.90.97.48:8080/healthcheck"
STALL_SEC = 1200  # 20 min without new completed question
POLL_SEC = 20


def log(msg):
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    os.makedirs(os.path.dirname(PROGRESS_LOG), exist_ok=True)
    with open(PROGRESS_LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def load_gold():
    gold = {}
    with open(DATASET, encoding="utf-8") as f:
        for i, line in enumerate(f):
            if not line.strip():
                continue
            obj = json.loads(line)
            gold[i] = str(obj["answer"]).strip()
    return gold


def extract_answer(text):
    if not text:
        return None
    pattern = r"\\boxed\{((?:[^{}]|\{[^{}]*\})*)\}"
    matches = re.findall(pattern, text)
    if matches:
        return matches[-1].strip()
    match = re.search(r"\\boxed\{?(\d+)\}?", text)
    if match:
        return match.group(1).strip()
    return None


def normalize_answer(ans):
    if ans is None:
        return None
    ans = ans.strip().rstrip(".")
    try:
        return str(int(float(ans)))
    except (ValueError, OverflowError):
        return ans


def find_pred_files():
    final = sorted(glob.glob(FINAL_GLOB))
    tmp = sorted(glob.glob(TMP_GLOB))
    return (final[-1] if final else None), (tmp[-1] if tmp else None)


def read_predictions(final_path, tmp_path):
    rows = []
    for path in (final_path, tmp_path):
        if not path or not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError:
                    # skip in-progress partial line
                    continue
    # dedupe by id, keep latest
    by_id = {}
    for row in rows:
        by_id[row.get("id", len(by_id))] = row
    return [by_id[k] for k in sorted(by_id)]


def proxy_ok():
    try:
        out = subprocess.check_output(
            ["curl", "-s", "--max-time", "5", PROXY_HEALTH],
            text=True,
        )
        data = json.loads(out)
        return data.get("status") == "ok"
    except Exception:
        return False


def eval_alive():
    try:
        out = subprocess.check_output(
            ["pgrep", "-f", f"ais_bench.*{RUN_TAG}"],
            text=True,
        )
        return bool(out.strip())
    except subprocess.CalledProcessError:
        return False


def tail_errors():
    if not os.path.exists(EVAL_LOG):
        return []
    with open(EVAL_LOG, encoding="utf-8", errors="replace") as f:
        lines = f.readlines()[-200:]
    return [ln for ln in lines if "MODEL-DATA-003" in ln or "ERROR" in ln or "Traceback" in ln]


def score_rows(rows, gold):
    correct = 0
    details = []
    for row in rows:
        idx = row.get("id", len(details))
        pred = normalize_answer(extract_answer(row.get("prediction", "")))
        ref = gold.get(idx)
        ok = pred is not None and ref is not None and pred == ref
        if ok:
            correct += 1
        details.append((idx, pred, ref, ok))
    return correct, details


def main():
    gold = load_gold()
    total = len(gold)
    final_file, tmp_file = find_pred_files()
    log(f"monitor start total={total} final={final_file or 'pending'} tmp={tmp_file or 'pending'}")
    seen = 0
    last_new_ts = time.time()

    while True:
        f, t = find_pred_files()
        final_file = f or final_file
        tmp_file = t or tmp_file
        rows = read_predictions(final_file, tmp_file)
        n = len(rows)
        if seen == 0 and n > 0:
            correct, details = score_rows(rows, gold)
            acc = 100.0 * correct / n if n else 0.0
            log(f"resume at Q{n}/{total} | running acc {correct}/{n} = {acc:.2f}%")
            seen = n
            last_new_ts = time.time()

        if n > seen:
            correct, details = score_rows(rows, gold)
            acc = 100.0 * correct / n if n else 0.0
            last = details[-1]
            log(
                f"Q{n}/{total} done | running acc {correct}/{n} = {acc:.2f}% | "
                f"last id={last[0]} pred={last[1]} gold={last[2]} ok={last[3]}"
            )
            seen = n
            last_new_ts = time.time()
            if n >= total:
                log("all questions inferred; waiting for final eval summary...")
                break

        if not eval_alive() and n < total:
            errs = tail_errors()
            log(f"CRITICAL eval process died at {n}/{total}; recent errors={len(errs)}")
            if errs:
                log("last error: " + errs[-1].strip()[:300])
            return 2

        if n < total and eval_alive() and (time.time() - last_new_ts) > STALL_SEC:
            log(f"CRITICAL stall >{STALL_SEC}s at {n}/{total}; proxy_ok={proxy_ok()}")
            return 3

        if n < total and not proxy_ok():
            log(f"WARNING proxy unhealthy while at {n}/{total}")

        time.sleep(POLL_SEC)

    # wait for summary csv
    anchor = final_file or tmp_file
    exp_dir = os.path.dirname(os.path.dirname(os.path.dirname(anchor)))
    for _ in range(90):
        csvs = sorted(glob.glob(f"{exp_dir}/summary/summary_*.csv"))
        if csvs:
            with open(csvs[-1], encoding="utf-8") as f:
                log("FINAL SUMMARY:\n" + f.read().strip())
            return 0
        if not eval_alive():
            break
        time.sleep(10)
    log("finished infer but summary not found yet")
    return 0


if __name__ == "__main__":
    sys.exit(main())
