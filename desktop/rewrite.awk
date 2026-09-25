# rewrite.awk -- portable (BSD/GNU awk) replacement for the import/mention rewriter.
# Invoked as: awk -v basenames="a.md b.md" -f rewrite.awk src > dst
#
# Matches @?~/.claude/<path> (optional leading @ = Claude Code import syntax).
# A trailing sentence period is never part of the path; backticks, quotes,
# commas and parens already fall outside the allowed path character class so
# they terminate the match naturally.
#
#   @~/.claude/<path>/<file>  (import, @ present)
#     -> references/<file>            if <file>'s basename is in the whitelist
#     -> left completely unchanged    otherwise (so --check flags the gap)
#
#   ~/.claude/<path>/<file>   (plain mention, no @)
#     -> references/<file>            if <file>'s basename is in the whitelist
#     -> claude-code:<path>/<file>    otherwise
#
#   ~/.claude/<path>/         (plain mention of a folder, trailing slash)
#     -> claude-code:<path>/          always (folders are never "copied")

BEGIN {
  n = split(basenames, arr, " ")
  for (i = 1; i <= n; i++) whitelist[arr[i]] = 1
}
{
  remaining = $0
  result = ""
  while (match(remaining, /@?~\/\.claude\/[A-Za-z0-9_.\/-]+/)) {
    pre = substr(remaining, 1, RSTART - 1)
    matched = substr(remaining, RSTART, RLENGTH)
    tail = substr(remaining, RSTART + RLENGTH)

    isImport = (substr(matched, 1, 1) == "@")
    pathpart = isImport ? substr(matched, 2) : matched
    rest = substr(pathpart, 11)  # strip literal "~/.claude/" (10 chars)

    carry = ""
    if (substr(rest, length(rest), 1) == ".") {
      rest = substr(rest, 1, length(rest) - 1)
      matched = substr(matched, 1, length(matched) - 1)
      carry = "."
    }

    isFolder = (substr(rest, length(rest), 1) == "/")

    if (isFolder) {
      repl = isImport ? matched : ("claude-code:" rest)
    } else {
      nseg = split(rest, segs, "/")
      base = segs[nseg]
      if (base in whitelist) {
        repl = "references/" base
      } else if (isImport) {
        repl = matched
      } else {
        repl = "claude-code:" rest
      }
    }

    result = result pre repl
    remaining = carry tail
  }
  print result remaining
}
