# Fuzzy

An allocation-free fuzzy matcher Ada/SPARK library. Case-sensitive,
byte-oriented (no encoding support), returns the K best scores. A small unproved
CLI is also provided for convenience.

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

Candidate text must be packed into one `String` that the caller owns.
`Fuzzy.Corpus.Append` does that packing, so clients need not re-derive the
capacity arithmetic. It appends into a caller-provided buffer and reports the
slice; on failure the buffer and fill level are untouched, so a client whose
total size is not known in advance can grow the buffer and retry. Slices are
absolute indexes, so they survive a move to a larger buffer that keeps the same
lower bound and copies the filled prefix.

```ada
with Fuzzy.Corpus;
--  Inside a client procedure:
Buffer : String (1 .. 4096);
Used : Natural := 0;
Items : Fuzzy.Candidate_Array (1 .. 2);
Slice : Fuzzy.Text_Slice;
Ok : Boolean;
Results : Fuzzy.Search_Result_Array (1 .. 30);
Count : Natural;
--  In the procedure body:
Fuzzy.Corpus.Append (Buffer, Used, "src/foo.adb", Slice, Ok);
Items (1) := (Text => Slice);
Fuzzy.Corpus.Append (Buffer, Used, "src/bar.ads", Slice, Ok);
Items (2) := (Text => Slice);
Fuzzy.Search ("fa", Buffer, Items, Results, Count);
```

Passing `Buffer` or `Buffer (1 .. Used)` to `Search` is equivalent, because no
slice refers to the unused part.

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

The CLI reads one candidate per input record and prints the ranked texts. Its
syntax is `fuzzy [--read0] [--print0] [--] QUERY [K]`, with K defaulting to 30.
Records are newline-delimited by default; `--read0` and `--print0` switch input
and output framing independently to NUL, so that a candidate containing a
newline can be represented. A record may hold any byte other than the delimiter
in force. Input need not end with a delimiter, and a delimiter at the very end
does not add an empty record. Empty records and K=0 are accepted. A lone `--`
ends the options, so a query beginning with a dash stays reachable. Because
standard input has no size known in advance, the CLI owns its corpus storage and
grows it by doubling, which is why it is the component that allocates. Client
applications should link the library directly.

`--interactive` turns the CLI into a full-screen picker instead of a batch
filter. It reads all candidates from standard input, then takes over
`/dev/tty` in raw mode: the query is re-matched against the whole corpus on
every keystroke, matched characters are highlighted, and the accepted
candidate is written to standard output. Standard output therefore stays free
to be a pipe or a command substitution, which is what a shell binding needs. A
positional QUERY becomes the initial query rather than a fixed one, and K is
not accepted, because the display bounds how many results are useful.

Keys follow fzf where they overlap: characters edit the query, `Ctrl-U` clears
it, `Ctrl-W` deletes a word, `Ctrl-A`/`Ctrl-E`/arrows move within it,
`Up`/`Down`/`Ctrl-P`/`Ctrl-N`/`Ctrl-K`/`Ctrl-J` move the selection, `Enter`
accepts, and `Esc` or `Ctrl-C` aborts. With `--multi`, `Tab` and `Shift-Tab`
mark the candidate under the cursor and step on; accepting then reports every
marked candidate in corpus order instead of the one under the cursor. Marks
belong to candidates rather than to result rows, so they survive a change of
query. The exit status is 0 when a candidate
was accepted, 1 when nothing matched, 2 when there is no usable terminal, and
130 on abort. The terminal mode is restored on every exit path, including
`SIGTERM` and `SIGHUP`.

The picker asks the matcher for one screenful of results and doubles that
bound only when the selection actually reaches the end of what came back, so
scrolling is unbounded without paying for a large K on every keystroke. The
terminal size is re-read on each redraw, so a resize takes effect on the next
keypress without a signal handler.

## Shell integration

`shell/fuzzy.bash` binds Ctrl-R to a history search and Ctrl-T to a path
search. Source it from `~/.bashrc`, after any other tool that binds those keys,
since the last binding wins:

```sh
source ~/tools/fuzzy_matcher/shell/fuzzy.bash
```

It lists the history newest first, collapses repeats, and separates entries
with NUL so that an entry spanning several lines stays one candidate. The
picker draws on the terminal, so the command substitution around it collects
only the chosen entry, which then replaces the current command line. Aborting
leaves the line untouched. Set `FUZZY_BIN` to point at a picker elsewhere.

Note that a multi-line command is one history entry only while the session
that typed it is alive; bash writes it to the history file as separate lines,
and a later shell reads it back as separate entries.

Ctrl-T lists the tree below the current directory, following symbolic links and
pruning `.git`, `node_modules` and `.svn`, and splices the marked paths into the
command line at the cursor, each quoted for the shell. `Tab` marks more than
one. Set `FUZZY_CTRL_T_COMMAND` to list candidate paths some other way; it must
separate them with NUL.

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
- A successful append yields a valid slice holding exactly the appended item,
  and leaves the already-filled prefix of the buffer unchanged, so slices handed
  out earlier stay valid and keep holding what they held. A refused append
  changes nothing.

There are no assumed lemmas, skipped proofs, or SPARK exclusions in the library.
Exact best-K membership and result-count completeness are tested against an
independent full-sort oracle; they are not claimed as proved postconditions.
The CLI, tests, and benchmark are ordinary Ada/Python outside the proof boundary.
The usual SPARK precondition and sufficient stack/storage assumptions apply.

The library is proved with FSF GNAT and FSF GNATprove, so the result rests
on a toolchain anyone can obtain. Reproduce it with `make prove`, and run
the test suites with `make test` and `make test-contracts`.

Incremental filtering, Unicode matching, and alternative alignment/scoring
policies are deferred.

## License

Copyright 2026 Johannes Kanig.

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
