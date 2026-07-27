#!/usr/bin/env python3
"""
AIME2025 Accuracy Benchmark via PD Proxy
Supports command-line arguments and configuration file for reproducibility.

Usage:
    python3 aime2025_benchmark.py
    python3 aime2025_benchmark.py --proxy http://HOST:8080 --model MODEL_NAME
    python3 aime2025_benchmark.py --dataset /path/to/aime2025.jsonl --max-tokens 4096
    python3 aime2025_benchmark.py --timeout 600 --stream  # use streaming to avoid timeout
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error

# ── Defaults (overridable via CLI or env) ──────────────────────────
PROXY = os.environ.get("AIME_PROXY", "http://90.90.97.37:8080")
MODEL = os.environ.get("AIME_MODEL", "MiniMax-M2.7-w8a8-QuaRot")
DATASET = os.environ.get(
    "AIME_DATASET", "/mnt/a800_share/xuchi/datasets/aime2025/aime2025.jsonl"
)
MAX_TOKENS = int(os.environ.get("AIME_MAX_TOKENS", "4096"))
TEMPERATURE = float(os.environ.get("AIME_TEMPERATURE", "0"))
TIMEOUT = int(os.environ.get("AIME_TIMEOUT", "600"))
LOG_DIR = os.environ.get("AIME_LOG_DIR", "/mnt/a800_share/l00848175/logs")
OUTPUT = os.environ.get("AIME_OUTPUT", os.path.join(LOG_DIR, "aime2025_results.json"))
USE_STREAM = os.environ.get("AIME_USE_STREAM", "1") == "1"

# ── CLI ─────────────────────────────────────────────────────────────
parser = argparse.ArgumentParser(
    description="AIME2025 Accuracy Benchmark (PD + MRV2)"
)
parser.add_argument("--proxy", default=PROXY, help=f"PD proxy URL (default: {PROXY})")
parser.add_argument("--model", default=MODEL, help=f"Model name (default: {MODEL})")
parser.add_argument("--dataset", default=DATASET, help=f"Dataset path (default: {DATASET})")
parser.add_argument("--max-tokens", type=int, default=MAX_TOKENS,
                    help=f"Max generation tokens (default: {MAX_TOKENS})")
parser.add_argument("--temperature", type=float, default=TEMPERATURE,
                    help=f"Temperature (default: {TEMPERATURE})")
parser.add_argument("--timeout", type=int, default=TIMEOUT,
                    help=f"Request timeout seconds (default: {TIMEOUT})")
parser.add_argument("--output", default=OUTPUT, help=f"Results JSON path (default: {OUTPUT})")
parser.add_argument("--no-stream", dest="stream", action="store_false",
                    help="Disable streaming (not recommended for long generations)")
parser.add_argument("--start", type=int, default=0, help="Start index (0-based)")
parser.add_argument("--count", type=int, default=0, help="Number of problems (0=all)")
args = parser.parse_args()

PROXY = args.proxy
MODEL = args.model
DATASET = args.dataset
MAX_TOKENS = args.max_tokens
TEMPERATURE = args.temperature
TIMEOUT = args.timeout
OUTPUT = args.output
USE_STREAM = args.stream

# ── Prompt template (from simple_eval_aime25.py) ───────────────────
PROMPT_TEMPLATE = """Solve the following AIME (American Invitational Mathematics Examination) problem step by step. The last line of your response should be of the form Answer: $ANSWER (without quotes) where $ANSWER is the answer to the problem.

Note: AIME answers are always integers from 000 to 999 (inclusive). If you get a non-integer answer, you likely made a computational error.

{question}

Remember to put your answer on its own line after "Answer:", and express your answer as an integer from 000 to 999."""

# ── Load dataset ────────────────────────────────────────────────────
os.makedirs(os.path.dirname(OUTPUT) or ".", exist_ok=True)

with open(DATASET) as f:
    all_problems = [json.loads(line) for line in f]

start_idx = args.start
end_idx = start_idx + args.count if args.count > 0 else len(all_problems)
problems = all_problems[start_idx:end_idx]
total = len(problems)

print("=" * 60)
print("AIME2025 Accuracy Benchmark")
print(f"  Model:      {MODEL}")
print(f"  Deployment: PD (Prefill-Decode) + MRV2, DP=4 TP=4")
print(f"  Proxy:      {PROXY}")
print(f"  Dataset:    {DATASET} ({len(all_problems)} total)")
print(f"  Range:      [{start_idx}:{end_idx}] ({total} problems)")
print(f"  Max tokens: {MAX_TOKENS}")
print(f"  Timeout:    {TIMEOUT}s")
print(f"  Streaming:  {USE_STREAM}")
print(f"  Output:     {OUTPUT}")
print("=" * 60)
sys.stdout.flush()

# ── Helper: extract AIME answer ────────────────────────────────────
def extract_answer(text: str):
    """Extract AIME answer from model output."""
    # Priority 1: explicit "Answer: <number>" line
    m = re.search(r"Answer:\s*(-?\d+(?:\.?\d*)?)\s*$", text, re.MULTILINE | re.IGNORECASE)
    if m:
        return m.group(1)

    # Priority 2: boxed answer
    m = re.search(r"\\boxed\{(\d+)\}", text)
    if m:
        return m.group(1)

    # Priority 3: last number in text
    numbers = re.findall(r"-?\d+\.?\d*", text)
    if numbers:
        # Remove trailing dots (e.g. "34." -> "34")
        return numbers[-1].rstrip(".")
    return None


def normalize_answer(raw):
    """Convert raw answer string to integer (AIME answers 000-999)."""
    try:
        return int(float(raw))
    except (ValueError, TypeError):
        return None


def is_correct(pred_raw, expected_raw):
    """Compare predicted and expected answers numerically."""
    pred_val = normalize_answer(pred_raw)
    exp_val = normalize_answer(expected_raw)
    if pred_val is None or exp_val is None:
        return False
    return pred_val == exp_val


# ── Streaming request ──────────────────────────────────────────────
def request_stream(prompt):
    """Stream tokens from PD proxy, collect full response text."""
    data = json.dumps({
        "model": MODEL,
        "prompt": prompt,
        "max_tokens": MAX_TOKENS,
        "temperature": TEMPERATURE,
        "stream": True
    }).encode("utf-8")

    req = urllib.request.Request(
        f"{PROXY}/v1/completions",
        data=data,
        headers={"Content-Type": "application/json"}
    )

    full_text = ""
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        # Read SSE chunks
        buffer = b""
        while True:
            try:
                chunk = resp.read(4096)
                if not chunk:
                    break
                buffer += chunk
                # Parse SSE lines
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    line = line.decode("utf-8", errors="replace").strip()
                    if line.startswith("data: "):
                        raw = line[6:]
                        if raw == "[DONE]":
                            break
                        try:
                            evt = json.loads(raw)
                            if evt.get("choices"):
                                token_text = evt["choices"][0].get("text", "")
                                full_text += token_text
                        except json.JSONDecodeError:
                            pass
            except Exception:
                break
    return full_text


# ── Non-streaming request ──────────────────────────────────────────
def request_sync(prompt):
    """Single-shot request to PD proxy."""
    data = json.dumps({
        "model": MODEL,
        "prompt": prompt,
        "max_tokens": MAX_TOKENS,
        "temperature": TEMPERATURE
    }).encode("utf-8")

    req = urllib.request.Request(
        f"{PROXY}/v1/completions",
        data=data,
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        result = json.loads(resp.read().decode("utf-8"))
    return result["choices"][0]["text"]


# ── Benchmark loop ─────────────────────────────────────────────────
results = []
correct = 0
start_total = time.time()

for i, p in enumerate(problems, start=start_idx + 1):
    question = p["question"]
    expected = str(p["answer"]).strip()
    prompt = PROMPT_TEMPLATE.format(question=question)
    display_idx = i - start_idx

    print(f"\n[{i}/{start_idx + total}] Q: {question[:100]}...")
    print(f"    Expected: {expected}")
    sys.stdout.flush()

    start = time.time()
    try:
        if USE_STREAM:
            text = request_stream(prompt)
        else:
            text = request_sync(prompt)

        elapsed = time.time() - start
        pred_raw = extract_answer(text)
        pred = str(normalize_answer(pred_raw)) if normalize_answer(pred_raw) is not None else (pred_raw or "NULL")
        ok = is_correct(pred_raw, expected)

        if ok:
            correct += 1

        print(f"    Pred: {pred} | {'CORRECT' if ok else 'WRONG'} ({elapsed:.0f}s)")
        print(f"    Response: {text[:200]}...")
        sys.stdout.flush()

        results.append({
            "idx": i,
            "question": question[:300],
            "expected": expected,
            "pred": pred,
            "correct": ok,
            "time": round(elapsed, 1),
            "response": text
        })

    except Exception as e:
        elapsed = time.time() - start
        print(f"    ERROR: {e} ({elapsed:.0f}s)")
        sys.stdout.flush()
        results.append({
            "idx": i,
            "question": question[:300],
            "expected": expected,
            "pred": "ERROR",
            "correct": False,
            "time": round(elapsed, 1),
            "error": str(e)
        })

# ── Final summary ──────────────────────────────────────────────────
elapsed_total = time.time() - start_total
accuracy = correct / total if total > 0 else 0.0

summary = f"""
{'=' * 60}
AIME2025 Results: {correct}/{total} = {accuracy * 100:.1f}%
Total time: {elapsed_total / 60:.1f} min ({elapsed_total:.0f}s)
Results saved: {OUTPUT}
{'=' * 60}
"""
print(summary)

report = {
    "model": MODEL,
    "deployment": "PD_MRV2_DP4TP4",
    "dataset": "AIME2025",
    "config": {
        "proxy": PROXY,
        "max_tokens": MAX_TOKENS,
        "temperature": TEMPERATURE,
        "timeout": TIMEOUT,
        "streaming": USE_STREAM,
        "range": f"[{start_idx}:{end_idx}]"
    },
    "correct": correct,
    "total": total,
    "accuracy": round(accuracy, 4),
    "total_time": round(elapsed_total, 1),
    "results": results
}

with open(OUTPUT, "w") as f:
    json.dump(report, f, indent=2, ensure_ascii=False)
