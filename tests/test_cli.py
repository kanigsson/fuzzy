"""End-to-end tests of the deliberately non-SPARK stdin/stdout adapter."""
from pathlib import Path
import subprocess
import os

CLI = Path(os.environ.get("FUZZY_BIN", Path(__file__).resolve().parents[1] / "bin" / "fuzzy")).resolve()

def run(*args, data=""):
    return subprocess.run([CLI, *args], input=data, text=True, capture_output=True)

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

print("PASS: 16 CLI checks")
