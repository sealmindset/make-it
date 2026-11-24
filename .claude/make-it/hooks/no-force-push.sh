#!/usr/bin/env bash
# no-force-push.sh -- a Claude Code PreToolUse hook (matcher "Bash"), added to ~/.claude/settings.json
# by make-it's installers (install.sh, install.ps1).
#
# Refuses a git push that can overwrite what is online without looking first: --force, -f (also
# inside a cluster such as -uf or -4f), --mirror, every shortening of the two that git takes or
# might take (--m, --mi ... and --fo, --for, --forc), a +refspec (+main, +HEAD:main), and a {a,b}
# group in a flag or a +refspec. Lets through --force-with-lease and --force-if-includes, which
# refuse when the online copy changed.
# Finds the push wherever git starts a command: after ; && || | ( ) ` or a new line, after
# VAR=value or a redirect (2>/dev/null git push -f), as /usr/bin/git or git.exe, with git's own
# options first (git -C dir push, git -c k=v push), and with the flags before or after the remote.
# Also behind ANY other command that is handed a git push as its arguments (env, sudo, time, xargs,
# timeout, ssh, docker exec, find -exec, ...), in the string a shell is given (bash -c, sh -c, a
# here-string, text piped into sh / bash / zsh / dash / ksh), in what eval, source, . and trap are
# given, in a function's body, and inside $(...), <(...) or backticks, in double quotes too. A git
# push whose arguments come from xargs is refused whatever they are, and so is one behind
# git -c alias... / -c remote.*.push / .mirror.
#
# Text that is only text is not refused: words inside quotes are one word, so a commit message, a
# note or a search that mentions a force push goes through. The text of a here-doc is data too
# (only the $(...) and backticks in a here-doc whose end word is not quoted are read, as the shell
# runs them), but ONLY in a command that cannot run it: every command in it is one of cat, tee,
# echo, printf, cd, mkdir, ls, rm, touch, true, false, pwd, date, wc, head, tail, grep, test, [,
# gh pr / issue / run / api / release, or git add / commit / push / status / diff / log / show /
# fetch / pull / checkout / switch / branch / rev-parse / stash / tag / restore / worktree, with no
# VAR=value in front, no git -c / --config-env, and no option that begins --e, --rec, --u or --o
# (--exec, --receive-pack, --upload-pack, --ext-diff, --output and every shortening git takes for
# them: they run a program or write a file). In any other command (a shell, a script, ./file,
# source, eval, python, a function, a variable as a command ...) the here-doc text is read as
# commands, as this guard always did. So writing a card or a note that mentions a force push and
# then pushing normally goes through; writing a script and running it does not.
# One more kind of text: a here-doc that is only an argument, "$(cat <<'EOF' ... )" in double
# quotes, handed to a command that is not a shell, eval, ssh, sudo, env, xargs or an option such as
# -c / -e (git commit -m "$(cat ...)", gh pr create --body "$(cat ...)", a script with a note). It
# is data when the command has no git push in it and nothing that could run it (no shell, eval,
# pipe, ./file or $variable as a command); otherwise it is read like any other here-doc.
#
# A guard against mistakes, not against hiding a push. It does NOT see: a script file written by an
# EARLIER command, or by this one with echo / printf, and then run; text an interpreter runs
# (python -c, perl -e, awk, make, node -e) when it is given as a quoted string (in a here-doc, see
# (3) below), also through a clustered or unusual option (perl -E, perl -le, python3 -Ic, awk
# "$(cat ...)"); a tool that takes a whole command as one string (parallel "..."); a gh alias
# set and used in the same command (gh alias set p "..."; gh p); a whole git push given as ONE quoted string to a command that is not a shell (ssh or
# docker with '...', env -S, su -c); git aliases and a force refspec already set in git config
# (remote.*.push, remote.*.mirror), also when this command sets them with git config; a hook folder
# with another name than hooks or .husky, a link that leads into one, or a program on the PATH,
# that this command overwrites; flags or a whole command that come out of a $VARIABLE, "$@" or
# $(...) (as in $(echo git) push -f, or F=-f; git push $F); the words git or push made by braces
# ({git,} push -f, git {push,} -f); and the word push split by quotes, a backslash, braces or
# $(...) (pu''sh, pu\sh, pu{sh,}).
#
# Known over-blocking. (1) On purpose: a git push with a force flag written out as bare words
# after another command (echo git push -f); xargs git push; a {a,b} group with a - or + in a
# push's arguments. (2) When the command can't be read and the raw-text rule decides (a push plus
# a +, --fo..., --m... or some -<letters>f flag such as rm -rf anywhere in the command): a command
# over 64 KB; a quote, $(...) or here-doc that never closes; $'...' with a backslash in it; a
# here-doc whose end word is not a plain word (or sits against other text, as in cat<<EOF), that
# has a line beginning with its end word or (when the end word is not quoted, or inside $(...))
# ending in a backslash, or that comes with a word holding .git, hooks, husky or config (in any
# case), or with a redirect target, tee or cd argument that is not a plain name (it holds ? * [ {
# $ ~ or ..; ~/plain is fine); << inside ${...} or x[...]; case inside $(...). When no git push
# was found in such a command, the message says so. (3) A here-doc in a command that is not on the list
# above (python3 - <<EOF, bash x.sh <<EOF, a cp or VAR=1 anywhere) is read as commands: it is
# refused when a line of it reads as a force push, and (2) applies when it can't be read (an
# apostrophe) or has the word push in it. The way out, always: run the push as its own command.
#
# Failure mode: fails OPEN on its own errors only for a command that is not a force push. When it
# can't read the command (see (2), and no "command" field, awk missing or failing), or the input
# is longer than 64 KB, it reads the command's raw text instead (from its "command" key on, or the
# whole input when there is none), with quotes and backslashes taken out: a push with any force
# sign in it is refused, and the message says so and gives the way out; anything else is let
# through. The installers also set "onFailure": "block" (Claude Code 2.1.295 and later), so a hook
# that can't start or crashes blocks the call instead of letting it through.
# If the hook file is gone (make-it removed), the command the installers write runs nothing and
# lets every command through: removing make-it turns the guard off, never the shell.
#
# Exit 0 = allowed. Exit 2 = refused (Claude Code gives Claude the message and doesn't run it).
# The reading is done in awk: bash's own string loops slow down with the square of a long command.

export LC_ALL=C

nopush() {
  printf '%s\n' "Blocked by make-it: this command has the word push and a force-like sign (--force, a +, or a flag such as -rf) inside text I couldn't fully read, so I refuse it to be safe. I found no git push in it. Run its parts as separate commands (the commit on its own, for example)." >&2
  exit 2
}
refuse() {
  printf '%s\n' "Blocked by make-it: $1 can overwrite work on GitHub that nobody here has seen. Use git push --force-with-lease instead: it refuses if the online copy changed. A plain force push is for a person to run by hand.${2:-}" >&2
  exit 2
}

input=$(cat) || input=""
case $input in *push*) ;; *) exit 0 ;; esac

out=""
[ "${#input}" -le 65536 ] && out=$(printf '%s' "$input" | awk '
function ws(c) { return c == " " || c == "\t" || c == "\n" || c == "\r" }
function word(L) { if (HV[L]) { T[L, ++NT[L]] = TK[L]; TS[L, NT[L]] = SU[L] } TK[L] = ""; HV[L] = 0; SU[L] = 0 }
function op(L, c) { word(L); T[L, ++NT[L]] = "\003" c }
function base(t) { sub(/.*\//, "", t); sub(/\.(exe|EXE)$/, "", t); return t }
function isshell(b) { return b ~ /^(sh|bash|zsh|dash|ksh)$/ }
# the commands that cannot run a file or the text they are given (with git and gh, see judge)
function calm(t) { return t ~ /^(cat|tee|echo|printf|cd|mkdir|ls|rm|touch|true|false|pwd|date|wc|head|tail|grep|test|\[|:|if|then|else|elif|fi|for|while|until|do|done|!|\{|\})$/ }
# text that a shell will run as commands (a bash -c string, what eval is given): read later, like the command
function script(t,   n, a, k) { n = split(t, a, ""); SB[++NS] = M + 1; for (k = 1; k <= n; k++) cm[++M] = a[k]; SE[NS] = M }
# Splits cm[i..m] into the words and command boundaries of list L, the way a shell does, up to the
# closing term (")" or "`"; "" = to the end). Returns where it stopped. Each $(...), <(...) and
# `...` gets a list of its own and leaves nothing in the word it sits in (it may come out empty).
# The text of a here-doc is stepped over and kept for later (see heredocs). Anything it is not sure
# of sets bad: the command is then unreadable and the raw-text rule decides.
function lex(i, term, L,   c, d, q, ansi, par, dl, qd, st, j) {
  q = ""; par = 0
  for (; i <= m; i++) {
    c = cm[i]
    if (q == "\047") {
      if (c == "\047") q = ""
      else if (ansi && c == "\\") { bad = 1; TK[L] = TK[L] cm[++i] }
      else TK[L] = TK[L] c
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
      else if (c == "$" && cm[i + 1] == "(") { j = ++NL; DQP[j] = L; DQK[j] = NT[L] + 1; i = lex(i + 2, ")", j); SU[L] = 1 }
      else if (c == "`") { i = lex(i + 1, "`", ++NL); SU[L] = 1 }
      else { if (c == "{" && cm[i - 1] == "$") br++; else if (c == "}" && br > 0) br--; TK[L] = TK[L] c }
      continue
    }
    if (c == term && term != "" && !(c == ")" && par > 0)) {
      word(L)
      for (j = 1; j <= NT[L]; j++) if (T[L, j] == "case") bad = 1    # a case arm may have closed it early
      return i
    }
    if (c == "\047" || c == "\"") { q = c; ansi = 0; HV[L] = 1 }
    else if (c == "$" && (cm[i + 1] == "\047" || cm[i + 1] == "\"")) { q = cm[++i]; ansi = (q == "\047"); HV[L] = 1 }
    else if (c == "$" && cm[i + 1] == "(") { i = lex(i + 2, ")", ++NL); HV[L] = 1; SU[L] = 1 }
    else if (c == "`") { i = lex(i + 1, "`", ++NL); HV[L] = 1; SU[L] = 1 }
    else if (c == "\\") { i++; if (cm[i] != "\n") { TK[L] = TK[L] cm[i]; HV[L] = 1 } }
    else if (c == " " || c == "\t" || c == "\r") word(L)
    else if (c == "<" && cm[i + 1] == "<") {
      if (cm[i + 2] == "<") { TK[L] = TK[L] "<<<"; HV[L] = 1; i += 2; continue }   # a here-string
      # A here-doc only where a shell is sure to see one: a word of its own (or after a number), not
      # inside ${...} or x[...]. Inside ((...)) and [[ ]] it is read as one too: those commands are
      # not calm, so the lines it takes are read as commands all the same.
      if (br > 0 || sq > 0 || TK[L] !~ /^[0-9]*$/) bad = 1
      word(L); i += 2
      st = 0; if (cm[i] == "-") { st = 1; i++ }
      while (cm[i] == " " || cm[i] == "\t") i++
      # its end word: a plain word, bare or in one pair of quotes or after one backslash
      dl = ""; qd = 0; d = cm[i]
      if (d == "\047" || d == "\"") { qd = 1; for (i++; i <= m && cm[i] != d; i++) dl = dl cm[i]; i++ }
      else { if (d == "\\") { qd = 1; i++ } for (; i <= m && cm[i] ~ /[A-Za-z0-9_]/; i++) dl = dl cm[i] }
      d = cm[i]
      if (dl !~ /^[A-Za-z0-9_]+$/) bad = 1
      if (i <= m && d != " " && d != "\t" && d != "\n" && d != ";" && d != "|" && d != "&" && d != "(" && d != ")" && d != "<" && d != ">") bad = 1
      i--
      HD[L, ++HN[L]] = dl; HQ[L, HN[L]] = qd; HS[L, HN[L]] = st
    }
    else if (c == "\n") { if (HN[L]) i = heredocs(i, L, term != ""); op(L, c) }
    else if (c == ";" || c == "|") op(L, c)
    else if (c == "(") {
      if (TK[L] ~ /[<>]$/) { i = lex(i + 1, ")", ++NL); HV[L] = 1; SU[L] = 1 }
      else { par++; op(L, c) }
    }
    else if (c == ")") { if (par > 0) par--; op(L, c) }
    else if (c == "&") {
      if (TK[L] ~ /[<>]$/ || cm[i + 1] == ">") { TK[L] = TK[L] c; HV[L] = 1 } else op(L, c)
    }
    else if (c == "#" && !HV[L]) { while (i < m && cm[i + 1] != "\n") i++ }
    else {
      if (c == "{" && cm[i - 1] == "$") br++; else if (c == "}" && br > 0) br--
      else if (c == "[" && HV[L]) sq++; else if (c == "]" && sq > 0) sq--
      TK[L] = TK[L] c; HV[L] = 1
    }
  }
  if (q != "" || term != "") bad = 1
  word(L)
  return i
}
# The here-docs opened on the line that ends at cm[i]: steps over their text and returns where the
# last one ends. The text is kept (PB, PE): it stays data only if the whole command is calm (see
# the END block); otherwise it is read as commands. When the end word is not quoted, the $(...) and
# `...` in the text are commands either way.
function heredocs(i, L, nested,   h, j, e, x, y, n, bs, sm) {
  j = i + 1; e = i
  for (h = 1; h <= HN[L]; h++) {
    n = length(HD[L, h]); bs = j
    for (;;) {
      if (j > m) { e = j; bad = 1; break }
      x = j; if (HS[L, h]) while (cm[x] == "\t") x++
      for (y = 1; y <= n && cm[x + y - 1] == substr(HD[L, h], y, 1); y++) ;
      for (e = j; e <= m && cm[e] != "\n"; e++) ;
      if (y > n && x + n == e) break
      if (y > n) bad = 1                                             # begins with the end word: EOF) ends it in some shells
      if ((nested || !HQ[L, h]) && e > j && cm[e - 1] == "\\") bad = 1   # the shell joins this line to the next
      j = e + 1
    }
    PB[++NP] = bs; PE[NP] = j - 1; PL[NP] = L; PQ[NP] = HQ[L, h]
    if (!HQ[L, h]) {
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
function haspush(a, b,   x) {
  for (x = a; x <= b - 3; x++) if (cm[x] == "p" && cm[x + 1] == "u" && cm[x + 2] == "s" && cm[x + 3] == "h") return 1
  return 0
}
function no(why) { print "REFUSE:" why; exit }
# A here-doc that is only the text of an argument: "$(cat <<\047EOF\047 ... )" in double quotes, handed
# to a command as one of its arguments (not to a shell, eval or an option that runs text). Main
# reads such text as a quoted word. It stays data unless the command has a git push in it or
# something that could run it (RUNNER: a shell, eval, a pipe, a ./file or $variable as a command).
function argtext(p,   L, k, n) {
  L = PL[p]
  if (!PQ[p] || !DQP[L] || !LENT[DQP[L], DQK[L]]) return 0
  n = 0
  for (k = 1; k <= NT[L]; k++) if (substr(T[L, k], 1, 1) != "\003") { if (T[L, k] != "cat") return 0; n++ }
  return n == 1
}
function strict(p) { if (haspush(PB[p], PE[p])) bad = 1; SB[++NS] = PB[p]; SE[NS] = PE[p] }
# Finds git ... push in list L and reads its arguments; hands on what a shell or eval is given.
# Every command may be handing a git push to something else, so git is looked for in its arguments
# too. Also notes whether the command is calm (CALM) and names a hook or config file (HOOKY).
function judge(L,   k, t, b, state, skip, ev, j, f, p0, piped, first, xa, cw, pv, prev, lt) {
  state = "start"; skip = 0; ev = ""; p0 = 1; piped = 0; xa = 0; cw = ""; prev = ""
  for (k = 1; k <= NT[L] + 1; k++) {
    t = (k > NT[L]) ? "\003" : T[L, k]
    if (substr(t, 1, 1) == "\003") {
      if (ev != "") script(ev)
      if (xa && state == "git") no("a git command that takes its arguments from xargs")
      ev = ""; state = "start"; skip = 0; xa = 0; cw = ""; prev = ""
      if (t == "\003|") { piped = 1; RUNNER = 1 } else { piped = 0; p0 = k + 1 }
      continue
    }
    pv = prev; prev = t; lt = tolower(t)
    # a file name that may be a git hook or config (any case), and a place this command writes to or
    # moves into (a redirect, tee, cd) whose name is not plain: with a here-doc, too close to call
    if (lt ~ /\.git(\/|$)|hooks|husky|config/) HOOKY = 1
    if ((pv ~ /^[0-9&]*>>?$/ || t ~ /^[0-9&]*>>?[^&>]/ || cw == "cd" || cw == "tee") && (t == "" || TS[L, k] || t ~ /[?*\[{$~]|\.\./ && t !~ /^~\/[^?*\[{$~]*$/ || (cw == "cd" && t == "-"))) HOOKY = 1
    # an option that can run a program, in any shortening: --exec --receive-pack --upload-pack --ext-diff --output
    if (t ~ /^--(e|rec|u|o)/) CALM = 0
    if ((state == "other" || state == "git" || state == "push" || state == "gh") && pv !~ /^(-c|-e|-S|-x|--eval|--command|--exec|--run)$/ && cw !~ /^(ssh|su|sudo|doas|docker|kubectl|env|xargs|watch|nohup|timeout|command|exec|time)$/) LENT[L, k] = 1
    if (skip) { skip = 0; continue }
    if (t == "") { if (state == "start") { CALM = 0; RUNNER = 1 } continue }                               # what a $(...) left: maybe nothing
    if (state == "start" || state == "other") {
      first = (state == "start")
      if (first) {
        if (t ~ /^[A-Za-z_][A-Za-z0-9_]*\+?=/ || t ~ /^-/) { CALM = 0; continue }
        if (t ~ /^(then|do|else|if|elif|while|until|!|\{)$/) continue
        if (!calm(t) && t != "git" && t != "gh") CALM = 0
        cw = base(t); if (t ~ /^\$/ || t ~ /\//) RUNNER = 1
      }
      b = t; sub(/[<>].*$/, "", b); b = base(b); if (first) sub(/^[={]/, "", b)
      if (b == "xargs") xa = 1
      if (b == "git") { state = "git"; if (!first || t != "git") CALM = 0 }
      else if (isshell(b) || (first && (b == "." || b == "source" || b == "trap"))) {
        state = "shell"; CALM = 0; RUNNER = 1
        if (piped) for (j = p0; j < k; j++) if (substr(T[L, j], 1, 1) != "\003") script(T[L, j])
      }
      else if (b == "eval") { state = "eval"; CALM = 0; RUNNER = 1 }
      else if (first && t == "gh") state = "gh"
      else state = "other"
    }
    else if (state == "gh") { if (t !~ /^(pr|issue|run|api|release)$/) CALM = 0; state = "other" }
    else if (state == "shell") script(t)
    else if (state == "eval") ev = ev " " t
    else if (state == "git") {
      if (t == "-c" && (T[L, k + 1] ~ /^alias\..*push/ || T[L, k + 1] ~ /^remote\..*\.(push|mirror)=/)) no("a git push set up with git -c (" T[L, k + 1] ")")
      if (t ~ /^(-C|-c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix|--attr-source)$/) { skip = 1; if (t != "-C") CALM = 0 }
      else if (t ~ /^-/) { if (t != "--no-pager") CALM = 0 }
      else if (t == "push") { state = "push"; SAWPUSH = 1; if (xa) no("a git push that takes its arguments from xargs") }
      else {
        if (t !~ /^(add|commit|status|diff|log|show|fetch|pull|checkout|switch|branch|rev-parse|stash|tag|restore|worktree)$/) CALM = 0
        state = "other"
      }
    } else if (state == "push") {
      if (t ~ /\{[^}]*(,|\.\.)[^}]*\}/ && t ~ /[-+]/) no("a git push with a {a,b} group in a flag or a +refspec (" t ")")
      if (t ~ /^--force(=|$)/ || (length(t) >= 4 && index("--force", t) == 1)) no("git push --force")
      if (t ~ /^--(force-with-lease(=.*)?|force-if-includes|no-.*)$/ || t == "--") continue
      if (t ~ /^--mirror=/ || (length(t) >= 3 && index("--mirror", t) == 1)) no("git push --mirror")
      if (t ~ /^--.*=/) continue
      if (t ~ /^(-o|--push-option|--repo|--receive-pack|--exec)$/) { skip = 1; continue }
      if (t ~ /^--/) continue
      if (t ~ /^-/) {
        for (j = 2; j <= length(t); j++) {
          f = substr(t, j, 1)
          if (f == "f") no("git push -f")
          if (f == "o") break
        }
        continue
      }
      if (t ~ /^\+/) no("a git push of a +refspec (" t ")")
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
  # The command first, then every script found in it (a judge that refuses prints and exits). Last,
  # the here-doc texts: data if every command was calm; if not, read as commands, and too close to
  # call when the text has the word push in it (an interpreter may be the one reading it), except
  # the text of an argument (see argtext); with a hook or config file named, too close to call.
  NL = 0; NS = 0; NP = 0; l = 0; k = 0; pp = 0; CALM = 1; HOOKY = 0; m = M
  lex(1, "", ++NL)
  for (;;) {
    while (l < NL) judge(++l)
    if (k < NS) { k++; m = SE[k]; lex(SB[k], "", ++NL); continue }
    if (pp < NP && HOOKY) bad = 1
    if (pp < NP && !CALM) {
      while (pp < NP) { pp++; if (argtext(pp)) LX[++nlx] = pp; else strict(pp) }
      continue
    }
    if ((SAWPUSH || RUNNER) && lx < nlx) { while (lx < nlx) strict(LX[++lx]); continue }
    break
  }
  print (bad ? (SAWPUSH ? "UNREADABLE" : "UNREADABLE:nopush") : "OK")
}' 2>/dev/null)

case $out in
  OK) exit 0 ;;
  REFUSE:*) refuse "${out#REFUSE:}" ;;
esac

# The command could not be read (or is too long to read quickly): decide from its raw text -- from
# its "command" key to the next key Claude Code sends, or the whole input -- refusing any push with
# a force sign. Quotes and backslashes are taken out first (JSON's \n, \t, \r become spaces), so a
# flag can't hide behind them. awk does it (bash's own replace is slow on megabytes); bash does it
# if awk can't.
unread=" I refuse these to be safe: if the push in this command is a plain one, run it as its own command."
v=$(printf '%s' "$input" | awk 'BEGIN { RS = "\001" } { s = s $0 } END {
  p = index(s, "\"command\"")
  if (p) {
    s = substr(s, p + 9); q = 0; split("\"description\" \"timeout\" \"run_in_background\"", ks, " ")
    for (k in ks) { x = index(s, ks[k]); if (x && (!q || x < q)) q = x }
    if (q) s = substr(s, 1, q - 1)
  }
  if (!index(s, "push")) { print "OK"; exit }
  if (s ~ /\$\047[^\047]*\\/) { print "FORCE"; exit }           # $\047...\047 with a backslash: it can spell any flag
  gsub(/\\\\\\n/, "", s); gsub(/\\[ntr]/, " ", s); gsub(/[\\"\047]/, "", s)
  gsub(/--force-with-lease|--force-if-includes/, "", s)
  if (index(s, "--force") || s ~ /--fo(r(c)?)?([^a-z]|$)/ || index(s, "--mi") || s ~ /--m([^a-z]|$)/ || index(s, "+") || s ~ /(^|[^[:alnum:]-])-[[:alnum:]]*f/) print "FORCE"
  else print "OK" }' 2>/dev/null)
case $v in
  OK) exit 0 ;;
  FORCE) [ "$out" = "UNREADABLE:nopush" ] && nopush; refuse "a git push I couldn't fully read, with a force sign in it," "$unread" ;;
esac
case $input in *"\$'"*) refuse "a git push I couldn't fully read, with a force sign in it," "$unread" ;; esac
t=${input//\\\\\\n/}; t=${t//\\[ntr]/ }; t=${t//[\\\"\']/}
t=${t//--force-with-lease/}; t=${t//--force-if-includes/}
case $t in *--fo*|*--m*|*+*) refuse "a git push I couldn't fully read, with a force sign in it," "$unread" ;; esac
[[ $t =~ (^|[^[:alnum:]-])-[[:alnum:]]*f ]] && refuse "a git push I couldn't fully read, with a force sign in it," "$unread"
exit 0
