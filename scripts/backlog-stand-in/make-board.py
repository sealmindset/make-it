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
        ev.append((ago, f'{B}/items/{folder}/' + ('epic.md' if not s else f'stories/{s}.md'), kv))
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
    git = lambda *a, when: subprocess.run(['git', '-C', B, '-c', 'user.name=stand-in', '-c', 'user.email=stand-in@example.invalid', '-c', 'commit.gpgsign=false',
                                           '-c', 'core.hooksPath=/dev/null', *a], check=True, capture_output=True,
                                          env=dict(os.environ, GIT_AUTHOR_DATE=f'{when}T12:00:00', GIT_COMMITTER_DATE=f'{when}T12:00:00'))
    git('init', '-q', when=d(40))
    open(f'{B}/.gitignore', 'w', encoding='utf-8').write('.slack-webhook\n')
    for ago in sorted({e[0] for e in ev}, reverse=True):
        for _, p, kv in (e for e in ev if e[0] == ago):
            open(p, 'w', encoding='utf-8').write('---\n' + ''.join(f'{k}: {x}\n' for k, x in kv.items()) + '---\n')
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
    ok = [{'__typename': 'CheckRun', 'status': 'COMPLETED', 'conclusion': 'SUCCESS'}]
    pr = lambda n, title, ago=0, **kv: {'number': n, 'title': title, 'isDraft': False, 'reviewDecision': '', 'mergeStateStatus': 'CLEAN', 'baseRefName': 'main', 'headRefOid': f'{n:040x}',
                                        'statusCheckRollup': ok, 'updatedAt': f'{d(ago)}T09:00:00Z', **kv}
    prs = [pr(14, 'feat: a new report page', isDraft=True, mergeStateStatus='BLOCKED', statusCheckRollup=[{'__typename': 'CheckRun', 'status': 'IN_PROGRESS', 'conclusion': ''}])]
    if on('ready-pr'): prs.append(pr(11, 'fix: refund totals'))
    if on('stalled-pr'):
        prs += [pr(12, 'fix: slow search', mergeStateStatus='BEHIND'),
                pr(13, 'chore: tidy the logs', 5, isDraft=True, statusCheckRollup=[{'__typename': 'CheckRun', 'status': 'COMPLETED', 'conclusion': 'FAILURE'}])]
    open(os.path.join(out, 'prs.json'), 'w', encoding='utf-8').write(json.dumps(prs))
    os.makedirs(f'{out}/behind'); os.makedirs(f'{out}/files')
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
