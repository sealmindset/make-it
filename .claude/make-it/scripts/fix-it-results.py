#!/usr/bin/env python3
"""fix-it-results.py -- /fix-it's record of what really happened (E02-S92).

/fix-it used to work its "Fixed" count out by subtraction (findings before minus findings after), so a
finding whose scanner did not run the second time counted as fixed; and it took "tests pass" and "still
builds" from commands whose failure fell through. This script is where those results come from now:

  start ATTESTATION            begin a run's record (kept inside .git, never committed)
  scope ID SEVERITY TITLE      one in-scope finding (once each)
  record ID EVENT [NOTE]       what happened to it: changed | failed | person | skipped, and after
                               the re-scan: gone | still
  rescan NEW_ATTESTATION       read which checks ran in the re-scan (its Category Breakdown table)
  check tests|build            find where the tests / the build live, run them there, record the result
  check NAME [--in DIR] -- CMD run one command as a named check, record the result
  summary                      the counts, each finding's outcome, and the sentences for the person

Rules it holds: every finding has exactly one outcome (fixed / changed, not re-checked / failed / needs a
person / not attempted) and the counts add up to the findings in scope; "fixed" needs a kept change AND
a re-scan that ran the same check and no longer reports it; every check is passed / failed / not run from
the command's own exit status and output, and "not run" is never worded or counted as passed.

Standard library only. Run it with `python3 -I`.
"""
import json
import os
import re
import shutil
import signal
import subprocess
import sys

SEVERITIES = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO']
EVENTS = ['changed', 'failed', 'person', 'skipped', 'gone', 'still']
OUTCOMES = ['fixed', 'unchecked', 'failed', 'person', 'not attempted']
HEAD = {'fixed': 'Fixed', 'unchecked': 'Changed, not re-checked', 'failed': 'Failed',
        'person': 'Needs a person', 'not attempted': 'Not attempted'}
RAN = ('PASS', 'FAIL')   # a re-scan row with one of these ran its check; anything else did not, or not all of it
SKIP_DIRS = {'node_modules', 'venv', '.venv', 'dist', 'build', '.next', '__pycache__', 'site-packages', 'guardrails'}


def die(msg):
    print('fix-it-results: ' + msg, file=sys.stderr)
    sys.exit(2)


def git(*args):
    try:
        p = subprocess.run(['git'] + list(args), capture_output=True, text=True)
    except OSError:
        die('git is not installed')
    if p.returncode != 0:
        die('this folder is not inside a git project, so there is nowhere to keep the record')
    return p.stdout.strip()


def paths():
    root = git('rev-parse', '--show-toplevel')
    return root, os.path.join(os.path.abspath(git('rev-parse', '--git-path', 'fix-it-run')), 'ledger.jsonl')


def load(ledger):
    if not os.path.isfile(ledger):
        die('no run has been started here: run `start <attestation>` first (Phase 0)')
    with open(ledger, encoding='utf-8') as f:
        return [json.loads(line) for line in f if line.strip()]


def add(ledger, row):
    with open(ledger, 'a', encoding='utf-8') as f:
        f.write(json.dumps(row) + '\n')


def category(fid):
    """DEP-TRIVY-002 -> DEP-TRIVY: the Category Breakdown row a finding belongs to."""
    return re.sub(r'-\d+$', '', fid)


def join(*parts):
    return '; '.join(p for p in parts if p)


def resolve(rows):
    """Each finding's one outcome, from its recorded events in order. Returns ({id: (sev, title, outcome, note)}, ids)."""
    scope, order, cats, rescanned = {}, [], {}, False
    for r in rows:
        if r[0] == 'scope':
            scope[r[1]] = [r[2], r[3], 'not attempted', '']
            order.append(r[1])
        elif r[0] == 'rescan':
            rescanned, cats = True, r[2]
        elif r[0] == 'event':
            f, ev, note = scope[r[1]], r[2], r[3]
            if ev == 'changed':
                f[2], f[3] = 'changed', note
            elif ev == 'failed':
                f[2], f[3] = 'failed', note
            elif ev == 'person':
                f[2], f[3] = 'person', note
            elif ev == 'skipped':
                f[2], f[3] = 'not attempted', note
            elif ev == 'still' and f[2] in ('changed', 'fixed', 'unchecked'):
                f[2], f[3] = 'failed', join(f[3], 'the new scan still reports it', note)
            elif ev == 'gone' and f[2] == 'changed':
                st = cats.get(category(r[1]))
                if st in RAN:
                    f[2] = 'fixed'
                else:
                    f[2] = 'unchecked'
                    f[3] = join(f[3], 'the new scan did not run this check (%s: %s)' % (category(r[1]), st or 'no row'))
    for f in scope.values():
        if f[2] == 'changed':   # a kept change with no verdict from a re-scan is not "fixed"
            f[2] = 'unchecked'
            f[3] = join(f[3], 'no new scan has checked it' if not rescanned else 'the new scan gave no verdict on it')
    return scope, order


def checks(rows):
    """The latest result of each check: {name: {where: (cmd, result, detail)}}. An automatic run replaces that name's earlier results."""
    out = {}
    for r in rows:
        if r[0] == 'checkrun':
            out[r[1]] = {}
        elif r[0] == 'check':
            out.setdefault(r[1], {})[r[2]] = (r[3], r[4], r[5])
    return out


# ---- running a check -------------------------------------------------------------------------------------

def timeout():
    try:
        return max(1, int(os.environ.get('FIXIT_CHECK_TIMEOUT', '900')))
    except ValueError:
        return 900


def run(cmd, cwd):
    """(exit status or None on timeout, output). 127 when the command cannot be started."""
    env = dict(os.environ, CI='true', PYTHONDONTWRITEBYTECODE='1')
    posix = os.name == 'posix'
    try:
        p = subprocess.Popen(cmd, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True, errors='replace', start_new_session=posix)
    except OSError:
        return 127, ''
    try:
        out, _ = p.communicate(timeout=timeout())
        return p.returncode, out
    except subprocess.TimeoutExpired:
        if posix:
            os.killpg(p.pid, signal.SIGKILL)   # the whole group: npm's children too
        else:
            p.kill()
        out, _ = p.communicate()
        return None, out


def count(out, word):
    """The biggest 'N passed' / 'pass N' style number in a test runner's output (pytest, jest, vitest, mocha, node --test)."""
    stem = {'pass': r'pass(?:ed|ing)', 'fail': r'fail(?:ed|ing|ures?)'}[word]
    nums = re.findall(r'(\d+) ' + stem + r'\b', out) + re.findall(r'(?m)^(?:\S\s+)?' + word + r' (\d+)\s*$', out)
    return max([int(n) for n in nums] or [0])


def classify(name, rc, out):
    """(result, detail): result is passed, failed or not run, from the exit status and the output."""
    out = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', out)
    if rc is None:
        return 'failed', 'it did not finish within %d seconds, so I stopped it' % timeout()
    if rc in (126, 127) or (rc and re.search(r'npx canceled|could not determine executable to run|No module named (pytest|mypy|ruff|flake8)\b', out)):
        return 'not run', 'the command could not be started (exit status %d: a tool it needs is not installed)' % rc
    if name != 'tests':
        return ('passed', 'it finished without an error') if rc == 0 else ('failed', 'exit status %d' % rc)
    passed, failed = count(out, 'pass'), count(out, 'fail')
    if re.search(r'no tests ran|No tests found|No test files found|no test specified', out) or (rc == 5 and not passed):
        return 'not run', 'the test command ran but found no tests'
    if rc != 0:
        return 'failed', ('%d failed, %d passed' % (failed, passed) if failed else 'exit status %d' % rc)
    if passed:
        return 'passed', '%d passed' % passed
    return 'not run', 'the test command finished without an error, but its output does not show a test that ran'


def record_check(ledger, root, name, where, cmd, rc, out):
    result, detail = classify(name, rc, out)
    rel = os.path.relpath(where, root)
    rel = '' if rel == '.' else rel + '/'
    add(ledger, ['check', name, rel, ' '.join(cmd), result, detail])
    tail = [line for line in out.splitlines() if line.strip()][-40:]
    if result != 'passed' and tail:
        print('\n'.join(tail))
    print('CHECK %s | %s | %s | %s | %s' % (name, rel or '(project folder)', ' '.join(cmd), result.upper(), detail))
    return result


def project_dirs(root):
    """The project folder, then its folders two levels down, hidden and installed-package folders left out."""
    out = [root]
    for d in out:   # the list grows as it is walked: root, its folders, then theirs
        if d != root and os.path.relpath(d, root).count(os.sep) >= 1:
            continue
        try:
            names = sorted(os.listdir(d))
        except OSError:
            continue
        out += [os.path.join(d, n) for n in names
                if not n.startswith('.') and n not in SKIP_DIRS and os.path.isdir(os.path.join(d, n))
                and not os.path.islink(os.path.join(d, n))]
    return out


def npm_script(d, script):
    try:
        with open(os.path.join(d, 'package.json'), encoding='utf-8') as f:
            s = json.load(f).get('scripts', {}).get(script, '')
    except (OSError, ValueError, AttributeError):
        return False
    return bool(s) and 'no test specified' not in s


def has_pytest_suite(d):
    def tests_in(p, deep):
        for base, dirs, files in os.walk(p):
            dirs[:] = [x for x in dirs if deep and not x.startswith('.') and x not in SKIP_DIRS]
            if any(re.match(r'(test_.*|.*_test)\.py$', f) for f in files):
                return True
        return False
    if os.path.isfile(os.path.join(d, 'pytest.ini')):
        return True
    try:
        with open(os.path.join(d, 'pyproject.toml'), encoding='utf-8') as f:
            if '[tool.pytest' in f.read():
                return True
    except OSError:
        pass
    return tests_in(d, False) or any(tests_in(os.path.join(d, t), True) for t in ('tests', 'test'))


def pytest_python(d, root):
    """The python that has pytest: the project's own venv first, then python3 / python."""
    for py in [os.path.join(x, v, 'bin', 'python') for x in (d, root) for v in ('.venv', 'venv')] + ['python3', 'python']:
        if (os.sep not in py or os.path.isfile(py)) and run([py, '-m', 'pytest', '--version'], d)[0] == 0:
            return py
    return None


def check_auto(ledger, root, name):
    add(ledger, ['checkrun', name])
    results, suites = [], []
    for d in project_dirs(root):
        if name == 'tests' and has_pytest_suite(d) and not any(d.startswith(s + os.sep) for s in suites):
            suites.append(d)   # ponytail: pytest in a folder also collects the folders below it, so those are not run twice
            py = pytest_python(d, root)
            cmd = [py or 'python3', '-m', 'pytest', '-q', '-p', 'no:cacheprovider']
            results.append(record_check(ledger, root, name, d, cmd, *(run(cmd, d) if py else (127, 'pytest is not installed'))))
        if npm_script(d, 'test' if name == 'tests' else 'build'):
            cmd = ['npm', 'test'] if name == 'tests' else ['npm', 'run', 'build']
            results.append(record_check(ledger, root, name, d, cmd, *(run(cmd, d) if shutil.which('npm') else (127, 'npm is not installed'))))
    if not results:
        what = 'no test suite' if name == 'tests' else 'no build step'
        add(ledger, ['check', name, '-', '', 'not run', 'I found %s in this project' % what])
        print('CHECK %s | - | - | NOT RUN | I found %s in this project' % (name, what))
        results.append('not run')
    return results


# ---- the summary -----------------------------------------------------------------------------------------

def plural(n, one, many):
    return '%d %s' % (n, one if n == 1 else many)


def check_sentences(done):
    out, res = [], {}
    for name in ['tests', 'build'] + sorted(k for k in done if k not in ('tests', 'build')):
        got = done.get(name)
        label = {'tests': 'Tests', 'build': 'Build'}.get(name, 'Check "%s"' % name)
        if not got:
            if name == 'tests':
                out.append("Tests: not run. I did not run your app's tests, so I can't say they pass.")
            else:
                out.append("Build: not checked. I did not build your app, so I can't say it still builds.")
            res[name] = {'not run'}
            continue
        res[name] = {v[1] for v in got.values()}
        for where, (cmd, result, detail) in sorted(got.items()):
            place = 'the project folder' if where == '' else where
            if where == '-':
                out.append('%s: %s. %s.%s' % (label, 'no tests ran' if name == 'tests' else 'not checked', detail[0].upper() + detail[1:],
                                              ' That is not a pass.' if name == 'tests' else " I can't say the app still builds."))
            elif result == 'passed':
                if name == 'tests':
                    out.append('Tests: passed in %s (`%s`: %s).' % (place, cmd, detail))
                elif name == 'build':
                    out.append('Build: the app still builds (`%s` in %s finished without an error).' % (cmd, place))
                else:
                    out.append('%s: passed in %s (`%s`).' % (label, place, cmd))
            elif result == 'failed':
                if name == 'tests':
                    out.append('Tests: did NOT pass in %s (`%s`: %s).' % (place, cmd, detail))
                elif name == 'build':
                    out.append('Build: the app does NOT build (`%s` in %s failed: %s).' % (cmd, place, detail))
                else:
                    out.append('%s: FAILED in %s (`%s`: %s).' % (label, place, cmd, detail))
            else:
                if name == 'tests':
                    out.append('Tests: no tests ran in %s (`%s`: %s). That is not a pass.' % (place, cmd, detail))
                elif name == 'build':
                    out.append('Build: not checked in %s (`%s`: %s). I can\'t say the app still builds.' % (place, cmd, detail))
                else:
                    out.append('%s: not run in %s (`%s`: %s). That is not a pass.' % (label, place, cmd, detail))
    return out, res


def summary(rows, ledger):
    scope, order = resolve(rows)
    n = len(order)
    by = {o: [i for i in order if scope[i][2] == o] for o in OUTCOMES}
    assert sum(len(v) for v in by.values()) == n, 'the outcomes do not add up to the findings in scope'
    print('RESULTS -- from the record of this run (%s)\n' % ledger)
    print('| Severity | In scope | ' + ' | '.join(HEAD[o] for o in OUTCOMES) + ' |')
    print('|---|---|' + '---|' * len(OUTCOMES))
    for sev in SEVERITIES:
        ids = [i for i in order if scope[i][0] == sev]
        if ids:
            print('| %s | %d | %s |' % (sev, len(ids), ' | '.join(str(sum(1 for i in ids if scope[i][2] == o)) for o in OUTCOMES)))
    print('| **Total** | %d | %s |\n' % (n, ' | '.join(str(len(by[o])) for o in OUTCOMES)))
    for i in order:
        sev, title, outcome, note = scope[i]
        print('- %s (%s) %s -- %s%s' % (i, sev, title, HEAD[outcome].upper(), ': ' + note if note else ''))
    done = checks(rows)
    print()
    for name in sorted(done):
        for where, (cmd, result, detail) in sorted(done[name].items()):
            print('CHECK %s | %s | %s | %s | %s' % (name, where or '(project folder)', cmd or '-', result.upper(), detail))

    say = []
    fixed = len(by['fixed'])
    ids = lambda o: ' (' + ', '.join(by[o]) + ')'
    if n == 0:
        say.append('No findings were in scope, so nothing was fixed.')
    elif fixed == n:
        say.append('%s I set out to fix %s fixed: each change is kept, and the new scan ran the same check and no longer reports it.'
                   % ('The 1 finding' if n == 1 else 'All %d findings' % n, 'is' if n == 1 else 'are'))
    else:
        say.append('Of the %s I set out to fix, %s' % (plural(n, 'finding', 'findings'), 'none is confirmed fixed.' if fixed == 0 else
                   '%d %s fixed: the change is kept, and the new scan ran the same check and no longer reports it.' % (fixed, 'is' if fixed == 1 else 'are')))
        k = len(by['unchecked'])
        if k:
            say.append("%s changed but not re-checked: no new scan ran the check that found %s, so I can't say %s fixed.%s"
                       % (plural(k, 'was', 'were'), 'it' if k == 1 else 'them', 'it is' if k == 1 else 'they are', ids('unchecked')))
        k = len(by['failed'])
        if k:
            say.append('%s not fixed: I tried, and the fix did not work or the new scan still reports the problem.%s'
                       % (plural(k, 'is', 'are'), ids('failed')))
        k = len(by['person'])
        if k:
            say.append('%s a person: I did not fix %s, and %s on the manual list.%s'
                       % (plural(k, 'needs', 'need'), 'it' if k == 1 else 'them', 'it is' if k == 1 else 'they are', ids('person')))
        k = len(by['not attempted'])
        if k:
            say.append('%s not attempted: nothing was changed for %s.%s'
                       % (plural(k, 'was', 'were'), 'it' if k == 1 else 'them', ids('not attempted')))
    lines, res = check_sentences(done)
    say += lines
    bad = sorted(k for k in res if 'failed' in res[k])
    unrun = sorted(k for k in res if 'not run' in res[k] and 'failed' not in res[k])
    urgent = [i for i in order if scope[i][0] in ('CRITICAL', 'HIGH')]
    open_urgent = [i for i in urgent if scope[i][2] != 'fixed']
    if urgent:
        say.append('Critical and high findings: %s.' % ('all %d fixed' % len(urgent) if not open_urgent else
                   '%d of %d not confirmed fixed (%s)' % (len(open_urgent), len(urgent), ', '.join(open_urgent))))
    lead = 'everything I set out to fix is fixed' if n else 'nothing was in scope to fix'
    if fixed == n and not bad and not unrun:
        say.append('Bottom line: %s, and every check I ran passed.' % lead)
    elif fixed == n and not bad:
        say.append('Bottom line: %s and nothing failed, but not every check ran (see above), so this is not a full all-clear.' % lead)
    else:
        why = []
        if fixed != n:
            why.append('%s not confirmed fixed' % plural(n - fixed, 'finding is', 'findings are'))
        why += [{'tests': 'the tests did not pass', 'build': 'the app does not build'}.get(b, 'the check "%s" failed' % b) for b in bad]
        for u in unrun:
            part = ' everywhere' if 'passed' in res[u] else ''
            why.append({'tests': 'tests did not run' + part if part else 'no tests ran', 'build': 'the build was not checked' + part}
                       .get(u, 'the check "%s" did not run%s' % (u, part)))
        say.append('Bottom line: this is not finished -- ' + '; '.join(why) + '.')
    print('\nSAY THIS TO THE PERSON (built from the record above; never reword a result into a better one):')
    print('\n'.join(say))


# ---- commands --------------------------------------------------------------------------------------------

def read_dashboard(path):
    """{category id: status} from the attestation's Category Breakdown table (the columns named ID and Status)."""
    cats, cols = {}, None
    try:
        with open(path, encoding='utf-8') as f:
            for line in f:
                cells = [c.strip() for c in line.strip().strip('|').split('|')]
                if not line.lstrip().startswith('|'):
                    cols = None
                elif cols is None and 'ID' in cells and 'Status' in cells:
                    cols = (cells.index('ID'), cells.index('Status'))
                elif cols and len(cells) > max(cols) and not set(cells[cols[0]]) <= set('-: '):
                    cats[cells[cols[0]]] = cells[cols[1]].upper()
    except OSError as e:
        die('cannot read %s: %s' % (path, e.strerror))
    return cats


def main(argv):
    if not argv:
        die(__doc__)
    cmd, args = argv[0], argv[1:]
    root, ledger = paths()
    if cmd == 'start' and len(args) == 1:
        os.makedirs(os.path.dirname(ledger), exist_ok=True)
        with open(ledger, 'w', encoding='utf-8') as f:
            f.write(json.dumps(['start', args[0]]) + '\n')
        print('Recording this run in %s (inside .git: it is never committed).' % ledger)
        return 0
    rows = load(ledger)
    scope, _ = resolve(rows)
    if cmd == 'scope' and len(args) == 3:
        fid, sev, title = args[0], args[1].upper(), args[2]
        if sev not in SEVERITIES:
            die('severity must be one of ' + ', '.join(SEVERITIES) + ', not ' + args[1])
        if fid in scope:
            die(fid + ' is already in scope')
        add(ledger, ['scope', fid, sev, title])
        print('in scope: %s (%s) -- not attempted until something is recorded for it' % (fid, sev))
    elif cmd == 'record' and len(args) >= 2:
        fid, ev, note = args[0], args[1], ' '.join(args[2:])
        if fid not in scope:
            die(fid + ' is not in scope: only an in-scope finding has an outcome')
        if ev not in EVENTS:
            die('the event must be one of ' + ', '.join(EVENTS) + ', not ' + ev)
        if ev in ('gone', 'still'):
            if not any(r[0] == 'rescan' for r in rows):
                die('no re-scan is recorded: run `rescan <new attestation>` first')
            if scope[fid][2] not in ('unchecked', 'fixed'):   # 'unchecked' here = a kept change awaiting its verdict
                die('%s has no kept change (it is "%s"), so the re-scan does not change its outcome' % (fid, scope[fid][2]))
        add(ledger, ['event', fid, ev, note])
        after = resolve(load(ledger))[0][fid]
        print('%s: %s%s' % (fid, HEAD[after[2]].upper() if ev in ('gone', 'still') or after[2] != 'unchecked' else 'CHANGED (not fixed until the re-scan confirms it)',
                            ' -- ' + after[3] if after[3] else ''))
    elif cmd == 'rescan' and len(args) == 1:
        cats = read_dashboard(args[0])
        if not cats:
            die('I could not read which checks ran from %s (no Category Breakdown rows with ID and Status). '
                'Nothing is recorded, so every changed finding stays "changed, not re-checked".' % args[0])
        add(ledger, ['rescan', args[0], cats])
        for c in sorted(cats):
            print('%s: %s -- %s' % (c, cats[c], 'ran' if cats[c] in RAN else 'did NOT run (or not all of it): its findings cannot be called fixed'))
    elif cmd == 'check' and args and args[0] in ('tests', 'build') and len(args) == 1:
        results = check_auto(ledger, root, args[0])
        return 0 if all(r == 'passed' for r in results) else 1
    elif cmd == 'check' and args and '--' in args and args.index('--') < len(args) - 1:
        i = args.index('--')
        head, command = args[:i], args[i + 1:]
        if not head or len(head) not in (1, 3) or (len(head) == 3 and head[1] != '--in'):
            die('usage: check NAME [--in DIR] -- COMMAND...')
        where = os.path.abspath(head[2]) if len(head) == 3 else root
        if not os.path.isdir(where):
            add(ledger, ['check', head[0], head[2] if len(head) == 3 else '', ' '.join(command), 'not run', 'the folder does not exist'])
            print('CHECK %s | %s | NOT RUN | the folder does not exist' % (head[0], where))
            return 1
        return 0 if record_check(ledger, root, head[0], where, command, *run(command, where)) == 'passed' else 1
    elif cmd == 'summary' and not args:
        summary(rows, ledger)
    else:
        die('unknown command or wrong arguments: ' + ' '.join(argv) + '\n' + __doc__)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
