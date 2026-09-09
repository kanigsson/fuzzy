# Validation

Validated on 2026-09-09 with the matching local GNAT Pro 27 toolchain and
GNATprove, using CVC5 and Z3. Reproduce the complete run with:

```sh
python3 scripts/validate.py
```

The script records resolved tool paths and versions, source SHA-256 hashes,
commands, exit statuses, proof reports, test logs, and benchmark samples in
`validation/`. All 28 commands in the recorded run exited successfully.
GNATprove is configured to fail on warnings and unproved checks.

## Proof

**323/323 checks discharged; zero unproved or justified checks.**

| Category | Checks |
| --- | ---: |
| Data dependencies | 10 |
| Initialization | 17 |
| Runtime safety | 155 |
| Assertions and loop invariants | 51 |
| Functional contracts | 67 |
| Termination | 23 |

All 19 reported subprograms/packages in the library unit were analyzed. The
proof establishes the safety and functional properties listed in README.md,
including subsequence soundness, rejection of every alternative alignment,
ordered highlight positions, score consistency, and sorted search output.
Exact best-K membership and result-count completeness remain test-validated.

Full report: [validation/proof-summary.txt](validation/proof-summary.txt).
Manifest: [validation/manifest.json](validation/manifest.json).

## Tests

Both the release and assertion-enabled library builds passed **132,415 Ada
checks** and **11 CLI checks**. The latter build executes ghost code and contracts.

The tests exhaust candidate strings of length 0–4 and patterns of length 0–3
over `aB/_`, comparing matching against an independent existential oracle.
An independent scoring implementation checks values and highlighted characters.
Search is compared against full selection sorting across all 85 patterns and
capacities 0–10, including empty candidates and duplicate texts. Additional cases
cover path/word bonuses, case sensitivity, non-one array bounds, indexes at
`Integer'Last`, no candidates, empty output buffers, and shorter-text tie-breaking
that overrides candidate index. CLI tests cover line packing, truncation, empty
lines, missing final newlines, and argument errors.

## Synthetic benchmark

Each row uses 100,000 generated 50-byte paths, K=30, and 20 full searches per
process. Three processes run sequentially per query. Times below are per-search
means within each process, then summarized across the three processes. Input
construction and output are outside the timed region. Checksums agreed across
all repeats. These are local synthetic measurements, not real-repository or
cross-machine performance guarantees.

| Query | Workload | Median ms/search | Range ms/search |
| --- | --- | ---: | ---: |
| `fma` | Every candidate matches | 6.587 | 6.525–6.639 |
| `999` | Selective numeric subsequence | 7.811 | 7.793–8.182 |
| `zzz` | No matches | 8.574 | 8.369–8.589 |
| empty | All candidates, length/index ranking | 0.451 | 0.442–0.451 |

The recorded run also includes 10,000-candidate measurements. Raw samples are in
[validation/benchmarks.json](validation/benchmarks.json). To vary size, query, or K:

```sh
make all
bin/bench_fuzzy 100000 fma 30
```

This benchmark exercises small-K search on a common-prefix corpus. It does not
establish that a sorted buffer is preferable to a heap for large K or adversarial
replacement orders; that comparison remains a future optimization task.
