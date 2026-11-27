#!/usr/bin/env bash
# One release a day, many fixes in it (E04-S16 task 8), proven by RUNNING scripts/release-day.sh and
# content-manifest.sh against a throwaway repo with its own throwaway `origin`, a small board, and the stand-in `gh`
# (scripts/backlog-stand-in/gh). Nothing here touches this repo, a real board or the network.
#   MANIFEST  `content-manifest.sh generate <root> --write [path]` writes the file and prints one line; without
#             --write it prints the manifest and writes nothing, as it always did; the usage text says so.
#   RELEASE   release-day.sh takes only pull requests that are READY (reviewed for the exact head, checks passed,
#             up to date): it builds one release branch from origin's main, squash-merges each in turn, writes the
#             manifest once from the merged files (two pull requests that each regenerated it never clash), runs the
#             quick contract tests, and prints the version commit, the commands, the close-with-a-note line for each
#             original pull request and the cards to close. A real conflict stops it and names the pull request. It
#             pushes and opens the pull request only with --version AND --go, never merges, never tags, never picks
#             the number; --dry-run changes nothing.
#   THE GATE  the CI check that fails a pull request whose manifest does not match its files is still there, whole.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
python3 -I - "$root" "$t" <<'PY'
import datetime, json, os, re, shutil, subprocess, sys
root, tmp = sys.argv[1], sys.argv[2]
STAND, RD, CM = f'{root}/scripts/backlog-stand-in', f'{root}/scripts/release-day.sh', f'{root}/.claude/make-it/scripts/content-manifest.sh'
TODAY = str(datetime.date.today())
ENV = dict(os.environ, GIT_AUTHOR_NAME='stand-in', GIT_AUTHOR_EMAIL='stand-in@example.invalid', GIT_COMMITTER_NAME='stand-in', GIT_COMMITTER_EMAIL='stand-in@example.invalid',
           GIT_CONFIG_COUNT='3', GIT_CONFIG_KEY_0='commit.gpgsign', GIT_CONFIG_VALUE_0='false', GIT_CONFIG_KEY_1='core.hooksPath', GIT_CONFIG_VALUE_1='/dev/null',
           GIT_CONFIG_KEY_2='init.defaultBranch', GIT_CONFIG_VALUE_2='main', PATH=STAND + os.pathsep + os.environ['PATH'])
ENV.pop('BACKLOG_DIR', None)
fail = 0
def ok(name, cond, detail=''):
    global fail
    print(('ok   ' if cond else 'FAIL ') + name + ('' if cond else f'\n     {str(detail)[-2200:]}'))
    fail |= not cond
def sh(*a, cwd=None, check=True, env=None):
    r = subprocess.run(a, cwd=cwd, capture_output=True, text=True, encoding='utf-8', env=env or ENV)
    if check and r.returncode: sys.exit(f'setup failed: {a}\n{r.stdout}{r.stderr}')
    return r
git = lambda d, *a, **k: sh('git', '-C', d, *a, **k).stdout.strip()
def put(p, text):
    os.makedirs(os.path.dirname(p), exist_ok=True); open(p, 'w', encoding='utf-8').write(text)

n = [0]
def world():
    """A throwaway repo with its own origin, six pull requests (each a `refs/pull/<n>/head` on the origin, each with
    its own regenerated manifest, as lanes make them today), and a board whose cards record the reviews."""
    n[0] += 1; w = f'{tmp}/w{n[0]}'; R = f'{w}/repo'
    sh('git', 'init', '-q', '--bare', '-b', 'main', f'{w}/origin.git'); sh('git', 'clone', '-q', f'{w}/origin.git', R)
    put(f'{R}/.claude/commands/a.md', 'alpha\n'); put(f'{R}/.claude/make-it/notes.md', 'notes\n'); put(f'{R}/.gitignore', '.claude/worktrees/\n')
    os.makedirs(f'{R}/.claude/make-it/scripts'); shutil.copy(CM, f'{R}/.claude/make-it/scripts/content-manifest.sh')
    put(f'{R}/VERSION', '1.0.0\n'); put(f'{R}/README.md', '# stand-in\n\n## Version History\n\n### v1.0.0 -- the first one\n\n- it exists\n')
    put(f'{R}/scripts/test-quick.sh', '#!/usr/bin/env bash\n# reads a.md\n! grep -q BROKEN .claude/commands/a.md\n'); put(f'{R}/scripts/test-other.sh', '#!/usr/bin/env bash\n# names nothing a pull request changes\nexit 1\n')
    def commit(msg):
        git(R, 'add', '-A'); put(f'{R}/CONTENT_MANIFEST', sh('bash', CM, 'generate', R).stdout); git(R, 'add', '-A'); git(R, 'commit', '-qm', msg)
    git(R, 'checkout', '-q', '-b', 'main'); commit('first'); git(R, 'push', '-q', 'origin', 'main')
    heads = {}
    for k, (path, text) in {11: ('.claude/commands/a.md', 'alpha eleven\n'), 12: ('.claude/commands/b.md', 'beta\n'), 13: ('.claude/commands/a.md', 'alpha thirteen\n'),
                            14: ('.claude/commands/c.md', 'gamma\n'), 15: ('.claude/commands/a.md', 'alpha\nBROKEN\n')}.items():
        git(R, 'checkout', '-q', '-b', f'pr{k}', 'main'); put(f'{R}/{path}', text); commit(f'fix {k}')
        git(R, 'push', '-q', 'origin', f'pr{k}:refs/pull/{k}/head'); heads[k] = git(R, 'rev-parse', 'HEAD')
    git(R, 'checkout', '-q', 'main')
    S = f'{w}/board/items/EPIC-01-bugs/stories'; put(f'{w}/board/items/EPIC-01-bugs/epic.md', '---\nid: E01\ntitle: "Bugs"\ntype: epic\nstatus: in-progress\n---\n')
    for k, title in {11: 'The first page says the wrong word', 12: 'There is no second page', 13: 'The first page shouts', 14: 'There is no third page', 15: 'A fix that breaks a test'}.items():
        put(f'{S}/S{k}.md', f'---\nid: E01-S{k}\ntitle: "{title}"\ntype: breakfix\nstatus: in-progress\nstage: Fix ready\npr: [{k}]\n' + ('' if k == 14 else f'reviewed: {TODAY} ready {heads[k]}\n') + '---\n')
    os.makedirs(f'{w}/behind')
    for h in heads.values(): put(f'{w}/behind/{h}', json.dumps({'behind_by': 0, 'ahead_by': 1}))
    return w, heads
def facts(w, heads, which, over=()):
    ok_ = [{'__typename': 'CheckRun', 'name': 'tests', 'status': 'COMPLETED', 'conclusion': 'SUCCESS'}]
    put(f'{w}/prs.json', json.dumps([{'number': k, 'title': f'fix: number {k}', 'isDraft': False, 'reviewDecision': '', 'mergeStateStatus': 'CLEAN', 'baseRefName': 'main',
                                      'headRefOid': dict(over).get(k, heads[k]), 'statusCheckRollup': ok_, 'updatedAt': f'{TODAY}T00:00:00Z'} for k in which]))
def rd(w, *args, prs=None):
    return subprocess.run(['bash', RD, '--repo', f'{w}/repo', '--board', f'{w}/board', *args], capture_output=True, text=True, encoding='utf-8', cwd=f'{w}/repo',
                          env=dict(ENV, GH_STUB_PRS=prs or f'{w}/prs.json'))
def state(w):  # everything a run could change: the repo's branches, tags, worktrees and files, and the origin's branches and tags
    R = f'{w}/repo'
    return (git(R, 'for-each-ref', '--format=%(refname) %(objectname)', 'refs/heads', 'refs/tags'), git(R, 'worktree', 'list'), git(R, 'status', '--porcelain'),
            git(f'{w}/origin.git', 'for-each-ref', '--format=%(refname) %(objectname)'), os.path.exists(f'{w}/gh-calls.log'))
both = lambda r: r.stdout + r.stderr

# ============================== THE MANIFEST: --write ==============================
w, heads = world(); R = f'{w}/repo'
put(f'{R}/.claude/commands/a.md', 'alpha changed\n')
before = open(f'{R}/CONTENT_MANIFEST').read()
r = sh('bash', CM, 'generate', R, check=False)
ok('generate without --write prints the manifest and writes nothing, as before', r.returncode == 0 and 'commands/a.md' in r.stdout and r.stdout != before and open(f'{R}/CONTENT_MANIFEST').read() == before, both(r))
printed = r.stdout
r = sh('bash', CM, 'generate', R, '--write', check=False)
ok('generate --write writes CONTENT_MANIFEST and prints one line', r.returncode == 0 and r.stdout.strip() == f'wrote {R}/CONTENT_MANIFEST (3 files)' and open(f'{R}/CONTENT_MANIFEST').read() == printed, both(r))
ok('what it wrote matches the files exactly', sh('bash', CM, 'verify', f'{R}/CONTENT_MANIFEST', f'{R}/.claude', check=False).returncode == 0
   and os.listdir(R).count('CONTENT_MANIFEST') == 1 and not [f for f in os.listdir(R) if f.startswith('CONTENT_MANIFEST.')], os.listdir(R))
r = sh('bash', CM, 'generate', '--write', '.', cwd=R, check=False)
ok('a folder after --write is the root, never the file to write', r.returncode == 0 and r.stdout.strip() == 'wrote ./CONTENT_MANIFEST (3 files)', both(r))
r = sh('bash', CM, 'generate', R, '--write', f'{w}/elsewhere.txt', check=False)
ok('--write <path> writes there instead', r.returncode == 0 and open(f'{w}/elsewhere.txt').read() == printed, both(r))
r = sh('bash', CM, 'generate', f'{w}/board', '--write', f'{w}/kept.txt', check=False); put(f'{w}/kept2.txt', 'old\n')
r2 = sh('bash', CM, 'generate', f'{w}/board', '--write', f'{w}/kept2.txt', check=False)
ok('when it cannot generate, nothing is written and the old file is left', r.returncode != 0 and not os.path.exists(f'{w}/kept.txt') and r2.returncode != 0 and open(f'{w}/kept2.txt').read() == 'old\n'
   and not [f for f in os.listdir(w) if f.startswith('kept') and f not in ('kept2.txt',)], both(r) + str(os.listdir(w)))
u = sh('bash', CM, check=False).stderr
ok('the usage text says generate only PRINTS, and that work was lost to throwing its output away', 'PRINTS the manifest, writes nothing' in u and 'generate <root> --write [path]' in u
   and 'Three lanes lost work' in u, u)

# ============================== THE DAILY RELEASE ==============================
w, heads = world(); R = f'{w}/repo'; facts(w, heads, (11, 12, 14))
clash = sh('git', '-C', R, 'merge-tree', '--write-tree', '--name-only', heads[11], heads[12], check=False)
ok('(control) the two ready pull requests clash in CONTENT_MANIFEST and nowhere else, as two lanes do today', clash.returncode == 1 and 'CONTENT_MANIFEST' in clash.stdout and 'a.md' not in clash.stdout.split('\n', 1)[1], clash.stdout)
before = state(w)
r = rd(w, '--dry-run'); out = r.stdout
ok('dry run: exits 0 and changes nothing -- no branch, no worktree, no file, nothing on the origin, no pull request opened', r.returncode == 0 and state(w) == before, both(r) + str(state(w)))
ok('dry run: takes every READY pull request and only those, each named by title and number with its card',
   re.search(r'^RELEASE OF THE DAY -- 2 pull requests on release/day-' + TODAY + r', from main at [0-9a-f]{7} · dry run, nothing changed$', out, re.M) is not None
   and '  merged  "fix: number 11" (#11) · The first page says the wrong word (E01-S11)' in out and '  merged  "fix: number 12" (#12) · There is no second page (E01-S12)' in out and '#14' not in out, both(r))
ok('dry run: the manifest was written once from the merged files and matches them (4 files), though both pull requests had regenerated it',
   re.search(r'^  Content manifest: wrote \./CONTENT_MANIFEST \(4 files\); content matches manifest \(4 files\)$', out, re.M) is not None, out)
ok('dry run: the quick tests are the ones that name a changed file; the rest are left to CI', '  Quick tests: 1 of 2 contract tests are quick ones for this release: 1 passed, 0 failed; CI runs all of them on the release pull request' in out, out)
ok('dry run: it prints the version commit it would make and never picks the number', 'The version commit it would make (the number is yours to pick; VERSION is 1.0.0 now):' in out
   and '    release: 2 fixes in one release (vX.Y.Z)' in out and '    scripts/release-day.sh --version X.Y.Z --go 11 12' in out, out)
ok('dry run: it prints the commands that open the pull request, merge it and tag it -- printed, never run', all(x in out for x in
   ('    git push -u origin release/vX.Y.Z', '    gh pr create --base main --head release/vX.Y.Z', '    gh pr merge ', '    git fetch origin && git tag vX.Y.Z origin/main && git push origin vX.Y.Z')), out)
ok('dry run: the close-with-a-note line for each original pull request, and the cards to close',
   all(f'    gh pr close {k} --comment "Released in vX.Y.Z by release pull request' in out for k in (11, 12)) and 'the branch is kept' in out
   and '    The first page says the wrong word (E01-S11): card.py set E01-S11 pr="[11, ' in out and '/backlog-it reconcile --prs' in out, out)
r = rd(w, '--dry-run', '--version', '9.9.9'); out = r.stdout
ok('dry run with a number: shows the version commit exactly (VERSION and the README), and still changes nothing', r.returncode == 0 and state(w) == before
   and 'The version commit it would make: release: 2 fixes in one release (v9.9.9)' in out and re.search(r'^\s+VERSION\s+\| ', out, re.M) is not None and re.search(r'^\s+README\.md\s+\| ', out, re.M) is not None, both(r))

r = rd(w, '14')
ok('a pull request that is not ready is refused, with the reason, and nothing is built', r.returncode == 1 and state(w) == before
   and 'pull request #14 is not ready, so it is left out: "fix: number 14" (#14), for There is no third page (E01-S14) -- every check passed, but no review is recorded for this version' in r.stderr, both(r))
facts(w, heads, (14,)); r = rd(w)
ok('no pull request ready: says so, builds nothing, exits 0', r.returncode == 0 and 'No pull request is ready' in r.stdout and state(w) == before, both(r))
r = rd(w, prs=f'{w}/no-such-file.json')
ok('the facts cannot be read: says so, builds nothing, exits 2', r.returncode == 2 and 'could not be read, so nothing was built' in r.stderr and state(w) == before, both(r))
for args, says in ((('--go',), '--go needs --version'), (('--version', '1.2', '--go'), 'takes a number like'), (('--frobnicate',), 'unexpected')):
    r = rd(w, *args)
    ok(f'refused before anything is read: {" ".join(args)}', r.returncode == 2 and says in r.stderr and state(w) == before, both(r))

facts(w, heads, (11, 13)); r = rd(w)
ok('a real conflict stops the run and names the pull request and the file', r.returncode == 1 and 'STOPPED -- "fix: number 13" (#13) conflicts with main or with a pull request merged before it in this release, in: .claude/commands/a.md' in r.stderr, both(r))
ok('after a stop nothing is left behind: the release branch it made is removed, nothing was pushed', state(w) == before and 'nothing was pushed, and the release branch this run made (release/day-' + TODAY + ') was removed again' in r.stderr, both(r) + str(state(w)))
facts(w, heads, (15,)); r = rd(w)
ok('a failing contract test stops the release and is named', r.returncode == 1 and 'FAILED scripts/test-quick.sh' in r.stderr and 'a contract test failed on the release branch' in r.stderr and state(w) == before, both(r))
put(f'{w}/board/items/EPIC-01-bugs/stories/S12.md', open(f'{w}/board/items/EPIC-01-bugs/stories/S12.md').read().replace(heads[12], heads[14]))
put(f'{w}/behind/{heads[14]}', json.dumps({'behind_by': 0, 'ahead_by': 1})); facts(w, heads, (12,), {12: heads[14]}); r = rd(w)
ok('a pull request that moved after its facts were read is refused: the review was of another commit', r.returncode == 1 and '"fix: number 12" (#12) changed after its facts were read' in r.stderr and state(w) == before, both(r))

# --- the real thing, without --go: one branch, kept, nothing pushed ---
w, heads = world(); R = f'{w}/repo'; facts(w, heads, (11, 12, 14)); before = state(w)
r = rd(w); out = r.stdout; W = f'{R}/.claude/worktrees/release-day-{TODAY}'
log = git(R, 'log', '--format=%s', f'main..release/day-{TODAY}', check=False).split('\n')
ok('without --go: one release branch from main, each pull request one squashed commit, then the manifest', r.returncode == 0
   and log == ['chore(release): write the content manifest', 'fix: number 12 (#12)', 'fix: number 11 (#11)'], both(r) + str(log))
ok('without --go: nothing is pushed, no pull request is opened, nothing is tagged, VERSION is as it was', state(w)[3:] == before[3:] and 'refs/tags' not in state(w)[0]
   and open(f'{W}/VERSION').read() == '1.0.0\n' and 'Nothing has been pushed. The branch release/day-' + TODAY + ' is kept in' in out, both(r))
gen = sh('bash', f'{W}/.claude/make-it/scripts/content-manifest.sh', 'generate', '.', cwd=W).stdout
ok('the release branch holds both fixes, and its manifest matches its files exactly', open(f'{W}/.claude/commands/a.md').read() == 'alpha eleven\n' and os.path.exists(f'{W}/.claude/commands/b.md')
   and gen == open(f'{W}/CONTENT_MANIFEST').read() and len(gen.splitlines()) == 4, gen)
r = rd(w)
ok('a second run the same day is refused instead of building over the first', r.returncode == 1 and 'is already here: finish that release, or remove it yourself' in r.stderr, both(r))

# --- with --version and --go: the version commit, the push, the pull request; never a merge, never a tag ---
put(f'{w}/notes.md', 'two pages are right again\n- The first page says the right word.\n- There is a second page.\n')
main_before = git(f'{w}/origin.git', 'rev-parse', 'refs/heads/main')
r = rd(w, '--version', '9.9.9', '--notes', f'{w}/notes.md', '--go', '11', '12'); out = r.stdout
O = f'{w}/origin.git'
ok('--version X --go: makes the version commit and pushes the release branch', r.returncode == 0 and git(O, 'log', '-1', '--format=%s', 'refs/heads/release/v9.9.9', check=False) == 'release: two pages are right again (v9.9.9)'
   and git(O, 'show', 'refs/heads/release/v9.9.9:VERSION', check=False) == '9.9.9', both(r))
readme = git(O, 'show', 'refs/heads/release/v9.9.9:README.md', check=False)
ok('the README\'s Version History gets the entry on top, from the notes', '## Version History\n\n### v9.9.9 -- two pages are right again\n\n- The first page says the right word.\n- There is a second page.\n\n### v1.0.0 -- the first one' in readme, readme)
calls = open(f'{w}/gh-calls.log').read() if os.path.exists(f'{w}/gh-calls.log') else ''
ok('it opens one pull request against main, and says so', calls.count('pr create') == 1 and '--base main --head release/v9.9.9 --title release: two pages are right again (v9.9.9)' in calls
   and 'Pushed release/v9.9.9 and opened the release pull request: https://github.com/stand-in/repo/pull/99' in out, calls + both(r))
ok('it never merges and never tags: main on the origin is where it was, no tag exists anywhere, and it says so', git(O, 'rev-parse', 'refs/heads/main') == main_before
   and git(O, 'tag') == '' and git(R, 'tag') == '' and 'It is not merged and not tagged.' in out and 'gh pr merge 99 --squash' in out and 'git tag v9.9.9 origin/main' in out, both(r))
W = f'{R}/.claude/worktrees/release-v9.9.9'
ok('what is released matches its manifest exactly: generating again on the release branch changes nothing', sh('bash', f'{W}/.claude/make-it/scripts/content-manifest.sh', 'generate', '.', cwd=W).stdout
   == git(O, 'show', 'refs/heads/release/v9.9.9:CONTENT_MANIFEST') + '\n' and sh('bash', CM, 'verify', f'{W}/CONTENT_MANIFEST', f'{W}/.claude', check=False).returncode == 0, '')
ok('after the release: the close-with-a-note line for each original pull request, with the release named, and the cards to close',
   all(f'    gh pr close {k} --comment "Released in v9.9.9 by release pull request #99, together with the day\'s other fixes. Closed, not merged, on purpose; the branch is kept."' in out for k in (11, 12))
   and '    There is no second page (E01-S12): card.py set E01-S12 pr="[12, 99]"' in out, out)
r = rd(w, '--version', '9.9.9', '--go', '11')
ok('the same number twice is refused', r.returncode == 1 and 'release/v9.9.9 is already here' in r.stderr, both(r))

# ============================== ONLY CODE REVIEWED FOR ITS EXACT HEAD GOES IN (review round 1) ==============================
OKC = [{'__typename': 'CheckRun', 'name': 'tests', 'status': 'COMPLETED', 'conclusion': 'SUCCESS'}]
def rows(w, heads, spec):  # spec: [(n, {field overrides})]
    base = dict(isDraft=False, reviewDecision='', mergeStateStatus='CLEAN', baseRefName='main', statusCheckRollup=OKC, updatedAt=f'{TODAY}T00:00:00Z')
    put(f'{w}/prs.json', json.dumps([dict(base, number=k, title=f'fix: number {k}', headRefOid=heads[k], **o) for k, o in spec]))
w, heads = world(); R = f'{w}/repo'
git(R, 'checkout', '-q', '-b', 'feat', 'main'); put(f'{R}/.claude/commands/evil.md', 'UNREVIEWED\n'); git(R, 'add', '-A'); git(R, 'commit', '-qm', 'unreviewed'); git(R, 'push', '-q', 'origin', 'feat')
git(R, 'checkout', '-q', '-b', 'pr20', 'feat'); put(f'{R}/.claude/commands/d.md', 'delta\n'); git(R, 'add', '-A'); git(R, 'commit', '-qm', 'pr20')
git(R, 'push', '-q', 'origin', 'pr20:refs/pull/20/head'); heads[20] = git(R, 'rev-parse', 'HEAD'); git(R, 'checkout', '-q', 'main')
put(f'{w}/board/items/EPIC-01-bugs/stories/S20.md', f'---\nid: E01-S20\ntitle: "Stacked"\ntype: breakfix\nstatus: in-progress\nstage: Fix ready\npr: [20]\nreviewed: {TODAY} ready {heads[20]}\n---\n')
put(f'{w}/behind/{heads[20]}', json.dumps({'behind_by': 0, 'ahead_by': 1}))
rows(w, heads, [(20, {'baseRefName': 'feat'})]); before = state(w); r = rd(w, '20')
ok('a stacked pull request (its base is another branch, not main) is refused with the reason, and nothing of its base comes in', r.returncode == 1 and state(w) == before
   and 'pull request #20 is not ready' in r.stderr and 'it is stacked on feat, not on main' in r.stderr, both(r))
r = rd(w); ok('a stacked pull request is never taken as ready when none is named', r.returncode == 0 and 'No pull request is ready' in r.stdout and state(w) == before, both(r))
rows(w, heads, [(11, {})]); r = rd(w, '--base', 'feat', '--dry-run', '11')
ok('the release takes only pull requests into its own --base: one into main is refused from a release of feat', r.returncode == 1 and 'it is stacked on main, not on feat' in r.stderr and state(w) == before, both(r))
rows(w, heads, [(11, {'statusCheckRollup': []})]); r = rd(w, '11')
ok('a pull request with no check reported on its head is not green: refused with the reason', r.returncode == 1 and state(w) == before and 'no check has run on this version yet' in r.stderr, both(r))
rows(w, heads, [(11, {'statusCheckRollup': [dict(OKC[0], conclusion='SKIPPED')]})]); r = rd(w, '11')
ok('a pull request whose every check was skipped is not green either', r.returncode == 1 and 'no check has run on this version yet' in r.stderr, both(r))
rows(w, heads, [(11, {'isCrossRepository': True, 'headRepositoryOwner': {'login': 'someone-else'}})]); r = rd(w, '--dry-run', '11')
ok('a pull request from another repository goes in only as the exact commit reviewed: it is fetched as GitHub keeps it (refs/pull/N/head) and checked against the review',
   r.returncode == 0 and '  merged  "fix: number 11" (#11)' in r.stdout and state(w) == before, both(r))
rows(w, heads, [(11, {})]); git(R, 'tag', 'v2.0.0', 'main'); git(R, 'push', '-q', 'origin', 'v2.0.0'); git(R, 'tag', '-d', 'v2.0.0')
before = state(w); r = rd(w, '--version', '2.0.0', '--dry-run')
ok('a number that is already a tag on the origin (not here) is refused', r.returncode == 2 and 'v2.0.0 is already a release tag' in r.stderr and state(w) == before, both(r))
for ver in ('1.0.0', '0.9.9'):
    r = rd(w, '--version', ver, '--dry-run')
    ok(f'a number not above VERSION (1.0.0) is refused: {ver}', r.returncode == 1 and f'v{ver} is not above the version main is at (1.0.0)' in r.stderr and state(w) == before, both(r))
r = rd(w, '--version', '1.0.1'); W = f'{R}/.claude/worktrees/release-v1.0.1'
ok('--version without --go on a real run: the version commit is made here, and nothing is pushed or opened', r.returncode == 0 and state(w)[3:] == before[3:]
   and open(f'{W}/VERSION').read() == '1.0.1\n' and 'Nothing has been pushed.' in r.stdout, both(r) + str(state(w)))

# ============================== THE GATE IS STILL WHOLE, AND THE ROUTINE IS WRITTEN DOWN ==============================
wf = open(f'{root}/.github/workflows/manifest-check.yml', encoding='utf-8').read()
ok('CI still fails a pull request whose manifest does not match its files, exactly (the check was not loosened to make room for this)',
   'pull_request:' in wf and 'content-manifest.sh generate . > /tmp/expected-manifest' in wf and 'diff -u CONTENT_MANIFEST /tmp/expected-manifest' in wf and 'exit 1' in wf
   and 'content-manifest.sh verify CONTENT_MANIFEST .claude' in wf, '')
flat = lambda p: re.sub(r'\s+', ' ', open(f'{root}/{p}', encoding='utf-8').read())
cmd, ref, ops = flat('.claude/commands/backlog-it.md'), flat('.claude/make-it/references/backlog-board.md'), flat('.claude/make-it/references/git-operations.md')
ok('the skill: "Release it" runs the day\'s release -- dry run first, the owner picks the number, then --version and --go',
   'scripts/release-day.sh --dry-run' in cmd and '--version <the number picked> --go' in cmd and 'never picks the version number' in cmd and 'independent review' in cmd.split('| Release it |')[1].split('| Sort them |')[0], '')
ok('the reference: one release a day is written down, with what it refuses', '### One release a day' in ref and all(x in ref for x in ('scripts/release-day.sh', 'written once, at release time', 'never merges', 'never tags', 'close it with a note')), '')
ok('git-operations: the daily release, the manifest rule and the rebase command are written down', '## One release a day' in ops and 'content-manifest.sh generate . --write' in ops
   and 'checks green on current `main`' in ops and 'independent review' in ops.split('## One release a day')[1], '')
src = open(RD, encoding='utf-8').read()
ok('the quick-test time is a named constant with its reason, and the script never forces a push or skips a hook',
   re.search(r'^QUICK_SECONDS=\d+\s+#.{20,}', src, re.M) is not None and '--force' not in src.replace('worktree remove --force', '') and '--no-verify' not in src, '')
sys.exit(fail)
PY
