# Validation

Validated on 2026-09-09 with FSF GNAT 16.1.0 and GNATprove FSF 16.1.0 as
installed by Alire, using the CVC5 and Z3 provers bundled with that GNATprove.
The recorded manifest pins the exact tool paths and versions. Reproduce the
complete run with:

```sh
python3 scripts/validate.py
```

The script records resolved tool paths and versions, source SHA-256 hashes,
commands, exit statuses, proof reports, test logs, and benchmark samples in
`validation/`. All 28 commands in the recorded run exited successfully.
GNATprove is configured to fail on warnings and unproved checks.

## Proof

**376/376 checks discharged; zero unproved or justified checks.**

| Category | Checks |
| --- | ---: |
| Data dependencies | 11 |
| Initialization | 20 |
| Runtime safety | 194 |
| Assertions and loop invariants | 51 |
| Functional contracts | 73 |
| Termination | 27 |

All 24 reported subprograms/packages in the two library units were analyzed. The
proof establishes the safety and functional properties listed in README.md,
including subsequence soundness, rejection of every alternative alignment,
ordered highlight positions, score consistency, and sorted search output.
Exact best-K membership and result-count completeness remain test-validated.

Full report: [validation/proof-summary.txt](validation/proof-summary.txt).
Manifest: [validation/manifest.json](validation/manifest.json).

## Tests

Both the release and assertion-enabled library builds passed **155,658 Ada
checks** and **16 CLI checks**. The latter build executes ghost code and contracts.

The tests exhaust candidate strings of length 0–4 and patterns of length 0–3
over `aB/_`, comparing matching against an independent existential oracle.
An independent scoring implementation checks values and highlighted characters.
Search is compared against full selection sorting across all 85 patterns and
capacities 0–10, including empty candidates and duplicate texts. Additional cases
cover path/word bonuses, case sensitivity, non-one array bounds, indexes at
`Integer'Last`, no candidates, empty output buffers, and shorter-text tie-breaking
that overrides candidate index.

Corpus packing replays every sequence of up to three items drawn from four
texts into buffers of capacity 0 through 8, checking the reported slice, that a
refused append leaves buffer and fill level untouched, that earlier slices still
hold their items afterwards, and that the packed result gives identical search
answers whole and trimmed to the fill level. Further cases cover buffer bounds
other than one, a null buffer, a full buffer still accepting an empty item, and
an item larger than the remaining room. CLI tests cover line packing,
truncation, empty lines, missing final newlines, argument errors, and both
buffer-growth paths.

## Synthetic benchmark

Each row uses 100,000 generated 50-byte paths, K=30, and 20 full searches per
process. Three processes run sequentially per query. Times below are per-search
means within each process, then summarized across the three processes. Input
construction and output are outside the timed region. Checksums agreed across
all repeats. These are local synthetic measurements, not real-repository or
cross-machine performance guarantees.

| Query | Workload | Median ms/search | Range ms/search |
| --- | --- | ---: | ---: |
| `fma` | Every candidate matches | 6.506 | 6.413–6.909 |
| `999` | Selective numeric subsequence | 8.085 | 8.078–8.258 |
| `zzz` | No matches | 9.005 | 8.861–9.033 |
| empty | All candidates, length/index ranking | 0.444 | 0.443–0.462 |

The recorded run also includes 10,000-candidate measurements. Raw samples are in
[validation/benchmarks.json](validation/benchmarks.json). To vary size, query, or K:

```sh
make all
bin/bench_fuzzy 100000 fma 30
```

This benchmark exercises small-K search on a common-prefix corpus. It does not
establish that a sorted buffer is preferable to a heap for large K or adversarial
replacement orders; that comparison remains a future optimization task.
