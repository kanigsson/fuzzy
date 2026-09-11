#  Optional, untracked, per-developer tool locations. The project states
#  which tools it needs and never where they live; a developer whose
#  environment offers several toolchains pins the choice here.
-include local.mk

GPRBUILD ?= gprbuild
GNATPROVE ?= gnatprove
GNATFORMAT ?= gnatformat
JOBS ?= 4

.PHONY: all test test-contracts prove flow benchmark format
all:
	$(GPRBUILD) -P tools.gpr -j$(JOBS)

test: all
	bin/test_fuzzy
	python3 tests/test_cli.py
	python3 tests/test_pick.py

test-contracts:
	$(GPRBUILD) -P tools.gpr -XFUZZY_BUILD=checks -j$(JOBS)
	bin/checks/test_fuzzy
	FUZZY_BIN=bin/checks/fuzzy python3 tests/test_cli.py
	FUZZY_BIN=bin/checks/fuzzy python3 tests/test_pick.py

flow:
	$(GNATPROVE) -P fuzzy.gpr --mode=flow -j$(JOBS)

prove:
	$(GNATPROVE) -P fuzzy.gpr --level=2 --timeout=20 --prover=cvc5,z3 --counterexamples=off -j$(JOBS)

benchmark: all
	bin/bench_fuzzy

#  Some sources hold UTF-8 literals, so the charset must be stated: the
#  formatter otherwise assumes iso-8859-1 and re-encodes them on every run.
format:
	$(GNATFORMAT) -P tools.gpr -U --charset utf-8
