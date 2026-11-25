#!/usr/bin/env bash
# release-day.sh -- one release a day, many fixes in it.
#
# WHY THIS EXISTS
#   Every fix used to be its own pull request AND its own release. Each release moved main, so
#   every other open branch had to rebase, and each rebase clashed in CONTENT_MANIFEST because
#   every branch had regenerated it. This builds ONE release out of the pull requests that are
#   ready, and writes the manifest ONCE, here, from the files as released -- so two fixes never
#   clash over it.
#
# WHAT IT DOES
#   1. Reads the facts, never a guess: `sync-prs.py --sort` (GitHub through `gh`, and each card's
#      `reviewed:` line). A pull request goes in only if it is READY: reviewed for the exact
#      commit that is its head now, every check passed, up to date with main.
#   2. Builds one release branch from origin/main in its own worktree and squash-merges each
#      pull request in turn. A clash in CONTENT_MANIFEST alone is not a conflict: the manifest is
#      rewritten at the end. Any other clash stops the run and names the pull request.
#   3. Writes CONTENT_MANIFEST from the merged files and checks it matches them exactly.
#   4. Runs the quick contract tests: the scripts/test-*.sh that changed, or that name a file
#      this release changes, each given QUICK_SECONDS. CI still runs every test on the release
#      pull request; this is the early warning.
#   5. PRINTS the version commit it would make, the commands that open the pull request, and what
#      to do after the release: the close-with-a-note line for each original pull request, and the
#      cards to close.
#
# WHAT IT NEVER DOES BY ITSELF
#   It never picks the version number. It pushes and opens the pull request only with BOTH
#   `--version X.Y.Z` and `--go`. It never merges and never tags: those commands are printed.
#   With `--dry-run` it changes nothing: it builds in a throwaway copy and removes it.
#   When it stops, the release branch it made is removed again; nothing was pushed.
#
# USAGE
#   scripts/release-day.sh [--repo DIR] [--board DIR] [--dry-run] [PR ...]
#   scripts/release-day.sh [--repo DIR] [--board DIR] --version X.Y.Z [--notes FILE] --go [PR ...]
#     PR ...      the pull requests to release; none = every one that is READY. One that is not
#                 READY is refused, with the reason.
#     --repo      the code repo (default: the repo this is run from)
#     --board     the backlog board that holds the cards (default: $BACKLOG_DIR, else
#                 <repo>/.claude/backlog)
#     --notes     the release note: its first line is the headline, the rest goes under it in the
#                 README's Version History (default: one line per pull request)
#     --tests     the tests to run instead of the quick ones, space-separated, or `none`
#     --base      the branch released from and into (default: main)
set -euo pipefail

QUICK_SECONDS=120  # how long one contract test may take here before it is left to CI: long enough for every helper test, short enough that one slow test cannot hold the release
QUICK_TOTAL=600    # how long the quick tests may take in all, in seconds: past ten minutes the rest are left to CI, which runs every test on the release pull request anyway

here="$(cd "$(dirname "$0")" && pwd)"
BIN="$here/../.claude/make-it/backlog/bin"
say() { printf '%s\n' "$*"; }
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

repo="" board="${BACKLOG_DIR:-}" dry="" go="" version="" notes="" tests="" base="main" prs=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo|--board|--version|--notes|--tests|--base)
      [ $# -ge 2 ] || { echo "release-day: $1 needs a value" >&2; exit 2; }
      case "$1" in --repo) repo="$2" ;; --board) board="$2" ;; --version) version="$2" ;; --notes) notes="$2" ;; --tests) tests="$2" ;; --base) base="$2" ;; esac
      shift 2 ;;
    --dry-run) dry=1; shift ;;
    --go) go=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) case "$1" in ''|*[!0-9]*) echo "release-day: unexpected \"$1\" (a pull request is its number)" >&2; exit 2 ;; esac
       prs="$prs $1"; shift ;;
  esac
done

repo="$(git -C "${repo:-.}" rev-parse --show-toplevel 2>/dev/null)" || { echo "release-day: not inside a git repo (use --repo)" >&2; exit 2; }
board="${board:-$repo/.claude/backlog}"
[ -d "$board/items" ] || { echo "release-day: no board at $board (use --board): the board is where each review is recorded, so nothing can be called ready without it" >&2; exit 2; }
[ -z "$go" ] || [ -n "$version" ] || { echo "release-day: --go needs --version X.Y.Z: the number is yours to pick" >&2; exit 2; }
if [ -n "$version" ]; then
  printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "release-day: --version takes a number like 1.72.0, not \"$version\"" >&2; exit 2; }
  ! git -C "$repo" rev-parse -q --verify "refs/tags/v$version" >/dev/null || { echo "release-day: v$version is already a release tag: pick the next number" >&2; exit 2; }
fi
[ -z "$notes" ] || [ -f "$notes" ] || { echo "release-day: no notes file at $notes" >&2; exit 2; }

tmp="$(mktemp -d)"; work=""; made=""
cleanup() {
  if [ -n "$made" ] && [ -z "${keep:-}" ]; then  # a branch this run made and did not finish: take it away again
    git -C "$repo" worktree remove --force "$work" >/dev/null 2>&1 || true
    git -C "$repo" branch -q -D "$made" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
stop() {
  echo "release-day: STOPPED -- $*" >&2
  if [ -n "$dry" ]; then echo "release-day: this was a dry run: nothing was changed." >&2
  elif [ -n "${keep:-}" ]; then echo "release-day: the release branch ($made) is kept as it is." >&2
  else echo "release-day: nothing was pushed${made:+, and the release branch this run made ($made) was removed again}." >&2; fi
  exit 1
}

# --- 1. the facts -------------------------------------------------------------------------------
if ! python3 "$BIN/sync-prs.py" "$board" --repo "$repo" --sort --json >"$tmp/facts.json" 2>"$tmp/facts.err"; then
  echo "release-day: the open pull requests could not be read, so nothing was built: $(cat "$tmp/facts.json" "$tmp/facts.err" | head -3 | tr '\n' ' ')" >&2
  exit 2
fi
# shellcheck disable=SC2086
python3 - "$tmp/facts.json" "$tmp/chosen.tsv" $prs <<'PY' || exit 1
import json, sys
facts = json.load(open(sys.argv[1], encoding='utf-8')); want = [int(x) for x in sys.argv[3:]]
rows = {r['n']: dict(r, group=g) for g, rs in facts['groups'].items() for r in rs}
bad = [n for n in want if n not in rows or rows[n]['group'] != 'ready']
for n in bad:
    print(f'release-day: pull request #{n} is not ready, so it is left out: ' + (f"{rows[n]['name']} -- {rows[n]['why']}" if n in rows else 'it is not an open pull request'), file=sys.stderr)
if bad: sys.exit('release-day: nothing was built. Release the ones that are ready, or settle these first.')
pick = sorted((rows[n] for n in dict.fromkeys(want)) if want else (r for r in rows.values() if r['group'] == 'ready'), key=lambda r: r['n'])
flat = lambda s: ' '.join(str(s or '-').split()) or '-'
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    f.write(''.join(f"{r['n']}\t{r['head']}\t{flat(r['title'])}\t{flat(r['card'])}\t{flat(r['card_name'])}\n" for r in pick))
PY
count="$(wc -l <"$tmp/chosen.tsv" | tr -d ' ')"
if [ "$count" -eq 0 ]; then
  say "No pull request is ready (reviewed for its current commit, checks passed, up to date with $base): nothing to release today."
  say "  \`sync-prs.py --sort\` says what each open pull request needs."
  exit 0
fi

# --- 2. one release branch, each pull request squash-merged in turn -----------------------------
url="$(git -C "$repo" remote get-url origin 2>/dev/null)" || stop "the repo has no \`origin\` to release from"
branch="release/${version:+v$version}"; [ -n "$version" ] || branch="release/day-$(date +%F)"
if [ -n "$dry" ]; then
  work="$tmp/work"
  git clone -q "$repo" "$work" 2>"$tmp/clone.err" || stop "could not make the throwaway copy: $(cat "$tmp/clone.err")"
  git -C "$work" remote set-url origin "$url"
  git -C "$work" fetch -q origin "$base" 2>"$tmp/fetch.err" || stop "could not fetch $base: $(cat "$tmp/fetch.err")"
  git -C "$work" checkout -q -B "$branch" FETCH_HEAD
else
  work="$repo/.claude/worktrees/$(printf '%s' "$branch" | tr '/' '-')"
  ! git -C "$repo" show-ref --verify -q "refs/heads/$branch" || stop "a branch named $branch is already here: finish that release, or remove it yourself, then run again"
  [ ! -e "$work" ] || stop "$work is already there: finish that release, or remove it yourself, then run again"
  git -C "$repo" fetch -q origin "$base" 2>"$tmp/fetch.err" || stop "could not fetch $base: $(cat "$tmp/fetch.err")"
  git -C "$repo" worktree add -q "$work" -b "$branch" FETCH_HEAD 2>"$tmp/wt.err" || stop "could not make the release worktree: $(cat "$tmp/wt.err")"
  made="$branch"
fi
from="$(git -C "$work" rev-parse HEAD)"

: >"$tmp/merged.txt"
while IFS="$(printf '\t')" read -r n head title card cname; do
  what="\"$title\" (#$n)"
  git -C "$work" fetch -q origin "refs/pull/$n/head" 2>"$tmp/fetch.err" || stop "$what could not be fetched: $(cat "$tmp/fetch.err")"
  got="$(git -C "$work" rev-parse FETCH_HEAD)"
  [ "$got" = "$head" ] || stop "$what changed after its facts were read (it is at $(printf '%.7s' "$got") now; the review was read for $(printf '%.7s' "$head")): it needs its review again"
  if ! git -C "$work" merge --squash "$head" >"$tmp/merge.log" 2>&1; then
    clash="$(git -C "$work" diff --name-only --diff-filter=U | grep -vx 'CONTENT_MANIFEST' || true)"
    [ -z "$clash" ] || stop "$what conflicts with $base or with a pull request merged before it in this release, in: $(printf '%s' "$clash" | tr '\n' ' '). Rebase it and get it reviewed again, or leave it out of today's release"
    git -C "$work" diff --name-only --diff-filter=U | grep -qx 'CONTENT_MANIFEST' || stop "$what could not be merged: $(tail -3 "$tmp/merge.log" | tr '\n' ' ')"
  fi
  # the manifest is written once, at the end, from the files as released: no pull request's copy of it is merged
  if git -C "$work" cat-file -e HEAD:CONTENT_MANIFEST 2>/dev/null; then git -C "$work" checkout -q HEAD -- CONTENT_MANIFEST; fi
  ! git -C "$work" diff --cached --quiet || stop "$what adds nothing that $base does not already have: close it with a note instead of releasing it"
  git -C "$work" commit -q -m "$title (#$n)" >"$tmp/commit.log" 2>&1 || stop "$what could not be committed: $(tail -3 "$tmp/commit.log" | tr '\n' ' ')"
  printf '%s\t%s\t%s\t%s\n' "$n" "$title" "$card" "$cname" >>"$tmp/merged.txt"
done <"$tmp/chosen.tsv"

# --- 3. the manifest, written here and nowhere else ---------------------------------------------
gen="$work/.claude/make-it/scripts/content-manifest.sh"
manifest="no content manifest in this repo"
if [ -f "$gen" ]; then
  manifest="$(cd "$work" && bash "$gen" generate . --write 2>&1)" || stop "the content manifest could not be written: $manifest"
  (cd "$work" && bash "$gen" verify CONTENT_MANIFEST .claude) >"$tmp/verify.log" 2>&1 || stop "the manifest it wrote does not match the files: $(tail -3 "$tmp/verify.log" | tr '\n' ' ')"
  if [ -n "$(git -C "$work" status --porcelain -- CONTENT_MANIFEST)" ]; then
    git -C "$work" add CONTENT_MANIFEST
    git -C "$work" commit -q -m "chore(release): write the content manifest" >"$tmp/commit.log" 2>&1 || stop "the manifest could not be committed: $(tail -3 "$tmp/commit.log" | tr '\n' ' ')"
  fi
  manifest="$manifest; $(cat "$tmp/verify.log")"
fi

# --- 4. the quick contract tests ----------------------------------------------------------------
python3 - "$work" "$from" "$QUICK_SECONDS" "$tests" "$QUICK_TOTAL" >"$tmp/tests.txt" <<'PY' || { cat "$tmp/tests.txt" >&2; stop "a contract test failed on the release branch (above): fix it in its pull request"; }
import glob, os, subprocess, sys, time
work, base, cap, asked, total = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], int(sys.argv[5])
began = time.time()
changed = subprocess.run(['git', '-C', work, 'diff', '--name-only', base, 'HEAD'], capture_output=True, text=True, check=True).stdout.split('\n')
every = sorted(glob.glob(os.path.join(work, 'scripts', 'test-*.sh')))
if asked == 'none': run = []
elif asked: run = [os.path.join(work, t) for t in asked.split()]
else:  # quick = a test that changed, or that names a file this release changes; bookkeeping files every release touches say nothing
    names = {os.path.basename(c) for c in changed if c and os.path.basename(c) not in ('CONTENT_MANIFEST', 'VERSION', 'README.md', 'CHANGELOG.md', 'TODO.md')}
    run = [t for t in every if os.path.relpath(t, work) in changed or any(n in open(t, encoding='utf-8', errors='replace').read() for n in names)]
ok = slow = 0; bad = []
for t in run:
    if time.time() - began > total: slow += 1; continue
    try: r = subprocess.run(['bash', t], cwd=work, capture_output=True, text=True, errors='replace', timeout=cap)
    except subprocess.TimeoutExpired: slow += 1; continue
    if r.returncode: bad.append((os.path.relpath(t, work), (r.stdout + r.stderr)[-1200:]))
    else: ok += 1
for t, out in bad: print(f'FAILED {t}\n{out}')
print(f"{len(run)} of {len(every)} contract tests are quick ones for this release: {ok} passed, {len(bad)} failed" + (f', {slow} left to CI (over {cap} seconds each, or past {total // 60} minutes in all)' if slow else '') + '; CI runs all of them on the release pull request')
sys.exit(1 if bad else 0)
PY

# --- 5. the version commit, and what to run next ------------------------------------------------
now="$(tr -d '[:space:]' <"$work/VERSION" 2>/dev/null || echo '?')"
headline="$count fixes in one release"; [ "$count" -ne 1 ] || headline="$(cut -f2 "$tmp/merged.txt")"
[ -z "$notes" ] || headline="$(sed -n '1p' "$notes")"
v="${version:-X.Y.Z}"
subject="release: $headline (v$v)"
if [ -n "$version" ]; then
  printf '%s\n' "$version" >"$work/VERSION"
  python3 - "$work/README.md" "$version" "$headline" "$tmp/merged.txt" "$notes" <<'PY'
import sys
readme, ver, head, merged, notes = sys.argv[1:6]
body = ''.join(open(notes, encoding='utf-8').read().split('\n', 1)[1:]).strip('\n') if notes else '\n'.join(f"- {l.split(chr(9))[1]} (#{l.split(chr(9))[0]})" for l in open(merged, encoding='utf-8').read().splitlines())
try: txt = open(readme, encoding='utf-8').read()
except OSError: sys.exit(0)
mark = '## Version History\n'
if mark in txt:  # the newest release is the first entry under the heading
    a, b = txt.split(mark, 1)
    open(readme, 'w', encoding='utf-8').write(f'{a}{mark}\n### v{ver} -- {head}\n\n{body}\n\n{b.lstrip(chr(10))}')
PY
  git -C "$work" add VERSION README.md 2>/dev/null || git -C "$work" add VERSION
  git -C "$work" commit -q -m "$subject" >"$tmp/commit.log" 2>&1 || stop "the version commit could not be made: $(tail -3 "$tmp/commit.log" | tr '\n' ' ')"
fi

say "RELEASE OF THE DAY -- $count pull request$([ "$count" -eq 1 ] || printf s) on $branch, from $base at $(printf '%.7s' "$from")$([ -z "$dry" ] || printf ' · dry run, nothing changed')"
while IFS="$(printf '\t')" read -r n title card cname; do
  say "  merged  \"$title\" (#$n)$([ "$card" = "-" ] || printf ' · %s' "$cname")"
done <"$tmp/merged.txt"
say "  Content manifest: $manifest"
say "  Quick tests: $(tail -1 "$tmp/tests.txt")"
if [ -n "$version" ]; then
  say "The version commit$([ -z "$dry" ] || printf ' it would make'): $subject"
  git -C "$work" show --stat --format= HEAD | sed 's/^/   /'
else
  say "The version commit it would make (the number is yours to pick; VERSION is $now now):"
  say "    $subject   -- sets VERSION and adds the entry at the top of the README's Version History"
fi

pr="<the release pull request's number>"
if [ -n "$go" ] && [ -z "$dry" ]; then
  git -C "$work" push -q -u origin "$branch" 2>"$tmp/push.err" || stop "the push failed: $(tail -2 "$tmp/push.err" | tr '\n' ' ')"
  keep=1
  { say "One release for the day: $count pull request$([ "$count" -eq 1 ] || printf s), each reviewed for the commit merged here and green before it went in."; say ""
    while IFS="$(printf '\t')" read -r n title card cname; do say "- $title (#$n)$([ "$card" = "-" ] || printf ' -- %s' "$cname")"; done <"$tmp/merged.txt"
    say ""; say "The content manifest was written here, from the files as released."; } >"$tmp/body.md"
  link="$(cd "$work" && gh pr create --base "$base" --head "$branch" --title "$subject" --body-file "$tmp/body.md" 2>"$tmp/gh.err")" || stop "the branch is pushed, but the pull request could not be opened: $(tail -2 "$tmp/gh.err" | tr '\n' ' ') -- open it by hand: gh pr create --base $base --head $branch --title \"$subject\""
  say "Pushed $branch and opened the release pull request: $link"
  case "$link" in */pull/*) pr="#${link##*/}" ;; esac
  say "It is not merged and not tagged. When its checks are green and it has its independent review:"
elif [ -n "$dry" ]; then
  say "To make it real (this dry run kept nothing and pushed nothing):"
  say "    scripts/release-day.sh --version $v --go$(cut -f1 "$tmp/merged.txt" | sed 's/^/ /' | tr -d '\n')"
  say "  which builds this again, makes the version commit, and runs:"
  say "    git push -u origin $branch"
  say "    gh pr create --base $base --head $branch --title \"$subject\""
  say "Then, when its checks are green and it has its independent review:"
else
  keep=1
  say "Nothing has been pushed. The branch $branch is kept in $work. To finish it by hand, in that folder:"
  [ -n "$version" ] || say "    set VERSION, add the entry at the top of the README's Version History, and commit both as: $subject"
  say "    git push -u origin $branch"
  say "    gh pr create --base $base --head $branch --title \"$subject\""
  say "Then, when its checks are green and it has its independent review:"
fi
say "    gh pr merge ${pr#\#} --squash        # checks green on current $base first, as for any merge"
say "    git fetch origin && git tag v$v origin/$base && git push origin v$v"
say "After the release, close each original pull request with a note (the branch is kept):"
while IFS="$(printf '\t')" read -r n title card cname; do
  say "    gh pr close $n --comment \"Released in v$v by release pull request $pr, together with the day's other fixes. Closed, not merged, on purpose; the branch is kept.\""
done <"$tmp/merged.txt"
say "Cards to close (shipped means done: add the release pull request to the card, and the board closes it once the release's checks pass):"
none=1
while IFS="$(printf '\t')" read -r n title card cname; do
  [ "$card" != "-" ] || continue
  none=""; say "    $cname: card.py set $card pr=\"[$n, ${pr#\#}]\""
done <"$tmp/merged.txt"
[ -z "$none" ] || say "    none: no card names these pull requests"
say "    then: /backlog-it reconcile --prs   (closes the cards from facts, and sorts every pull request still open)"
