#!/usr/bin/env python3
"""Close cards from facts -- shipped means done. A card is done (`closed_as: shipped-tests-pass`) when every
pull request in its `pr:` is closed and one is merged, a release carries that merge, and every check that ran on
that release passed. Forward only, and never on a guess: when a fact cannot be read, the card is left and the
reason is said.

Usage: sync-prs.py [board_dir] --repo PATH [--project NAME] [--dry-run]
       sync-prs.py [board_dir] --repo PATH [--project NAME] --sort [--json]
       sync-prs.py --self-test
  --repo  the code repo whose PRs bare numbers in `pr:` name (settings `repo`); `gh` reads its
          remote. A PR in another repo goes in `pr:` as its full URL. With no --repo, no `gh` or
          no auth, the PR step is skipped and said so.
  The release that carries a merge is the repo's newest tag, when that tag holds the merge commit; a repo
  with no tag at all releases by merging, and the merge commit's own checks decide. Nothing is confirmed by a
  real run: the closed card says so, and how to reopen it. A bundle closes only when each of its parts has
  passed its own check. A card left at the older Checked stage closes; one at the older Live stage follows
  the rule above. Writes the cards and BOARD.md; the caller commits them (the board's sync step).
  --sort  every open pull request in exactly one of six groups, from facts (status.py's `sort_prs`): READY, OUT OF
          DATE, CAN BE SETTLED, STALLED, NEEDS YOU, WILL NEVER MERGE, each line with the action. Read-only. When the
          facts cannot be read it says so, sorts nothing and exits 2. A plain run (`reconcile --prs`) ends with the
          same list, so the sort happens after every merge and release without anyone remembering. --json prints
          the groups for another helper (scripts/release-day.sh).
"""
import datetime, importlib.util, json, os, re, subprocess, sys

_bin = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('regen_board', os.path.join(_bin, 'regen-board.py'))
sys.dont_write_bytecode = True  # no __pycache__ beside the installed scripts
R = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(R)
_cspec = importlib.util.spec_from_file_location('card', os.path.join(_bin, 'card.py'))
C = importlib.util.module_from_spec(_cspec); _cspec.loader.exec_module(C)  # the one card writer
_sspec = importlib.util.spec_from_file_location('status_board', os.path.join(_bin, 'status.py'))
S = importlib.util.module_from_spec(_sspec); _sspec.loader.exec_module(S)  # the rule that sorts open pull requests lives beside the first screen that counts them
v = R.v
BEFORE_DONE = ('Reported', 'Cause found', 'Fix ready', 'Live')  # Live: the older stage for "merged"; it follows the same rule now
URL = r'https?://[^\s,\]]+/pull/\d+'
GOOD, BAD = ('success', 'skipped', 'neutral'), ('failure', 'timed_out', 'cancelled', 'action_required', 'startup_failure', 'stale')

def prs(d):
    """pr: [1590, 1593] · 1590 · #1590 · full PR URLs (any repo). None for a repo#N short form."""
    s = v(d, 'pr'); rest = re.sub(URL, ' ', s)
    if re.search(r'\w#\d', rest): return None  # "splashdown#71": which repo is ambiguous -- ask for the URL
    return re.findall(URL, s) + [int(n) for n in re.findall(r'\d+', rest)]

def name(n): return f'#{n}' if isinstance(n, int) else '{}#{}'.format(*re.search(r'([^/]+)/pull/(\d+)$', n).groups())

def gh(repo):
    """What `gh` knows, each answer cached: {'pr': number or URL -> {state, mergedAt, mergeCommit},
    'release': (pr, merge commit) -> (how, tag), 'checks': (pr, tag or commit) -> (how, detail)}. None when gh can't run."""
    try:
        if subprocess.run(['gh', 'auth', 'status'], cwd=repo, capture_output=True, timeout=30).returncode: return None
    except (OSError, subprocess.TimeoutExpired): return None
    cache = {}
    def ask(*a):  # (parsed JSON, None) or (None, why)
        if a not in cache:
            try:
                r = subprocess.run(['gh', *a], cwd=repo, capture_output=True, text=True, encoding='utf-8', timeout=30)
                cache[a] = (json.loads(r.stdout), None) if r.returncode == 0 else (None, (r.stderr.strip().splitlines() or ['?'])[-1][:70])
            except subprocess.TimeoutExpired: cache[a] = (None, 'gh timed out')
            except ValueError: cache[a] = (None, 'gh gave no JSON')
        return cache[a]
    # the repo a pull request lives in: `{owner}/{repo}` (gh fills it in from --repo) or, for a URL, the one it names
    api = lambda n, path: ask('api', 'repos/' + ('{owner}/{repo}' if isinstance(n, int) else '/'.join(n.split('/')[3:5])) + '/' + path)
    def look(n):
        j, why = ask('pr', 'view', str(n), '--json', 'state,mergedAt,mergeCommit')
        return j if isinstance(j, dict) else {'state': 'UNKNOWN', 'why': why}
    def release(n, sha):
        """('in', tag) the newest tag holds the merge · ('not yet', tag) it does not · ('merge', '') the repo has
        no tag: merging is releasing · ('unreadable', why)."""
        tags, why = api(n, 'tags?per_page=1')
        if not isinstance(tags, list): return 'unreadable', why or 'the tags could not be read'
        if not tags: return 'merge', ''
        # ponytail: GitHub lists the newest tag first in practice; where it does not, a merge reads as "not in a
        # release yet" and the card is left open -- never closed wrongly
        tag = tags[0].get('name', '')
        cmp, why = api(n, f'compare/{sha}...{tag}')
        if not isinstance(cmp, dict) or not isinstance(cmp.get('behind_by'), int): return 'unreadable', why or 'the release could not be compared'
        return ('in' if cmp['behind_by'] == 0 else 'not yet'), tag
    def checks(n, ref):
        """('pass', count) · ('fail', (failed names, count)) · ('running', count) · ('none', 0) · ('partial', 'N of its M') · ('unreadable', why)."""
        j, why = api(n, f'commits/{ref}/check-runs?per_page=100')
        runs = j.get('check_runs') if isinstance(j, dict) else None
        if not isinstance(runs, list): return 'unreadable', why or 'no answer'
        # ponytail: one page of 100 is read. A release with more is never called passed on a part of its checks: the card is left and the count said; page here if that ever bites
        if isinstance(j.get('total_count'), int) and j['total_count'] > len(runs): return 'partial', f"{len(runs)} of its {j['total_count']}"
        bad = [c.get('name') or '?' for c in runs if c.get('conclusion') in BAD]
        if bad: return 'fail', (bad, len(runs))
        if any(c.get('status') != 'completed' or c.get('conclusion') not in GOOD for c in runs): return 'running', len(runs)
        ran = sum(c.get('conclusion') == 'success' for c in runs)  # a skipped check proves nothing: only the ones that ran and passed are counted
        return ('pass', ran) if ran else ('none', 0)
    return {'pr': look, 'release': release, 'checks': checks}

def eligible(d, closing):  # still movable right now: open, and at the stage the move starts from
    return v(d, 'status') != 'done' and (v(d, 'stage') == 'Checked' if closing else v(d, 'stage') in BEFORE_DONE)

def moves(B, G):
    """([(path, changes, note, the section and lines written on the card)], [(path, why it waits)])."""
    out, wait = [], []
    cards = R.load(B); T = R.tree(cards)
    for p, d in cards.items():
        if '/stories/' not in p: continue
        if v(d, 'status') == 'done' or R.bundle_of(d, T): continue  # a part of a bundle closes on its own check (`part-done`), never here, whatever its stage
        still = R.open_parts(d, T)  # a bundle: each card in it closes on its own check, and the bundle only after them
        unchecked = (f"{len(still)} of its parts ha{'s' if len(still) == 1 else 've'} not passed {'its' if len(still) == 1 else 'their'} own check: "
                     + ', '.join(R.name(m) for m in still) + ' -- record each with `part-done`, or take it out with `unbundle`')
        if eligible(d, True):
            if still: wait.append((p, f'at Checked, but {unchecked}'))
            else: out.append((p, {'status': 'done'}, 'Checked → done (the live check passed)', None))
            continue
        if not eligible(d, False): continue
        nums = prs(d)
        if nums is None: wait.append((p, 'pr: names another repo by short form -- use the PR URL')); continue
        if not nums:
            if v(d, 'stage') in ('Fix ready', 'Live'): wait.append((p, 'no pr: -- set it to the fix PR'))
            continue
        if not G: wait.append((p, 'PR step skipped')); continue
        got = {n: G['pr'](n) for n in nums}
        blocking = [f"{name(n)} {s['state'].lower()}" + (f" ({s['why']})" if s.get('why') else '') for n, s in got.items() if s['state'] in ('OPEN', 'UNKNOWN')]
        merged = sorted((n for n, s in got.items() if s['state'] == 'MERGED'), key=lambda n: got[n].get('mergedAt') or '')
        if blocking or not merged:
            wait.append((p, ', '.join(blocking) or ', '.join(f'{name(n)} closed without merging' for n in nums))); continue
        n = merged[-1]; sha = (got[n].get('mergeCommit') or {}).get('oid'); did = f"{name(n)} merged {(got[n].get('mergedAt') or '')[:10]}".rstrip()
        if not sha: wait.append((p, f'{did}, but its merge commit could not be read -- left as it is')); continue
        how, tag = G['release'](n, sha)
        if how == 'unreadable': wait.append((p, f'{did}, but its release could not be read ({tag}) -- left as it is')); continue
        if how == 'not yet': wait.append((p, f'{did}, not in a release yet (the newest is {tag})')); continue
        rel, its = (f'released in {tag}', "that release's") if how == 'in' else ('the merge is the release (the repo has no release tag)', "the merge's")
        res, x = G['checks'](n, tag if how == 'in' else sha)
        if res != 'pass':
            wait.append((p, f'{did}, {rel}, but ' + ({'unreadable': f'its checks could not be read ({x}) -- left as it is', 'partial': f'only {x} checks could be read -- left as it is', 'none': 'no checks ran on it, so nothing says the tests pass -- left as it is',
                                                    'running': 'its checks are still running'}.get(res) or f"{len(x[0])} of its {x[1]} checks failed ({', '.join(x[0][:3])}) -- not done: a test says otherwise"))); continue
        if still: wait.append((p, f'{did}, {rel}, but {unchecked}')); continue
        proof = f"{did}; {rel}; all {x} of {its} checks passed"
        note = f"{v(d, 'stage')} → done · {proof} · not confirmed by a real run: reopen it if use shows otherwise"
        if v(d, 'decision'): note += ' · it still has a decision: -- if that was answered, clear decision: and answers:'
        out.append((p, {'status': 'done', 'closed_as': 'shipped-tests-pass'}, note,
                    ('Shipped means done', '- closed on the rule "shipped means done": a fix counts as fixed unless a test proves otherwise\n'
                     f"- evidence: pull request {proof}\n- not confirmed by a real run. If use shows it is not fixed: `/backlog-it reopen {v(d, 'id')} <what you saw>`")))
    return out, wait

def apply(p, changes, note, body, T):
    """Write the move through card.py's writer. False if the card moved meanwhile."""
    # ponytail: re-read at write time -- another session may have moved the card while gh ran
    if not eligible(R.fm(p), 'closed_as' not in changes): return False
    C.write(p, changes, f'{body[0]} ({T})' if body else f'PR sync ({T})', body[1] if body else f'- {note}', T)
    return True

def run(B, G, dry, proj=None, T=None):
    T = T or datetime.date.today()
    out, wait = moves(B, G)
    cards = R.load(B)
    cid = lambda p: R.name(cards[p])  # a card by its title with its id, never a bare id
    if not dry: C.lock(B); out = [m for m in out if apply(*m, T)]  # card.py's writer lock
    if out and not dry:
        subprocess.run([sys.executable, os.path.join(_bin, 'regen-board.py'), B] + (['--project', proj] if proj else []), check=True)
    lines = [f"PR sync -- {R.arg(proj or os.path.basename(B))} · {T}" + (' · no --repo or gh: PR step skipped' if not G else '') + (' · dry run, nothing written' if dry else '')]
    lines += [f'  {cid(p)} · {note}' for p, _, note, _ in out] or ['  nothing to close']
    lines += ['Waiting:'] + [f'  {cid(p)} · {why}' for p, why in wait] if wait else []
    lines.append(f"{'Would close' if dry else 'Closed'} {len(out)} · waiting {len(wait)}")
    return '\n'.join(lines)

def sort(B, repo, proj=None, as_json=False, T=None):
    """(the sorted list of every open pull request, 0) -- or (why nothing was sorted, 2) when the facts cannot be read."""
    T = T or datetime.date.today()
    rows, why = S.pr_rows(repo, S.R.load(B), T)
    if rows is None: return f'Open pull requests could not be read ({why}): nothing was sorted.', 2
    g = S.sort_prs(rows)
    if not as_json: return S.sort_text(g, R.arg(proj or os.path.basename(B)), T), 0
    row = lambda pr, why, act: dict(n=pr['n'], head=pr['head'], title=pr['title'], card=v(pr['card'] or {}, 'id') or None, card_name=R.name(pr['card'], 80) if pr['card'] else None,
                                    name=S.pr_called(pr), why=why, action=act)
    return json.dumps({'open': len(rows), 'groups': {k: [row(*x) for x in xs] for k, xs in g.items()}}, ensure_ascii=False), 0

def self_test():
    import tempfile
    T = datetime.date.today()
    with tempfile.TemporaryDirectory() as t:
        S = f'{t}/items/EPIC-01-bugs/stories'; os.makedirs(S)
        def card(n, body='', **kv):
            open(f'{S}/S{n}.md', 'w', encoding='utf-8').write('---\n' + ''.join(f'{k}: {x}\n' for k, x in {'id': f'E01-S{n}', 'type': 'breakfix', 'status': 'in-progress', **kv}.items()) + f'---\n{body}')
        open(f'{t}/items/EPIC-01-bugs/epic.md', 'w', encoding='utf-8').write('---\nid: E01\ntitle: Bugs\nstatus: in-progress\n---\n')
        url = 'https://github.com/org2/repo1/pull/109'
        card(1, stage='Fix ready', pr='[101]', priority='P1')                       # merged, released, checks pass -> done
        card(17, stage='Live', pr='[101]')                                          # the older Live stage: the same rule -> done
        card(2, stage='Fix ready', pr='[102, 103]')                                 # one still open -> waits
        card(3, stage='Cause found', pr='104')                                      # closed unmerged -> waits
        card(4, stage='Checked')                                                    # -> done
        card(5, stage='Fix ready', pr='[105]')                                      # merged after the newest release -> waits
        card(6, '\nFixed in PR #106.\n', stage='Fix ready')                         # no pr: -> waits, never guessed
        card(8, stage='Fix ready', pr='[101]', status='done')                       # done: left alone
        card(9, stage='Fix ready', pr=url)                                          # another repo's PR, by URL: its checks failed -> waits
        card(10, stage='Fix ready', pr='[110]', decision='Ratify #110?')            # closes, flags the decision
        card(12, stage='Fix ready', pr='splashdown#71')                             # short form: ambiguous -> waits
        card(13, stage='Needs decision', pr='[101]')                                # older waiting form: left alone
        card(18, stage='Fix ready', pr='[104, 101]')                                # its own PR closed, a release PR carried it -> done
        card(19, stage='Fix ready', pr='[111]')                                     # checks unreadable -> waits, said
        card(20, stage='Fix ready', pr='[101]', bundles='[E01-S21]'); card(21, stage='Fix ready', pr='[101]', bundledIn='E01-S20')  # a bundle with an open part -> waits; the part never closes on a PR
        open(f'{S}/S11.md', 'w', encoding='utf-8').write('---\nid: E01-S11\ntype: story\nstatus: in-progress\npr: [101]\n---\n')  # no stage: untouched
        st = {101: 'MERGED', 102: 'MERGED', 103: 'OPEN', 104: 'CLOSED', 105: 'MERGED', 106: 'MERGED', 109: 'OPEN', url: 'MERGED', 110: 'MERGED', 111: 'MERGED', 71: 'MERGED'}
        G = {'pr': lambda n: {'state': st.get(n, 'UNKNOWN'), 'mergedAt': '2026-10-15T10:00:00Z', 'mergeCommit': {'oid': f'c{n}'}},
             'release': lambda n, sha: ('not yet', 'v1.2.0') if n == 105 else ('in', 'v1.2.0'),
             'checks': lambda n, ref: ('fail', (['unit tests'], 3)) if n == url else ('unreadable', 'HTTP 502') if n == 111 else ('pass', 3)}
        before = {p: open(p, encoding='utf-8').read() for p in R.load(t)}
        out = run(t, G, dry=True, proj='t', T=T)
        assert {p: open(p, encoding='utf-8').read() for p in R.load(t)} == before and not os.path.exists(f'{t}/BOARD.md') and 'Would close 5' in out, out
        out = run(t, G, dry=False, proj='t', T=T)
        c = {v(d, 'id'): d for d in R.load(t).values()}
        done = lambda n: (v(c[f'E01-S{n}'], 'status'), v(c[f'E01-S{n}'], 'closed_as'))
        assert all(done(n) == ('done', 'shipped-tests-pass') for n in (1, 17, 10, 18)) and done(4) == ('done', ''), out
        assert [v(c[f'E01-S{n}'], 'stage') for n in (2, 3, 5, 6, 9, 12, 13, 19, 20)] == ['Fix ready', 'Cause found', 'Fix ready', 'Fix ready', 'Fix ready', 'Fix ready', 'Needs decision', 'Fix ready', 'Fix ready'], out
        assert not any(v(c[f'E01-S{n}'], 'status') == 'done' for n in (2, 3, 5, 6, 9, 12, 13, 19, 20, 11)) and v(c['E01-S8'], 'closed_as') == '', out
        assert v(c['E01-S6'], 'pr') == '' and v(c['E01-S1'], 'updated') == str(T) and v(c['E01-S1'], 'priority') == 'P1', out
        assert '(E01-S2) · #103 open' in out and '(E01-S3) · #104 closed without merging' in out and '(E01-S6) · no pr:' in out, out
        assert '(E01-S5) · #105 merged 2026-10-15, not in a release yet (the newest is v1.2.0)' in out, out
        assert '(E01-S9) · repo1#109 merged 2026-10-15, released in v1.2.0, but 1 of its 3 checks failed (unit tests)' in out and '(E01-S12) · pr: names another repo by short form' in out, out
        assert '(E01-S19) · #111 merged 2026-10-15, released in v1.2.0, but its checks could not be read (HTTP 502) -- left as it is' in out, out
        assert '(E01-S20) · #101 merged 2026-10-15, released in v1.2.0, but 1 of its parts has not passed its own check: Untitled card (E01-S21)' in out, out
        assert not any(f'(E01-S{n})' in out.replace('(E01-S21)', '') for n in (8, 11, 13, 21)), out  # done, stage-less, the older waiting form, a part
        one = open(f'{S}/S1.md', encoding='utf-8').read()
        assert 'Untitled card (E01-S1) · Fix ready → done · #101 merged 2026-10-15; released in v1.2.0; all 3 of that release\'s checks passed · not confirmed by a real run' in out, out
        assert f'## Shipped means done ({T})' in one and 'not confirmed by a real run' in one and '`/backlog-it reopen E01-S1 <what you saw>`' in one, one
        assert 'clear decision: and answers:' in out and '**Shipping:** S2, S5, S6, S9, S12, S19, S20' in open(f'{t}/BOARD.md', encoding='utf-8').read(), open(f'{t}/BOARD.md', encoding='utf-8').read()
        assert not [f for f in os.listdir(S) if f.endswith('.tmp')], os.listdir(S)
        out = run(t, G, dry=False, proj='t', T=T)  # nothing left to close: idempotent
        assert 'nothing to close' in out and 'Closed 0' in out, out
        assert v(R.fm(f'{S}/S21.md'), 'status') == 'in-progress'  # the part, merged PR and all, is still open
        card(21, stage='Fix ready', status='done', bundledIn='E01-S20')  # the part passed its own check: now the bundle closes
        assert '(E01-S20) · Fix ready → done' in run(t, G, dry=False, proj='t', T=T)
        card(14, stage='Checked'); card(15, stage='Fix ready', pr='[101]')
        out = run(t, None, dry=False, proj='t', T=T)  # no gh: Checked still closes, PR cards wait
        assert '(E01-S15) · PR step skipped' in out and v(R.fm(f'{S}/S14.md'), 'status') == 'done' and v(R.fm(f'{S}/S15.md'), 'stage') == 'Fix ready', out
        card(16, stage='Fix ready', pr='[101]')  # another session closes it while gh runs: the write is refused
        late = dict(G, pr=lambda n: (card(16, stage='Fix ready', status='done'), G['pr'](n))[1])
        out = run(t, late, dry=False, proj='t', T=T)
        assert v(R.fm(f'{S}/S16.md'), 'closed_as') == '' and 'E01-S16' not in out, out
        for how, says in ((('merge', ''), 'the merge is the release (the repo has no release tag); all 3 of the merge\'s checks passed'), (('unreadable', 'HTTP 500'), 'its release could not be read (HTTP 500)')):
            card(22, stage='Fix ready', pr='[101]'); out = run(t, dict(G, release=lambda n, sha: how), dry=True, proj='t', T=T)
            assert says in out, out
        for res, says in ((('running', 2), 'its checks are still running'), (('none', 0), 'no checks ran on it')):
            out = run(t, dict(G, checks=lambda n, ref: res), dry=True, proj='t', T=T); assert says in out and 'Would close 0' in out, out
    print('sync-prs self-test: OK')

if __name__ == '__main__':
    args = sys.argv[1:]
    if args == ['--self-test']: self_test(); sys.exit(0)
    opts = {}
    for k in ('--repo', '--project'):
        if k in args:
            i = args.index(k)
            if i + 1 >= len(args) or args[i + 1].startswith('--'): sys.exit(f'sync-prs: {k} needs a value')
            opts[k] = args[i + 1]; del args[i:i + 2]
    dry = '--dry-run' in args; args = [a for a in args if a != '--dry-run']
    sorting, as_json = '--sort' in args, '--json' in args; args = [a for a in args if a not in ('--sort', '--json')]
    if len(args) > 1 or any(a.startswith('--') for a in args): sys.exit(f'sync-prs: unexpected {args}')
    B = os.path.abspath(os.path.expanduser(args[0] if args else R.default_board('sync-prs')))
    if not os.path.isdir(f'{B}/items'): sys.exit(f'sync-prs: no items/ folder in {B}')
    repo = os.path.expanduser(opts['--repo']) if '--repo' in opts else None
    if sorting:
        text, rc = sort(B, repo, opts.get('--project'), as_json); print(text); sys.exit(rc)
    print(run(B, gh(repo) if repo else None, dry, opts.get('--project')))
    if repo: print('\n' + sort(B, repo, opts.get('--project'))[0])  # after every merge and release: every open pull request, sorted
