#!/usr/bin/env python3
"""Launch external online DP ranks for Prefill or Decode.

Aligned with vllm-ascend examples/external_online_dp/launch_online_dp.py,
with PD role + kv_port support for MultiConnector (PD + KV pool).
"""

from __future__ import annotations

import argparse
import multiprocessing
import os
import subprocess
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Launch multi-rank vLLM DP engines.")
    parser.add_argument("--role", choices=["prefill", "decode"], required=True)
    parser.add_argument("--dp-size", type=int, required=True, help="Global data parallel size.")
    parser.add_argument("--tp-size", type=int, default=1, help="Tensor parallel size.")
    parser.add_argument("--pp-size", type=int, default=1, help="Pipeline parallel size.")
    parser.add_argument("--dp-size-local", type=int, default=-1, help="Local DP size on this node.")
    parser.add_argument("--dp-rank-start", type=int, default=0, help="Starting global DP rank.")
    parser.add_argument("--dp-address", type=str, required=True, help="DP master address.")
    parser.add_argument("--dp-rpc-port", type=str, default="12345", help="DP RPC port.")
    parser.add_argument("--vllm-start-port", type=int, default=9000, help="First engine HTTP port.")
    parser.add_argument("--kv-port-base", type=int, required=True, help="Base kv_port for MooncakeConnectorV1.")
    parser.add_argument(
        "--visible-devices-list",
        type=str,
        default="",
        help="Semicolon-separated ASCEND_RT_VISIBLE_DEVICES per local DP rank, e.g. '0,1;2,3'.",
    )
    parser.add_argument(
        "--template",
        type=str,
        default="",
        help="Path to run_dp_template.sh (default: ./run_dp_template.sh).",
    )
    return parser.parse_args()


def run_command(
    template: str,
    visible_devices: str,
    engine_port: int,
    dp_size: int,
    dp_rank: int,
    dp_address: str,
    dp_rpc_port: str,
    tp_size: int,
    role: str,
    kv_port: int,
    pp_size: int = 1,
) -> None:
    command = [
        "bash",
        template,
        visible_devices,
        str(engine_port),
        str(dp_size),
        str(dp_rank),
        dp_address,
        str(dp_rpc_port),
        str(tp_size),
        role,
        str(kv_port),
        str(pp_size),
    ]
    print("[launch_online_dp] exec:", " ".join(command), flush=True)
    subprocess.run(command, check=True)


def main() -> int:
    args = parse_args()
    script_dir = Path(__file__).resolve().parent
    template = args.template or str(script_dir / "run_dp_template.sh")
    if not os.path.exists(template):
        print(f"Template file {template} does not exist.", file=sys.stderr)
        return 1

    dp_size_local = args.dp_size_local if args.dp_size_local != -1 else args.dp_size
    devices_list = [x for x in args.visible_devices_list.split(";") if x.strip()]
    if devices_list and len(devices_list) != dp_size_local:
        print(
            f"visible-devices-list length ({len(devices_list)}) "
            f"must equal dp-size-local ({dp_size_local})",
            file=sys.stderr,
        )
        return 1

    processes = []
    for i in range(dp_size_local):
        dp_rank = args.dp_rank_start + i
        engine_port = args.vllm_start_port + i
        kv_port = args.kv_port_base + i
        if devices_list:
            visible_devices = devices_list[i]
        else:
            visible_devices = ",".join(
                str(x) for x in range(i * args.tp_size, (i + 1) * args.tp_size)
            )

        process = multiprocessing.Process(
            target=run_command,
            args=(
                template,
                visible_devices,
                engine_port,
                args.dp_size,
                dp_rank,
                args.dp_address,
                args.dp_rpc_port,
                args.tp_size,
                args.role,
                kv_port,
                args.pp_size,
            ),
        )
        processes.append(process)
        process.start()

    exit_code = 0
    for process in processes:
        process.join()
        if process.exitcode not in (0, None):
            exit_code = process.exitcode or 1
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
