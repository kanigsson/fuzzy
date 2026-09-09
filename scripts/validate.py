#!/usr/bin/env python3
"""Record reproducible proof, test, and sequential synthetic benchmark evidence."""
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "validation"
OUT.mkdir(exist_ok=True)
manifest = {"timestamp_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "platform": platform.platform(), "tools": {}, "commands": [], "sha256": {}}
for name, variable in [("gprbuild", "GPRBUILD"), ("gnatprove", "GNATPROVE"), ("gnat", "GNAT")]:
    path = shutil.which(os.environ.get(variable, name))
    if path is None:
        raise SystemExit(f"missing tool: {name}")
    manifest["tools"][name] = {"path": str(Path(path).resolve()), "version": subprocess.check_output(
        [path, "--version"], text=True, stderr=subprocess.STDOUT)}
for directory in ["src", "cli", "tests", "benchmarks", "scripts"]:
    for path in sorted((ROOT / directory).rglob("*")):
        if path.is_file() and "__pycache__" not in path.parts:
            manifest["sha256"][str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
for name in ["fuzzy.gpr", "tools.gpr", "Makefile", "fuzzy_matcher_design.md"]:
    manifest["sha256"][name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()

def run(args, log):
    print(" ".join(args), flush=True)
    start = time.monotonic()
    result = subprocess.run(args, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (OUT / log).write_text(result.stdout)
    manifest["commands"].append({"argv": args, "log": log, "exit_code": result.returncode,
                                 "elapsed_seconds": time.monotonic() - start})
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if result.returncode:
        raise SystemExit(f"command failed; see {OUT / log}")
    return result.stdout

run(["make", "flow"], "flow.log")
proof = run(["make", "prove"], "prove.log")
if "Success: all checks proved" not in proof:
    raise SystemExit("proof did not report complete closure")
shutil.copyfile(ROOT / "obj/release/library/gnatprove/gnatprove.out", OUT / "proof-summary.txt")
run(["make", "test-contracts"], "test-contracts.log")
run(["make", "test"], "test.log")
benchmarks = []
for size in [10_000, 100_000]:
    for query in ["fma", "999", "zzz", ""]:
        for repeat in range(3):
            output = run(["bin/bench_fuzzy", str(size), query, "30"],
                         f"bench-{size}-{query or 'empty'}-{repeat}.log")
            match = re.search(r"seconds=\s*([\d.]+) checksum=\s*(-?\d+)", output)
            if match is None:
                raise SystemExit("unrecognized benchmark output")
            benchmarks.append({"candidates": size, "query": query, "k": 30, "searches": 20,
                               "seconds": float(match[1]), "checksum": int(match[2])})
for size in [10_000, 100_000]:
    for query in ["fma", "999", "zzz", ""]:
        if len({b["checksum"] for b in benchmarks if b["candidates"] == size and b["query"] == query}) != 1:
            raise SystemExit("inconsistent benchmark checksums")
(OUT / "benchmarks.json").write_text(json.dumps(benchmarks, indent=2) + "\n")
print(f"Validation complete: {OUT}")
