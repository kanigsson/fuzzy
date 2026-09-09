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
print("PASS: 11 CLI checks")
