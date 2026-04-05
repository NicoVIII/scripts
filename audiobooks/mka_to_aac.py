#!/usr/bin/env python3
"""Convert a .mka file to .m4a (AAC HE v2) using ffmpeg in Docker."""

from __future__ import annotations

import argparse
import os
import re
import select
import shutil
import subprocess
import sys
import time
from pathlib import Path


TIME_PATTERN = re.compile(r"time=([0-9:.]+)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert a .mka file to .m4a using Dockerized ffmpeg."
    )
    parser.add_argument("input_file", help="Input .mka file (absolute or relative path)")
    parser.add_argument("bitrate", help="Target bitrate, e.g. 48k or 64k")
    return parser.parse_args()

def validate_bitrate(bitrate: str) -> bool:
    return bool(re.fullmatch(r"[0-9]+[kK]", bitrate))

def normalize_input_path(input_arg: str) -> Path:
    path = Path(input_arg)
    if not path.is_absolute():
        path = Path.cwd() / path
    return path.resolve()


def run_conversion_with_progress(docker_cmd: list[str]) -> tuple[int, str]:
    """Run dockerized ffmpeg and print lightweight progress updates."""
    process = subprocess.Popen(
        docker_cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    if process.stderr is None:
        return process.wait(), ""

    start = time.monotonic()
    last_heartbeat = start
    latest_media_time = "unknown"
    stderr_lines: list[str] = []

    print("[progress] Conversion started...", flush=True)

    while True:
        ready, _, _ = select.select([process.stderr], [], [], 1.0)
        if ready:
            line = process.stderr.readline()
            if line:
                stderr_lines.append(line)
                match = TIME_PATTERN.search(line)
                if match:
                    latest_media_time = match.group(1)
            elif process.poll() is not None:
                break

        now = time.monotonic()
        if process.poll() is None and now - last_heartbeat >= 10:
            elapsed = int(now - start)
            print(
                f"[progress] still converting... {elapsed}s elapsed "
                f"(media {latest_media_time})",
                flush=True,
            )
            last_heartbeat = now

        if process.poll() is not None and not ready:
            break

    remainder = process.stderr.read()
    if remainder:
        stderr_lines.append(remainder)

    return process.wait(), "".join(stderr_lines)

def main() -> int:
    args = parse_args()

    if shutil.which("docker") is None:
        print("Error: docker is required but was not found in PATH.", file=sys.stderr)
        return 1

    if not validate_bitrate(args.bitrate):
        print(
            f"Error: bitrate must look like 48k or 64k (got '{args.bitrate}').",
            file=sys.stderr,
        )
        return 1

    input_path = normalize_input_path(args.input_file)

    if not input_path.is_file():
        print(f"Error: input file not found: {input_path}", file=sys.stderr)
        return 1

    if input_path.suffix.lower() != ".mka":
        print(
            f"Error: input file must end with .mka (got '{input_path.name}').",
            file=sys.stderr,
        )
        return 1

    work_dir = input_path.parent
    input_file = input_path.name
    output_file = f"{input_path.stem}.m4a"

    docker_cmd: list[str] = [
        "docker",
        "run",
        "--rm",
        "--user",
        f"{os.getuid()}:{os.getgid()}",
        "-v",
        f"{work_dir}:/workspace",
        "-w",
        "/workspace",
        "jrottenberg/ffmpeg:ubuntu",
        "-y",
        "-i",
        input_file,
        "-c:a",
        "libfdk_aac",
        "-profile:a",
        "aac_he_v2",
        "-b:a",
        args.bitrate,
        output_file,
    ]

    return_code, ffmpeg_stderr = run_conversion_with_progress(docker_cmd)
    if return_code != 0:
        print(f"Error: conversion failed with exit code {return_code}.", file=sys.stderr)
        if ffmpeg_stderr.strip():
            print(ffmpeg_stderr, file=sys.stderr)
        return return_code

    output_path = work_dir / output_file
    if not output_path.is_file() or output_path.stat().st_size == 0:
        print(
            "Error: conversion completed but output file is missing or empty: "
            f"{output_path}",
            file=sys.stderr,
        )
        return 1

    print("Done.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
