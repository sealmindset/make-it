#!/usr/bin/env python3
"""fix-it-results.py -- /fix-it's record of what really happened.

/fix-it used to work its "Fixed" count out by subtraction (findings before minus findings after), so a
finding whose scanner did not run the second time counted as fixed; and it took "tests pass" and "still
builds" from commands whose failure fell through. This script is where those results come from now:

  start ATTESTATION            begin a run's record (kept inside .git, never committed)
  scope ID SEVERITY SCANNER TITLE   one in-scope finding (once each), with the scanner that found it
  record ID EVENT [NOTE]       what happened to it: changed | failed | person | unsaved | skipped, and
                               after the re-scan: gone | still
  rescan NEW_ATTESTATION       read what ran in the re-scan (its Category Breakdown table, its "Not run:"
                               list and "Tools used:" line) and how many critical and high findings it lists
  check tests|build            find where the tests / the build live, run them there, record the result
  check NAME [--in DIR] -- CMD run one command as a named check, record the result
  summary                      the counts, each finding's outcome, and the sentences for the person

Rules it holds: every finding has exactly one outcome (fixed / changed, not re-checked / failed / needs a
person / not attempted) and the counts add up to the findings in scope; "fixed" needs a kept change AND
a re-scan in which the scanner that found it ran and no longer reports it; every check is passed / failed / not run from
the command's own exit status and output, and "not run" is never worded or counted as passed.

Standard library only. Run it with `python3 -I`.
"""
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time

SEVERITIES = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO']
EVENTS = ['changed', 'failed', 'person', 'unsaved', 'skipped', 'gone', 'still']
OUTCOMES = ['fixed', 'unchecked', 'failed', 'person', 'not attempted']
HEAD = {'fixed': 'Fixed', 'unchecked': 'Changed, not re-checked', 'failed': 'Failed',
        'person': 'Needs a person', 'not attempted': 'Not attempted'}
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


def named(scanner, text):
    """Is this scanner named in that text, as a whole word?"""
    return bool(scanner.strip('- ')) and bool(re.search(r'(?<![A-Za-z0-9])' + re.escape(scanner.strip()) + r'(?![A-Za-z0-9])', text, re.I))


def scanner_ran(facts, fid, scanner):
    """(did the scanner that found this finding run in the re-scan?, the reason when it did not).

    /nemo-it's rows: PASS = every check in the category ran; FAIL = something was found, whether or not every
    scanner ran; NO FINDINGS = some did not run; NOT RUN = none ran. So only PASS speaks for the whole row. For FAIL
    and NO FINDINGS the scanner itself has to be named in "Tools used:" (the tools that produced a result), and a
    scanner named under "Not run:" did not run whatever its row says."""
    cat = category(fid)
    st = facts.get('cats', {}).get(cat)
    if st is None:
        return False, 'the new report has no row for %s' % cat
    if named(scanner, facts.get('notrun', '')):
        return False, 'the new scan did not run %s' % scanner
    if st == 'PASS':
        return True, ''
    if st.startswith(('FAIL', 'NO FINDINGS')):
        if named(scanner, facts.get('tools', '')):
            return True, ''
        return False, 'the new report does not say %s ran (%s: %s)' % (scanner.strip('- ') or 'the scanner that found it', cat, st)
    return False, 'the new scan did not run this check (%s: %s)' % (cat, st)


def resolve(rows):
    """Each finding's one outcome, from its recorded events in order.
    Returns ({id: [severity, title, outcome, note, kind, scanner]}, ids, the re-scan's facts or None)."""
    scope, order, facts = {}, [], None
    for r in rows:
        if r[0] == 'scope':
            scope[r[1]] = [r[2], r[3], 'not attempted', '', '', r[4]]
            order.append(r[1])
        elif r[0] == 'rescan':
            facts = r[2]
        elif r[0] == 'event':
            f, ev, note = scope[r[1]], r[2], r[3]
            if ev == 'changed':
                f[2], f[3], f[4] = 'changed', note, ''
            elif ev == 'failed':
                f[2], f[3], f[4] = 'failed', note, ''
            elif ev in ('person', 'unsaved'):
                f[2], f[3], f[4] = 'person', note, 'unsaved' if ev == 'unsaved' else 'manual'
            elif ev == 'skipped':
                f[2], f[3], f[4] = 'not attempted', note, ''
            elif ev == 'still' and f[2] in ('changed', 'fixed', 'unchecked'):
                f[2], f[3], f[4] = 'failed', join(f[3], 'the new scan still reports it', note), ''
            elif ev == 'gone' and f[2] == 'changed':
                ran, why = scanner_ran(facts or {}, r[1], f[5])
                if ran:
                    f[2] = 'fixed'
                else:
                    f[2], f[3], f[4] = 'unchecked', join(f[3], why), 'notrun'
    for f in scope.values():
        if f[2] == 'changed':   # a kept change with no verdict from a re-scan is not "fixed"
            f[2] = 'unchecked'
            f[4] = 'noverdict' if facts else 'norescan'
            f[3] = join(f[3], 'the new scan ran, but no result was recorded for it' if facts else 'no new scan has checked it')
    return scope, order, facts


def checks(rows):
    """Each check's results: {name: {(where, command): (result, detail)}}. Running the same command in the same folder
    again replaces its result (the code changed, the check was re-run). A different command under the same name is
    kept beside it, so a pass never covers a fail. An automatic run replaces that name's earlier automatic results."""
    out, auto = {}, {}
    for r in rows:
        if r[0] == 'checkrun':
            for key in auto.pop(r[1], set()):
                out.get(r[1], {}).pop(key, None)
        elif r[0] == 'check':
            out.setdefault(r[1], {})[(r[2], r[3])] = (r[4], r[5])
            if r[6]:
                auto.setdefault(r[1], set()).add((r[2], r[3]))
    return out


# ---- running a check -------------------------------------------------------------------------------------

def timeout():
    try:
        return max(1, int(os.environ.get('FIXIT_CHECK_TIMEOUT', '900')))
    except ValueError:
        return 900


def run(cmd, cwd, ci=False):
    """(exit status or None on timeout, output). 127 when the command cannot be started.
    CI=true is set for tests only (it stops a test runner waiting in watch mode). It is not set for a build: some
    front-end builds turn warnings into errors under CI, and that would be a false "does NOT build"."""
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
    if ci:
        env['CI'] = 'true'
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
    """The biggest 'N passed' / 'pass N' style number in a test runner's output (pytest, jest, vitest, mocha, node --test, tape)."""
    stem = {'pass': r'pass(?:ed|ing)', 'fail': r'fail(?:ed|ing|ures?)'}[word]
    nums = re.findall(r'(\d+) ' + stem + r'\b', out) + re.findall(r'(?m)^(?:\S\s+)?' + word + r'\s+(\d+)\s*$', out)
    if word == 'pass':
        nums += re.findall(r'(?m)^Ran (\d+) tests? in ', out)   # unittest
    else:
        nums += re.findall(r'\bfailures=(\d+)', out)
    return max([int(n) for n in nums] or [0])


def classify(name, rc, out):
    """(result, detail): result is passed, failed or not run, from the exit status and the output."""
    out = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', out)
    if rc is None:
        return 'failed', 'it did not finish within %d seconds, so I stopped it' % timeout()
    passed, failed = (count(out, 'pass'), count(out, 'fail')) if name == 'tests' else (0, 0)
    if not passed and not failed and (rc in (126, 127) or (rc and re.search(
            r'npx canceled|could not determine executable to run|No module named (pytest|mypy|ruff|flake8)\b', out))):
        return 'not run', 'the command could not be started (exit status %d: a tool it needs is not installed)' % rc
    if name != 'tests':
        return ('passed', 'it finished without an error') if rc == 0 else ('failed', 'exit status %d' % rc)
    # "no tests ran" needs the runner's own no-tests signal AND no count of any test at all
    if not passed and not failed and (rc == 5 or re.search(r'no tests ran|No tests found|No test files found|no test specified', out)):
        return 'not run', 'the test command ran but found no tests'
    if failed or rc != 0:   # any failed count, or any non-zero exit, is a failure -- whatever else the output says
        return 'failed', join('%d failed, %d passed' % (failed, passed) if failed or passed else '', 'exit status %d' % rc if not failed or rc == 0 else '')
    if passed:
        return 'passed', '%d passed' % passed
    return 'not run', 'the test command finished without an error, but its output does not show a test that ran'


def record_check(ledger, root, name, where, cmd, rc, out, auto=False):
    result, detail = classify(name, rc, out)
    rel = os.path.relpath(where, root)
    rel = '' if rel == '.' else rel + '/'
    add(ledger, ['check', name, rel, ' '.join(cmd), result, detail, auto])
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
    results, dirs = [], project_dirs(root)
    # every folder with its own tests is its own run; a "tests" folder belongs to the folder above it
    suites = [d for d in dirs if has_pytest_suite(d)] if name == 'tests' else []
    suites = [d for d in suites if not (os.path.basename(d) in ('tests', 'test') and os.path.dirname(d) in suites)]
    for d in dirs:
        if d in suites:
            py = pytest_python(d, root)
            # a suite further down gets its own run and its own line, so this run leaves it out
            cmd = [py or 'python3', '-m', 'pytest', '-q', '-p', 'no:cacheprovider'] + [
                '--ignore=' + os.path.relpath(x, d) for x in suites if x.startswith(d + os.sep)]
            results.append(record_check(ledger, root, name, d, cmd, *(run(cmd, d, True) if py else (127, 'pytest is not installed')), auto=True))
        if npm_script(d, 'test' if name == 'tests' else 'build'):
            cmd = ['npm', 'test'] if name == 'tests' else ['npm', 'run', 'build']
            results.append(record_check(ledger, root, name, d, cmd,
                                        *(run(cmd, d, name == 'tests') if shutil.which('npm') else (127, 'npm is not installed')), auto=True))
    if name == 'build' and not results and makefile_builds(root):
        cmd = ['make', 'build']
        results.append(record_check(ledger, root, name, root, cmd, *run(cmd, root), auto=True))
    if not results:
        what = ('I found no test suite in this project' if name == 'tests' else
                "I don't know how to build this project: I found no `build` script in a package.json and no `build` target in a Makefile")
        add(ledger, ['check', name, '-', '', 'not run', what, True])
        print('CHECK %s | - | - | NOT RUN | %s' % (name, what))
        results.append('not run')
    return results


def makefile_builds(root):
    try:
        with open(os.path.join(root, 'Makefile'), encoding='utf-8', errors='replace') as f:
            return bool(re.search(r'(?m)^build\s*:', f.read()))
    except OSError:
        return False


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
        res[name] = {v[0] for v in got.values()}
        for (where, cmd), (result, detail) in sorted(got.items()):
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
    scope, order, facts = resolve(rows)
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
        sev, title, outcome, note = scope[i][:4]
        print('- %s (%s) %s -- %s%s' % (i, sev, title, HEAD[outcome].upper(), ': ' + note if note else ''))
    done = checks(rows)
    print()
    for name in sorted(done):
        for (where, cmd), (result, detail) in sorted(done[name].items()):
            print('CHECK %s | %s | %s | %s | %s' % (name, where or '(project folder)', cmd or '-', result.upper(), detail))

    say = []
    fixed = len(by['fixed'])
    ids = lambda o: ' (' + ', '.join(by[o]) + ')'
    confirmed = 'the change is kept, and the scanner that found it ran in the new scan and no longer reports it'
    each = lambda k: '' if k == 1 else 'for each, '
    if n == 0:
        say.append('No findings were in scope, so nothing was fixed.')
    elif fixed == n:
        say.append('%s I set out to fix %s fixed: %s%s.'
                   % ('The 1 finding' if n == 1 else 'All %d findings' % n, 'is' if n == 1 else 'are', each(n), confirmed))
    else:
        say.append('Of the %s I set out to fix, %s' % (plural(n, 'finding', 'findings'), 'none is confirmed fixed.' if fixed == 0 else
                   '%d %s fixed: %s%s.' % (fixed, 'is' if fixed == 1 else 'are', each(fixed), confirmed)))
        for kind, why in (('norescan', 'no new scan ran after the change'),
                          ('notrun', 'the new report does not show that the scanner that found %s ran'),
                          ('noverdict', 'the new scan ran, but I did not record what it says about %s')):
            got = [i for i in by['unchecked'] if scope[i][4] == kind]
            k = len(got)
            if k:
                it = 'it' if k == 1 else 'them'
                say.append("%s changed but not re-checked: %s, so I can't say %s fixed. (%s)"
                           % (plural(k, 'was', 'were'), why % it if '%s' in why else why, 'it is' if k == 1 else 'they are', ', '.join(got)))
        k = len(by['failed'])
        if k:
            say.append('%s not fixed: I tried, and the fix did not work or the new scan still reports the problem.%s'
                       % (plural(k, 'is', 'are'), ids('failed')))
        got = [i for i in by['person'] if scope[i][4] != 'unsaved']
        k = len(got)
        if k:
            say.append('%s a person: I did not fix %s, and %s on the manual list. (%s)'
                       % (plural(k, 'needs', 'need'), 'it' if k == 1 else 'them', 'it is' if k == 1 else 'they are', ', '.join(got)))
        got = [i for i in by['person'] if scope[i][4] == 'unsaved']
        k = len(got)
        if k:
            say.append('%s a fix in your files that could not be saved: %s a person to save it, and %s not fixed until it is saved and scanned again. (%s)'
                       % (plural(k, 'has', 'have'), 'it needs' if k == 1 else 'they need', 'it is' if k == 1 else 'they are', ', '.join(got)))
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
        say.append('Of the %s I set out to fix: %s.' % (plural(len(urgent), 'critical or high finding', 'critical and high findings'),
                   ('it is fixed' if len(urgent) == 1 else 'all %d are fixed' % len(urgent)) if not open_urgent else
                   '%d not confirmed fixed (%s)' % (len(open_urgent), ', '.join(open_urgent))))
    # what the NEW REPORT lists, in or out of scope: this, not the scope, decides "ready to ship"
    rest = ''
    if facts is None:
        left = None
        if n:
            say.append("No new scan was recorded, so I can't say how many critical and high findings are left.")
    elif facts.get('critical') is None or facts.get('high') is None:
        left = None
        say.append("I could not read from the new report how many critical and high findings it lists, so I can't say none are left.")
        rest = ", but I can't say how many critical and high findings the new report lists"
    else:
        left = facts['critical'] + facts['high']
        if left == 0:
            say.append('The new report lists no critical or high finding.')
        else:
            say.append('The new report still lists %d critical and %d high %s, counting any I did not set out to fix: this is not ready to ship.'
                       % (facts['critical'], facts['high'], 'finding' if left == 1 else 'findings'))
            rest = ', but the new report still lists %s, so this is not ready to ship' % plural(left, 'critical or high finding', 'critical or high findings')
    lead = 'everything I set out to fix is fixed' if n else 'nothing was in scope to fix'
    if fixed == n and not bad and not unrun:
        say.append('Bottom line: %s, and every check I ran passed%s.' % (lead, rest))
    elif fixed == n and not bad:
        say.append('Bottom line: %s and nothing failed, but not every check ran (see above), so this is not a full all-clear%s.'
                   % (lead, rest.replace(', so this is not ready to ship', '')))
    else:
        why = []
        if fixed != n:
            why.append('%s not confirmed fixed' % plural(n - fixed, 'finding is', 'findings are'))
        why += [{'tests': 'the tests did not pass', 'build': 'the app does not build'}.get(b, 'the check "%s" failed' % b) for b in bad]
        for u in unrun:
            part = ' everywhere' if 'passed' in res[u] else ''
            why.append({'tests': 'tests did not run' + part if part else 'no tests ran', 'build': 'the build was not checked' + part}
                       .get(u, 'the check "%s" did not run%s' % (u, part)))
        if left:
            why.append('the new report still lists %s' % plural(left, 'critical or high finding', 'critical or high findings'))
        say.append('Bottom line: this is not finished -- ' + '; '.join(why) + '.')
    print('\nSAY THIS TO THE PERSON (built from the record above; never reword a result into a better one):')
    print('\n'.join(say))


# ---- commands --------------------------------------------------------------------------------------------

def read_report(path):
    """What a /nemo-it attestation says ran, and how many critical and high findings it lists:
      cats     {category id: status} from the Category Breakdown table (the columns named ID and Status)
      notrun   the text under "**Not run:**" and "**Skipped -- production detected:**" (one line each, nemo-it.md Phase 5)
      tools    the "**Tools used:**" / "Tools:" lines: only the tools that produced a result
      critical, high   the Count column of the Severity Distribution table (None when it cannot be read)"""
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            lines = f.read().splitlines()
    except OSError as e:
        die('cannot read %s: %s' % (path, e.strerror))
    facts = {'cats': {}, 'notrun': '', 'tools': '', 'critical': None, 'high': None}
    head, listing = None, 0
    for line in lines:
        t = line.strip()
        if t.startswith('|'):
            cells = [c.strip().strip('*') for c in t.strip('|').split('|')]
            if head is None:
                head = cells
            elif set(''.join(cells)) <= set('-: '):
                pass
            elif 'ID' in head and 'Status' in head and len(cells) > max(head.index('ID'), head.index('Status')):
                facts['cats'][cells[head.index('ID')]] = cells[head.index('Status')].upper()
            elif 'Severity' in head and 'Count' in head and len(cells) > max(head.index('Severity'), head.index('Count')):
                key, num = cells[head.index('Severity')].lower(), cells[head.index('Count')]
                if key in ('critical', 'high') and num.isdigit():
                    facts[key] = int(num)
            listing = 0
            continue
        head = None
        plain = t.lstrip('-* ').replace('**', '')
        if re.match(r'(Not run|Skipped -- production detected):', plain):
            listing = 1 if plain.split(':', 1)[1].strip() else 2   # 2: the list starts on a later line
            facts['notrun'] += ' ' + plain
        elif re.match(r'Tools( used)?:', plain):
            listing = 0
            facts['tools'] += ' ' + plain
        elif listing and t and not t.startswith(('#', '**', '---')):
            listing = 1
            facts['notrun'] += ' ' + t
        elif not (listing == 2 and not t):   # one blank line may sit between the heading and its list
            listing = 0
    return facts


def sha(path):
    try:
        with open(path, 'rb') as f:
            return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return None


def main(argv):
    if not argv:
        die(__doc__)
    cmd, args = argv[0], argv[1:]
    root, ledger = paths()
    if cmd == 'start' and len(args) == 1:
        os.makedirs(os.path.dirname(ledger), exist_ok=True)
        with open(ledger, 'w', encoding='utf-8') as f:
            f.write(json.dumps(['start', os.path.abspath(args[0]), sha(args[0])]) + '\n')
        print('Recording this run in %s (inside .git: it is never committed).' % ledger)
        return 0
    rows = load(ledger)
    scope = resolve(rows)[0]
    if cmd == 'scope' and len(args) == 4:
        fid, sev, scanner, title = args[0], args[1].upper(), args[2], args[3]
        if sev not in SEVERITIES:
            die('severity must be one of ' + ', '.join(SEVERITIES) + ', not ' + args[1])
        if fid in scope:
            die(fid + ' is already in scope')
        add(ledger, ['scope', fid, sev, title, scanner])
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
        add(ledger, ['event', fid, ev, note, time.time()])
        after = resolve(load(ledger))[0][fid]
        print('%s: %s%s' % (fid, HEAD[after[2]].upper() if ev in ('gone', 'still') or after[2] != 'unchecked' else 'CHANGED (not fixed until the re-scan confirms it)',
                            ' -- ' + after[3] if after[3] else ''))
    elif cmd == 'rescan' and len(args) == 1:
        first = rows[0]
        changes = [r[4] for r in rows if r[0] == 'event' and r[2] == 'changed']
        refuse = 'Nothing is recorded, so every changed finding stays "changed, not re-checked".'
        if os.path.abspath(args[0]) == first[1] or (first[2] and sha(args[0]) == first[2]):
            die('%s is the report this run started from, not a new scan. %s' % (args[0], refuse))
        if changes and os.path.isfile(args[0]) and os.path.getmtime(args[0]) < min(changes):
            die('%s was written before the first fix of this run, so it cannot have checked any fix. %s' % (args[0], refuse))
        facts = read_report(args[0])
        if not facts['cats']:
            die('I could not read which checks ran from %s (no Category Breakdown rows with ID and Status). %s' % (args[0], refuse))
        add(ledger, ['rescan', args[0], facts])
        for c in sorted(facts['cats']):
            print('%s: %s' % (c, facts['cats'][c]))
        print('Not run, as the report lists it:%s' % (facts['notrun'] or ' nothing listed'))
        print('Tools that produced a result:%s' % (facts['tools'] or ' none listed'))
        print('Critical and high findings in this report: %s' % ('could not be read' if facts['critical'] is None or facts['high'] is None
                                                                else '%d critical, %d high' % (facts['critical'], facts['high'])))
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
            add(ledger, ['check', head[0], head[2] if len(head) == 3 else '', ' '.join(command), 'not run', 'the folder does not exist', False])
            print('CHECK %s | %s | NOT RUN | the folder does not exist' % (head[0], where))
            return 1
        return 0 if record_check(ledger, root, head[0], where, command, *run(command, where, head[0] == 'tests')) == 'passed' else 1
    elif cmd == 'summary' and not args:
        summary(rows, ledger)
    else:
        die('unknown command or wrong arguments: ' + ' '.join(argv) + '\n' + __doc__)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
