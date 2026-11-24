#!/usr/bin/env bash
# no-force-push.sh -- a Claude Code PreToolUse hook (matcher "Bash"), added to ~/.claude/settings.json
# by make-it's installers (install.sh, install.ps1).
#
# Refuses a git push that can overwrite what is online without looking first: --force, -f (also
# inside a cluster such as -uf), --mirror, and a +refspec (+main, +HEAD:main). Lets through
# --force-with-lease and --force-if-includes, which refuse when the online copy changed.
# Finds the push wherever git starts a command: after ; && || | ( ) ` or a new line, after
# VAR=value, behind env / command / sudo / doas / nice / nohup / time / exec / builtin (with any
# options they take, such as sudo -u root or nice -n 5, and as /usr/bin/env), as /usr/bin/git or
# git.exe, with git's own options first (git -C dir push, git -c k=v push), and with the flags
# before or after the remote. Also behind xargs / timeout, in the string a shell is given (bash -c,
# sh -c, a here-doc or here-string fed to sh / bash / zsh / dash / ksh or piped on), in what eval is
# given, and inside $(...) or backticks, in double quotes too.
#
# Text that is only text is not refused: words inside quotes are one word, and the text of a
# here-doc is data (only the $(...) and backticks in a here-doc whose end word is not quoted are
# read, as the shell runs them). So a commit message, a note, a card or a search that mentions a
# force push goes through, and so does writing one into a file.
#
# A guard against mistakes, not against hiding a push. It does NOT see: a script file (written by
# this command or an earlier one) that is then run, git aliases, a force refspec set in git config
# (remote.*.push, remote.*.mirror), flags that come out of a $VARIABLE or $(...), a command whose
# name is made by $(...) or backticks (as in $(echo git) push -f), a here-doc that reaches a shell
# by another road (eval "$(cat <<EOF ...)", ssh, python), a case pattern inside $(...), or
# quote-splitting such as pu''sh.
#
# Known over-blocking, only when the command can't be read and the raw-text rule decides (a push
# plus a + or some -<letters>f flag such as rm -rf anywhere in the command): a command over 64 KB;
# a here-doc with no end line; a here-doc on a line that names a shell, or a word given to a shell,
# with an apostrophe in its text. The way out: run the push as its own command.
#
# Failure mode: fails OPEN on its own errors only for a command that is not a force push. When it
# can't read the command (no "command" field, an unterminated string, quote, $(...) or here-doc,
# awk missing or failing), or the input is longer than 64 KB, it reads the command's raw text
# instead (from its "command" key on, or the whole input when there is none): a push with any force
# sign in it is refused, and the message says so and gives the way out; anything else is let
# through. The installers also set "onFailure": "block" (Claude Code
# 2.1.295 and later), so a hook that can't start or crashes blocks the call instead of letting it
# through. If the hook file is gone (make-it removed), the command the installers write runs
# nothing and lets every command through: removing make-it turns the guard off, never the shell.
#
# Exit 0 = allowed. Exit 2 = refused (Claude Code gives Claude the message and doesn't run it).
# The reading is done in awk: bash's own string loops slow down with the square of a long command.

export LC_ALL=C

refuse() {
  printf '%s\n' "Blocked by make-it: $1 can overwrite work on GitHub that nobody here has seen. Use git push --force-with-lease instead: it refuses if the online copy changed. A plain force push is for a person to run by hand.${2:-}" >&2
  exit 2
}

input=$(cat) || input=""
case $input in *push*) ;; *) exit 0 ;; esac

out=""
[ "${#input}" -le 65536 ] && out=$(printf '%s' "$input" | awk '
function ws(c) { return c == " " || c == "\t" || c == "\n" || c == "\r" }
function word(L) { if (HV[L]) T[L, ++NT[L]] = TK[L]; TK[L] = ""; HV[L] = 0 }
function op(L, c) { word(L); T[L, ++NT[L]] = "\003" c }
function base(t) { sub(/.*\//, "", t); sub(/\.(exe|EXE)$/, "", t); return t }
function isshell(b) { return b ~ /^(sh|bash|zsh|dash|ksh)$/ }
# text that a shell will run as commands (a bash -c string, what eval is given): read later, like the command
function script(t,   n, a, k) { n = split(t, a, ""); SB[++NS] = M + 1; for (k = 1; k <= n; k++) cm[++M] = a[k]; SE[NS] = M }
# Splits cm[i..m] into the words and command boundaries of list L, the way a shell does, up to the
# closing term (")" or "`"; "" = to the end). Returns where it stopped. Each $(...) and `...` gets a
# list of its own; the text of a here-doc is stepped over (see heredocs).
function lex(i, term, L,   c, d, q, ansi, par, ar, dl, qd, st) {
  q = ""; par = 0; ar = (term == ")" && cm[i] == "(")      # ar: inside ((...)), where << is arithmetic
  for (; i <= m; i++) {
    c = cm[i]
    if (q == "\047") {
      if (c == "\047") q = ""; else if (ansi && c == "\\") TK[L] = TK[L] cm[++i]; else TK[L] = TK[L] c
      continue
    }
    if (q == "\"") {
      if (c == "\"") q = ""
      else if (c == "\\") {
        d = cm[i + 1]
        if (d == "\"" || d == "\\" || d == "$" || d == "`") { TK[L] = TK[L] d; i++ }
        else if (d == "\n") i++
        else TK[L] = TK[L] c
      }
      else if (c == "$" && cm[i + 1] == "(") i = lex(i + 2, ")", ++NL)
      else if (c == "`") i = lex(i + 1, "`", ++NL)
      else TK[L] = TK[L] c
      continue
    }
    if (c == term && term != "" && !(c == ")" && par > 0)) { word(L); return i }
    if (c == "\047" || c == "\"") { q = c; ansi = 0; HV[L] = 1 }
    else if (c == "$" && (cm[i + 1] == "\047" || cm[i + 1] == "\"")) { q = cm[++i]; ansi = (q == "\047"); HV[L] = 1 }
    else if (c == "$" && cm[i + 1] == "(") { i = lex(i + 2, ")", ++NL); TK[L] = TK[L] "$()"; HV[L] = 1 }
    else if (c == "`") { i = lex(i + 1, "`", ++NL); TK[L] = TK[L] "$()"; HV[L] = 1 }
    else if (c == "\\") { i++; if (cm[i] != "\n") { TK[L] = TK[L] cm[i]; HV[L] = 1 } }
    else if (c == " " || c == "\t" || c == "\r") word(L)
    else if (c == "<" && cm[i + 1] == "<" && !ar) {
      word(L); i += 2
      if (cm[i] == "<") continue                      # a here-string: the next word is read as usual
      st = 0; if (cm[i] == "-") { st = 1; i++ }
      while (cm[i] == " " || cm[i] == "\t") i++
      dl = ""; qd = 0                                 # the word that ends the here-doc, its quotes taken off
      for (; i <= m; i++) {
        d = cm[i]
        if (d == "\047" || d == "\"") { qd = 1; for (i++; i <= m && cm[i] != d; i++) dl = dl cm[i] }
        else if (d == "\\") { qd = 1; dl = dl cm[++i] }
        else if (ws(d) || d == ";" || d == "|" || d == "&" || d == "(" || d == ")" || d == "<" || d == ">") break
        else dl = dl d
      }
      i--
      HD[L, ++HN[L]] = dl; HQ[L, HN[L]] = qd; HS[L, HN[L]] = st
    }
    else if (c == "\n") { if (HN[L]) i = heredocs(i, L); op(L, c) }
    else if (c == ";" || c == "|") op(L, c)
    else if (c == "(") { par++; if (cm[i + 1] == "(") ar = 1; op(L, c) }
    else if (c == ")") { if (par > 0) par--; if (cm[i + 1] == ")") ar = 0; op(L, c) }
    else if (c == "&") {
      if (TK[L] ~ /[<>]$/ || cm[i + 1] == ">") { TK[L] = TK[L] c; HV[L] = 1 } else op(L, c)
    }
    else if (c == "#" && !HV[L]) { while (i < m && cm[i + 1] != "\n") i++ }
    else { TK[L] = TK[L] c; HV[L] = 1 }
  }
  if (q != "" || term != "") bad = 1
  word(L)
  return i
}
# The here-docs opened on the line that ends at cm[i]: steps over their text and returns where the
# last one ends. The text is data, like a quoted string, with two exceptions that do run: when the
# line names a shell or ends in a pipe, the text is a script (read later); and when the end word is
# not quoted, the $(...) and `...` in the text are commands.
function heredocs(i, L,   k, h, scr, j, e, x, y, n, bs, sm) {
  word(L)
  scr = (T[L, NT[L]] == "\003|")
  for (k = NT[L]; k >= 1 && T[L, k] != "\003\n"; k--) if (isshell(base(T[L, k]))) scr = 1
  j = i + 1; e = i
  for (h = 1; h <= HN[L]; h++) {
    n = length(HD[L, h]); bs = j
    for (;;) {
      if (j > m) { e = j; bad = 1; break }
      x = j; if (HS[L, h]) while (cm[x] == "\t") x++
      for (y = 1; y <= n && cm[x + y - 1] == substr(HD[L, h], y, 1); y++) ;
      for (e = j; e <= m && cm[e] != "\n"; e++) ;
      if (y > n && x + n == e) break
      j = e + 1
    }
    if (scr) { SB[++NS] = bs; SE[NS] = j - 1 }
    else if (!HQ[L, h]) {
      sm = m; m = j - 1
      for (x = bs; x <= m; x++) {
        if (cm[x] == "\\") x++
        else if (cm[x] == "$" && cm[x + 1] == "(") x = lex(x + 2, ")", ++NL)
        else if (cm[x] == "`") x = lex(x + 1, "`", ++NL)
      }
      m = sm
    }
    j = e + 1
  }
  HN[L] = 0
  return e
}
# finds git ... push in list L and reads its arguments; hands on what a shell or eval is given
function judge(L,   k, t, b, state, skip, ev, j, f) {
  state = "start"; skip = 0; ev = ""
  for (k = 1; k <= NT[L] + 1; k++) {
    t = (k > NT[L]) ? "\003" : T[L, k]
    if (substr(t, 1, 1) == "\003") { if (ev != "") script(ev); ev = ""; state = "start"; skip = 0; continue }
    if (skip) { skip = 0; continue }
    if (state == "start" || state == "wrap") {
      if (state == "start") {
        if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || t ~ /^-/) continue
        if (t ~ /^(then|do|else|if|elif|while|until|!|\{)$/) continue
      }
      # behind a wrapper: its options and their values, every word up to the git or shell it runs
      b = base(t)
      if (b == "git") state = "git"
      else if (isshell(b)) state = "shell"
      else if (b == "eval") state = "eval"
      else if (state == "start") state = (b ~ /^(env|command|sudo|doas|nohup|time|exec|builtin|nice|xargs|timeout)$/) ? "wrap" : "other"
    } else if (state == "shell") script(t)
    else if (state == "eval") ev = ev " " t
    else if (state == "git") {
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
}
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
  M = 0; closed = 0
  for (i++; i <= n; i++) {
    c = ch[i]
    if (c == "\"") { closed = 1; break }
    if (c == "\\") {
      e = ch[++i]
      if (e == "n") c = "\n"; else if (e == "t") c = "\t"; else if (e == "r") c = "\r"
      else if (e == "b" || e == "f") c = " "; else if (e == "u") { c = "?"; i += 4 } else c = e
    }
    cm[++M] = c
  }
  if (!closed) { print "UNREADABLE"; exit }
  # the command first, then every script found in it (a judge that refuses prints and exits)
  NL = 0; NS = 0; l = 0; k = 0; m = M
  lex(1, "", ++NL)
  while (l < NL || k < NS) {
    while (l < NL) judge(++l)
    if (k < NS) { k++; m = SE[k]; lex(SB[k], "", ++NL) }
  }
  print (bad ? "UNREADABLE" : "OK")
}' 2>/dev/null)

case $out in
  OK) exit 0 ;;
  REFUSE:*) refuse "${out#REFUSE:}" ;;
esac

# The command could not be read (or is too long to read quickly): decide from its raw text -- from
# its "command" key to the next key Claude Code sends, or the whole input -- refusing any push with
# a force sign. awk does it (bash's own replace is slow on megabytes); bash does it if awk can't.
unread=" I refuse these to be safe: if the push in this command is a plain one, run it as its own command."
v=$(printf '%s' "$input" | awk 'BEGIN { RS = "\001" } { s = s $0 } END {
  p = index(s, "\"command\"")
  if (p) {
    s = substr(s, p + 9); q = 0; split("\"description\" \"timeout\" \"run_in_background\"", ks, " ")
    for (k in ks) { x = index(s, ks[k]); if (x && (!q || x < q)) q = x }
    if (q) s = substr(s, 1, q - 1)
  }
  if (!index(s, "push")) { print "OK"; exit }
  gsub(/--force-with-lease|--force-if-includes/, "", s)
  if (index(s, "--force") || index(s, "--mirror") || index(s, "+") || s ~ /(^|[^[:alnum:]-])-[[:alpha:]]*f/) print "FORCE"
  else print "OK" }' 2>/dev/null)
case $v in
  OK) exit 0 ;;
  FORCE) refuse "a git push I couldn't fully read, with a force sign in it," "$unread" ;;
esac
t=${input//--force-with-lease/}; t=${t//--force-if-includes/}
case $t in *--force*|*--mirror*|*+*) refuse "a git push I couldn't fully read, with a force sign in it," "$unread" ;; esac
[[ $t =~ (^|[^[:alnum:]-])-[[:alpha:]]*f ]] && refuse "a git push I couldn't fully read, with a force sign in it," "$unread"
exit 0
