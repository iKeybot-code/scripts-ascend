#!/usr/bin/env python3
"""GSM8K Top-10 Smoke Test via PD Proxy"""
import json
import re
import time
import urllib.request
import urllib.error

PROXY = "http://90.90.97.37:8080"
MODEL = "MiniMax-M2.7-w8a8-QuaRot"
DATASET = "/usr/local/python3.11.10/lib/python3.11/site-packages/ais_bench/datasets/gsm8k/test.jsonl"

with open(DATASET) as f:
    questions = [json.loads(line) for line in f.readlines()[:10]]

print("=" * 60)
print("GSM8K Top-10 PD Smoke Test")
print(f"Model: {MODEL} (MRV2)")
print(f"Proxy: {PROXY}")
print("=" * 60)

correct = 0
start = time.time()

for i, q in enumerate(questions):
    question = q["question"]
    expected = q["answer"].split("#### ")[-1].strip()
    prompt = f"Question: {question}\nAnswer: Let me think step by step.\n"

    print(f"\n--- Question {i+1} ---")
    print(f"Q: {question[:100]}...")
    print(f"Expected answer: {expected}")

    data = json.dumps({
        "model": MODEL,
        "prompt": prompt,
        "max_tokens": 256,
        "temperature": 0,
        "stop": ["Question:", "\n\n"]
    }).encode("utf-8")

    try:
        req = urllib.request.Request(
            f"{PROXY}/v1/completions",
            data=data,
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=120) as resp:
            result = json.loads(resp.read().decode("utf-8"))

        text = result["choices"][0]["text"]
        # Extract last number from response
        numbers = re.findall(r"-?\d+\.?\d*", text)
        pred = numbers[-1] if numbers else "NULL"

        print(f"Response: {text[:120]}...")
        print(f"Pred: {pred} | Expected: {expected} | ", end="")
        if pred == expected:
            correct += 1
            print("CORRECT")
        else:
            print("WRONG")
    except Exception as e:
        print(f"ERROR: {e}")

elapsed = time.time() - start
print(f"\n{'=' * 60}")
print(f"Accuracy: {correct}/10 = {correct * 10}%")
print(f"Time: {elapsed:.1f}s")
print(f"{'=' * 60}")
