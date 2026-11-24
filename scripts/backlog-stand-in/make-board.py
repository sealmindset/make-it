#!/usr/bin/env python3
"""Make a stand-in backlog board: a temp git repo with cards in every state the first screen's rule
cares about, plus the pull-request facts the `gh` stand-in beside this file prints.

Usage: make-board.py DIR [--without a,b,...] [--plan wave|ran-out|stuck|share|none] [--groom-days N|none]
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
  --groom-days (default 20): GROOM-PLAN.md dated that many days ago; none = no GROOM-PLAN.md.
"""
import datetime, json, os, subprocess, sys

def main(args):
    opt = lambda k, d: args[args.index(k) + 1] if k in args else d
    out, off, plan, groom = args[0], set(opt('--without', '').split(',')), opt('--plan', 'wave'), opt('--groom-days', '20')
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
    card(20, 'E01-S2', 'Totals are wrong after a refund', status='in-progress', stage='Fix ready', pr='[11]', updated=d(0))
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
    waves = {'wave': '1. **dispatch-it** ×3 · Export drops the last row (E01-S10) · Search ignores accents (E01-S11) · Upload fails on big files (E01-S12) -- three separate files\n'
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
    pr = lambda n, title, ago=0, **kv: {'number': n, 'title': title, 'isDraft': False, 'reviewDecision': '', 'mergeStateStatus': 'CLEAN',
                                        'statusCheckRollup': ok, 'updatedAt': f'{d(ago)}T09:00:00Z', **kv}
    prs = [pr(14, 'feat: a new report page', isDraft=True, mergeStateStatus='BLOCKED', statusCheckRollup=[{'__typename': 'CheckRun', 'status': 'IN_PROGRESS', 'conclusion': ''}])]
    if on('ready-pr'): prs.append(pr(11, 'fix: refund totals'))
    if on('stalled-pr'):
        prs += [pr(12, 'fix: slow search', mergeStateStatus='BEHIND'),
                pr(13, 'chore: tidy the logs', 5, isDraft=True, statusCheckRollup=[{'__typename': 'CheckRun', 'status': 'COMPLETED', 'conclusion': 'FAILURE'}])]
    open(os.path.join(out, 'prs.json'), 'w', encoding='utf-8').write(json.dumps(prs))

if __name__ == '__main__':
    if len(sys.argv) < 2 or sys.argv[1].startswith('-'): sys.exit(__doc__)
    main(sys.argv[1:])
