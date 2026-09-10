# Bash integration for the fuzzy picker: Ctrl-R searches the shell history.
#
# Source this from ~/.bashrc, after any other tool that binds Ctrl-R, since
# the last binding wins. Set FUZZY_BIN to override the picker location.

if [[ $- =~ i ]]; then

__fuzzy_bin=${FUZZY_BIN:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && builtin pwd)/bin/fuzzy}

if [[ ! -x $__fuzzy_bin ]]; then
  echo "fuzzy.bash: no picker at $__fuzzy_bin; Ctrl-R left unbound" >&2
else

# History entries may span several lines, so records are separated by a NUL
# and each entry is emitted whole. "fc -lnr" lists the entries newest first,
# indenting each with a tab; a line starting with a tab therefore begins the
# next entry, and anything else continues the current one. Repeated commands
# are collapsed to the most recent occurrence.
__fuzzy_history_awk='
function emit(entry) { sub(/^[ *]/, "", entry); if (!seen[entry]++) printf "%s%c", entry, 0 }
NR == 1 { current = substr($0, 2); next }
/^\t/ { emit(current); current = substr($0, 2); next }
{ current = current RS $0 }
END { if (NR) emit(current) }'

__fuzzy_history__() {
  local selected
  # The picker draws on /dev/tty, so the command substitution collects only
  # the chosen entry. It exits non-zero when nothing was chosen, which leaves
  # the command line untouched. The selected entry is printed as a single
  # record, so a newline inside it is content rather than a separator.
  selected=$(
    set +o pipefail
    builtin fc -lnr -2147483648 2> /dev/null |
      LC_ALL=C command awk "$__fuzzy_history_awk" |
      "$__fuzzy_bin" --interactive --read0 -- "$READLINE_LINE"
  ) || return
  [[ -n $selected ]] || return
  READLINE_LINE=$selected
  READLINE_POINT=0x7fffffff
}

bind -m emacs-standard -x '"\C-r": __fuzzy_history__'
bind -m vi-command -x '"\C-r": __fuzzy_history__'
bind -m vi-insert -x '"\C-r": __fuzzy_history__'

fi

fi
