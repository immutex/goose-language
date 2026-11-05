#!/usr/bin/env python3
"""Check every example in this skill with the Goose compiler.

Usage:
    python scripts/verify.py [--goose PATH] [--run]

With no --goose, the script searches PATH, then common build locations.
--run also executes the examples that do not need a native build.
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXAMPLES = ROOT / "examples"

# Examples that call thread_spawn must be built, not run through the JIT.
NEEDS_BUILD = {"07_threads.goose"}

# Arguments for examples that read input.
ARGS = {"06_wordcount.goose": [str(EXAMPLES / "data" / "words.txt")]}


def find_goose(explicit: str | None) -> str | None:
    if explicit:
        return explicit
    found = shutil.which("goose")
    if found:
        return found
    candidates = [
        ROOT.parent / "goose" / "build" / "Release" / "goose.exe",
        ROOT.parent / "goose" / "build" / "goose",
        Path.home() / ".goose" / "goose.exe",
        Path.home() / ".goose" / "goose",
    ]
    for c in candidates:
        if c.exists():
            return str(c)
    return None


def run(cmd: list[str]) -> tuple[int, str]:
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--goose")
    ap.add_argument("--run", action="store_true")
    args = ap.parse_args()

    goose = find_goose(args.goose)
    if not goose:
        print("error: goose not found. Pass --goose PATH.", file=sys.stderr)
        return 2

    files = sorted(EXAMPLES.glob("*.goose"))
    if not files:
        print("error: no examples found", file=sys.stderr)
        return 2

    failures = 0
    for f in files:
        code, out = run([goose, "check", str(f)])
        status = "ok" if code == 0 else "FAIL"
        print(f"[{status}] check {f.name}")
        if code != 0:
            failures += 1
            print(out)
            continue
        if args.run and f.name not in NEEDS_BUILD:
            cmd = [goose, "run", str(f)]
            extra = ARGS.get(f.name)
            if extra:
                cmd += ["--"] + extra
            code, out = run(cmd)
            status = "ok" if code == 0 else "FAIL"
            print(f"[{status}] run   {f.name}")
            if code != 0:
                failures += 1
                print(out)

    print(f"\n{len(files) - failures}/{len(files)} passed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
