"""End-to-end tests of the deliberately non-SPARK stdin/stdout adapter."""
from pathlib import Path
import subprocess
import os

CLI = Path(os.environ.get("FUZZY_BIN", Path(__file__).resolve().parents[1] / "bin" / "fuzzy")).resolve()

def run(*args, data=""):
    """Records may contain any byte other than the delimiter, so the adapter is
    driven as a byte channel and decoded only where the test wants text."""
    r = subprocess.run([CLI, *args], input=data.encode(), capture_output=True)
    r.stdout = r.stdout.decode()
    r.stderr = r.stderr.decode()
    return r

r = run("ab", data="zz\na_b\nab\nAB\nab\n")
assert (r.returncode, r.stdout, r.stderr) == (0, "ab\nab\na_b\n", ""), r
assert run("ab", "1", data="a_b\nab\n").stdout == "ab\n"
assert run("", data="bbb\n\na\n").stdout == "\na\nbbb\n"
assert run("ab", "0", data="ab\n").stdout == ""
assert run("ab").stdout == ""
assert run("ab", data="ab").stdout == "ab\n"  # no final input newline
assert run("a", data="A\n").stdout == ""
for args in [(), ("a", "-1"), ("a", "nonsense"), ("a", "1", "extra")]:
    r = run(*args)
    assert r.returncode != 0 and "usage:" in r.stderr, r

# The adapter grows its text and candidate buffers by doubling. Slices are
# absolute indexes into the buffer, so they must survive the moves. These
# 1500 lines of 45 bytes outgrow both initial capacities; candidates stay
# short because the assertion-enabled build executes the ghost matching
# model, whose cost grows with candidate length and pattern length.
many = "".join("src/module_%05d/some_component_name.adb\n" % i for i in range(1500))
r = run("zzz", "3", data=many + "zzz_unique_target.adb\n")
assert (r.returncode, r.stdout) == (0, "zzz_unique_target.adb\n"), r
assert run("mca", "2", data=many).stdout.count("\n") == 2
# One line outgrowing the text buffer several times within a single append.
# The query is empty so ranking, not the ghost model, does the work.
big = "y" * 200000
r = run("", "1", data="a\n" + big + "\n")
assert (r.returncode, r.stdout) == (0, "a\n"), r.returncode
r = run("", "2", data=big + "\n")
assert (r.returncode, r.stdout) == (0, big + "\n"), r.returncode

# NUL framing. The shell history integration needs it: a history entry may
# itself span several lines, which newline framing cannot represent.
assert run("--read0", "ab", data="zz\0a_b\0ab\0").stdout == "ab\na_b\n"
assert run("--read0", "ab", data="zz\0ab").stdout == "ab\n"  # no final delimiter
assert run("--read0", "", data="\0").stdout == "\n"  # one empty record
assert run("--read0", "ab", data="").stdout == ""
assert run("--print0", "ab", data="ab\n").stdout == "ab\0"
assert run("--print0", "", data="\n").stdout == "\0"
multiline = "git commit -m 'a\nb'"
r = run("--read0", "--print0", "gc", data=multiline + "\0ls\0")
assert (r.returncode, r.stdout) == (0, multiline + "\0"), r
# A record straddling many reads of the input, in both framings.
assert run("--read0", "", "2", data=big + "\0").stdout == big + "\n"
assert run("--read0", "--print0", "", "1", data="a\0" + big + "\0").stdout == "a\0"

# A lone "--" ends the options, keeping a query that starts with a dash
# reachable; anything else beginning with two dashes is an error.
assert run("--", "-x", data="-x\ny\n").stdout == "-x\n"
assert run("--print0", "--", "-x", "1", data="-x\n").stdout == "-x\0"
for args in [("--bogus", "a"), ("--read0",), ("--",), ("--", "a", "1", "extra")]:
    r = run(*args)
    assert r.returncode != 0 and "usage:" in r.stderr, r

print("PASS: 30 CLI checks")
