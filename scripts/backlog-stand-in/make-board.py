#!/usr/bin/env python3
"""Make a stand-in backlog board: a temp git repo with cards in every state the first screen's rule
cares about, plus the pull-request facts the `gh` stand-in beside this file prints.

Usage: make-board.py DIR [--without a,b,...] [--with x,y,...] [--plan wave|ran-out|stuck|share|none] [--groom-days N|none]
  DIR/board     the board (its own git repo, commits dated so the weekly counts are real)
  DIR/prs.json  what `gh pr list` answers (point GH_STUB_PRS at it)
  Everything is on unless taken out with --without:
    waiting     a card with a question for the owner
    ready-pr    an open pull request that is reviewed, up to date, checks passing
    stalled-pr  one pull request behind main, one draft with a failing check and no change for 5 days
    growing     more cards opened than closed in each of the last two weeks
    safe-card   three bugs that can start
  Always there: four held high-stakes cards (two of them each free three cards), cards that wait on
  them, one pull request that is moving (never to be mentioned), and a finished card.
  --plan (default wave): wave = PLAN.md whose first wave can start; ran-out = every wave done;
    stuck = the next wave is a held card; share = its only wave is running and the cards that could
    start are not in it; none = no PLAN.md.
  Off unless asked for with --with:
    closed-kinds  five cards closed today: one plain done, two closed as shipped-tests-pass, one as
                  not-needed, one as duplicate
    reviewed      the ready pull request's card records a review of its current commit (`reviewed: <date> ready <commit>`);
                  reviewed-old = of an earlier commit; reviewed-not-ready = the review said not ready;
                  reviewed-malformed = the field has no commit
    behind        the ready pull request is 2 commits behind main; cannot-compare = gh cannot say
    other-work    a story in progress that is not a bug, changed today; other-quiet = one more, untouched for 20 days
    overlap       the moving pull request changes a file a card in the plan's first wave also names;
                  overlap-two = files of two of its cards; overlap-all = of all three
    no-files      gh cannot say which files the open pull requests change
    running-list  the Bugs epic holds a running list: two areas, three lines, one of them fixed
    bundle-set    cards to combine: three export bugs (two name the same two files in `files:`, the third names one
                  of them only in its text; together they are more than one sitting), two report stories where one
                  waits on the other, and a plain story that names the same file as a held high-stakes card
    shipped       fixes whose pull request is merged: one in the newest release (v1.2.0) with passing checks, one
                  still at the old Live stage, one whose own pull request was closed and a release pull request
                  carried it, one merged after that release, one still open. What `gh` then says of the release:
                  checks-unreadable, checks-fail, checks-running, no-checks (none ran), many-checks (150, of which
                  one page of 100 is read), no-tags (the repo has no
                  release at all: the merge is the release)
    quiet         cards quiet for 40 days, one for each reason a card never closes by itself (each marked `expires: ok`,
                  so only the hard rule keeps it), cards nobody has marked (three of them the kind only a judge
                  can tell is unsafe), one whose words changed after the mark, and two marked plain ideas quiet
                  for exactly 30 days and for 29
  --groom-days (default 20): GROOM-PLAN.md dated that many days ago; none = no GROOM-PLAN.md.
"""
import datetime, json, os, subprocess, sys

def main(args):
    opt = lambda k, d: args[args.index(k) + 1] if k in args else d
    out, off, plan, groom = args[0], set(opt('--without', '').split(',')), opt('--plan', 'wave'), opt('--groom-days', '20')
    extra = set(opt('--with', '').split(','))
    on = lambda k: k not in off
    T = datetime.date.today(); d = lambda n: str(T - datetime.timedelta(days=n))
    B = os.path.join(out, 'board'); os.makedirs(f'{B}/items/EPIC-01-bugs/stories'); os.makedirs(f'{B}/items/EPIC-02-board-work/stories')
    ev = []  # (days ago, path, frontmatter): written and committed oldest first, one commit a day
    def card(ago, cid, title, **kv):
        e, s = cid.split('-') if '-' in cid else (cid, None)
        folder = {'E01': 'EPIC-01-bugs', 'E02': 'EPIC-02-board-work'}[e]
        kv = {'id': cid, 'title': f'"{title}"', 'type': 'epic' if not s else 'breakfix' if e == 'E01' else 'story',
              'status': 'backlog', 'priority': 'P2', 'created': d(ago), 'updated': d(ago), **kv}
        if s and e == 'E01' and kv['status'] != 'done': kv.setdefault('stage', 'Reported')
        body = kv.pop('body', '')
        if kv.pop('stamp', False):  # a judge's mark, with the board's own print of the whole card as it will be written
            text = '---\n' + ''.join(f'{k}: {x}\n' for k, x in kv.items()) + '---\n' + body
            kv = {**kv, 'expires': 'ok', 'expires_why': 'a tidy-up nobody asked for; it cannot hurt anyone', 'expires_by': 'groom', **{'expires_of': kv.pop('expires_of', None) or STAMP(text)}}
        ev.append((ago, f'{B}/items/{folder}/' + ('epic.md' if not s else f'stories/{s}.md'), kv, body))
    card(40, 'E01', 'Bugs', status='in-progress'); card(40, 'E02', 'Board work', status='in-progress')
    held = dict(stakes='critical')
    card(30, 'E02-S1', 'Move sign-in to the new provider', priority='P1', **held)
    card(30, 'E02-S2', 'Change the billing tables', **held)
    card(30, 'E02-S3', 'Delete the old audit data', **held)
    card(30, 'E02-S4', 'Send the monthly statement to every customer', **held)
    card(30, 'E02-S5', 'The sign-in page uses the new provider', dependsOn='[E02-S1]')
    card(30, 'E02-S6', 'The roles screen reads the new provider', dependsOn='[E02-S1]')
    card(30, 'E02-S7', 'Invoices read the new billing tables', dependsOn='[E02-S2]')
    card(20, 'E01-S2', 'Totals are wrong after a refund', status='in-progress', stage='Fix ready', pr='[11]', updated=d(0),
         **({'reviewed': f'{d(0)} ready {11:040x}'[:len(d(0)) + 15]} if 'reviewed' in extra else {'reviewed': f'{d(40)} ready 0ddba11'} if 'reviewed-old' in extra
            else {'reviewed': f'{d(0)} not ready, two findings'} if 'reviewed-not-ready' in extra else {'reviewed': f'{d(0)} ready'} if 'reviewed-malformed' in extra else {}))
    if 'other-quiet' in extra: card(20, 'E02-S9', 'An old page nobody finished', status='in-progress')
    if 'other-work' in extra: card(20, 'E02-S8', 'A new page for monthly reports', status='in-progress', updated=d(0))
    if 'closed-kinds' in extra:
        for n, kind in ((41, None), (42, 'shipped-tests-pass'), (43, 'shipped-tests-pass'), (44, 'not-needed'), (45, 'duplicate')):
            card(25, f'E01-S{n}', f'A card closed in way {n}')
            card(0, f'E01-S{n}', f'A card closed in way {n}', status='done', created=d(25), **({'closed_as': kind} if kind else {}))
    card(20, 'E01-S4', 'Search is slow on big accounts', status='in-progress', stage='Fix ready', pr='[12]', updated=d(0))
    card(12, 'E01-S20', 'The old report shows stale numbers', dependsOn='[E02-S1]')
    card(11, 'E01-S22', 'The help page links to a page that is gone', dependsOn='[E02-S2]')
    card(1, 'E01-S21', 'The export button does nothing for one role', dependsOn='[E02-S2]')
    card(25, 'E01-S30', 'A finished fix'); card(10, 'E01-S30', 'A finished fix', status='done', created=d(25))
    if on('waiting'):
        card(3, 'E01-S3', 'Filings give up after two tries',
             decision='The retry job gave up on 3 filings after two tries; nothing else waits on them. Retry, or refile by hand?',
             answers='Retry -- runs them again tonight (Recommended; against: a third failure costs another day) | Refile -- you re-enter the 3 by hand')
    if on('safe-card') or plan in ('wave', 'share'):
        run = dict(status='in-progress', stage='Cause found', updated=d(0)) if plan == 'share' else {}
        card(10, 'E01-S10', 'Export drops the last row', **run)
        card(9, 'E01-S11', 'Search ignores accents'); card(2, 'E01-S12', 'Upload fails on big files')
    if not on('growing'):  # six fixes closed this week: the pile shrinks
        for n in range(31, 37):
            card(25, f'E01-S{n}', f'An old fix number {n}'); card(1, f'E01-S{n}', f'An old fix number {n}', status='done', created=d(25))
    found = '\n## Goal\nx\n\n## Found\nIn a review of other work.\n'
    if 'bundle-set' in extra:
        card(8, 'E01-S60', 'The export file has no header', priority='P3', size='S', category='export', files='[src/export.py, src/csv.py]', body=found)
        card(8, 'E01-S61', 'The export total is off by one', priority='P1', size='S', category='export', files='[src/csv.py, src/export.py]', body=found)
        card(8, 'E01-S62', 'Export times out on big accounts', size='L', category='export', body='\n## Goal\nThe loop in `src/export.py` reads every row twice.\n')
        card(8, 'E02-S20', 'Sort the report by date', size='S', category='reports', dependsOn='[E02-S21]', body=found)
        card(8, 'E02-S21', 'Add a date column to the report', size='S', category='reports', body=found)
        card(8, 'E02-S22', 'Tidy the words on the sign-in page', size='S', category='sign-in', files='[src/auth.py]', body=found)
        card(8, 'E02-S23', 'The sign-in page remembers the last user', size='S', category='sign-in', stakes='critical', files='[src/auth.py]', body=found)
    if 'shipped' in extra:
        fix = dict(status='in-progress', stage='Fix ready', updated=d(0))
        card(6, 'E01-S70', 'Dates show in the wrong time zone', pr='[21]', **fix)
        card(6, 'E01-S72', 'The invoice email has no subject', pr='[23]', **fix)
        card(6, 'E01-S74', 'A fix merged long ago that nobody checked', pr='[21]', signal='the page shows it', **dict(fix, stage='Live'))
        card(6, 'E01-S75', 'A fix carried by the release pull request', pr='[25, 21]', **fix)
        card(6, 'E01-S76', 'A fix still in review', pr='[26]', **fix)
    if 'quiet' in extra:
        import importlib.util  # the mark a judge leaves on a card that may close when quiet, made by the board's own function
        spec = importlib.util.spec_from_file_location('status_board', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '.claude', 'make-it', 'backlog', 'bin', 'status.py'))
        S = importlib.util.module_from_spec(spec); spec.loader.exec_module(S)
        STAMP = S.stamp_of
        q = lambda n, title, ago=40, stamp=True, **kv: card(ago, f'E02-S{n}', title, **{'body': found, 'stamp': stamp, **kv})
        q(30, 'A tidy-up nobody asked for', 30); q(31, 'Another tidy-up nobody asked for', 29)
        card(40, 'E01-S80', 'An old bug found in a review', body=found, stamp=True)
        q(33, 'Rework the page that moves customer records', stakes='critical')
        q(34, 'Rotate the API token every month')
        q(35, 'The page you asked for', body='\n## Captured\n> make me a page\n_via /backlog-it capture_\n')
        q(36, 'A plain idea nobody has marked', stamp=False)
        q(37, 'A pinned tidy-up', pin='1')
        q(38, 'A tidy-up another card waits on')
        q(39, 'A tidy-up the owner decided on', dependsOn='[E02-S38]', body=found + '\n## Owner decision\nDo it after the move.\n')
        q(40, 'A tidy-up another card talks about')
        q(41, 'A card that talks about another', 0, body='\n## Captured\n> this goes with E02-S40\n')
        q(42, 'A tidy-up with a pull request', pr='[30]')
        q(43, 'A tidy-up somebody started', status='in-progress')
        q(44, 'A tidy-up inside a bundle', bundledIn='E02-S46'); q(45, 'Its partner inside the bundle', bundledIn='E02-S46')
        q(46, 'Two tidy-ups in one sitting', bundles='[E02-S44, E02-S45]')
        q(47, 'A tidy-up somebody brought back', reopened=d(40))
        q(48, 'A tidy-up of no known type', type='')
        # the independent review's cards: nothing in their fields says "safety" or "a person asked" -- only a judge who reads them can
        q(90, 'Anyone can read other customers invoices', stamp=False)
        q(91, 'Drops the customer table on upgrade', stamp=False)
        q(92, 'Owner asked in Found line', stamp=False, body='\n## Goal\nx\n\n## Found (2026-09-01, the owner asked for this)\nRob said: I want this.\n')
        q(93, 'The page must say the true total', maturity='mandate')
        q(94, 'A tidy-up whose words changed after it was marked', expires_of='000000000000')
        q(95, 'A tidy-up dated in the future', updated=str(T + datetime.timedelta(days=96)))
        q(96, 'A tidy-up with no dates', 0, created='', updated='')  # git still dates it; on a copy with no git nothing does
    git = lambda *a, when: subprocess.run(['git', '-C', B, '-c', 'user.name=stand-in', '-c', 'user.email=stand-in@example.invalid', '-c', 'commit.gpgsign=false',
                                           '-c', 'core.hooksPath=/dev/null', *a], check=True, capture_output=True,
                                          env=dict(os.environ, GIT_AUTHOR_DATE=f'{when}T12:00:00', GIT_COMMITTER_DATE=f'{when}T12:00:00'))
    git('init', '-q', when=d(40))
    open(f'{B}/.gitignore', 'w', encoding='utf-8').write('.slack-webhook\n')
    for ago in sorted({e[0] for e in ev}, reverse=True):
        for _, p, kv, body in (e for e in ev if e[0] == ago):
            open(p, 'w', encoding='utf-8').write('---\n' + ''.join(f'{k}: {x}\n' for k, x in kv.items()) + '---\n' + body)
        git('add', '-A', when=d(ago)); git('commit', '-qm', f'cards of {d(ago)}', when=d(ago))
    if 'running-list' in extra:
        with open(f'{B}/items/EPIC-01-bugs/epic.md', 'a', encoding='utf-8') as fh:
            fh.write('\n## Running list: export\n- the header row is counted as data (export.py) · found 2026-11-20 in "Export drops the last row (E01-S10)"\n'
                     '- the file name has no date (export.py) · found 2026-11-20 in "Export drops the last row (E01-S10)"\n'
                     '- fixed 2026-11-22: "the file name has no date" · pull request 9\n'
                     '\n## Running list: search\n- an empty search shows an error (search.py) · found 2026-11-21 in "Search ignores accents (E01-S11)"\n')
    waves = {'wave': '1. **dispatch-it** ×3 · Export drops the last row (E01-S10) · Search ignores accents (E01-S11) · Upload fails on big files (E01-S12) -- three separate files\n'
                     '   - Export drops the last row (E01-S10) -- the oldest · files: src/export.py\n'
                     '   - Search ignores accents (E01-S11) -- small · files: src/search.py, src/text.py\n'
                     '   - Upload fails on big files (E01-S12) -- one function · files: src/upload.py\n'
                     '2. **solo** · The old report shows stale numbers (E01-S20) -- after the sign-in move (E02-S1)\n',
             'ran-out': '1. **solo** · A finished fix (E01-S30) -- done\n',
             'stuck': '1. **solo** · A finished fix (E01-S30) -- done\n2. **solo** · Move sign-in to the new provider (E02-S1) -- it frees two cards\n',
             'share': '1. **solo** · Export drops the last row (E01-S10) -- the oldest bug\n'}
    if plan != 'none':
        open(f'{B}/PLAN.md', 'w', encoding='utf-8').write(f'# Run Plan -- {d(1)}  (scope: all)\n\n## Waves\n{waves[plan]}\n'
            '## ⚠️ Held -- needs the alignment brief and an explicit go\n- ⚠️ Change the billing tables (E02-S2) -- high-stakes\n')
    if groom != 'none':
        open(f'{B}/GROOM-PLAN.md', 'w', encoding='utf-8').write(f'# Groom Plan -- {d(int(groom))}  (scope: all)\n')
    git('add', '-A', when=d(0)); git('commit', '-qm', 'plans', '--allow-empty', when=d(0))
    os.makedirs(f'{out}/behind'); os.makedirs(f'{out}/files')
    ok = [{'__typename': 'CheckRun', 'status': 'COMPLETED', 'conclusion': 'SUCCESS'}]
    pr = lambda n, title, ago=0, **kv: {'number': n, 'title': title, 'isDraft': False, 'reviewDecision': '', 'mergeStateStatus': 'CLEAN', 'baseRefName': 'main', 'headRefOid': f'{n:040x}',
                                        'statusCheckRollup': ok, 'updatedAt': f'{d(ago)}T09:00:00Z', **kv}
    prs = [pr(14, 'feat: a new report page', isDraft=True, mergeStateStatus='BLOCKED', statusCheckRollup=[{'__typename': 'CheckRun', 'status': 'IN_PROGRESS', 'conclusion': ''}])]
    if on('ready-pr'): prs.append(pr(11, 'fix: refund totals'))
    if on('stalled-pr'):
        prs += [pr(12, 'fix: slow search', mergeStateStatus='BEHIND'),
                pr(13, 'chore: tidy the logs', 5, isDraft=True, statusCheckRollup=[{'__typename': 'CheckRun', 'status': 'COMPLETED', 'conclusion': 'FAILURE'}])]
    open(os.path.join(out, 'prs.json'), 'w', encoding='utf-8').write(json.dumps(prs))
    if 'shipped' in extra:  # what the gh stand-in answers about merged pull requests, the newest release and its checks
        os.makedirs(f'{out}/prstate'); os.makedirs(f'{out}/checks')
        state = lambda n, st, sha=None: open(f'{out}/prstate/{n}.json', 'w', encoding='utf-8').write(json.dumps(
            {'state': st, 'mergedAt': f'{d(3)}T10:00:00Z' if sha else None, 'mergeCommit': {'oid': sha} if sha else None}))
        state(21, 'MERGED', 'c21'); state(23, 'MERGED', 'c23'); state(25, 'CLOSED')
        tag = None if 'no-tags' in extra else 'v1.2.0'
        open(f'{out}/tags.json', 'w', encoding='utf-8').write(json.dumps([{'name': tag}] if tag else []))
        for sha, behind in (('c21', 0), ('c23', 1)):
            open(f'{out}/behind/{sha}...{tag}', 'w', encoding='utf-8').write(json.dumps({'behind_by': behind}))
        run = lambda name, concl='success', st='completed': {'name': name, 'status': st, 'conclusion': concl}
        runs = ([run('unit tests'), run('lint'), run('build', 'skipped')] if not extra & {'checks-fail', 'checks-running', 'no-checks'}
                else [run('unit tests', 'failure'), run('lint')] if 'checks-fail' in extra else [run('unit tests', None, 'in_progress')] if 'checks-running' in extra else [])
        if 'many-checks' in extra: runs = [run(f'check {k}') for k in range(100)]  # one page of 100, and GitHub says there are 150
        if 'checks-unreadable' not in extra:
            for ref in ([tag] if tag else ['c21', 'c23']):
                open(f'{out}/checks/{ref}.json', 'w', encoding='utf-8').write(json.dumps({'total_count': 150 if 'many-checks' in extra else len(runs), 'check_runs': runs}))
    for p in prs:  # what the gh stand-in answers about each pull request: how far behind main, and its files
        if 'cannot-compare' not in extra:
            open(f"{out}/behind/{p['number']:040x}", 'w', encoding='utf-8').write(json.dumps({'behind_by': 2 if 'behind' in extra and p['number'] == 11 else 0}))
        if 'no-files' not in extra:
            hit = ['src/search.py'] * bool(extra & {'overlap', 'overlap-two', 'overlap-all'}) + ['src/export.py'] * bool(extra & {'overlap-two', 'overlap-all'}) + ['src/upload.py'] * ('overlap-all' in extra)
            paths = hit if hit and p['number'] == 14 else [f"src/pr{p['number']}.py"]
            open(f"{out}/files/{p['number']}.json", 'w', encoding='utf-8').write(json.dumps({'files': [{'path': x} for x in paths]}))

if __name__ == '__main__':
    if len(sys.argv) < 2 or sys.argv[1].startswith('-'): sys.exit(__doc__)
    main(sys.argv[1:])
