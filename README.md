# Fuzzy

An allocation-free SPARK library for case-sensitive, byte-oriented subsequence
matching and deterministic top-K search. It implements version 1 of
[fuzzy_matcher_design.md](fuzzy_matcher_design.md). Candidate text and metadata
remain owned by the caller; the library has no filesystem, Git, or I/O dependency.
The small Ada CLI is outside SPARK.

## Build and use

Use a matching GNAT/GPRbuild and GNATprove installation with Ada 2022 support.

```sh
make test                 # library, CLI, independent oracle tests
make test-contracts      # also execute contracts and ghost assertions
make flow                # initialization and dependency analysis
make prove               # runtime safety and functional contracts
make benchmark           # 100,000 synthetic paths, K=30, 20 searches
printf '%s\n' src/foo.adb src/bar.ads | bin/fuzzy fa 30
```

`GPRBUILD`, `GNATPROVE`, and `JOBS` can be overridden for a selected toolchain.
`fuzzy.gpr` builds a reusable static library; client projects import it with
`with "fuzzy.gpr";`. The library is also an Alire crate, so a client can instead
depend on it with `alr with fuzzy`; `alr build` builds the library alone, while
the CLI, tests, and benchmark stay behind the `Makefile` targets above. The
default release build retains Ada runtime checks and omits assertion/ghost
execution. `-XFUZZY_BUILD=checks` enables assertions and uses separate library,
object, and executable directories.

```ada
with Fuzzy;
--  Inside a client procedure:
Data : constant String := "src/foo.adbsrc/bar.ads";
Items : constant Fuzzy.Candidate_Array :=
  [(Text => (First => 1, Length => 11)),
   (Text => (First => 12, Length => 11))];
Results : Fuzzy.Search_Result_Array (1 .. 30);
Count : Natural;
--  In the procedure body:
Fuzzy.Search ("fa", Data, Items, Results, Count);
--  Consume Results (Results'First .. Results'First + Count - 1).
```

`Score` scores one borrowed slice. `Search` returns candidate indexes and scores.
`Match_Details` recomputes the same score and returns a highlight offset for each
pattern character; its positions buffer must hold at least `Pattern'Length`
elements. See [src/fuzzy.ads](src/fuzzy.ads) for the full contracts.

## Matching and scoring

Characters compare exactly, including case. There is no Unicode decoding,
normalization, case folding, or edit-distance matching. A pattern matches when
its characters occur in order, possibly with gaps. The alignment is greedy:
each character uses its earliest available occurrence. It does not maximize the
score over alternative alignments.

The score starts at minus the candidate length. For each matched character:

| Contribution | Points |
| --- | ---: |
| Character matched | +16 |
| Immediately follows the preceding matched character | +12 |
| First character, or immediately after `/` or `\` | +16 |
| After `_`, `-`, `.`, space, or a lowercase-to-uppercase ASCII transition | +8 |
| In the basename, after the last `/` or `\` | +8 |
| Each skipped character before this match, including the leading gap | -2 |

Bonuses add together. Trailing characters incur only the length penalty.
An empty pattern matches every candidate with score `-Length`. An unsuccessful
match returns score zero. Always use `Matched` to distinguish failure: zero and
negative scores can also belong to successful matches.

With candidate length L and pattern length M, successful scores lie within
`[-3*L, 60*M]`. `Score_Type` covers `[-3*Integer'Last, 60*Integer'Last]` using a
wide integer representation. No smaller candidate-length cap or saturation is
needed, and score arithmetic is proved not to overflow.

## Storage and ranking

All input/output arrays may have arbitrary lower bounds. Nonempty slices must
lie within `Data`; empty slices never dereference `First`. Slices may overlap,
and equal texts remain distinct candidates. Identity is the actual array index.

Results are ordered by decreasing score, then increasing candidate length,
then increasing candidate index. Only the first `Result_Count` output elements
are meaningful; unused slots are initialized but carry no result semantics.
Zero-capacity result buffers and empty candidate arrays are supported.

Highlight positions are **one-based offsets within the candidate**. Convert an
offset to a packed buffer index with `Candidate.First + (Offset - 1)`. Successful
matching returns exactly `Pattern'Length` positions; failure returns count zero,
without exposing a partial alignment. Unused positions carry no semantics.

`Score` uses constant auxiliary storage and linear time in candidate and pattern
length. `Search` keeps a sorted buffer in the caller's K result slots. Its worst
case is O(total candidate text + candidate count * pattern length + matches * K),
with O(1) executable auxiliary storage. It does not allocate or sort all matches.
This favors small display limits; a heap can be introduced if larger K workloads
justify it. Detailed matching reruns the greedy alignment after scoring. Proof-only arrays and
lemmas are erased in release builds.

The CLI reads one candidate per line and prints the ranked texts. Its syntax is
`fuzzy QUERY [K]`, with K defaulting to 30. It accepts empty lines and K=0; it
cannot represent a candidate containing a newline. Client applications should
link the library directly.

## Verification scope

GNATprove checks the entire library. All runtime safety, initialization, global
dependency, and termination obligations are discharged. Functional contracts
establish:

- Matching is equivalent to the recursive earliest-occurrence subsequence model.
- Successful highlight offsets are inside the candidate, strictly increasing,
  and point to the corresponding pattern characters.
- `Witness_Implies_Match` proves that any ordered occurrence witness implies a
  match, so a negative answer excludes alternative alignments too.
- Every returned result identifies a matching input candidate and carries the
  same score as `Score`; `Match_Details` returns that score as well.
- The returned prefix is strictly ordered by the documented ranking relation.

There are no assumed lemmas, skipped proofs, or SPARK exclusions in the library.
Exact best-K membership and result-count completeness are tested against an
independent full-sort oracle; they are not claimed as proved postconditions.
The CLI, tests, and benchmark are ordinary Ada/Python outside the proof boundary.
The usual SPARK precondition and sufficient stack/storage assumptions apply.

See [VALIDATION.md](VALIDATION.md) for measured results and reproduction details.
Incremental filtering, Unicode matching, and alternative alignment/scoring
policies are deferred.

## License

Apache License 2.0. See [LICENSE](LICENSE).
