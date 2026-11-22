#!/usr/bin/env bash
# no-force-push.sh -- a Claude Code PreToolUse hook (matcher "Bash"), added to ~/.claude/settings.json
# by make-it's installers (install.sh, install.ps1).
#
# Refuses a git push that can overwrite what is online without looking first: --force, -f (also
# inside a cluster such as -uf), --mirror, and a +refspec (+main, +HEAD:main). Lets through
# --force-with-lease and --force-if-includes, which refuse when the online copy changed.
# Finds the push wherever git starts a command: after ; && || | ( ) ` or a new line, after
# VAR=value, behind env / command / sudo / nohup / time / exec, as /usr/bin/git or git.exe, with
# git's own options first (git -C dir push, git -c k=v push), and with the flags before or after
# the remote. Words inside quotes are one word, so a commit message that mentions a force push is
# not refused. A tripwire for mistakes, not proof against someone hiding a push (an alias, a
# config refspec, bash -c "..."), which it does not look for.
#
# Failure mode: fails OPEN on its own errors only for a command that is not a force push. When it
# can't read the command (no "command" field, an unterminated string or quote, awk missing or
# failing), it reads the raw text instead: a push with any force sign in it is refused; anything
# else is let through. If bash cannot run this file at all, Claude Code reports a hook error and
# does not block; nothing in this file can change that.
#
# Exit 0 = allowed. Exit 2 = refused (Claude Code gives Claude the message and doesn't run it).
# The reading is done in awk: bash's own string loops slow down with the square of a long command.

export LC_ALL=C

refuse() {
  printf '%s\n' "Blocked by make-it: $1 can overwrite work on GitHub that nobody here has seen. Use git push --force-with-lease instead: it refuses if the online copy changed. A plain force push is for a person to run by hand." >&2
  exit 2
}

input=$(cat) || input=""
case $input in *push*) ;; *) exit 0 ;; esac

out=$(printf '%s' "$input" | awk '
function ws(c) { return c == " " || c == "\t" || c == "\n" || c == "\r" }
function word() { if (have) toks[++nt] = tok; tok = ""; have = 0 }
function op() { word(); toks[++nt] = "\003" }
BEGIN { RS = "\001" }
{ s = s $0 }
END {
  n = split(s, ch, "")
  p = index(s, "\"command\"")
  if (!p) { print "UNREADABLE"; exit }
  i = p + 9
  while (i <= n && ws(ch[i])) i++
  if (ch[i] != ":") { print "UNREADABLE"; exit }
  i++
  while (i <= n && ws(ch[i])) i++
  if (ch[i] != "\"") { print "UNREADABLE"; exit }
  # the JSON string, decoded (\u escapes are only control or non-ASCII characters here: never part of a flag)
  m = 0; closed = 0
  for (i++; i <= n; i++) {
    c = ch[i]
    if (c == "\"") { closed = 1; break }
    if (c == "\\") {
      e = ch[++i]
      if (e == "n") c = "\n"; else if (e == "t") c = "\t"; else if (e == "r") c = "\r"
      else if (e == "b" || e == "f") c = " "; else if (e == "u") { c = "?"; i += 4 } else c = e
    }
    cm[++m] = c
  }
  if (!closed) { print "UNREADABLE"; exit }
  # words and command boundaries, the way a shell splits them
  nt = 0; tok = ""; have = 0; q = ""
  for (i = 1; i <= m; i++) {
    c = cm[i]
    if (q == "\047") { if (c == "\047") q = ""; else tok = tok c; continue }
    if (q == "\"") {
      if (c == "\"") q = ""
      else if (c == "\\") {
        d = cm[i + 1]
        if (d == "\"" || d == "\\" || d == "$" || d == "`") { tok = tok d; i++ }
        else if (d == "\n") i++
        else tok = tok c
      } else tok = tok c
      continue
    }
    if (c == "\047" || c == "\"") { q = c; have = 1 }
    else if (c == "\\") { i++; if (cm[i] != "\n") { tok = tok cm[i]; have = 1 } }
    else if (c == " " || c == "\t" || c == "\r") word()
    else if (c == "\n" || c == ";" || c == "|" || c == "(" || c == ")" || c == "`") op()
    else if (c == "&") {
      if (tok ~ /[<>]$/ || cm[i + 1] == ">") { tok = tok c; have = 1 } else op()
    }
    else if (c == "#" && !have) { while (i < m && cm[i + 1] != "\n") i++ }
    else { tok = tok c; have = 1 }
  }
  if (q != "") { print "UNREADABLE"; exit }
  word()
  # find git ... push, then read its arguments
  state = "start"; skip = 0
  for (k = 1; k <= nt; k++) {
    t = toks[k]
    if (t == "\003") { state = "start"; skip = 0; continue }
    if (skip) { skip = 0; continue }
    if (state == "start") {
      if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || t ~ /^-/) continue
      if (t ~ /^(env|command|sudo|nohup|time|exec|builtin|nice|then|do|else|if|elif|while|until|!|\{)$/) continue
      b = t; sub(/.*\//, "", b); sub(/\.(exe|EXE)$/, "", b)
      state = (b == "git") ? "git" : "other"
    } else if (state == "git") {
      if (t ~ /^(-C|-c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix)$/) skip = 1
      else if (t ~ /^-/) ;
      else if (t == "push") state = "push"
      else state = "other"
    } else if (state == "push") {
      if (t == "--force") { print "REFUSE:git push --force"; exit }
      if (t ~ /^--(force-with-lease(=.*)?|force-if-includes|no-.*)$/ || t == "--" || t ~ /^--.*=/) continue
      if (t ~ /^(-o|--push-option|--repo|--receive-pack|--exec)$/) { skip = 1; continue }
      if (t ~ /^--m/ && length(t) >= 4 && index("--mirror", t) == 1) { print "REFUSE:git push --mirror"; exit }
      if (t ~ /^--/) continue
      if (t ~ /^-/) {
        for (j = 2; j <= length(t); j++) {
          f = substr(t, j, 1)
          if (f == "f") { print "REFUSE:git push -f"; exit }
          if (f == "o") break
        }
        continue
      }
      if (t ~ /^\+/) { print "REFUSE:a git push of a +refspec (" t ")"; exit }
    }
  }
  print "OK"
}' 2>/dev/null)

case $out in
  OK) exit 0 ;;
  REFUSE:*) refuse "${out#REFUSE:}" ;;
esac

# The command could not be read: decide from the raw text, refusing any push with a force sign.
t=${input//--force-with-lease/}; t=${t//--force-if-includes/}
case $t in *--force*|*--mirror*|*+*) refuse "a git push I couldn't fully read, with a force sign in it," ;; esac
[[ $t =~ (^|[^[:alnum:]-])-[[:alpha:]]*f ]] && refuse "a git push I couldn't fully read, with a force sign in it,"
exit 0
