GPRBUILD ?= gprbuild
GNATPROVE ?= gnatprove
JOBS ?= 4

.PHONY: all test test-contracts prove flow benchmark
all:
	$(GPRBUILD) -P tools.gpr -j$(JOBS)

test: all
	bin/test_fuzzy
	python3 tests/test_cli.py

test-contracts:
	$(GPRBUILD) -P tools.gpr -XFUZZY_BUILD=checks -j$(JOBS)
	bin/checks/test_fuzzy
	FUZZY_BIN=bin/checks/fuzzy python3 tests/test_cli.py

flow:
	$(GNATPROVE) -P fuzzy.gpr --mode=flow -j$(JOBS)

prove:
	$(GNATPROVE) -P fuzzy.gpr --level=2 --timeout=20 --prover=cvc5,z3 --counterexamples=off -j$(JOBS)

benchmark: all
	bin/bench_fuzzy
