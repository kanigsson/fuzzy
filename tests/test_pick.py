"""Drives the interactive picker through a real pty.

The picker takes over /dev/tty while standard input carries the candidates and
standard output carries the result, so all three have to be separate here for
the test to mean anything.
"""
from pathlib import Path
import os
import pty
import select
import signal
import termios
import time

CLI = Path(os.environ.get("FUZZY_BIN", Path(__file__).resolve().parents[1] / "bin" / "fuzzy")).resolve()

ESC = b"\x1b"
UP, DOWN = ESC + b"[A", ESC + b"[B"


class Session:
    def __init__(self, args, candidates, delim=b"\0"):
        r_in, w_in = os.pipe()
        r_out, w_out = os.pipe()
        self.pid, self.master = pty.fork()
        if self.pid == 0:  # child
            os.dup2(r_in, 0)
            os.dup2(w_out, 1)
            for fd in (r_in, w_in, r_out, w_out):
                os.close(fd)
            os.execv(str(CLI), [str(CLI), *args])
            os._exit(127)
        os.close(r_in)
        os.close(w_out)
        self.out = r_out
        self.saved_mode = termios.tcgetattr(self.master)
        os.write(w_in, delim.join(candidates) + delim)
        os.close(w_in)
        self.screen = b""

    def settle(self, quiet=0.25, limit=5.0):
        """Drain the display until the picker stops writing."""
        deadline = time.time() + limit
        while time.time() < deadline:
            ready, _, _ = select.select([self.master], [], [], quiet)
            if not ready:
                return self.screen
            try:
                chunk = os.read(self.master, 65536)
            except OSError:
                return self.screen
            if not chunk:
                return self.screen
            self.screen += chunk
        return self.screen

    def send(self, keys):
        self.screen = b""
        os.write(self.master, keys)
        return self.settle()

    def finish(self):
        self.settle()
        _, status = os.waitpid(self.pid, 0)
        mode = termios.tcgetattr(self.master)
        result = os.read(self.out, 65536)
        os.close(self.out)
        os.close(self.master)
        assert os.WIFEXITED(status) or os.WIFSIGNALED(status), status
        code = os.WEXITSTATUS(status) if os.WIFEXITED(status) else -os.WTERMSIG(status)
        return code, result, mode == self.saved_mode


HISTORY = [b"git status", b"git commit -m 'a\nb'", b"ls -la", b"gnatprove -P p"]


def start(*args, candidates=HISTORY):
    s = Session(["--interactive", "--read0", *args], candidates)
    s.settle()
    return s


# Typing filters, and Enter reports the highlighted candidate on stdout.
s = start()
s.send(b"gc")
s.send(b"\r")
code, out, restored = s.finish()
assert (code, out) == (0, b"git commit -m 'a\nb'\n"), (code, out)
assert restored, "terminal mode not restored"

# A candidate holding a newline survives the round trip under NUL framing.
s = start("--print0")
s.send(b"gc")
s.send(b"\r")
code, out, _ = s.finish()
assert (code, out) == (0, b"git commit -m 'a\nb'\x00"), (code, out)

# The initial query is a starting point, editable like anything typed.
s = start("git")
s.send(b"\r")
code, out, _ = s.finish()
assert (code, out[:10]) == (0, b"git status"), (code, out)

# Selection moves; Ctrl-N and the down arrow agree.
for key in (DOWN, b"\x0e"):
    s = start()
    s.send(b"git")
    s.send(key)
    s.send(b"\r")
    code, out, _ = s.finish()
    assert (code, out) == (0, b"git commit -m 'a\nb'\n"), (key, code, out)

# Escape and Ctrl-C abort with fzf's status and print nothing.
for key in (ESC, b"\x03"):
    s = start()
    s.send(b"g")
    s.send(key)
    code, out, restored = s.finish()
    assert (code, out, restored) == (130, b"", True), (key, code, out, restored)

# Nothing matched: Enter reports status 1 rather than a candidate.
s = start()
s.send(b"zzqq")
s.send(b"\r")
code, out, _ = s.finish()
assert (code, out) == (1, b""), (code, out)

# Editing keys reach the query line.
s = start()
s.send(b"gitx")
s.send(b"\x7f")          # backspace
s.send(b"\x15")          # clear the line
s.send(b"ls")
s.send(b"\r")
code, out, _ = s.finish()
assert (code, out) == (0, b"ls -la\n"), (code, out)

# The display shows the match counter and highlights matched characters.
s = start()
screen = s.send(b"git")
assert b"/4" in screen, screen
assert ESC + b"[32m" in screen, screen
s.send(b"\x03")
s.finish()

# A control character inside a candidate must be shown, not executed: writing
# one to a terminal in raw mode would move the cursor and break the layout.
s = start()
screen = s.send(b"gc")
assert "↵".encode() in screen, screen
assert b"a\nb" not in screen, screen
s.send(b"\x03")
s.finish()

# An empty query keeps the input order, which is what makes the most recent
# history entry come first rather than the shortest one.
s = start()
s.send(b"\r")
code, out, _ = s.finish()
assert (code, out) == (0, b"git status\n"), (code, out)

# A termination signal must still hand the terminal back.
s = start()
os.kill(s.pid, signal.SIGTERM)
code, out, restored = s.finish()
assert restored, "terminal mode not restored after SIGTERM"
assert code == 143, code

print("PASS: 15 interactive checks")
