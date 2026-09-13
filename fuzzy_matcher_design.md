# Fuzzy Matching Library Design

## 1. Purpose

This document proposes the design of a reusable fuzzy matching library, intended initially for use in a code exploration tool that can search files in both the current work tree and arbitrary Git revisions.

The core design goal is to separate:

1. **candidate enumeration** — where searchable items come from;
2. **fuzzy matching and ranking** — how candidate text is matched against a query;
3. **application metadata** — what each candidate means to the client.

The fuzzy matcher itself should know nothing about files, Git, revisions, symbols, or the filesystem.

A file finder for a historical Git revision can therefore work as:

```text
Git revision
    |
    v
enumerate paths at revision
    |
    v
packed candidate text + candidate descriptors
    |
    v
fuzzy search library
    |
    v
ranked candidate indexes
```

The same library can later be reused for files, commits, symbols, references, commands, and other searchable items.

The proposed implementation is **library-first**, with an optional thin stdin/stdout CLI on top.

---

## 2. Design Principles

The initial design should prioritize:

- simple semantics;
- stateless search;
- predictable memory use;
- no ownership of client data by the matcher;
- no dependency on filesystem or Git concepts;
- suitability for SPARK;
- no required dynamic allocation in the matching core;
- deterministic ranking;
- easy benchmarking;
- easy extension to incremental search later.

The first implementation should deliberately avoid premature optimization.

In particular, full re-search on every query change should be the default until benchmarks show that incremental filtering is necessary.

---

## 3. High-Level Architecture

```text
                    CLIENT APPLICATION

        +---------------------------------------+
        | Git tree / filesystem / symbols / ... |
        +--------------------+------------------+
                             |
                             v
                  candidate construction
                             |
                     +-------+-------+
                     |               |
                     v               v
              packed String    Candidate_Array
                     |               |
                     +-------+-------+
                             |
                             v
                    FUZZY MATCH LIBRARY
                             |
                             v
                 Search_Result_Array
                             |
                             v
                    CLIENT APPLICATION
                             |
                             v
               candidate metadata / UI
```

The application owns all candidate storage.

The matcher borrows the searchable text read-only and returns candidate indexes plus scores.

---

## 4. Candidate Representation

### 4.1 Rationale

Using an array of access-to-string values would introduce:

- dynamic allocation;
- lifetime concerns;
- ownership complexity;
- potential complications for SPARK;
- poor locality.

Using bounded strings would impose an arbitrary maximum candidate length.

Instead, searchable candidate text should be stored in one packed character buffer, with individual candidates represented as slices into that buffer.

Conceptually:

```text
Data:
"src/foo.adbsrc/bar.adstests/foo.adb..."

Candidates:
1 -> First = 1,  Length = 11
2 -> First = 12, Length = 11
3 -> First = 23, Length = 13
```

### 4.2 Proposed Types

```ada
package Fuzzy with SPARK_Mode is

   subtype Candidate_Index is Positive;

   type Text_Slice is record
      First  : Positive;
      Length : Natural;
   end record;

   type Candidate is record
      Text : Text_Slice;
   end record;

   type Candidate_Array is
     array (Candidate_Index range <>) of Candidate;

end Fuzzy;
```

The exact contracts should guarantee that every slice lies inside the supplied text buffer.

A candidate's index in `Candidate_Array` is its identity from the fuzzy matcher's point of view.

---

## 5. Client-Owned Metadata

The matcher should not carry application-specific metadata.

For example, the code explorer may have:

```text
Candidate 173

Path:       src/parser.adb
Revision:   abc123...
Object ID:  ...
Modified:   True
Language:   Ada
```

The fuzzy matcher sees only:

```text
Candidate_Index = 173
Searchable text = "src/parser.adb"
```

The client may maintain parallel arrays or another data structure indexed by `Candidate_Index`.

This keeps the matcher generic and avoids serialization or copying of application objects.

---

## 6. Match Scoring

The low-level matcher determines whether a pattern is a subsequence of a candidate and assigns a score.

A first implementation can use a simple linear scan with bonuses and penalties such as:

- consecutive-character bonus;
- path-component-start bonus;
- basename bonus;
- word-boundary bonus;
- gap penalty;
- candidate-length penalty.

For example:

```text
Pattern:
fa

Candidates:
src/frontend/analysis.adb
src/fuzzy_algorithm.adb
tests/system/file_access.adb
```

The second candidate may rank highest because the characters occur at useful structural boundaries and close together.

The exact scoring model should be documented independently from the search algorithm.

---

## 7. Score Type

A bounded score type is preferable to an unconstrained integer.

For example:

```ada
type Score_Type is range -1_000_000 .. 1_000_000;
```

The chosen bounds should be derived from the maximum possible score for supported candidate and pattern lengths.

The implementation should prove that scoring cannot overflow.

---

## 8. Low-Level Match Operation

The fundamental primitive should operate on one candidate.

```ada
procedure Score
  (Pattern   : String;
   Data      : String;
   Candidate : Text_Slice;
   Matched   : out Boolean;
   Value     : out Score_Type);
```

Conceptually:

```text
Score("foo", "src/foo.adb")
    -> Matched = True
    -> Value   = 187
```

This primitive should be pure with respect to program state:

```ada
Global => null
```

where practical.

It forms the basis for both batch search and later incremental filtering.

---

## 9. Search Result Type

The main search result should remain small.

```ada
type Search_Result is record
   Candidate : Candidate_Index;
   Score     : Score_Type;
end record;

type Search_Result_Array is
  array (Positive range <>) of Search_Result;
```

The result contains only:

- the candidate index;
- the score.

The client uses the index to recover the candidate text and metadata.

---

## 10. Top-K Search API

The principal batch operation is:

```ada
procedure Search
  (Pattern      : String;
   Data         : String;
   Candidates   : Candidate_Array;
   Results      : out Search_Result_Array;
   Result_Count : out Natural);
```

The length of `Results` defines `K`, the maximum number of returned matches.

For example:

```ada
Results : Search_Result_Array (1 .. 30);

Fuzzy.Search
  (Pattern      => Query,
   Data         => Names,
   Candidates   => Files,
   Results      => Results,
   Result_Count => Count);
```

The implementation scans all candidates and retains only the best `K`.

This avoids allocating or sorting a complete result set.

A bounded heap is a natural implementation for maintaining the best results.

---

## 11. Deterministic Ordering

Ranking should be deterministic.

A recommended ordering is:

1. higher fuzzy score;
2. shorter candidate text;
3. lower candidate index.

This provides stable results across runs and makes the expected behavior straightforward to specify and test.

---

## 12. Match Positions and Highlighting

The main search result should **not** include every matched character position.

Doing so would enlarge the hot-path result structure and complicate the search implementation.

Instead, use a separate detailed operation for the few results actually displayed.

```ada
type Match_Position_Array is
  array (Positive range <>) of Positive;

procedure Match_Details
  (Pattern        : String;
   Data           : String;
   Candidate      : Text_Slice;
   Matched        : out Boolean;
   Value          : out Score_Type;
   Positions      : out Match_Position_Array;
   Position_Count : out Natural);
```

The UI can therefore do:

```text
search 100,000 candidates
        |
        v
return top 30
        |
        v
recompute details for those 30
        |
        v
highlight matching characters
```

Re-running the matcher for a few dozen candidates should be negligible compared with the full search.

---

## 13. Initial Interactive Search Strategy

### 13.1 Recommendation

Version 1 should simply search the full candidate set on every query change.

Example:

```text
query "s"
    -> Search(all candidates)

query "sr"
    -> Search(all candidates)

query "src"
    -> Search(all candidates)

query "src/"
    -> Search(all candidates)
```

This is intentionally simple.

### 13.2 Advantages

Full re-search provides:

- no persistent matcher state;
- simple SPARK reasoning;
- simple handling of backspace;
- simple arbitrary query editing;
- simple replacement of the candidate set;
- easy parallelization later;
- easy performance measurement;
- fewer public API concepts.

For typical source repositories, the cost may already be small enough.

A repository with:

```text
100,000 paths
average path length = 50
```

contains only about five million path characters.

A simple compiled subsequence matcher can scan that volume quickly.

The implementation should therefore be benchmarked before adding incremental complexity.

---

## 14. Incremental Search

Incremental filtering is a possible later optimization.

### 14.1 Key Property

For ordinary subsequence matching:

```text
if candidate does not match "fo",
then it cannot match "foo".
```

Therefore, while the user appends characters, the candidate set can only shrink.

Example:

```text
all candidates
     |
     | "f"
     v
38,000 matches
     |
     | "fo"
     v
8,000 matches
     |
     | "foo"
     v
700 matches
```

### 14.2 Important Limitation

Incremental search must **not** refine only the previous top-K results.

For example, a candidate ranked 5000th for:

```text
f
```

may become the best candidate for:

```text
foo
```

Therefore an incremental implementation must retain all matching candidate indexes, not merely displayed results.

---

## 15. Proposed Incremental Filtering API

If incremental filtering is later required, keep the search state outside the matcher.

```ada
type Candidate_Index_Array is
  array (Positive range <>) of Candidate_Index;

procedure Filter
  (Pattern      : String;
   Data         : String;
   Candidates   : Candidate_Array;
   Input        : Candidate_Index_Array;
   Input_Count  : Natural;
   Output       : out Candidate_Index_Array;
   Output_Count : out Natural);
```

The client may keep two work buffers:

```text
All candidates
      |
      | query = "f"
      v
Buffer_A
      |
      | query = "fo"
      v
Buffer_B
      |
      | query = "foo"
      v
Buffer_A
```

The buffers can be reused by swapping roles after each refinement.

This avoids dynamic allocation and keeps ownership explicit.

---

## 16. Handling Backspace

Version 1 should not maintain a history of intermediate candidate sets.

If:

```text
foo -> fo
```

the implementation should simply re-search from the full candidate set.

This avoids retaining potentially large stacks of matching-candidate arrays.

If profiling later shows that backspace performance matters, a bounded cache of previous query states can be added at the application level.

---

## 17. Proposed Version 1 API

A minimal first public API could consist of three operations.

### 17.1 Score One Candidate

```ada
procedure Score
  (Pattern   : String;
   Data      : String;
   Candidate : Text_Slice;
   Matched   : out Boolean;
   Value     : out Score_Type);
```

### 17.2 Search All Candidates

```ada
procedure Search
  (Pattern      : String;
   Data         : String;
   Candidates   : Candidate_Array;
   Results      : out Search_Result_Array;
   Result_Count : out Natural);
```

### 17.3 Compute Highlight Information

```ada
procedure Match_Details
  (Pattern        : String;
   Data           : String;
   Candidate      : Text_Slice;
   Matched        : out Boolean;
   Value          : out Score_Type;
   Positions      : out Match_Position_Array;
   Position_Count : out Natural);
```

An incremental `Filter` operation should be deferred until there is evidence that it is necessary.

---

## 18. Possible Package Structure

One possible organization is:

```text
fuzzy.ads
fuzzy.adb

fuzzy-scoring.ads
fuzzy-scoring.adb

fuzzy-ranking.ads
fuzzy-ranking.adb
```

Responsibilities:

### `Fuzzy.Scoring`

- subsequence matching;
- score computation;
- match positions;
- scoring contracts.

### `Fuzzy.Ranking`

- top-K maintenance;
- deterministic tie-breaking;
- bounded heap or equivalent data structure.

### `Fuzzy`

- client-facing API;
- orchestration of matching and ranking.

The exact split can remain small initially.

---

## 19. SPARK Verification Goals

The matcher is a good candidate for SPARK verification because the core is:

- pure or nearly pure;
- array-oriented;
- bounded;
- algorithmic;
- independent of external state.

Useful properties include:

### Runtime safety

- no out-of-bounds accesses;
- no integer overflow;
- no invalid slice access;
- no uninitialized values.

### Match correctness

If `Matched = True`, then every pattern character occurs in the candidate in order.

For returned positions:

```text
Positions(1) < Positions(2) < ... < Positions(N)
```

and every position lies within the candidate slice.

### No-match correctness

If `Matched = False`, then the pattern is not a subsequence of the candidate.

### Search correctness

Every returned result:

- refers to a valid candidate;
- matches the pattern;
- has the correct score.

### Ranking correctness

The returned results are ordered according to the documented deterministic ranking.

The implemented `Search` contract also proves that every omitted matching
candidate ranks below every returned result, and that omission is allowed only
when the output buffer is full. With distinct, correctly scored results, this
establishes exactly the best `min(K, number of matches)` candidates.

---

## 20. Optional CLI

A thin command-line frontend can be provided on top of the library.

Conceptually:

```bash
git ls-tree -r --name-only REV | fuzzy QUERY
```

or:

```bash
find src -type f | fuzzy QUERY
```

The CLI should not define the architecture of the library.

Its responsibilities should be limited to:

- reading candidates;
- building the packed text representation;
- invoking the library;
- printing matches or selected candidates.

The code exploration application should link the library directly rather than repeatedly spawning the CLI.

---

## 21. Git Revision Integration

The code exploration client can enumerate files for an arbitrary revision using Git tree data.

Conceptually:

```text
selected revision
      |
      v
enumerate tree paths
      |
      v
build packed candidate buffer
      |
      v
Fuzzy.Search
```

Changing the selected revision replaces the candidate set.

No change to the fuzzy matching algorithm is required.

The candidate source may therefore be any of:

```text
working tree files
files at Git revision
modified files
commits
symbols
references
commands
```

The matcher treats all of them identically.

---

## 22. Recommended Development Sequence

### Version 1

Implement:

- packed text representation;
- `Text_Slice`;
- linear subsequence matcher;
- simple path-aware scoring;
- `Score`;
- bounded top-K `Search`;
- `Match_Details`;
- deterministic tie-breaking;
- SPARK contracts;
- benchmarks.

Use full re-search on every query change.

### Version 2, only if needed

Consider:

- incremental filtering;
- candidate-index scratch buffers;
- previous-query detection;
- full reset on backspace or arbitrary query edits.

### Later

Possible extensions include:

- alternative scoring schemes;
- generic-text versus path-specific scoring;
- parallel candidate scoring;
- optimized SIMD-friendly scanning outside the verified core if justified;
- more sophisticated dynamic-programming alignment;
- persistent CLI mode if independently useful.

---

## 23. Summary of Recommended Decisions

The initial design should use:

- **library-first architecture**;
- **client-owned candidate storage**;
- **one packed `String` plus `Text_Slice` descriptors**;
- **candidate array index as candidate identity**;
- **small `(Candidate_Index, Score)` result records**;
- **separate detailed matching for highlight positions**;
- **bounded top-K output**;
- **deterministic ranking**;
- **full re-search on every keystroke initially**;
- **incremental filtering only after benchmarking**;
- **no internal dynamic allocation in the core matcher**;
- **SPARK verification for safety, match correctness, and ranking properties**.

This design keeps the fuzzy matcher small, reusable, fast, and independent of the code explorer while providing a clean path toward later optimization.
