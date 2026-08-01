#!/usr/bin/env python3
"""
AIME2026 精度评测脚本 (轻量版，不依赖 AISBench)
通过 proxy API (OpenAI 兼容) 调用 minimaxm27 进行评测。

用法:
  python3 eval_aime2026.py [选项]

选项:
  --host HOST         Proxy 地址 (默认: 90.90.97.15)
  --port PORT         Proxy 端口 (默认: 8080)
  --model MODEL       模型名 (默认: minimaxm27)
  --num N             评测条数 (默认: 全部 30 题)
  --max-tokens N      最大输出 token 数 (默认: 32768)
  --temperature T     温度 (默认: 0.0)
  --dataset PATH      数据集路径 (默认: 同目录下 aime2026.jsonl)
  --output-dir DIR    结果输出目录 (默认: ./outputs)
  --timeout SEC       单题超时秒数 (默认: 600)
"""

import argparse
import json
import os
import re
import sys
import time
import traceback
from datetime import datetime

try:
    import requests
except ImportError:
    print("[ERROR] 请安装 requests: pip install requests")
    sys.exit(1)


def load_dataset(path):
    """加载 AIME2026 JSONL 数据集"""
    problems = []
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line:
                problems.append(json.loads(line))
    return problems


def build_prompt(problem):
    """构建 AIME 评测 prompt (0-shot CoT)"""
    return (
        "Solve the following math problem step by step. "
        "Put your answer inside \\boxed{}.\n\n"
        f"{problem}\n\n"
        "Remember to put your answer inside \\boxed{}."
    )


def extract_answer(text):
    """
    从模型输出中提取 \\boxed{...} 内的答案。
    支持多层嵌套和多种格式。
    """
    if not text:
        return None

    # 尝试提取最后一个 \boxed{...}
    pattern = r'\\boxed\{((?:[^{}]|\{[^{}]*\})*)\}'
    matches = re.findall(pattern, text)
    if matches:
        # 返回最后一个匹配
        return matches[-1].strip()

    # 备用: 尝试匹配 \boxed 后面跟数字
    match = re.search(r'\\boxed\{?(\d+)\}?', text)
    if match:
        return match.group(1).strip()

    return None


def normalize_answer(ans):
    """标准化答案为整数或者数值字符串"""
    if ans is None:
        return None
    ans = ans.strip().rstrip('.')
    try:
        # 尝试转为整数
        return str(int(float(ans)))
    except (ValueError, OverflowError):
        # 无法转换则返回原值
        return ans


def evaluate_one(problem, api_url, model, max_tokens, temperature, timeout):
    """评测单题"""
    problem_id = problem.get('id', '?')
    question = problem['problem']
    ground_truth = str(problem['answer']).strip()

    prompt = build_prompt(question)

    payload = {
        "model": model,
        "messages": [
            {"role": "user", "content": prompt}
        ],
        "max_tokens": max_tokens,
        "temperature": temperature,
        "top_p": 0.95,
        "seed": 1024,
    }

    result = {
        "id": problem_id,
        "problem": question[:200] + "..." if len(question) > 200 else question,
        "ground_truth": ground_truth,
        "correct": False,
        "extracted_answer": None,
        "full_response": "",
        "elapsed": 0,
        "error": None,
    }

    try:
        start = time.time()
        resp = requests.post(
            f"{api_url}/v1/chat/completions",
            json=payload,
            timeout=timeout,
            headers={"Content-Type": "application/json"},
        )
        result["elapsed"] = round(time.time() - start, 1)

        if resp.status_code != 200:
            result["error"] = f"HTTP {resp.status_code}: {resp.text[:500]}"
            return result

        data = resp.json()
        choice = data.get("choices", [{}])[0]
        content = choice.get("message", {}).get("content", "")
        finish_reason = choice.get("finish_reason", "unknown")
        result["full_response"] = content

        # 提取答案
        extracted = extract_answer(content)
        result["extracted_answer"] = extracted

        # 比对答案
        pred = normalize_answer(extracted)
        gt = normalize_answer(ground_truth)
        result["correct"] = (pred == gt)
        result["finish_reason"] = finish_reason

    except requests.exceptions.Timeout:
        result["error"] = f"Timeout after {timeout}s"
    except requests.exceptions.ConnectionError as e:
        result["error"] = f"Connection error: {e}"
    except Exception as e:
        result["error"] = f"Error: {e}\n{traceback.format_exc()}"

    return result


def main():
    parser = argparse.ArgumentParser(description="AIME2026 精度评测")
    parser.add_argument("--host", default="90.90.97.15")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--model", default="minimaxm27")
    parser.add_argument("--num", type=int, default=0, help="评测条数 (0=全部)")
    parser.add_argument("--max-tokens", type=int, default=8192)
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--dataset", default=None)
    parser.add_argument("--output-dir", default=None)
    parser.add_argument("--timeout", type=int, default=7200)
    args = parser.parse_args()

    api_url = f"http://{args.host}:{args.port}"

    # 数据集路径
    script_dir = os.path.dirname(os.path.abspath(__file__))
    dataset_path = args.dataset or os.path.join(script_dir, "aime2026.jsonl")

    if not os.path.exists(dataset_path):
        print(f"[ERROR] 数据集不存在: {dataset_path}")
        sys.exit(1)

    # 输出目录
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = args.output_dir or os.path.join(script_dir, "outputs", f"aime2026_{timestamp}")
    os.makedirs(output_dir, exist_ok=True)

    # 加载数据集
    problems = load_dataset(dataset_path)
    total = len(problems)
    if args.num > 0:
        problems = problems[:args.num]
    num = len(problems)

    print("=" * 60)
    print("  AIME2026 精度评测")
    print("=" * 60)
    print(f"  API 地址 : {api_url}")
    print(f"  模型     : {args.model}")
    print(f"  数据集   : {dataset_path}")
    print(f"  总题数   : {total}")
    print(f"  评测数   : {num}")
    print(f"  max_tokens: {args.max_tokens}")
    print(f"  temperature: {args.temperature}")
    print(f"  输出目录 : {output_dir}")
    print("=" * 60)
    print()

    # 健康检查
    try:
        r = requests.get(f"{api_url}/health", timeout=10)
        print(f"[health] {r.status_code} - {r.text[:200]}")
    except Exception as e:
        print(f"[WARN] 健康检查失败: {e}")

    # 模型列表
    try:
        r = requests.get(f"{api_url}/v1/models", timeout=10)
        models = [m["id"] for m in r.json().get("data", [])]
        print(f"[models] {models}")
    except Exception as e:
        print(f"[WARN] 模型列表获取失败: {e}")

    print()

    results = []
    correct = 0
    errors = 0

    for i, prob in enumerate(problems):
        p_id = prob.get('id', i + 1)
        print(f"[{i+1}/{num}] Problem {p_id}...", end=" ", flush=True)

        r = evaluate_one(
            prob, api_url, args.model,
            args.max_tokens, args.temperature, args.timeout
        )
        results.append(r)

        if r["error"]:
            errors += 1
            print(f"ERROR: {r['error'][:100]}")
        elif r["correct"]:
            correct += 1
            print(f"CORRECT (answer={r['extracted_answer']}, {r['elapsed']}s)")
        else:
            gt = r["ground_truth"]
            pred = r.get("extracted_answer", "None")
            print(f"WRONG (gt={gt}, pred={pred}, {r['elapsed']}s)")

    # 计算准确率
    valid = [r for r in results if r["error"] is None]
    acc = correct / len(valid) if valid else 0.0
    overall_acc = correct / num if num > 0 else 0.0

    # 保存详细结果
    detail_path = os.path.join(output_dir, "results.json")
    with open(detail_path, 'w', encoding='utf-8') as f:
        json.dump({
            "config": {
                "api_url": api_url,
                "model": args.model,
                "max_tokens": args.max_tokens,
                "temperature": args.temperature,
                "timestamp": timestamp,
            },
            "summary": {
                "total": num,
                "correct": correct,
                "errors": errors,
                "valid": len(valid),
                "accuracy": round(acc * 100, 2),
                "overall_accuracy": round(overall_acc * 100, 2),
            },
            "details": results,
        }, f, ensure_ascii=False, indent=2)

    # 打印总结
    print()
    print("=" * 60)
    print("  评测结果")
    print("=" * 60)
    print(f"  总题数     : {num}")
    print(f"  正确       : {correct}")
    print(f"  错误       : {errors}")
    print(f"  有效题数   : {len(valid)}")
    print(f"  准确率     : {acc*100:.1f}% ({correct}/{len(valid)})")
    print(f"  总体准确率 : {overall_acc*100:.1f}% ({correct}/{num})")
    print(f"  结果文件   : {detail_path}")
    print("=" * 60)


if __name__ == "__main__":
    main()
