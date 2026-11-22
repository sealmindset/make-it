#!/usr/bin/env python3
"""Tests for secret-scan.py, driven only through its command line.

Run from the repo root:  python3 -I scripts/test-secret-scan.py -v
(CI: .github/workflows/secret-scan.yml.  It lives here, not next to the script, so it is never installed.)

Every test builds a throwaway repo (bare origin + work clone), plants secret
values, runs the scanner, and asserts (1) the exact stdout, (2) the exit code,
(3) that no planted value -- not even an 8-byte slice of it -- appears in
stdout or stderr.  Python 3.9 compatible, stdlib only.
"""
import codecs
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HERE = os.path.join(ROOT, '.claude', 'make-it', 'scripts')  # where secret-scan.py lives
SCRIPT = os.path.join(HERE, 'secret-scan.py')
L_UNSAVED, L_NEW, L_SAVED = '== unsaved edits ==', '== new files ==', '== saved, not sent =='
GIT = ['git', '-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'commit.gpgsign=false']
BASE = 'name = "demo"\n'


def _b(x):
    return x if isinstance(x, bytes) else x.encode('utf-8')


class Result(object):
    def __init__(self, cp, secs):
        self.code, self.out, self.err, self.secs = cp.returncode, cp.stdout, cp.stderr, secs

    @property
    def lines(self):
        return self.out.decode('utf-8').splitlines()


class Repo(object):
    """A work repo + bare origin inside a temp dir (mirrors the harness fresh())."""

    def __init__(self, test, remote=True):
        td = tempfile.TemporaryDirectory()
        test.addCleanup(td.cleanup)
        self.test = test
        self.root = os.path.realpath(td.name)
        self.work = os.path.join(self.root, 'work')
        if remote:
            self._git(self.root, 'init', '-q', '--bare', 'origin')
        self._git(self.root, 'init', '-q', '-b', 'main', 'work')
        self.git('commit', '-q', '--allow-empty', '-m', 'init')
        self.write('app.py', BASE)
        self.commit('app')
        if remote:
            self.git('remote', 'add', 'origin', os.path.join(self.root, 'origin'))
            self.push()

    @staticmethod
    def _git(cwd, *args):
        return subprocess.run(GIT + list(args), cwd=cwd, check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout

    def git(self, *args):
        return self._git(self.work, *args)

    def path(self, rel):
        return os.path.join(self.work, rel)

    def write(self, rel, data):
        p = self.path(rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'wb') as f:
            f.write(_b(data))

    def append(self, rel, data):
        with open(self.path(rel), 'ab') as f:
            f.write(_b(data))

    def commit(self, msg='c'):
        self.git('add', '-A')
        self.git('commit', '-q', '-m', msg)

    def push(self):
        self.git('push', '-q', 'origin', 'main')

    def branch(self, name='feat'):
        self.git('checkout', '-q', '-b', name)

    def scan(self, via_cwd=False, args=None):
        cmd = [sys.executable, SCRIPT]
        if args is None:
            args = [] if via_cwd else ['--repo', self.work]
        t = time.time()
        cp = subprocess.run(cmd + args, cwd=self.work if via_cwd else None,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
        return Result(cp, time.time() - t)


class Base(unittest.TestCase):
    def fresh(self, remote=True):
        return Repo(self, remote)

    def check(self, res, unsaved=(), new=(), saved=(), secrets=(), code=None):
        """Exact stdout + exit code + no planted value leaked."""
        exp = [L_UNSAVED] + list(unsaved) + [L_NEW] + list(new) + [L_SAVED] + list(saved)
        self.assertEqual(res.lines, exp, 'stderr=%r' % res.err[:300])
        if code is None:
            code = 1 if (unsaved or new or saved) else 0
        self.assertEqual(res.code, code)
        self.no_leak(res, secrets)

    def no_leak(self, res, secrets):
        for out in (res.out, res.err):
            self.assertNotIn(b'\x1b', out, 'escape code in output')
        self.assertNotIn(b'\r', res.out)
        blob = res.out + b'\n' + res.err
        for s in secrets:
            s = _b(s)
            for i in range(max(1, len(s) - 7)):
                self.assertNotIn(s[i:i + 8], blob, 'secret value leaked: slice at %d' % i)

    def script_exists(self):
        self.assertTrue(os.path.isfile(SCRIPT), 'secret-scan.py does not exist yet: %s' % SCRIPT)

    def setUp(self):
        # Guard: a missing script makes python exit 2, which equals "couldn't check".
        self.script_exists()


def need_shell(shell):
    """Fail (not skip, not FileNotFoundError) when a shell the 3e legs run under is missing."""
    if shutil.which(shell) is None:
        raise AssertionError('%s is required to run the 3e checks under %s and was not found on PATH '
                             '(CI installs zsh in .github/workflows/secret-scan.yml)' % (shell, shell))


def kv(name, value, sep=' = ', q='"'):
    return '%s%s%s%s%s\n' % (name, sep, q, value, q)


# GitGuardian scans this file, so no fake value is written out whole: each is joined here at run time
# from harmless pieces.  fake(tag) is the common 'zq9FAKE...' value; the rest are named once below.
def fake(tag):
    return 'zq9' + 'FAKE' + tag


MYPW = 'My' + 'Pass' + 'word=' + '2024' + 'xyz'      # + a letter: the password part of a database URL, between 'app:' and '@db'
ACME = 'Acme' + 'ProdPassword'
LOCALDEV = 'localdev' + 'pass1'
HUNTER = 'hunter' + '2hunter2'
SK_LIVE = 'sk' + '-live-'
B64 = 'Zk9/' + 'c2Vj' + 'cmV0QPwd='         # base64 text that is 'ZkO' + 'secret' + '@Pwd='-like
TAIL = 'abcdefgh' + '1'
SK_KEY = 'sk' + '_live_AcmeSecretKey'


# ---------------------------------------------------------------- harness a-v
class HarnessCases(Base):
    def test_a_unsaved_password_and_binary_png_does_not_hide_it(self):
        r = self.fresh()
        v1, v2 = 'unstaged-secret-value-5678', 'inside-binary-file-1234'
        r.append('app.py', kv('PASSWORD', v1))
        r.write('z.png', b'\x89PNG\r\n\x1a\n\x00\x00' + bytes(range(256)) * 16 + _b('\n' + kv('PASSWORD', v2)))
        self.check(r.scan(), unsaved=['app.py:2'], secrets=[v1, v2])

    def test_b_untracked_file(self):
        r = self.fresh()
        v = 'untracked-secret-value-9012'
        r.write('a.py', kv('TOKEN', v))
        self.check(r.scan(), new=['a.py:1'], secrets=[v])

    def test_c_never_pushed_branch(self):
        r = self.fresh()
        v = 'committed-secret-value-1234'
        r.branch()
        r.append('app.py', kv('API_KEY', v))
        r.commit('key')
        self.check(r.scan(), saved=['app.py:2'], secrets=[v])

    def test_d_added_then_removed_in_unsent_commits_still_a_hit(self):
        # The brief: "added then removed in unsent commits (a hit: both commits are sent)".
        # Every commit in HEAD --not --remotes is scanned, added lines only.
        r = self.fresh()
        v = 'added-then-removed-value-777'
        r.branch()
        r.append('app.py', kv('API_KEY', v))
        r.commit('add')
        r.write('app.py', BASE)
        r.commit('rm')
        self.check(r.scan(), saved=['app.py:2'], secrets=[v])

    def test_e_dotenv_is_keep_out_untracked_and_tracked(self):
        r = self.fresh()
        v1, v2 = 'dotenv-secret-value-4444', 'dotenv-secret-value-5555'
        r.write('.env', 'PASSWORD="%s"\n' % v1)
        self.check(r.scan(), secrets=[v1, v2])
        r.git('add', '-f', '.env')
        r.commit('env')
        r.push()
        r.write('.env', 'PASSWORD="%s"\n' % v2)
        self.check(r.scan(), secrets=[v1, v2])

    def test_f_clean(self):
        r = self.fresh()
        self.check(r.scan())

    def test_g_unsent_commit_removes_already_pushed_secret(self):
        r = self.fresh()
        v = 'already-pushed-value-abcd'
        r.append('app.py', kv('API_KEY', v))
        r.commit('leak')
        r.push()
        r.write('app.py', BASE)
        r.commit('remove hardcoded key')
        self.check(r.scan(), secrets=[v])

    def test_h_uncommitted_edit_removes_pushed_secret(self):
        r = self.fresh()
        v = 'already-pushed-value-abcd'
        r.append('app.py', kv('API_KEY', v))
        r.commit('leak')
        r.push()
        r.write('app.py', BASE)
        self.check(r.scan(), secrets=[v])

    def test_i_evil_merge(self):
        r = self.fresh()
        v = 'evil-merge-value-abcd'
        r.branch('side')
        r.write('side.py', 'side = "s"\n')
        r.commit('side')
        r.git('checkout', '-q', 'main')
        r.git('merge', '-q', '--no-ff', '--no-commit', 'side')
        r.append('app.py', kv('API_KEY', v))
        r.git('add', 'app.py')
        r.git('commit', '-q', '-m', 'merge')
        self.check(r.scan(), saved=['app.py:2'], secrets=[v])

    SHAPE_VALUES = ['sk' + '-1234567890abcdef', HUNTER]
    SHAPES = kv('API_KEY', SHAPE_VALUES[0]) + kv('PASSWORD', HUNTER, q="'")

    def test_j_value_shapes_unsaved(self):
        r = self.fresh()
        r.append('app.py', self.SHAPES + kv('SECRET_KEY', 'abcdefghijk'))
        self.check(r.scan(), unsaved=['app.py:2', 'app.py:3', 'app.py:4'],
                   secrets=self.SHAPE_VALUES + ['abcdefghijk'])

    def test_k_value_shapes_untracked(self):
        r = self.fresh()
        r.write('k.py', self.SHAPES)
        self.check(r.scan(), new=['k.py:1', 'k.py:2'], secrets=self.SHAPE_VALUES)

    def test_l_value_shapes_unsent_commit(self):
        r = self.fresh()
        r.branch()
        r.append('app.py', self.SHAPES)
        r.commit('k')
        self.check(r.scan(), saved=['app.py:2', 'app.py:3'], secrets=self.SHAPE_VALUES)

    V_COMMITTED, V_UNSTAGED = 'committed-secret-value-1234', 'unstaged-secret-value-5678'

    def _committed_plus_unsaved(self, r):
        r.branch()
        r.append('app.py', kv('API_KEY', self.V_COMMITTED))
        r.commit('key')
        r.append('app.py', kv('PASSWORD', self.V_UNSTAGED))

    def _check_m(self, r, via_cwd=False):
        self.check(r.scan(via_cwd=via_cwd), unsaved=['app.py:3'], saved=['app.py:2'],
                   secrets=[self.V_COMMITTED, self.V_UNSTAGED])

    def test_m_one_saved_one_unsaved(self):
        r = self.fresh()
        self._committed_plus_unsaved(r)
        self._check_m(r)

    def test_m2_default_repo_is_cwd(self):
        r = self.fresh()
        self._committed_plus_unsaved(r)
        self._check_m(r, via_cwd=True)

    def test_n_color_ui_always(self):
        r = self.fresh()
        r.git('config', 'color.ui', 'always')
        self._committed_plus_unsaved(r)
        self._check_m(r)

    def test_o_diff_noprefix(self):
        r = self.fresh()
        r.git('config', 'diff.noprefix', 'true')
        r.append('app.py', kv('PASSWORD', self.V_UNSTAGED))
        self.check(r.scan(), unsaved=['app.py:2'], secrets=[self.V_UNSTAGED])

    def test_p_diff_mnemonicprefix(self):
        r = self.fresh()
        r.git('config', 'diff.mnemonicPrefix', 'true')
        self._committed_plus_unsaved(r)
        self._check_m(r)

    def test_q_all_hostile_config_and_diff_external(self):
        r = self.fresh()
        ext = os.path.join(r.root, 'ext.sh')
        with open(ext, 'w') as f:
            f.write('#!/bin/sh\necho external-diff-output "$1"\n')
        os.chmod(ext, 0o755)
        for k, v in (('diff.noprefix', 'true'), ('diff.mnemonicPrefix', 'true'),
                     ('color.ui', 'always'), ('diff.external', ext)):
            r.git('config', k, v)
        self._committed_plus_unsaved(r)
        res = r.scan()
        self.assertNotIn(b'external-diff-output', res.out)
        self._check_m(r)

    def _names(self, quote_path):
        r = self.fresh()
        r.git('config', 'core.quotePath', quote_path)
        v1, v2, v3 = 'committed-secret-value-1234', 'spaced-secret-value-1234', 'unstaged-secret-value-5678'
        r.branch()
        r.write('naïve.py', kv('API_KEY', v1))
        r.write('my file.py', kv('TOKEN', v2))
        r.commit('key')
        r.append('my file.py', kv('PASSWORD', v3))
        self.check(r.scan(), unsaved=['my file.py:2'],
                   saved=['my file.py:1', 'naïve.py:1'], secrets=[v1, v2, v3])

    def test_r_non_ascii_and_spaced_names_quotepath_true(self):
        self._names('true')

    def test_r_non_ascii_and_spaced_names_quotepath_false(self):
        self._names('false')

    def test_s_placeholder_in_path_is_not_exempt_committed_and_unsaved(self):
        r = self.fresh()
        v1, v2 = 'real-secret-value-1234', 'real-secret-value-5678'
        r.branch()
        r.write('lib/placeholder_image.py', kv('API_KEY', v1))
        r.commit('key')
        r.write('lib/placeholder_image.py', kv('TOKEN', v2))
        self.check(r.scan(), unsaved=['lib/placeholder_image.py:1'],
                   saved=['lib/placeholder_image.py:1'], secrets=[v1, v2])

    def test_t_untracked_placeholder_path_and_other(self):
        r = self.fresh()
        v1, v2 = 'real-secret-value-5678', 'real-secret-value-9999'
        r.write('lib/placeholder_image.py', kv('TOKEN', v1))
        r.write('lib/other.py', kv('TOKEN', v2))
        r.write('a/b/c/deep.py', kv('TOKEN', v2))
        self.check(r.scan(), new=['a/b/c/deep.py:1', 'lib/other.py:1',
                                  'lib/placeholder_image.py:1'], secrets=[v1, v2])

    def test_u_real_placeholders_are_skipped_everywhere(self):
        r = self.fresh()
        r.branch()
        r.append('app.py', kv('API_KEY', 'your-api-key-here') + kv('TOKEN', 'changeme-changeme'))
        r.commit('ph')
        r.append('app.py', kv('PASSWORD', 'placeholder-password'))
        r.write('u.py', kv('SECRET', 'TODO-fill-me-in') + kv('PASSWORD', 'see .example file'))
        self.check(r.scan(), secrets=['your-api-key-here', 'changeme-changeme', 'placeholder-password',
                                      'TODO-fill-me-in'])

    def test_v_todo_in_filename_does_not_exempt(self):
        r = self.fresh()
        v = 'real-secret-value-5678'
        r.write('TODO.py', kv('TOKEN', v))
        self.check(r.scan(), new=['TODO.py:1'], secrets=[v])


# ---------------------------------------------------------------- harness w, x
class EncodingAndSizeCases(Base):
    def test_w1_unsaved_latin1_file_edit_does_not_hide_secret(self):
        r = self.fresh()
        v = 'unstaged-secret-value-5678'
        r.write('a_seed.csv', 'id,name\n')
        r.commit('seed')
        r.push()
        r.append('a_seed.csv', b'1,caf\xe9\n')
        r.append('app.py', kv('PASSWORD', v))
        self.check(r.scan(), unsaved=['app.py:2'], secrets=[v])

    def test_w2_unsent_commit_latin1_first_then_secret(self):
        r = self.fresh()
        v = 'committed-secret-value-1234'
        r.branch()
        r.write('a_seed.csv', b'id,name\n1,caf\xe9\n')
        r.append('app.py', kv('API_KEY', v))
        r.commit('both')
        self.check(r.scan(), saved=['app.py:2'], secrets=[v])

    def test_w3_unsent_commit_secret_first_latin1_after(self):
        r = self.fresh()
        v = 'committed-secret-value-1234'
        r.branch()
        r.write('z_seed.csv', b'id,name\n1,caf\xe9\n')
        r.append('app.py', kv('API_KEY', v))
        r.commit('both')
        self.check(r.scan(), saved=['app.py:2'], secrets=[v])

    def test_w4_untracked_latin1_file_holding_secret(self):
        r = self.fresh()
        v = 'untracked-secret-value-9012'
        r.write('l1.py', b'caf\xe9\n' + _b(kv('TOKEN', v)))
        self.check(r.scan(), new=['l1.py:2'], secrets=[v])

    def test_w5_latin1_byte_on_the_secret_line(self):
        r = self.fresh()
        v1, v2 = b'caf\xe9-committed-secret-1234', b'caf\xe9-unsaved-secret-5678'
        r.branch()
        r.append('app.py', b'API_KEY = "' + v1 + b'"\n')
        r.commit('k')
        r.append('app.py', b'PASSWORD = "' + v2 + b'"\n')
        self.check(r.scan(), unsaved=['app.py:3'], saved=['app.py:2'], secrets=[v1, v2])

    def test_w6_untracked_latin1_byte_on_the_secret_line(self):
        r = self.fresh()
        v = b'caf\xe9-untracked-secret-9012'
        r.write('l2.py', b'TOKEN = "' + v + b'"\n')
        self.check(r.scan(), new=['l2.py:1'], secrets=[v])

    def _bundle(self):
        # ~2 MB on one line, no newline
        return (b'QUJD' * 520000)

    def test_x1_two_mb_single_line_untracked_and_staged(self):
        r = self.fresh()
        v = 'unstaged-secret-value-5678'
        r.write('a_bundle.js', self._bundle())
        r.append('app.py', kv('PASSWORD', v))
        res = r.scan()
        self.check(res, unsaved=['app.py:2'], secrets=[v])
        self.assertLess(res.secs, 20)
        r.git('add', 'a_bundle.js')  # now it is an added line in `git diff HEAD`
        res = r.scan()
        self.check(res, unsaved=['app.py:2'], secrets=[v])
        self.assertLess(res.secs, 20)

    def test_x1b_two_mb_single_line_with_secret_at_the_end(self):
        r = self.fresh()
        v = 'bundle-secret-value-0001'
        r.write('big.py', self._bundle() + b'\n' + _b(kv('TOKEN', v)))
        res = r.scan()
        self.check(res, new=['big.py:2'], secrets=[v])
        self.assertLess(res.secs, 20)

    def test_x2_nul_after_9000_bytes_is_text(self):
        r = self.fresh()
        v1, v2 = 'committed-secret-value-1234', 'after-nul-secret-value-77'
        r.branch()
        r.write('a_big.txt', b'a' * 9000 + b'\nx\x00y\n' + _b(kv('TOKEN', v2)))
        r.append('app.py', kv('API_KEY', v1))
        r.commit('k')
        self.check(r.scan(), saved=['a_big.txt:3', 'app.py:2'], secrets=[v1, v2])

    def test_x3_double_quote_in_committed_file_name(self):
        r = self.fresh()
        v = 'committed-secret-value-1234'
        r.branch()
        r.write('q"x.py', kv('API_KEY', v))
        r.commit('k')
        self.check(r.scan(), saved=['q"x.py:1'], secrets=[v])


# ---------------------------------------------------------------- binary rule
class BinaryCases(Base):
    def test_binary_in_every_scope_is_skipped_other_hits_survive(self):
        r = self.fresh()
        vs = ['bin-tracked-secret-1111', 'bin-committed-secret-2222', 'bin-untracked-secret-3333',
              'text-secret-value-4444']
        r.write('data.bin', b'\x00\x01')
        r.commit('bin')
        r.push()
        r.branch()
        r.write('c.bin', b'\x00\x02' + _b('\n' + kv('PASSWORD', vs[1])))
        r.commit('c')
        r.append('data.bin', _b('\n' + kv('PASSWORD', vs[0])))
        r.write('u.bin', b'\x00' + _b('\n' + kv('PASSWORD', vs[2])))
        r.append('app.py', kv('TOKEN', vs[3]))
        self.check(r.scan(), unsaved=['app.py:2'], secrets=vs)

    def test_nul_at_byte_7999_is_binary(self):
        r = self.fresh()
        v = 'late-binary-secret-8888'
        r.write('edge.py', b'#' * 7990 + b'\x00\n' + _b(kv('TOKEN', v)))
        self.check(r.scan(), secrets=[v])


# ---------------------------------------------------------------- scope rules
class ScopeCases(Base):
    def test_context_line_with_pushed_secret_is_not_a_hit(self):
        r = self.fresh()
        v = 'pushed-context-secret-1234'
        r.write('app.py', BASE + kv('API_KEY', v))
        r.commit('leak')
        r.push()
        r.write('app.py', 'name = "other"\n' + kv('API_KEY', v))
        self.check(r.scan(), secrets=[v])

    def test_staged_and_unstaged_both_count(self):
        r = self.fresh()
        v1, v2 = 'staged-secret-value-1111', 'unstaged-secret-value-2222'
        r.append('app.py', kv('PASSWORD', v1))
        r.git('add', 'app.py')
        r.append('app.py', kv('TOKEN', v2))
        self.check(r.scan(), unsaved=['app.py:2', 'app.py:3'], secrets=[v1, v2])

    def test_line_numbers_are_in_the_new_version_across_hunks(self):
        r = self.fresh()
        v = 'shifted-secret-value-1234'
        body = ''.join('# line %d\n' % i for i in range(2, 31))
        r.write('app.py', BASE + body)
        r.commit('long')
        r.push()
        lines = (BASE + body).splitlines(True)
        lines.insert(0, '# new top\n')
        lines.insert(26, kv('TOKEN', v))  # inserted after 25 old lines + 1 shift
        r.write('app.py', ''.join(lines))
        self.check(r.scan(), unsaved=['app.py:27'], secrets=[v])

    def test_saved_line_number_is_from_the_commit_that_added_it(self):
        r = self.fresh()
        v = 'added-early-secret-1234'
        r.branch()
        r.append('app.py', kv('API_KEY', v))
        r.commit('add')
        r.write('app.py', '# header\n' + BASE + kv('API_KEY', v))
        r.commit('shift')
        self.check(r.scan(), saved=['app.py:2'], secrets=[v])

    def test_same_line_added_in_two_commits_is_reported_once(self):
        r = self.fresh()
        v = 'readded-secret-value-1234'
        r.branch()
        r.append('app.py', kv('API_KEY', v))
        r.commit('add')
        r.write('app.py', BASE)
        r.commit('rm')
        r.append('app.py', kv('API_KEY', v))
        r.commit('readd')
        self.check(r.scan(), saved=['app.py:2'], secrets=[v])

    def test_clean_merge_does_not_double_report_a_side_branch_line(self):
        r = self.fresh()
        v = 'side-branch-secret-1234'
        r.branch('side')
        r.append('app.py', kv('API_KEY', v))
        r.commit('side')
        r.git('checkout', '-q', 'main')
        r.write('app.py', '# header\n' + BASE)
        r.commit('main moves')
        r.git('merge', '-q', '--no-ff', '-m', 'merge', 'side')
        self.check(r.scan(), saved=['app.py:2'], secrets=[v])

    def test_no_remote_all_history_counts(self):
        r = self.fresh(remote=False)
        v1, v2 = 'noremote-secret-value-1', 'noremote-secret-value-2'
        r.append('app.py', kv('API_KEY', v1))
        r.commit('one')
        r.write('b.py', kv('TOKEN', v2))
        r.commit('two')
        self.check(r.scan(), saved=['app.py:2', 'b.py:1'], secrets=[v1, v2])

    def test_no_remote_clean_repo_has_no_hits(self):
        self.check(self.fresh(remote=False).scan())

    def test_ignored_untracked_files_are_not_scanned(self):
        r = self.fresh()
        v1, v2 = 'ignored-secret-value-1234', 'visible-secret-value-5678'
        r.write('.gitignore', 'ignored.py\nbuild/\n')
        r.write('ignored.py', kv('TOKEN', v1))
        r.write('build/out.py', kv('TOKEN', v1))
        r.write('seen.py', kv('TOKEN', v2))
        self.check(r.scan(), new=['seen.py:1'], secrets=[v1, v2])

    def test_output_is_sorted_numerically_by_line_and_deduped(self):
        r = self.fresh()
        v1, v2, v3 = 'sorted-secret-value-aaaa', 'sorted-secret-value-bbbb', 'sorted-secret-value-cccc'
        a = '# 1\n' + kv('PASSWORD', v1) + '# x\n' * 7 + kv('TOKEN', v2)  # PASSWORD line 2, TOKEN line 10
        r.write('b.py', kv('TOKEN', v3))
        r.write('a.py', a)
        exp = ['a.py:2', 'a.py:10', 'b.py:1']
        self.check(r.scan(), new=exp, secrets=[v1, v2, v3])
        r.branch()
        r.commit('b first')  # commits both; order of files in the commit is irrelevant
        self.check(r.scan(), saved=exp, secrets=[v1, v2, v3])


# ---------------------------------------------------------------- naming rule
class NameRuleCases(Base):
    HITS = [
        ('PASSWORD', 'PASSWORD = "{v}"'),
        ('DB_PASSWORD', 'DB_PASSWORD="{v}"'),
        ('SECRET_KEY', 'SECRET_KEY: "{v}"'),
        ('AWS_SECRET_ACCESS_KEY', 'AWS_SECRET_ACCESS_KEY := "{v}"'),
        ('apiKey', 'apiKey = "{v}"'),
        ('TOKEN', "TOKEN = '{v}'"),
        ('CLIENT_SECRET', 'CLIENT_SECRET = `{v}`'),
        ('DB_PASSWORD', 'export DB_PASSWORD="{v}"'),
        ('API_TOKEN', '- API_TOKEN: "{v}"'),
        ('password', '"password": "{v}",'),
        ('passwd', "'passwd': '{v}'"),
        ('pwd', 'pwd   =   "{v}"'),
        ('credentials', 'credentials = "{v}"'),
        ('apikey', 'apikey = "{v}"'),
        ('private_key', 'private_key = "{v}"'),
        ('ssh-key', 'ssh-key = "{v}"'),
        ('master.key', 'master.key = "{v}"'),
        ('signing_key', 'signing_key = "{v}"'),
        ('encryptionKey', 'encryptionKey = "{v}"'),
        ('access_key', 'access_key = "{v}"'),
        ('client_key', 'client_key = "{v}"'),
        ('db.password', 'db.password = "{v}"'),
        ('userPassword', 'userPassword = "{v}"'),
        ('clientSecret', 'clientSecret = "{v}"'),
        ('indented_token', '        indented_token = "{v}"'),
    ]
    MISSES = ['secretName', 'secretKeyRef', 'tokenUrl', 'password_hash', 'public_key', 'key',
              'token_count', 'username', 'monkey']

    def test_secret_named_identifiers_hit_and_lookalikes_do_not(self):
        r = self.fresh()
        lines, exp, vals = [], [], []
        for i, (name, tmpl) in enumerate(self.HITS):
            v = 'val%02d-nameTbl-secret' % i
            vals.append(v)
            lines.append(tmpl.format(v=v))
            exp.append('names.py:%d' % (i + 1))
        for j, name in enumerate(self.MISSES):
            v = 'miss%02d-nameTbl-secret' % j
            vals.append(v)
            lines.append('%s = "%s"' % (name, v))
        r.write('names.py', '\n'.join(lines) + '\n')
        self.check(r.scan(), new=exp, secrets=vals)

    def test_name_rule_applies_to_unsaved_and_saved_too(self):
        r = self.fresh()
        v1, v2, v3 = 'tbl-aws-secret-value-1', 'tbl-secretname-value-2', 'tbl-aws-secret-value-3'
        r.branch()
        r.append('app.py', kv('AWS_SECRET_ACCESS_KEY', v1) + kv('secretName', v2))
        r.commit('k')
        r.append('app.py', kv('SECRET_KEY', v3))
        self.check(r.scan(), unsaved=['app.py:4'], saved=['app.py:2'],
                   secrets=[v1, v2, v3])


# ---------------------------------------------------------------- value rule
class ValueRuleCases(Base):
    def test_quoted_length_boundary_and_quote_kinds(self):
        r = self.fresh()
        short, ok = 'abcdefg', 'abcdefgh'
        r.write('v.py', kv('PASSWORD', short) + kv('PASSWORD', ok) + kv('TOKEN', 'q7chars', q="'")
                + kv('TOKEN', 'bt-eight-chars', q='`') + 'PASSWORD = ""\n')
        self.check(r.scan(), new=['v.py:2', 'v.py:4'], secrets=[ok, 'bt-eight-chars'])

    def test_references_are_not_hits(self):
        r = self.fresh()
        r.write('refs.py', kv('PASSWORD', '${DB_PASSWORD}') + kv('PASSWORD', '$DB_PASSWORD_VAR')
                + kv('TOKEN', '{{ vault_token_value }}') + 'api_key = os.getenv("API_KEY")\n'
                + 'token = self.token_value\nTOKEN = %s\n' % 'abcdefghijkl')
        self.check(r.scan(), secrets=['abcdefghijkl'])

    def test_placeholders_are_case_insensitive_and_only_in_the_value(self):
        r = self.fresh()
        ph = ['my-EXAMPLE-key', 'ToDo-later-1', 'a-PlaceHolder-1', 'ChangeMe123', 'change-me-please',
              'your_token_here', 'your-api-key-HERE', '<your-secret>', 'abXXXXcdef', 'ab****cdef']
        near = ['abxxxcdefg', 'your-token-now1']
        text = ''.join(kv('PASSWORD', v) for v in ph + near)
        r.write('ph.py', text)
        n = len(ph)
        self.check(r.scan(), new=['ph.py:%d' % (n + 1), 'ph.py:%d' % (n + 2)],
                   secrets=near)

    def test_crlf_line_endings_do_not_leak_cr_or_break_hits(self):
        r = self.fresh()
        v1, v2 = 'crlf-' + 'secret-value-1234', 'crlf-' + 'unquoted-1234'
        r.write('crlf.py', 'x = 1\r\n' + kv('TOKEN', v1).replace('\n', '\r\n'))
        r.write('crlf.yml', 'password: %s\r\n' % v2)
        self.check(r.scan(), new=['crlf.py:2', 'crlf.yml:1'], secrets=[v1, v2])

    def test_unusual_line_separators_do_not_shift_line_numbers(self):
        r = self.fresh()
        v = 'separator-secret-1234'
        junk = 'a\x0bb\x0cc\x1cd\x1de\x1ef\rg \u0085     end\n'
        r.write('sep.py', junk + kv('TOKEN', v))
        self.check(r.scan(), new=['sep.py:2'], secrets=[v])

    def test_diff_lookalike_content_cannot_misdirect_the_scan(self):
        r = self.fresh()
        v = 'lookalike-secret-1234'
        r.append('app.py', '++ b/fake.py\n@@ -1 +100 @@\ndiff --git a/x b/x\n' + kv('PASSWORD', v))
        self.check(r.scan(), unsaved=['app.py:5'], secrets=[v])

    def test_file_without_trailing_newline(self):
        r = self.fresh()
        v1, v2 = 'nonewline-secret-1111', 'nonewline-secret-2222'
        r.branch()
        r.write('nonl.py', 'TOKEN = "%s"' % v1)
        r.commit('nonl')
        r.write('nonl2.py', 'TOKEN = "%s"' % v2)
        self.check(r.scan(), new=['nonl2.py:1'], saved=['nonl.py:1'], secrets=[v1, v2])


# ---------------------------------------------------------------- config files
class ConfigFileCases(Base):
    def test_unquoted_values_hit_only_in_config_files(self):
        r = self.fresh()
        v = HUNTER
        hit = ['config.ini', 'a.cfg', 'a.conf', 'a.properties', 'a.toml', 'a.yaml', 'a.yml', 'Dockerfile',
               'Dockerfile.dev', 'docker-compose.dev', 'docker-compose.override.yml', '.env.example',
               'prod.env', 'sub/x.env.sample']
        miss = ['run.sh', 'notes.txt', 'app.js', 'a.py', 'README.md', 'config.json']
        for n in hit + miss:
            r.write(n, 'PASSWORD=%s\n' % v)
        self.check(r.scan(), new=['%s:1' % n for n in sorted(hit)], secrets=[v])

    def test_unquoted_value_shapes_in_a_compose_file(self):
        r = self.fresh()
        vs = ['super' + 'secret1', HUNTER, 'abc12345' + '#frag']
        text = ('services:\n  db:\n    environment:\n'
                '      - POSTGRES_PASSWORD=%s\n'            # 4 hit
                '      password: %s # a comment\n'          # 5 hit
                '      TOKEN=%s\n'                          # 6 hit
                '      PASSWORD=short # a-long-comment-here\n'
                '      PASSWORD=$DB_PASSWORD\n'
                '      password: ${DB_PASSWORD}\n'
                '      password: {{.Values.dbPassword}}\n'
                '      secretName: app-tls-dev\n'
                '      PASSWORD=changeme-now\n'
                '      TOKEN=<token-here>\n'
                '      PASSWORD=\n') % tuple(vs)
        r.write('docker-compose.yml', text)
        self.check(r.scan(), new=['docker-compose.yml:4', 'docker-compose.yml:5',
                                  'docker-compose.yml:6'], secrets=vs)

    def test_committed_compose_and_dotenv_in_unsent_commits(self):
        r = self.fresh()
        v1, v2 = 'super' + 'secret1', HUNTER
        r.branch()
        r.write('docker-compose.yml',
                'services:\n  db:\n    environment:\n      - POSTGRES_PASSWORD=%s\n' % v1)
        r.commit('compose')
        r.write('.env', 'PASSWORD=%s\n' % v2)
        r.commit('env')
        self.check(r.scan(), saved=['.env:1', 'docker-compose.yml:4'],
                   secrets=[v1, v2])

    def test_unquoted_non_config_and_unquoted_python_no_hit_when_committed_or_unsaved(self):
        r = self.fresh()
        v = HUNTER
        r.branch()
        r.write('a.py', 'TOKEN = %s\n' % v)
        r.write('secretname.yaml', 'secretName: app-tls-dev\n')
        r.commit('x')
        r.append('app.py', 'token = self.token_value\napi_key = os.getenv("API_KEY")\n'
                 'PASSWORD = %s\n' % v)
        self.check(r.scan(), secrets=[v])


# ---------------------------------------------------------------- keep-out list
class KeepOutCases(Base):
    KEEP = ['.env', '.env.local', '.env.production', 'sub/dir/.env', 'id_rsa', 'id_rsa.pub', 'sub/id_rsa',
            'id_ed25519', 'id_ecdsa', 'id_dsa', 'server.pem', 'a/b/tls.key', 'login.keychain-db',
            '.aws/credentials', '.netrc', 'gcp-credentials.json', 'credentials.json', 'sub/my-service-account.json',
            'db.sqlite3', 'x.sqlite', 'data.db', 'c.p12', 'c.pfx']

    def test_untracked_keep_out_files_are_never_hits(self):
        r = self.fresh()
        v = 'keepout-secret-value-1'
        for n in self.KEEP:
            r.write(n, kv('PASSWORD', v))
        self.check(r.scan(), secrets=[v])

    def test_staged_new_keep_out_files_are_never_hits(self):
        r = self.fresh()
        v = 'keepout-secret-value-2'
        for n in ('.env', 'sub/id_rsa', 'server.pem', 'db.sqlite3'):
            r.write(n, kv('PASSWORD', v))
        r.git('add', '-f', '.')
        self.check(r.scan(), secrets=[v])

    def test_modified_tracked_keep_out_files_are_never_hits(self):
        r = self.fresh()
        v1, v2 = 'keepout-old-value-1234', 'keepout-new-value-5678'
        names = ('.env', 'sub/id_rsa', 'c.pem', 'db.sqlite3')
        for n in names:
            r.write(n, kv('PASSWORD', v1))
        r.git('add', '-f', '.')
        r.git('commit', '-q', '-m', 'track')
        r.push()
        for n in names:
            r.write(n, kv('PASSWORD', v2))
        self.check(r.scan(), secrets=[v1, v2])

    def test_keep_out_does_not_apply_to_saved_not_sent(self):
        r = self.fresh()
        v = 'keepout-saved-value-1'
        r.branch()
        r.write('id_rsa', kv('PASSWORD', v))
        r.write('db.sqlite3', kv('TOKEN', v))
        r.git('add', '-f', '.')
        r.git('commit', '-q', '-m', 'oops')
        self.check(r.scan(), saved=['db.sqlite3:1', 'id_rsa:1'], secrets=[v])

    def test_dotenv_example_and_lookalikes_are_scanned(self):
        r = self.fresh()
        v = 'looks-real-secret-value-9'
        r.write('.env.example', 'API_KEY=%s\n' % v)
        r.write('credentials.py', kv('API_KEY', v))
        r.write('service-account.yaml', kv('API_KEY', v))
        r.write('a.pem.txt', kv('API_KEY', v))
        r.write('envfile.py', kv('API_KEY', v))
        self.check(r.scan(), new=['.env.example:1', 'a.pem.txt:1', 'credentials.py:1',
                                  'envfile.py:1', 'service-account.yaml:1'], secrets=[v])


# ---------------------------------------------------------------- exit code 2
class CouldNotCheckCases(Base):
    def test_plain_directory_is_not_a_git_repo(self):
        td = tempfile.TemporaryDirectory()
        self.addCleanup(td.cleanup)
        v = 'plain-dir-secret-value-1'
        with open(os.path.join(td.name, 'x.py'), 'w') as f:
            f.write(kv('TOKEN', v))
        cp = subprocess.run([sys.executable, SCRIPT, '--repo', td.name], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=60)
        res = Result(cp, 0)
        self.assertEqual(res.code, 2)
        self.assertEqual(res.out, b'')
        self.assertNotIn(b'x.py:', res.out)
        self.no_leak(res, [v])

    def test_plain_directory_via_cwd(self):
        td = tempfile.TemporaryDirectory()
        self.addCleanup(td.cleanup)
        cp = subprocess.run([sys.executable, SCRIPT], cwd=td.name, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=60)
        self.assertEqual(cp.returncode, 2)
        self.assertEqual(cp.stdout, b'')

    def test_missing_path(self):
        td = tempfile.TemporaryDirectory()
        self.addCleanup(td.cleanup)
        cp = subprocess.run([sys.executable, SCRIPT, '--repo', os.path.join(td.name, 'nope')],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
        self.assertEqual(cp.returncode, 2)
        self.assertEqual(cp.stdout, b'')


class AmendmentCases(Base):
    """Amendments 2026-10-17: `mock` is a placeholder word; control bytes in printed names are \\xNN."""

    def _write_named(self, r, name, v, var='TOKEN'):
        with open(os.path.join(r.work, name), 'wb') as f:
            f.write(_b(kv(var, v)))

    def test_mock_values_are_no_hit_in_all_three_scopes(self):
        r = self.fresh()
        m1, m2, m3 = 'mock-oidc-secret-1234', 'MyMockToken12345', 'MOCK_secret_value_99'
        real = ['real-secret-value-1111', 'real-secret-value-2222', 'real-secret-value-3333']
        r.branch()
        r.append('app.py', kv('CLIENT_SECRET', m1) + kv('API_KEY', real[0]))
        r.commit('saved')
        r.append('app.py', kv('AUTH_TOKEN', m2) + kv('PASSWORD', real[1]))
        r.write('new.py', kv('SECRET_KEY', m3) + kv('TOKEN', real[2]))
        self.check(r.scan(), unsaved=['app.py:5'], new=['new.py:2'],
                   saved=['app.py:3'], secrets=[m1, m2, m3] + real)

    def test_mock_alone_is_clean_in_each_scope(self):
        r = self.fresh()
        vals = ['mock-oidc-secret-1234', 'MyMockToken12345', 'mock-password-abcdef']
        r.branch()
        r.append('app.py', kv('CLIENT_SECRET', vals[0]))
        r.commit('saved')
        r.append('app.py', kv('AUTH_TOKEN', vals[1]))
        r.write('new.py', kv('PASSWORD', vals[2]))
        self.check(r.scan(), secrets=vals)

    def test_newline_name_is_escaped_and_stays_one_line(self):
        r = self.fresh()
        v = 'newline-name-secret-1234'
        self._write_named(r, 'x\ny.py', v)
        self.check(r.scan(), new=['x\\x0ay.py:1'], secrets=[v])

    def test_tab_and_esc_names_are_escaped(self):
        r = self.fresh()
        v1, v2 = 'tab-name-secret-value-1', 'esc-name-secret-value-2'
        self._write_named(r, 'a\tb.py', v1)
        self._write_named(r, 'e\x1bz.py', v2)
        self.check(r.scan(), new=['a\\x09b.py:1', 'e\\x1bz.py:1'], secrets=[v1, v2])

    def test_committed_name_faking_a_label_cannot_forge_one(self):
        r = self.fresh()
        v = 'label-forging-secret-1234'
        r.branch()
        self._write_named(r, 'a\n== new files ==\nb.py', v)
        r.commit('evil name')
        res = r.scan()
        self.assertEqual([l for l in res.lines if l.startswith('== ')], [L_UNSAVED, L_NEW, L_SAVED])
        self.check(res, saved=['a\\x0a== new files ==\\x0ab.py:1'], secrets=[v])

    def test_spaces_quote_and_non_ascii_names_stay_unescaped(self):
        r = self.fresh()
        v1, v2, v3 = 'plain-name-secret-1111', 'plain-name-secret-2222', 'plain-name-secret-3333'
        self._write_named(r, 'my file.py', v1)
        self._write_named(r, 'q"t.py', v2)
        self._write_named(r, 'naïve.py', v3)
        self.check(r.scan(), new=['my file.py:1', 'naïve.py:1', 'q"t.py:1'],
                   secrets=[v1, v2, v3])


class ReviewHoleCases(Base):
    """Review attacks (2026-10-17): value re-read as a name, replace refs, git pins, ignored .env.example."""

    def test_value_is_not_reread_as_a_name_in_compose(self):
        r = self.fresh()
        r.write('docker-compose.yml', '      - DATABASE_URL=postgres://app:%sQ@db/app\n' % MYPW)
        res = r.scan()
        self.check(res, secrets=[MYPW + 'Q'])
        self.assertNotIn(b'MyPassword', res.out + res.err)

    def test_value_is_not_reread_as_a_name_in_py(self):
        r = self.fresh()
        r.write('u.py', 'url = "postgres://app:%sQ@db/app"\n' % MYPW)
        res = r.scan()
        self.check(res, secrets=[MYPW + 'Q'])
        self.assertNotIn(b'MyPassword', res.out + res.err)

    def test_git_replace_cannot_hide_a_saved_secret(self):
        r = self.fresh()
        v = 'replace-hidden-secret-9876'
        r.branch()
        r.append('app.py', kv('API_KEY', v))
        r.commit('add')
        a = r.git('rev-parse', 'HEAD').decode().strip()
        r.write('app.py', BASE)
        r.commit('rm')
        c = r.git('commit-tree', a + '^^{tree}', '-p', a + '^', '-m', 'stand-in').decode().strip()
        r.git('replace', a, c)
        self.check(r.scan(), saved=['app.py:2'], secrets=[v])

    def _pin(self, v, setup):
        r = self.fresh()
        r.branch()
        setup(r)
        r.append('app.py', kv('API_KEY', v))
        r.commit('secret')
        return r

    def test_pin_diff_suppress_blank_empty(self):
        v = 'suppress-blank-secret-1234'
        r = self.fresh()
        r.git('config', 'diff.suppressBlankEmpty', 'true')
        r.write('app.py', BASE + '\nx = 1\n')
        r.commit('ctx')
        r.push()
        r.branch()
        r.append('app.py', kv('API_KEY', v))
        r.commit('secret')
        self.check(r.scan(), saved=['app.py:4'], secrets=[v])

    def test_pin_gitattributes_binary(self):
        v = 'attr-binary-secret-value-22'
        r = self._pin(v, lambda r: r.write('.gitattributes', '*.py binary\n'))
        self.check(r.scan(), saved=['app.py:2'], secrets=[v])

    def test_pin_gitattributes_minus_diff(self):
        v = 'attr-nodiff-secret-value-33'
        r = self._pin(v, lambda r: r.write('.gitattributes', '*.py -diff\n'))
        self.check(r.scan(), saved=['app.py:2'], secrets=[v])

    def test_pin_textconv_driver_printing_nothing(self):
        v = 'textconv-secret-value-4444'

        def setup(r):
            r.write('.gitattributes', '*.py diff=hide\n')
            r.git('config', 'diff.hide.textconv', "sh -c 'echo redacted' #")
        r = self._pin(v, setup)
        self.check(r.scan(), saved=['app.py:2'], secrets=[v])

    def test_pin_log_show_root_false_with_secret_in_root_commit(self):
        v = 'root-commit-secret-value-55'
        r = self.fresh(remote=False)
        r.git('config', 'log.showRoot', 'false')
        r.git('checkout', '-q', '--orphan', 'rooted')
        r.git('rm', '-q', '-rf', '.')
        r.write('app.py', kv('API_KEY', v))
        r.commit('root')
        self.check(r.scan(), saved=['app.py:1'], secrets=[v])

    def _ignore_env(self, r):
        ig = os.path.join(r.root, 'global-ignore')
        with open(ig, 'w') as f:
            f.write('.env*\n')
        r.git('config', 'core.excludesFile', ig)

    def test_ignored_untracked_env_example_is_still_scanned(self):
        r = self.fresh()
        v = SK_LIVE + 'realkey-123456'
        self._ignore_env(r)
        r.write('.env.example', 'API_KEY=%s\n' % v)
        self.check(r.scan(), new=['.env.example:1'], secrets=[v])

    def test_ignored_nested_env_example_is_still_scanned(self):
        r = self.fresh()
        v = SK_LIVE + 'realkey-123456'
        self._ignore_env(r)
        r.write('config/.env.example', 'API_KEY=%s\n' % v)
        self.check(r.scan(), new=['config/.env.example:1'], secrets=[v])

    def test_ignored_env_local_stays_no_hit(self):
        r = self.fresh()
        v = SK_LIVE + 'realkey-123456'
        self._ignore_env(r)
        r.write('.env.local', 'API_KEY=%s\n' % v)
        self.check(r.scan(), secrets=[v])

    def test_env_example_in_ignored_folder_is_not_scanned(self):
        r = self.fresh()
        v = 'sk' + '_test_realisticvalue123'
        r.write('.gitignore', 'node_modules/\n')
        r.commit('ignore')
        r.write('node_modules/pkg/.env.example', 'API_KEY=%s\n' % v)
        self.check(r.scan(), secrets=[v], code=0)

    def test_root_env_example_hidden_by_excludes_file_is_still_a_hit(self):
        r = self.fresh()
        v = 'sk' + '_test_rootvalue12345'
        self._ignore_env(r)
        r.write('.env.example', 'API_KEY=%s\n' % v)
        self.check(r.scan(), new=['.env.example:1'], secrets=[v], code=1)

    # ---- re-review holes (2026-10-17)
    def _utf16_repo(self):
        r = self.fresh()
        r.write('.gitattributes', '*.cfg text working-tree-encoding=UTF-16LE\n')
        r.write('old.cfg', 'NAME=demo\n'.encode('utf-16-le'))
        r.commit('cfg')
        r.push()
        return r

    def test_working_tree_encoding_in_unsaved_and_new_scopes(self):
        r = self._utf16_repo()
        v1, v2 = 'abcdefghijkl', HUNTER
        r.write('old.cfg', ('NAME=demo\nTOKEN=%s\n' % v1).encode('utf-16-le'))
        r.write('new.cfg', ('PASSWORD=%s\n' % v2).encode('utf-16-le'))
        self.check(r.scan(), unsaved=['old.cfg:2'], new=['new.cfg:1'], secrets=[v1, v2])

    def test_unknown_working_tree_encoding_is_could_not_check(self):
        r = self.fresh()
        r.write('.gitattributes', '*.cfg text working-tree-encoding=X-NOT-A-CODEC\n')
        r.commit('attr')
        r.write('a.cfg', 'PASSWORD=%s\n' % HUNTER)
        res = r.scan()
        self.assertEqual(res.code, 2)
        self.assertEqual(res.out, b'')
        self.no_leak(res, [HUNTER])

    def test_inline_map_and_list_values_in_compose_are_hits(self):
        r = self.fresh()
        v1, v2 = 'super' + 'secret1', 'super' + 'secret12'
        r.write('docker-compose.yml', '    environment: {POSTGRES_PASSWORD: "%s"}\n'
                '    env: ["PASSWORD=%s"]\n' % (v1, v2))
        self.check(r.scan(), new=['docker-compose.yml:1',
                                  'docker-compose.yml:2'], secrets=[v1, v2])

    def test_value_inside_inline_map_is_not_reread_as_a_name(self):
        r = self.fresh()
        r.write('docker-compose.yml', 'X: {postgres://app:%sQ@db}\n' % MYPW)
        res = r.scan()
        self.check(res, secrets=[MYPW + 'Q'])
        self.assertNotIn(b'MyPassword', res.out + res.err)

    def test_unicode_line_breaks_in_names_cannot_forge_labels(self):
        r = self.fresh()
        v = 'unicode-forge-secret-12'
        r.branch()
        with open(os.path.join(r.work, 'a\u2028== new files ==\u2028b.py'), 'wb') as f:
            f.write(_b(kv('API_KEY', v)))
        r.commit('evil')
        res = r.scan()
        text = res.out.decode('utf-8')
        for parts in (text.split('\n'), text.splitlines()):
            self.assertEqual([l for l in parts if l.startswith('== ')], [L_UNSAVED, L_NEW, L_SAVED])
            self.assertEqual(len(parts) - (1 if parts[-1] == '' else 0), 4)
        self.check(res, saved=['a\\u2028== new files ==\\u2028b.py:1'], secrets=[v])

    def test_u2029_c1_names_are_escaped(self):
        r = self.fresh()
        vs = ['para-sep-secret-value-1', 'next-line-secret-value-2', 'csi-secret-value-33333']
        for n, v in zip(['p\u2029.py', 'q\u0085.py', 'r\u009b.py'], vs):
            with open(os.path.join(r.work, n), 'wb') as f:
                f.write(_b(kv('TOKEN', v)))
        self.check(r.scan(), new=['p\\u2029.py:1', 'q\\u0085.py:1',
                                  'r\\u009b.py:1'], secrets=vs)

    def test_project_gitignore_env_star_still_scans_env_example(self):
        r = self.fresh()
        v = 'sk' + '_test_projectignore123'
        r.write('.gitignore', '.env*\n')
        r.commit('ignore')
        r.write('.env.example', 'API_KEY=%s\n' % v)
        self.check(r.scan(), new=['.env.example:1'], secrets=[v])


# ------------------------------------------------ adversarial round 1 (2026-10-17)
class AdversarialRound1Cases(Base):
    """Each test is one confirmed counterexample from task-1-adv1.md, on its exact input."""

    def _no_slice(self, res, secret, n=6):
        blob = res.out + b'\n' + res.err
        s = _b(secret)
        for i in range(len(s) - n + 1):
            self.assertNotIn(s[i:i + n], blob, 'secret slice leaked at %d' % i)

    def _subtle_flag(self, flag):
        r = self.fresh()
        v = fake('secretA1xyz')
        r.write('app.py', BASE + kv('API_KEY', v))
        r.git('add', 'app.py')
        r.git('update-index', flag, 'app.py')
        r.write('app.py', b'\0\0binary junk\n')
        self.check(r.scan(), unsaved=['app.py:2'], secrets=[v])

    def test_1_name_started_inside_a_string_literal_leaks_nothing(self):
        r = self.fresh()
        v = B64
        r.write('auth.py', 'token = jwt.encode(payload, "%s", algorithm="HS256")\n' % v)
        res = r.scan()
        self._no_slice(res, v)
        self.no_leak(res, [v])
        self.assertNotIn(b'c2VjcmV0', res.out + res.err)
        self.assertTrue(res.code == 0 or b'auth.py' in res.out)

    def test_2a_assume_unchanged_staged_secret_with_binary_worktree(self):
        self._subtle_flag('--assume-unchanged')

    def test_2b_skip_worktree_staged_secret_with_binary_worktree(self):
        self._subtle_flag('--skip-worktree')

    def test_3_conflicted_merge_in_progress_scans_the_merge_side(self):
        r = self.fresh()
        v = fake('secretM1xyz')
        r.branch('side')
        r.write('app.py', BASE + kv('API_KEY', v))
        r.commit('side add')
        r.write('app.py', 'name = "side"\n')
        r.commit('side rm')
        r.git('checkout', '-q', 'main')
        r.write('app.py', 'name = "main"\n')
        r.commit('main edit')
        cp = subprocess.run(GIT + ['merge', 'side'], cwd=r.work,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertNotEqual(cp.returncode, 0, 'merge was expected to conflict')
        self.assertTrue(os.path.exists(os.path.join(r.work, '.git', 'MERGE_HEAD')))
        r.write('app.py', 'name = "resolved"\n')
        self.check(r.scan(), saved=['app.py:2'], secrets=[v])

    @unittest.skipUnless(hasattr(os, 'symlink'), 'platform has no symlinks')
    def test_4_symlink_whose_target_text_is_a_secret(self):
        r = self.fresh()
        v = fake('secretC1xyz')
        os.symlink('API_KEY="%s"' % v, r.path('link.py'))
        self.check(r.scan(), new=['link.py:1'], secrets=[v])

    def test_5a_new_file_with_clean_filter_is_scanned_as_stored(self):
        r = self.fresh()
        v = fake('secretD1xyz')
        r.git('config', 'filter.r13.clean', "tr 'A-Za-z' 'N-ZA-Mn-za-m'")
        r.write('.gitattributes', 'settings.py filter=r13\n')
        r.write('settings.py', codecs.encode(kv('API_KEY', v), 'rot13'))
        self.check(r.scan(), new=['settings.py:1'], secrets=[v])

    def test_5b_unsaved_with_nul_stripping_clean_filter(self):
        r = self.fresh()
        v = fake('secretD2xyz')
        r.git('config', 'filter.nonul.clean', "tr -d '\\000'")
        r.write('.gitattributes', 'app.py filter=nonul\n')
        r.commit('attrs')
        r.push()
        r.write('app.py', b'\0name = "demo"\n' + _b(kv('API_KEY', v)))
        self.check(r.scan(), unsaved=['app.py:2'], secrets=[v])

    def test_6_two_megabyte_single_line_finishes_quickly(self):
        r = self.fresh()
        r.write('big.py', 'PASSWORD = "' + '<' * 2000000 + '"\n')
        t = time.time()
        try:
            cp = subprocess.run([sys.executable, SCRIPT, '--repo', r.work],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        except subprocess.TimeoutExpired:
            self.fail('scan of a 2 MB single line did not finish within 20s')
        res = Result(cp, time.time() - t)
        self.assertEqual(res.code, 1)
        self.assertEqual(res.lines, [L_UNSAVED, L_NEW, 'big.py:1', L_SAVED])
        self.assertLess(len(res.out) + len(res.err), 2000)
        self.assertNotIn(b'<<<<', res.out + res.err)
        self.no_leak(res, [])

    def test_7_literal_ending_in_name_sep_does_not_hide_the_real_secret(self):
        r = self.fresh()
        v1, v2, v3 = fake('secretG1aa'), fake('secretG1bb'), fake('secretG1cc')
        r.write('db.py', 'conn = psycopg2.connect("dbname=" + name, password="%s")\n' % v1)
        r.write('api.js', 'fetch(base + "?user=" + u, { apiKey: "%s" });\n' % v2)
        r.write('pr.py', 'print("user=", user); API_KEY = "%s"\n' % v3)
        self.check(r.scan(), new=['api.js:1', 'db.py:1', 'pr.py:1'],
                   secrets=[v1, v2, v3])

    def test_8_triple_quoted_value_is_not_an_empty_literal(self):
        r = self.fresh()
        v = fake('secretF1aaa')
        r.write('f1.py', 'PASSWORD = """%s"""\n' % v)
        self.check(r.scan(), new=['f1.py:1'], secrets=[v])


class ReReview3Cases(Base):
    """Confirmed counterexamples from task-1-review3.md, each on its exact input."""

    def _no_slice(self, res, secret, n=6):
        blob = res.out + b'\n' + res.err
        s = _b(secret)
        for i in range(len(s) - n + 1):
            sl = s[i:i + n]
            self.assertNotIn(sl, blob, 'secret slice leaked at %d' % i)

    def test_1_ternary_branches_never_print(self):
        r = self.fresh()
        admin, ghp = 'Admin' + 'Password', 'ghp' + '_MySecretToken'
        r.write('app.js', 'const pw = prod ? "%s" : "%s";\n' % (ACME, LOCALDEV))
        r.write('cfg.js', 'const c = { password: isProd ? "%s" : "%s" };\n' % (admin, 'devdev' + 'devdev'))
        r.write('App.java', 'String t = prod ? "%s" : "%s";\n' % (ghp, 'devtoken' + 'value'))
        r.write('sq.js', "const pw = prod ? '%s' : '%s';\n" % (ACME, LOCALDEV))
        res = r.scan()
        blob = res.out + b'\n' + res.err
        for v in (ACME, admin, ghp):
            self._no_slice(res, v)
            self.assertNotIn(_b(v), blob)
        self.check(res)

    def _one(self, rel, text, hit, secret):
        r = self.fresh()
        r.write(rel, text)
        self.check(r.scan(), new=[hit], secrets=[secret])

    def test_2a_json_loads_literal_body_is_scanned(self):
        self._one('a.py', 'data = json.loads(\'{"password": "%s"}\')\n' % HUNTER,
                  'a.py:1', HUNTER)

    def test_2b_json_parse_literal_body_is_scanned(self):
        self._one('b.js', 'const c = JSON.parse(\'{"apiKey":"%s"}\');\n' % (SK_LIVE + 'abcdef123456'),
                  'b.js:1', SK_LIVE + 'abcdef123456')

    def test_2c_curl_json_body_in_shell_is_scanned(self):
        self._one('seed.sh', 'curl -d \'{"username":"admin","password":"%s"}\' http://localhost/api\n' % fake('secretSH1'),
                  'seed.sh:1', fake('secretSH1'))

    def test_2d_compose_command_export_is_scanned(self):
        self._one('docker-compose.yml', '    command: sh -c "export X=1; PASSWORD=%s"\n' % fake('compose1'),
                  'docker-compose.yml:1', fake('compose1'))

    def test_2e_compose_command_and_chain_is_scanned(self):
        self._one('c2/docker-compose.yml',
                  '    command: bash -c "pip install x && SECRET_KEY=%s python app.py"\n' % fake('compose2'),
                  'c2/docker-compose.yml:1', fake('compose2'))

    def test_3_lexer_misread_never_leaks_a_base64_slice(self):
        r = self.fresh()
        v = B64
        r.write('x.js', 's.replace(/"/g, "_"); sign("%s", algorithm="HS256")\n' % v)
        r.write('Y.cs', 'var p = @"C:\\Users\\"; Encode("%s", algorithm="HS256");\n' % v)
        r.write('app.yml', 'description: use key %sabcdefgh1\n' % v)
        res = r.scan()
        self._no_slice(res, v)
        self.assertNotIn(b'c2VjcmV0', res.out + res.err)
        self.check(res, secrets=[v])

    def _lfs_repo(self):
        r = self.fresh()
        r.git('lfs', 'install', '--local')
        r.git('lfs', 'track', '*.json')
        r.commit('lfs attrs')
        r.push()
        return r

    @unittest.skipUnless(shutil.which('git-lfs'), 'git-lfs not installed')
    def test_4a_untracked_lfs_file_content_is_scanned(self):
        r = self._lfs_repo()
        v = SK_LIVE + 'lfs-secret-12345'
        r.write('settings.json', '{"apiKey": "%s"}\n' % v)
        self.check(r.scan(), new=['settings.json:1'], secrets=[v])

    @unittest.skipUnless(shutil.which('git-lfs'), 'git-lfs not installed')
    def test_4b_missing_lfs_object_fails_closed(self):
        r = self._lfs_repo()
        v = SK_LIVE + 'lfs-secret-12345'
        r.branch('feat')
        r.write('settings.json', '{"apiKey": "%s"}\n' % v)
        r.commit('add settings')
        shutil.rmtree(r.path('.git/lfs/objects'))
        res = r.scan()
        self.assertEqual(res.code, 2, 'stderr=%r' % res.err[:300])
        self.assertEqual(res.out, b'')
        self.no_leak(res, [v])


class ReReview4Cases(Base):
    """Confirmed counterexamples from task-1-review4.md, each on its exact input."""

    def _no_slice(self, res, secret, n=6):
        blob = res.out + b'\n' + res.err
        s = _b(secret)
        for i in range(len(s) - n + 1):
            sl = s[i:i + n]
            self.assertNotIn(sl, blob, 'secret slice leaked at %d' % i)

    def _one(self, rel, text, hit, secret):
        r = self.fresh()
        r.write(rel, text)
        self.check(r.scan(), new=[hit], secrets=[secret])

    SETUP = ("kubectl create secret generic app-secrets \\\n"
             "  --from-literal=JWT_SECRET='%s' \\\n"
             "  --from-literal=POSTGRES_PASSWORD='%s'\n") % (fake('jwtA1xyz9'), fake('pgB1xyz9'))

    def _from_literal(self, rel):
        r = self.fresh()
        r.write(rel, self.SETUP)
        self.check(r.scan(), new=[rel + ':2', rel + ':3'],
                   secrets=[fake('jwtA1xyz9'), fake('pgB1xyz9')])

    def test_1a_from_literal_in_shell_script_hits(self):
        self._from_literal('setup.sh')

    def test_1b_from_literal_in_onboarding_doc_hits(self):
        self._from_literal('ONBOARDING-K8S.md')

    def test_1c_terraform_var_equals_hits(self):
        self._one('infra.sh', 'terraform apply -var=db_password="%s"\n' % fake('tfC1xyz9'),
                  'infra.sh:1', fake('tfC1xyz9'))

    def test_1d_helm_set_equals_hits(self):
        self._one('deploy.sh', 'helm install x --set=auth.password="%s"\n' % fake('helmD1x9'),
                  'deploy.sh:1', fake('helmD1x9'))

    def test_1e_yaml_item_from_literal_hits(self):
        self._one('job.yml', '        - --from-literal=password=%s\n' % fake('yamlE1x9'),
                  'job.yml:1', fake('yamlE1x9'))

    def _clean(self, files, secret):
        r = self.fresh()
        for rel, text in files.items():
            r.write(rel, text)
        res = r.scan()
        self.check(res, secrets=[secret])
        self._no_slice(res, secret)
        self.assertNotIn(_b(secret), res.out + res.err)

    def test_2_multiline_ternary_never_prints_the_value(self):
        self._clean({'ml.js': 'const pw = isProd ?\n  "%s" : "%s";\n' % (ACME, LOCALDEV),
                     'ml.php': "$pw = $isProd ?\n  '%s' : '%s';\n" % (ACME, LOCALDEV)},
                    ACME)

    def test_3_shell_test_never_prints_the_value(self):
        self._clean({'yoda.sh': 'if [ "%s" = "$(cat /run/pw)" ]; then echo ok; fi\n' % ACME,
                     'yoda2.sh': 'if [[ "%s" = "$(cat /run/pw)" ]]; then echo ok; fi\n' % ACME},
                    ACME)

    @unittest.skipUnless(shutil.which('git-lfs'), 'git-lfs not installed')
    def test_5a_lfs_unsaved_edit_hits(self):
        r = ReReview3Cases._lfs_repo(self)
        r.write('s.json', '{"name": "demo"}\n')
        r.commit('s')
        r.push()
        v = SK_LIVE + 'lfs-unsaved-1234'
        r.append('s.json', '"apiKey": "%s"\n' % v)
        self.check(r.scan(), unsaved=['s.json:2'], secrets=[v])

    @unittest.skipUnless(shutil.which('git-lfs'), 'git-lfs not installed')
    def test_5b_lfs_saved_commit_hits(self):
        r = ReReview3Cases._lfs_repo(self)
        r.branch('feat')
        v = SK_LIVE + 'lfs-saved-5678'
        r.write('t.json', '{"apiKey": "%s"}\n' % v)
        r.commit('add t')
        self.check(r.scan(), saved=['t.json:1'], secrets=[v])


class ReReview5Cases(Base):
    """Confirmed counterexamples from task-1-review5.md, each on its exact input."""

    def _one(self, rel, text, hit, secret):
        r = self.fresh()
        r.write(rel, text)
        self.check(r.scan(), new=[hit], secrets=[secret])

    def _clean(self, rel, text, secret):
        r = self.fresh()
        r.write(rel, text)
        res = r.scan()
        self.check(res, secrets=[secret])
        blob = res.out + b'\n' + res.err
        s = _b(secret)
        for i in range(len(s) - 5):
            sl = s[i:i + 6]
            self.assertNotIn(sl, blob, 'secret slice leaked at %d' % i)
        self.assertNotIn(s, blob)

    def test_1a_comment_question_mark_keeps_python_dict_key(self):
        self._one('settings.py',
                  'CONFIG = {\n    "debug": False,  # needed in prod?\n    "password": "%s",\n' % fake('dictP1xyz'),
                  'settings.py:3', fake('dictP1xyz'))

    def test_1b_comment_question_mark_keeps_js_key(self):
        self._one('cfg.js',
                  'module.exports = {\n  retries: 3, // enough?\n  "apiKey": "%s",\n' % fake('jsP2xyz12'),
                  'cfg.js:3', fake('jsP2xyz12'))

    def test_1c_comment_question_mark_after_open_brace(self):
        self._one('s.py', 'DB = {  # which db?\n    "password": "%s",\n' % fake('braceP7xy'),
                  's.py:2', fake('braceP7xy'))

    def test_1d_comment_question_mark_after_yaml_parent(self):
        self._one('c.yml', 'env:  # needed?\n  "PASSWORD": "%s"\n' % fake('yamlP6xyz'),
                  'c.yml:2', fake('yamlP6xyz'))

    def test_2a_comment_only_line_ending_in_question_mark_keeps_key(self):
        self._one('g.py', 'CONFIG = {\n    # rotate?\n    "password": "%s",\n' % fake('guardG1xyz'),
                  'g.py:3', fake('guardG1xyz'))

    def test_2b_yaml_parent_without_question_mark_keeps_key(self):
        self._one('g.yml', 'env:\n  "PASSWORD": "%s"\n' % fake('guardG2xyz'),
                  'g.yml:2', fake('guardG2xyz'))

    def test_3_ternary_with_trailing_comment_never_prints_the_value(self):
        self._clean('t1.js',
                    'const pw = isProd ? // production\n  "%s" : "%s";\n' % (ACME, LOCALDEV),
                    ACME)

    def test_4_blank_line_after_question_mark_never_prints_the_value(self):
        self._clean('t2.js',
                    'const pw = isProd ?\n\n  "%s" : "%s";\n' % (ACME, LOCALDEV),
                    ACME)


class QuotedKeyCases(Base):
    """Owner amendments: nothing from file contents is printed. A hit is `file:line` or no hit."""

    PLANT = ACME
    VAL = LOCALDEV

    def _no_leak_slices(self, res, secret):
        blob = res.out + b'\n' + res.err
        s = _b(secret)
        for i in range(len(s) - 5):
            sl = s[i:i + 6]
            self.assertNotIn(sl, blob, 'secret slice leaked at %d' % i)
        self.assertNotIn(s, blob)

    def _leak_free(self, res, secrets, hit_re_lines=None):
        self.assertIn(res.code, (0, 1), 'stderr=%r' % res.err[:300])
        for ln in res.lines:
            if ln.startswith('=='):
                continue
            self.assertTrue(re.match(r'^[^:]+:\d+$', ln), 'hit line is not file:line: %r' % ln)
        self.no_leak(res, secrets)
        for s in secrets:
            self._no_leak_slices(res, s)

    def _untracked(self, rel, text, secrets, hit):
        r = self.fresh()
        r.write(rel, text)
        res = r.scan()
        self.check(res, new=[hit], secrets=secrets)
        self._leak_free(res, secrets)
        return res

    def test_1_blank_line_then_unchanged_question_mark_line(self):
        r = self.fresh()
        r.write('t.js', 'const pw = isProd ?\n\n  "%s";\n' % LOCALDEV)
        r.commit('t')
        r.push()
        r.write('t.js', 'const pw = isProd ?\n\n  "%s" : "%s";\n' % (self.PLANT, self.VAL))
        res = r.scan()
        self.check(res, unsaved=['t.js:3'], secrets=[self.PLANT, self.VAL])
        self._leak_free(res, [self.PLANT, self.VAL])

    def test_2_block_comment_after_question_mark(self):
        self._untracked('u.js', 'const pw = isProd ? /* prod */\n  "%s" : "%s";\n' % (self.PLANT, self.VAL),
                        [self.PLANT, self.VAL], 'u.js:2')

    def test_3_regex_with_double_slash_before_question_mark(self):
        self._untracked('v.js', 'const ok = /https?:\\/\\//.test(u) ?\n  "%s" : "%s";\n' % (self.PLANT, self.VAL),
                        [self.PLANT, self.VAL], 'v.js:2')

    def test_4_secret_used_as_dict_key(self):
        r = self.fresh()
        r.write('w.py', 'KEYS = {"%s": "acme-corporation"}\n' % SK_KEY)
        res = r.scan()
        self.check(res, new=['w.py:1'], secrets=[SK_KEY, 'acme-corporation'])
        self._leak_free(res, [SK_KEY, 'acme-corporation'])

    def test_5_json_key_that_is_the_value_looking_string_hits_and_is_not_printed(self):
        r = self.fresh()
        r.write('x.json', '{"%s": "%s"}\n' % (ACME, fake('jsonX1xyz')))
        res = r.scan()
        self.check(res, new=['x.json:1'], secrets=[fake('jsonX1xyz')])
        self.assertNotIn(_b(ACME), res.out + res.err)


class OutputOrderCases(Base):
    """Hits sort by (file, line) and de-duplicate per line; blank lines must not slow the scan."""

    def test_a_two_quoted_keys_on_one_line_print_once(self):
        r = self.fresh()
        r.write('t.js', 'const c = { "password": "%s", "apiKey": "%s" };\n' % (fake('dupA1xyz9'), fake('dupB1xyz9')))
        self.check(r.scan(), new=['t.js:1'], secrets=[fake('dupA1xyz9'), fake('dupB1xyz9')])

    def test_b_order_is_file_then_line(self):
        r = self.fresh()
        r.write('a.json', '{"password": "%s"}\n' % fake('sortC1xy9'))
        r.write('a.py', kv('API_KEY', fake('sortD1xy9')))
        self.check(r.scan(), new=['a.json:1', 'a.py:1'],
                   secrets=[fake('sortC1xy9'), fake('sortD1xy9')])

    def test_c_long_line_then_many_blank_lines_is_fast(self):
        r = self.fresh()
        r.write('big.py', 'x = "' + 'a' * 2000000 + '"\n' + '\n' * 10000 + kv('API_KEY', fake('speedE1x9')))
        t = time.time()
        cp = subprocess.run([sys.executable, SCRIPT, '--repo', r.work],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        res = Result(cp, time.time() - t)
        self.check(res, new=['big.py:10002'], secrets=[fake('speedE1x9')])


class ValueStringCases(Base):
    """A string that is itself a VALUE is scanned inside too (amendment, last bullet)."""

    def _one(self, rel, text, v):
        r = self.fresh()
        r.write(rel, text)
        res = r.scan()
        self.check(res, new=[rel + ':1'], secrets=[v])
        self.assertEqual(res.code, 1)

    def test_a_python_assignment_of_a_command_string(self):
        self._one('a.py', 'cmd = \'API_KEY="%s" ./deploy.sh\'\n' % fake('secretV1xyz'), fake('secretV1xyz'))

    def test_b_python_keyword_argument_command_string(self):
        self._one('b.py', 'subprocess.run(args=\'API_KEY="%s" ./deploy.sh\', shell=True)\n' % fake('secretV2xyz'),
                  fake('secretV2xyz'))

    def test_c_js_object_property_command_string(self):
        self._one('c.js', 'const job = { cmd: \'export API_KEY="%s"\' };\n' % fake('secretV3xyz'), fake('secretV3xyz'))

    def test_d_compose_command_string(self):
        self._one('docker-compose.yml', '    command: "sh -c \'export PASSWORD=%s; ./run\'"\n' % fake('secretV4xyz'),
                  fake('secretV4xyz'))

    def test_e_guard_url_with_password_equals_stays_clean(self):
        r = self.fresh()
        r.write('d.py', 'url = "postgres://app:%sQ@db/app"\n' % MYPW)
        res = r.scan()
        self.check(res, secrets=[MYPW + 'Q'])
        self.assertEqual(res.code, 0)


class AdversarialRound2Cases(Base):
    """Counterexamples from task-1-adv2.md, each on its exact input."""

    def test_1_password_value_with_equals_is_never_printed(self):
        r = self.fresh()
        r.write('docker-compose.yml',
                ('services:\n  a:\n'
                 '    command: ["./wait-for", "postgresql+asyncpg://app:%sQ@db/app"]\n'
                 '    x: 1\n'
                 '      - postgresql+asyncpg://app:%sA@db/app\n') % (MYPW, MYPW))
        r.write('Dockerfile', 'FROM x\nENV DATABASE_URL postgresql+asyncpg://app:%sB@db/app\n' % MYPW)
        r.write('settings.toml', 'urls = ["postgresql+psycopg2://app:%sC@db/app"]\n' % MYPW)
        r.write('braces.yml', 'X: {postgresql+asyncpg://app:%sQ@db}\n' % MYPW)
        r.write('k8s.yaml', 'args:\n          - -Dspring.datasource.password=%sQ\n' % MYPW)
        r.write('fr.yml', 'cl\u00e9: %sQ\n' % MYPW)
        res = r.scan()
        self.assertEqual(res.code, 1, 'stderr=%r' % res.err[:300])
        self.assertEqual(res.lines, [L_UNSAVED, L_NEW, 'Dockerfile:2', 'braces.yml:1',
                                     'docker-compose.yml:3', 'docker-compose.yml:5', 'fr.yml:1',
                                     'k8s.yaml:2', 'settings.toml:1', L_SAVED])
        for v in ('My' + 'Password', '2024' + 'xyz'):
            self.assertNotIn(_b(v), res.out + res.err)
        self.no_leak(res, [MYPW + 'Q'])

    def test_2_quoted_assignments_inside_literals_in_non_config_files(self):
        r = self.fresh()
        vs = [fake('secretS1xyz'), fake('secretP1xyz'), fake('secretJ1xyz'), fake('secretM1xyz')]
        r.write('deploy.sh', "#!/bin/sh\nssh app@prod.example.net 'export DB_PASSWORD=\"%s\"; ./migrate'\n" % vs[0])
        r.write('run.py', "import subprocess\nsubprocess.run('API_KEY=\"%s\" ./deploy.sh', shell=True)\n" % vs[1])
        r.write('job.js', "const { execSync } = require('child_process');\n"
                          "execSync(`SECRET_KEY='%s' node worker.js`);\n" % vs[2])
        r.write('README.md', '# App\nBefore starting, run `export API_KEY="%s"` in your shell.\n' % vs[3])
        self.check(r.scan(), new=['README.md:2', 'deploy.sh:2', 'job.js:2', 'run.py:2'], secrets=vs)

    def test_3_yaml_value_ending_in_question_mark_does_not_hide_next_key(self):
        r = self.fresh()
        v = fake('secretY2xyz')
        r.write('queries.yml', 'find_user: SELECT * FROM users WHERE id = ?\n"db_password": "%s"\n' % v)
        r.write('ctl.yml', 'find_user: SELECT * FROM users WHERE id = 1\n"db_password": "%s"\n' % v)
        self.check(r.scan(), new=['ctl.yml:2', 'queries.yml:2'], secrets=[v])


# ------------------------------------------------- adversarial round 3 (last)
class AdversarialRound3Cases(Base):
    SECRET = fake('secretF1xyzwq')
    PLACEHOLDER_TXT = b'name = "demo"\n' + _b(kv('API_KEY', 'x' * 20))
    FILLED = b'name = "demo"\n' + _b(kv('API_KEY', SECRET))

    def _sec(self, path):
        return int(os.stat(path).st_mtime)

    def _racy(self, binary):
        """Build the racy-index repo and PROVE its precondition; retry if the timing missed the second."""
        last = None
        for _ in range(5):
            r = self.fresh()
            index = r.path('.git/index')
            stale = b'\0' + self.FILLED[1:] if binary else self.PLACEHOLDER_TXT
            t = time.time()
            time.sleep(1 - (t - int(t)) + 0.02)  # start just after a second boundary
            if binary:
                r.write('app.py', stale)
                r.git('add', 'app.py')  # index written this second
            else:
                r.write('app.py', stale)
                r.git('commit', '-qam', 'config with placeholder')  # index written this second
            r.write('app.py', self.FILLED)  # same size, no git command after this
            f_sec, i_sec = self._sec(r.path('app.py')), self._sec(index)
            idx_mtime_ns = os.stat(index).st_mtime_ns
            blob = subprocess.run(['git', 'hash-object', '--stdin'], cwd=r.work, input=stale,
                                  stdout=subprocess.PIPE, check=True).stdout.decode().strip()
            staged = r.git('ls-files', '-s', 'app.py').decode().split()[1]
            last = (f_sec, i_sec, len(stale), os.path.getsize(r.path('app.py')), staged == blob)
            if f_sec == i_sec and last[2] == last[3] and last[4]:
                self.assertEqual(os.stat(index).st_mtime_ns, idx_mtime_ns, 'a git command ran after the rewrite')
                # The real index must still hold the OLD content, so only a stat shortcut could hide the edit.
                self.assertEqual(r.git('cat-file', 'blob', staged), stale)
                time.sleep(max(0, i_sec + 1.1 - time.time()))  # scan strictly later than that second
                return r
        self.fail('racy-index precondition never held in 5 tries '
                  '(file sec, index sec, old size, new size, index has old blob) = %r' % (last,))

    def test_1a_racy_index_text_rewrite_after_commit(self):
        r = self._racy(binary=False)
        self.check(r.scan(), unsaved=['app.py:2'], secrets=[self.SECRET])

    def test_1b_racy_index_binary_staged_then_text_rewrite(self):
        r = self._racy(binary=True)
        self.check(r.scan(), unsaved=['app.py:2'], secrets=[self.SECRET])

    def test_3a_name_glued_after_punctuation_in_five_files(self):
        r = self.fresh()
        r.branch()
        v = [fake('secretD%dxyzw' % i) for i in range(1, 6)]
        r.write('boot.py', 'import cfg\nget_settings().api_key = "%s"\n' % v[0])
        r.write('seed.js', 'const users = [];\nusers[0].password = "%s";\n' % v[1])
        r.write('db.go', 'package main\nfunc init() { cfg.DB().Password = "%s" }\n' % v[2])
        r.write('dev.js', 'const x = 1;\n  //apiKey = "%s";\n' % v[3])
        r.write('patches/settings.patch', '--- a/s\n+++ b/s\n@@ -1,1 +1,2 @@\n name = "demo"\n+API_KEY = "%s"\n' % v[4])
        r.commit('glued names')
        self.check(r.scan(), saved=['boot.py:2', 'db.go:2', 'dev.js:2', 'patches/settings.patch:5', 'seed.js:2'],
                   secrets=v)

    def test_3b_name_glued_after_bang_call_and_index(self):
        r = self.fresh()
        r.branch()
        v = [fake('secretE%dxyzw' % i) for i in range(1, 4)]
        r.write('a.ts', 'class A {}\nthis.config!.apiKey = "%s";\n' % v[0])
        r.write('b.js', 'const Client = 1;\nnew Client().token = "%s";\n' % v[1])
        r.write('c.py', 'clients = {}\nclients["prod"].secret = "%s"\n' % v[2])
        r.commit('glued names 2')
        self.check(r.scan(), saved=['a.ts:2', 'b.js:2', 'c.py:2'], secrets=v)

    def test_3c_control_name_like_word_after_plus_in_base64_run_is_no_hit(self):
        # Like ReReview3Cases.test_3 (which covers `/`): the lookbehind's reason to exist, for `+`.
        r = self.fresh()
        r.write('app.yml', 'description: use key %s%s\nnote: %s%s\n' % (B64.replace('/', '+'), TAIL, B64, TAIL))
        self.check(r.scan(), secrets=[B64.replace('/', '+') + TAIL])


class ReReview6Cases(Base):
    """Re-review 6: the widened NAME lookbehind (9f5e390) must not add false hits. All new files."""

    def test_1_compose_volume_mounts_are_no_hit(self):
        r = self.fresh()
        r.write('docker-compose.yml', 'services:\n  backend:\n    image: app-backend\n    volumes:\n'
                '      - ~/.git-credentials:/root/.git-credentials:ro\n'
                '      - ./db_password:/run/secrets/db_password:ro\n'
                '      - /client_secret:/app/client_secret:ro\n')
        self.check(r.scan())

    def test_2a_js_regex_literal_starting_with_name_is_no_hit(self):
        r = self.fresh()
        r.write('redact.js', 'const x = 1;\nconst TOKEN_RE = /token="([a-f0-9]{32})"/;\n')
        self.check(r.scan())

    def test_2b_yaml_pattern_regex_starting_with_name_is_no_hit(self):
        r = self.fresh()
        r.write('semgrep.yml', "rules:\n  - pattern-regex: '(?i)/token=([a-z0-9]{8,})'\n")
        self.check(r.scan())

    def test_3a_quoted_url_path_starting_with_name_config_is_no_hit(self):
        r = self.fresh()
        r.write('app.yml', 'name: demo\nurl: "/token=%s"\n' % ('abcdefgh' + '12345'))
        self.check(r.scan(), secrets=[('abcdefgh' + '12345')])

    def test_3b_quoted_url_path_starting_with_name_source_is_no_hit(self):
        r = self.fresh()
        r.write('call.js', "const x = 1;\nfetch(\"/token='%s'\")\n" % ('abcdefgh' + '12345'))
        self.check(r.scan(), secrets=[('abcdefgh' + '12345')])

    def test_4_base64_run_starting_with_slash_is_no_hit(self):
        r = self.fresh()
        r.write('app.yml', 'description: use key /%s%s\n' % (B64[4:], TAIL))
        self.check(r.scan(), secrets=[B64[4:] + TAIL])

    def test_5_protocol_relative_url_password_is_still_a_hit(self):
        r = self.fresh()
        r.write('proxy.yml', 'upstream: "//app:%sQ@db/app"\n' % MYPW)
        self.check(r.scan(), new=['proxy.yml:1'], secrets=[MYPW + 'Q', '2024xyzQ'])


RETROFIT_IT = os.path.normpath(os.path.join(HERE, '..', '..', 'commands', 'retrofit-it.md'))
OPERATOR_SAFETY = os.path.normpath(os.path.join(HERE, '..', 'references', 'operator-safety.md'))
ARGO_IT = os.path.normpath(os.path.join(HERE, '..', '..', 'commands', 'argo-it.md'))
INSTALLED = '~/.claude/make-it/scripts/secret-scan.py'


class ArgoItWiringCases(Base):
    """argo-it.md step 3e: the shell block calls the scanner, as written, and fails closed."""

    def _doc(self):
        with open(ARGO_IT, encoding='utf-8') as f:
            return f.read()

    def _section(self):
        doc = self._doc()
        m = re.search(r'^\*\*3e\.[^\n]*\n', doc, re.M)
        self.assertTrue(m, 'argo-it.md: no "**3e." heading found')
        end = re.search(r'^\*\*4\. ', doc[m.end():], re.M)
        self.assertTrue(end, 'argo-it.md: no "**4." heading after 3e')
        return doc[m.end():m.end() + end.start()]

    def _block(self):
        m = re.search(r'^```bash\n(.*?)^```', self._section(), re.M | re.S)
        self.assertTrue(m, 'argo-it.md: no ```bash block found after the 3e heading')
        return m.group(1)

    def _run(self, cwd):
        block = self._block()
        self.assertTrue(INSTALLED in block, '3e block does not call %s' % INSTALLED)
        block = block.replace(INSTALLED, SCRIPT)
        cp = subprocess.run(['bash', '-c', block], cwd=cwd, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=180)
        return Result(cp, 0)

    def _code(self):
        return '\n'.join(l for l in self._block().splitlines() if not l.lstrip().startswith('#'))

    def test_old_inline_scan_is_gone(self):
        code = self._code()
        for old in ('PATTERN=', 'SKIP=', 'TAG=', 'awk', 'grep', 'xargs'):
            self.assertTrue(old not in code, 'old inline scan still in 3e: %r' % old)

    def test_block_runs_scanner_and_prints_its_output(self):
        r = self.fresh()
        r.branch()
        r.append('app.py', kv('API_KEY', fake('committed1234')))
        r.commit('key')
        r.append('app.py', kv('PASSWORD', fake('unsaved5678')))
        res = self._run(r.work)
        self.check(res, unsaved=['app.py:3'], saved=['app.py:2'],
                   secrets=[fake('committed1234'), fake('unsaved5678')])

    def test_block_clean_repo_prints_labels_exit_0(self):
        r = self.fresh()
        self.check(self._run(r.work))

    def test_block_surfaces_exit_2_outside_a_repo(self):
        with tempfile.TemporaryDirectory() as td:
            res = self._run(os.path.realpath(td))
        self.assertEqual(res.code, 2, 'exit code swallowed: out=%r err=%r' % (res.out, res.err[:200]))

    def test_scanner_call_has_no_exit_masking(self):
        for ln in self._code().splitlines():
            if 'secret-scan.py' in ln:
                self.assertNotRegex(ln, r'\|\||;\s*true|\|\s*\w|\bset \+e', 'masks the exit: %r' % ln)
        self.assertNotRegex(self._code(), r'(?m)^\s*set \+e|\|\|\s*(true|:)\b')

    def test_gate_text_no_var_name_and_no_quoting_of_hits(self):
        sec = re.sub(r'^```bash\n.*?^```', '', self._section(), flags=re.M | re.S)
        self.assertTrue('VAR_NAME' not in sec, 'scanner prints no NAME; gate must say line N of [file]')
        self.assertNotRegex(sec, r'(?i)\b(quote|quoting|repeat|echo|print|display|show)\b[^.\n]{0,40}'
                                 r'\b(hit|line|value|contents?)\b',
                            '3e tells the agent to quote a hit line or value')

    def test_gate_fails_closed_wording(self):
        sec = self._section()
        self.assertTrue("I couldn't check your changes for secrets, so I haven't saved or sent anything" in sec,
                        '3e lacks the could-not-check stop message')
        self.assertRegex(sec, r'(?i)exit')

    def test_pre_push_rules_name_the_script(self):
        doc = self._doc()
        i = doc.index('**Pre-push self-review rules')
        self.assertTrue('secret-scan.py' in doc[i:i + 3000], 'pre-push rules do not name the script')


class ArgoItAdversarial1Cases(Base):
    """Adversarial round 1 on 3e: following it to the letter must not still send a secret."""

    def _prose(self):
        w = ArgoItWiringCases('test_old_inline_scan_is_gone')
        return re.sub(r'^```bash\n.*?^```', '', w._section(), flags=re.M | re.S)

    def test_hit_paths_are_from_the_repo_top_folder(self):
        # project is web/ inside the repo; hits print top-folder paths, so 3e must say where to open them
        p = self._prose()
        self.assertRegex(p, r'git rev-parse --show-toplevel', '3e never names the top folder command')
        self.assertRegex(p, r'(?is)(top[- ]?(level )?folder|top level|repo(sitory)?.s top|show-toplevel)'
                            r'[^.]{0,200}(file|path|hit)|(file|path|hit)[^.]{0,200}'
                            r'(top[- ]?(level )?folder|top level|show-toplevel)',
                         '3e does not tie the hit path to the top folder')
        self.assertRegex(p, r'(?is)\bnot\b[^.]{0,60}(project (root|folder)|working (folder|directory))',
                         '3e does not say the path is NOT from the project folder')

    def test_refuses_env_that_is_a_link_or_tracked(self):
        p = self._prose()
        i = p.index('Move only the ones')
        mv = p[i - 1500:i + 1500]
        self.assertRegex(mv, r'(?i)(symlink|symbolic link|\bis a link\b|-L \.env)',
                         '3e never tells the agent to refuse a linked .env')
        self.assertRegex(mv, r'git ls-files|git check-ignore', '3e gives no tracked/ignored check for .env')
        self.assertRegex(mv, r'(?is)(link|tracked|ignore)[^.]{0,300}\bstop\b|\bstop\b[^.]{0,300}(link|tracked|ignore)',
                         '3e does not say to stop when .env is linked or tracked')
        self.assertRegex(mv, r'(?i)before[^.]{0,80}(writ|mov|put)[^.]{0,80}\.env|'
                             r'\.env[^.]{0,80}before', 'the .env check is not placed before the write')

    def test_escaped_names_are_not_literal(self):
        p = self._prose()
        self.assertTrue('\\x' in p and '\\u' in p, '3e names neither \\xNN nor \\uXXXX escapes')
        self.assertRegex(p, r'(?is)\\x[^.]{0,200}(escape|control)[^.]{0,300}\bstop\b|'
                            r'(escape|control)[^.]{0,200}\\x[^.]{0,300}\bstop\b',
                         '3e does not say to stop on an escaped name')
        self.assertRegex(p, r'(?i)not (a )?literal|isn.t literal|never (a )?literal',
                         '3e does not say the escape is not the literal file name')

    def test_move_every_value_on_a_flagged_line(self):
        p = self._prose()
        self.assertRegex(p, r'(?i)\bevery\s+(secret[- ]looking\s+|such\s+|found\s+)?value\b[^.\n]{0,60}\bline|'
                            r'\bline\b[^.\n]{0,60}\bevery\s+(secret[- ]looking\s+|such\s+|found\s+)?value\b',
                         '3e does not say to move every value on a flagged line')


class ArgoItReReview2Cases(Base):
    """Re-review 2 on 3e: the .env check must work before step 4's ignore line exists, and close the gaps."""

    def _w(self):
        return ArgoItWiringCases('test_old_inline_scan_is_gone')

    def _move(self):
        """The move paragraph (raw, code kept): from 'Move only the ones' to the end of that paragraph."""
        sec = self._w()._section()
        i = sec.index('Move only the ones')
        j = sec.find('\n\n', i)
        return sec[i:j if j != -1 else len(sec)]

    def _tail(self):
        mv = self._move()
        return mv[mv.index('Once it exits 0'):]

    def _env_cmds(self):
        """Inline code / fenced blocks in the move paragraph that prepare or check .env (not diagnostics)."""
        mv = self._move()
        spans = re.findall(r'```(?:bash|sh)?\n(.*?)```|`([^`\n]+)`', mv, re.S)
        cmds = []
        for blk, inl in spans:
            c = (blk or inl).strip()
            if '.env' not in c or not re.search(r'\b(test|git|grep|printf|find)\b', c):
                continue
            if (re.search(r'ls-files|error-unmatch', c) and 'check-ignore' not in c) or re.match(r'test -[Lld] ', c):
                continue  # a per-reason probe that is meant to exit 1 on a good .env
            cmds.append(c)
        self.assertTrue(cmds, '3e move paragraph gives no .env safety command in code')
        self.assertTrue(any('check-ignore' in c for c in cmds), 'no git check-ignore in the .env command(s)')
        return cmds

    def _run_env(self, r, shell):
        need_shell(shell)
        script = '\n'.join('{ %s\n} || exit 1' % c for c in self._env_cmds())  # any failing step stops
        cp = subprocess.run([shell, '-c', script], cwd=r.work, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=60)
        return cp.returncode

    def _ignored(self, r):
        return subprocess.run(['git', 'check-ignore', '-q', '.env'], cwd=r.work).returncode == 0

    def _both(self, mk, ok):
        for shell in ('bash', 'zsh'):
            r = self.fresh()
            mk(r)
            code = self._run_env(r, shell)
            if ok:
                self.assertEqual(code, 0, '%s: .env check stopped a good .env' % shell)
                self.assertTrue(self._ignored(r), '%s: .env not ignored after the check' % shell)
            else:
                self.assertNotEqual(code, 0, '%s: .env check passed an unsafe .env' % shell)

    def test_i1_gitignore_without_env_passes_and_adds_the_ignore(self):
        def mk(r):
            r.write('.gitignore', 'node_modules/\n')
            r.commit('ignore')
            r.write('.env', 'X=1\n')
        self._both(mk, True)

    def test_i1_no_gitignore_passes(self):
        self._both(lambda r: r.write('.env', 'X=1\n'), True)

    def test_i1_guard_tracked_env_fails(self):
        def mk(r):
            r.write('.gitignore', '.env\n')
            r.write('.env', 'X=1\n')
            r.git('add', '-f', '.env')
            r.commit('tracked')
            self.assertIn(b'.env', r.git('ls-files', '.env'))
        self._both(mk, False)

    def test_i1_guard_symlinked_env_fails(self):
        def mk(r):
            r.write('config/local.settings', 'DEBUG=1\n')
            r.commit('t')
            os.symlink('config/local.settings', r.path('.env'))
        self._both(mk, False)

    def test_i1_guard_negated_env_fails(self):
        def mk(r):
            r.write('.gitignore', '.env*\n!.env\n')
            r.commit('neg')
            r.write('.env', 'X=1\n')
        self._both(mk, False)

    def test_m1_hard_linked_env_fails(self):
        def mk(r):
            r.write('.gitignore', '.env\n')
            r.write('config/local.settings', 'DEBUG=1\n')
            r.commit('t')
            os.link(r.path('config/local.settings'), r.path('.env'))
        self._both(mk, False)

    def test_m2_value_goes_to_the_project_root_env_just_checked(self):
        t = self._tail()
        self.assertRegex(t, r'(?is)each value goes to.{0,120}project root.{0,120}check',
                         '3e does not say the value goes to the project-root .env that was just checked')

    def test_m3_escaped_name_stop_covers_folders_and_underscores(self):
        sec = self._w()._section()
        i = sec.index('hidden or unusual character')
        j = sec.index('run /argo-it again', i)
        stop = sec[i:j]
        self.assertRegex(stop, r'(?i)\b(folders?|director(y|ies)|path)\b',
                         'escaped-name stop speaks only of a file, not its folders/path')
        self.assertRegex(stop, r'(?i)underscores?', 'plain-name rule does not allow underscores')

    def test_m4_rescan_after_move_and_hit_left_means_stop(self):
        t = self._tail()
        self.assertRegex(t, r'(?is)\b(run|re-?run)\b[^.]{0,120}\b(3e|scan)\b[^.]{0,60}\bagain\b|'
                            r'\bagain\b[^.]{0,60}\b(3e|scan)\b', '3e does not tell the agent to run the scan again after moving')
        self.assertRegex(t, r'(?is)\b(any|a)\s+hit\b[^.]{0,120}\bstop\b|\bstop\b[^.]{0,120}\b(any|a)\s+hit\b',
                         '3e does not say a hit left after moving means stop')

    def test_m5_stop_message_tells_the_three_reasons_apart(self):
        mv = self._move()
        per_reason = (re.search(r'ls-files|error-unmatch', mv) and re.search(r'test -L', mv)
                      and re.search(r'check-ignore', mv))
        says_which = re.search(r'(?i)which (check|one|test)[^.]{0,40}(fail|stop)|(failing|failed) check', mv)
        self.assertTrue(per_reason or says_which,
                        '3e gives no way to tell link / tracked / not-ignored apart')


class ArgoItReReview3Cases(Base):
    """Re-review 3 on 3e: a tracked .Env/.ENV (case-insensitive disk), a .env folder, re-scan wording."""

    def _w(self):
        return ArgoItWiringCases('test_old_inline_scan_is_gone')

    def _move(self):
        return ArgoItReReview2Cases('test_m2_value_goes_to_the_project_root_env_just_checked')._move()

    def _tail(self):
        mv = self._move()
        return mv[mv.index('Once it exits 0'):]

    def _env_cmds(self):
        """The ignore line and the check, as 3e gives them (probes that pick a reason are left out)."""
        spans = re.findall(r'```(?:bash|sh)?\n(.*?)```|`([^`\n]+)`', self._move(), re.S)
        cmds = [(b or i).strip() for b, i in spans]
        cmds = [c for c in cmds if '.env' in c and ('check-ignore' in c or 'printf' in c)
                and not re.match(r'test -[Ll] \.env \|\|', c)]
        self.assertTrue(any('check-ignore' in c for c in cmds), 'no .env check (git check-ignore) in 3e')
        return cmds

    def _run(self, r, shell):
        need_shell(shell)
        script = '\n'.join('{ %s\n} || exit 1' % c for c in self._env_cmds())
        return subprocess.run([shell, '-c', script], cwd=r.work, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=60).returncode

    def _both(self, mk, ok, what):
        for shell in ('bash', 'zsh'):
            r = self.fresh()
            mk(r)
            code = self._run(r, shell)
            if ok:
                self.assertEqual(code, 0, '%s: %s: the check stopped a good .env' % (shell, what))
            else:
                self.assertNotEqual(code, 0, '%s: %s: the check passed an unsafe .env' % (shell, what))

    def _tracked_odd_case(self, name):
        def mk(r):
            r.write('.gitignore', 'node_modules/\n')
            r.write(name, 'X=1\n')
            r.commit('tracked ' + name)
            r.push()
            self.assertIn(name.encode(), r.git('ls-files'))
        self._both(mk, False, 'tracked %s' % name)

    def test_ia_tracked_dot_Env_fails(self):
        self._tracked_odd_case('.Env')

    def test_ia_tracked_dot_ENV_fails(self):
        self._tracked_odd_case('.ENV')

    def test_ia_guard_env_beside_tracked_env_example_passes(self):
        def mk(r):
            r.write('.gitignore', 'node_modules/\n')
            r.write('.env.example', 'X=\n')
            r.commit('example')
            r.write('.env', 'X=1\n')
        self._both(mk, True, '.env beside tracked .env.example')

    def test_ia_guard_env_beside_tracked_envrc_passes(self):
        def mk(r):
            r.write('.gitignore', 'node_modules/\n')
            r.write('.envrc', 'export X=1\n')
            r.commit('envrc')
            r.write('.env', 'X=1\n')
        self._both(mk, True, '.env beside tracked .envrc')

    def test_m1_env_folder_is_named_as_a_folder(self):
        mv = self._move()
        self.assertRegex(mv, r'test -d \.env', '3e has no probe for a .env that is a folder')
        self.assertRegex(mv, r'\[[^\]]*\bfolder\b[^\]]*\]',
                         '3e stop reason list has no "folder" reason for .env')

    def test_m2_stop_messages_do_not_claim_gitignore_keeps_a_tracked_env_local(self):
        mv = self._move()
        self.assertNotRegex(mv, r'(?is)\.gitignore\s+that\s+keeps\s+\.env\s+on\s+this\s+computer',
                            'a stop message still says .gitignore keeps .env on this computer')

    def test_m2_stop_messages_say_in_plain_words_what_was_added(self):
        mv = self._move()
        self.assertRegex(mv, r'(?is)\b(if|when|only)\b[^.\]]{0,60}\badded\b|\badded\b[^.\]]{0,80}\bonly (if|when)\b',
                         'the stop message does not say the .gitignore line is mentioned only when something was added')
        self.assertRegex(mv, r'(?is)\badded\b[^.\]]{0,60}\.env[^.\]]{0,60}\.gitignore',
                         'the stop message does not say what was added to .gitignore')
        self.assertRegex(mv, r'(?is)\.gitignore\b[^.\]]{0,40}(file|list)[^.\]]{0,60}(leaves?|ignores?|skips?)\b',
                         'the stop message does not gloss what .gitignore is')

    def test_m3a_rescan_runs_once_after_all_named_values_are_moved(self):
        self.assertRegex(self._tail(), r'(?is)\bafter\s+(all|every)\b[^.]{0,60}\b(move|moved|moves|named|values?)\b',
                         '3e does not say to re-scan once, after all the named values are moved')

    def test_m3b_rescan_exit_1_means_stop_not_a_new_ask(self):
        t = self._tail()
        self.assertRegex(t, r'(?is)exit(s|ing)?\s+1[^.]{0,100}\bstop\b', '3e does not say exit 1 on the re-scan means stop')
        self.assertRegex(t, r'(?i)(don.t|do not|not)\s+ask\s+again|no\s+(new|second|another)\s+ask|not\s+(a\s+)?new\s+ask',
                         '3e does not say the re-scan exit 1 is not a new ask')

    def test_m3c_user_names_nothing_means_stop_and_say_which_values(self):
        self.assertRegex(self._move(), r'(?is)((names?|picks?)\s+(nothing|none|no\s+\w+)|doesn.t\s+(name|pick)\s+any|nothing\s+is\s+(named|picked))'
                                       r'[^.]{0,200}\bstop\b[^.]{0,200}\b(which|values?|holding)\b',
                         '3e does not say to stop, and say which values hold things up, when the user names nothing')

    def test_m3d_rescan_stop_gives_a_next_step(self):
        t = self._tail()
        m = re.search(r'3e (block|scan)\b[^.]{0,30}\bagain', t)
        self.assertTrue(m, 'no re-scan sentence found')
        self.assertRegex(t[m.start():], r'(?i)what to do next',
                         'the re-scan stop gives no next step')


class ArgoItReReview4Cases(Base):
    """Re-review 4 on 3e: case-folding corners (n-2) and the small-fixes bracket on every stop (n-1)."""

    def _env_cmds(self):
        return ArgoItReReview3Cases('test_m1_env_folder_is_named_as_a_folder')._env_cmds()

    def _run(self, cwd, shell):
        need_shell(shell)
        script = '\n'.join('{ %s\n} || exit 1' % c for c in self._env_cmds())
        return subprocess.run([shell, '-c', script], cwd=cwd, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=60).returncode

    def test_n2i_mis_set_ignorecase_false_untracked_dot_ENV_fails(self):
        for shell in ('bash', 'zsh'):
            r = self.fresh()
            r.git('config', 'core.ignorecase', 'false')
            r.write('.ENV', 'X=1\n')
            self.assertNotEqual(self._run(r.work, shell), 0,
                                '%s: core.ignorecase=false + untracked .ENV: the check passed' % shell)

    def test_n2i_guard_ignorecase_false_plain_untracked_env_passes(self):
        for shell in ('bash', 'zsh'):
            r = self.fresh()
            r.git('config', 'core.ignorecase', 'false')
            r.write('.env', 'X=1\n')
            self.assertEqual(self._run(r.work, shell), 0, '%s: the check stopped a plain .env' % shell)

    def test_n2ii_tracked_Web_env_folder_renamed_to_web_fails(self):
        for shell in ('bash', 'zsh'):
            r = self.fresh()
            r.write('Web/.env', 'X=1\n')
            r.commit('tracked Web/.env')
            os.rename(r.path('Web'), r.path('web'))  # case-only rename on disk; git's index still says Web/
            self.assertIn(b'Web/.env', r.git('ls-files'))
            self.assertNotEqual(self._run(r.path('web'), shell), 0,
                                '%s: tracked Web/.env, run from web/: the check passed' % shell)

    def test_n1_every_stop_after_3a_3c_carries_the_small_fixes_bracket(self):
        sec = ArgoItWiringCases('test_old_inline_scan_is_gone')._section()
        parts = sec.split('"')[1::2]  # the quoted messages
        parts = [' '.join(m.split()) for m in parts]  # wrapped messages count too
        stops = [m for m in parts if re.search(r"haven't (moved, )?(saved or )?sent anything", m)]
        self.assertGreaterEqual(len(stops), 7, 'expected the 7 3e stop messages, found %d' % len(stops))
        for m in stops:
            self.assertRegex(m, r'small\s+fixes.{0,80}3a, 3b(,| or) 3c',
                             'a 3e stop message lacks the small-fixes bracket: %r' % m[:90])


class ArgoItAdversarial2Cases(Base):
    """Adversarial round 2 (task-2-adv2.md, finding 1): a Unicode space or invisible character in a hit's file
    name must print as \\uXXXX, so the agent never retypes it as an ASCII space and opens the wrong file."""

    SPACES = [0x00A0, 0x1680] + list(range(0x2000, 0x200B)) + [0x202F, 0x205F, 0x3000]
    INVISIBLE = [0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0x00AD, 0x202E]

    def _name_hit(self, cp):
        r = self.fresh()
        # fake value built at run time from harmless pieces (GitGuardian scans this file)
        v = 'zq9' + 'FAKE' + 'unicode' + '%04x' % cp
        r.write('api' + chr(cp) + 'client.py', 'import os\n' + kv('API' + '_' + 'KEY', v))
        return r.scan(), v

    def test_1_unicode_space_in_name_prints_escaped(self):
        for cp in self.SPACES:
            with self.subTest(cp='U+%04X' % cp):
                res, v = self._name_hit(cp)
                self.check(res, new=['api\\u%04xclient.py:2' % cp], secrets=[v])

    def test_1_invisible_format_char_in_name_prints_escaped(self):
        for cp in self.INVISIBLE:
            with self.subTest(cp='U+%04X' % cp):
                res, v = self._name_hit(cp)
                self.check(res, new=['api\\u%04xclient.py:2' % cp], secrets=[v])

    def test_1_ascii_space_in_name_still_prints_raw(self):
        r = self.fresh()
        v = 'zq9' + 'FAKE' + 'ascii0001'
        r.write('api client.py', 'import os\n' + kv('API' + '_' + 'KEY', v))
        self.check(r.scan(), new=['api client.py:2'], secrets=[v])

    def test_1_folder_name_with_nbsp_prints_escaped(self):
        r = self.fresh()
        v = 'zq9' + 'FAKE' + 'folder0002'
        r.write('my\u00a0app/settings.py', 'import os\n' + kv('SECRET' + '_' + 'KEY', v))
        self.check(r.scan(), new=['my\\u00a0app/settings.py:2'], secrets=[v])

    def test_2_3e_hit_file_that_cannot_be_opened_stops_with_a_reason_and_next_step(self):
        sec = ArgoItWiringCases('test_old_inline_scan_is_gone')._section()
        paras = [p for p in re.split(r'\n\s*\n', re.sub(r'^```bash\n.*?^```', '', sec, flags=re.M | re.S))
                 if re.search(r"(?i)\b(missing|does(n.t| not) exist|isn.t there|not there|not where)\b", p)
                 and re.search(r'(?i)\bopen', p) and re.search(r'(?i)what to do next', p)]
        self.assertTrue(paras, '3e has no stop for a hit whose file cannot be opened (missing / not where the path says)')
        for p in paras:
            self.assertRegex(p, r'(?i)\bstop\b', '3e does not say to stop when the hit file cannot be opened')
            self.assertNotRegex(p, r'(?i)run /argo-it again and pick',
                                'the cannot-open stop repeats "run /argo-it again and pick", which fails the same way')


class ArgoItReReview6Cases(Base):
    """Re-review 6, I-1 / m-1: a private-use, unassigned or newer-Unicode character in a hit's name prints as
    \\uXXXX (anything not printable), on every Python, so the agent never types back a different file."""

    # U+F8FF, U+E000, U+F001: private use (BMP); U+F0000: private use (supplementary)
    PRIVATE_USE = [0xF8FF, 0xE000, 0xF001, 0xF0000]
    # Unassigned on Python 3.9's Unicode data (14.0 / 15.0 characters), known to newer Pythons
    NEWER_UNICODE = [0x0890, 0x13439]

    def _name_hit(self, cp):
        r = self.fresh()
        v = 'zq9' + 'FAKE' + 'privuse' + '%05x' % cp  # fake value built at run time
        r.write('p1' + chr(cp) + 'x.py', 'import os\n' + kv('API' + '_' + 'KEY', v))
        return r.scan(), v

    def _expect(self, cp):
        return 'p1\\u%04xx.py:2' % cp

    def test_i1_private_use_char_in_name_prints_escaped(self):
        for cp in self.PRIVATE_USE:
            with self.subTest(cp='U+%04X' % cp):
                res, v = self._name_hit(cp)
                self.check(res, new=[self._expect(cp)], secrets=[v])

    def test_m1_newer_unicode_char_in_name_prints_escaped_on_any_python(self):
        for cp in self.NEWER_UNICODE:
            with self.subTest(cp='U+%04X' % cp):
                res, v = self._name_hit(cp)
                self.check(res, new=[self._expect(cp)], secrets=[v])

    def test_i1_unassigned_char_in_committed_name_prints_escaped(self):
        # APFS refuses to create such a name, so put it straight into a commit (no file on disk)
        r = self.fresh()
        v = 'zq9' + 'FAKE' + 'unassigned'
        blob = subprocess.run(GIT + ['hash-object', '-w', '--stdin'], cwd=r.work, check=True,
                              input=_b('import os\n' + kv('API' + '_' + 'KEY', v)),
                              stdout=subprocess.PIPE).stdout.decode().strip()
        r.git('update-index', '--add', '--cacheinfo', '100644,%s,u\u0378x.py' % blob)
        r.git('commit', '-q', '-m', 'unassigned name')
        self.check(r.scan(), saved=['u\\u0378x.py:2'], secrets=[v])

    def test_i1_controls_ascii_space_accents_emoji_print_raw(self):
        for name in ('api client.py', 'caf\u00e9.py', 'smile\U0001F600.py'):
            with self.subTest(name=name):
                r = self.fresh()
                v = 'zq9' + 'FAKE' + 'plain0001'
                r.write(name, 'import os\n' + kv('API' + '_' + 'KEY', v))
                self.check(r.scan(), new=[name + ':2'], secrets=[v])


class ArgoItReReview7Cases(Base):
    """Re-review 7, I-A / m-1: a name that isn't in NFC form prints with its non-ASCII characters escaped (the
    agent would type it back in NFC and open a different file); a raw non-UTF-8 byte prints as \\xNN."""

    def _committed(self, name, tag):
        # no file on disk (APFS refuses or normalizes some names): a committed index entry only
        r = self.fresh()
        v = 'zq9' + 'FAKE' + tag
        blob = subprocess.run(GIT + ['hash-object', '-w', '--stdin'], cwd=r.work, check=True,
                              input=_b('import os\n' + kv('API' + '_' + 'KEY', v)),
                              stdout=subprocess.PIPE).stdout.decode().strip()
        subprocess.run(GIT + ['update-index', '--add', '--index-info'], cwd=r.work, check=True,
                       input=b'100644 ' + blob.encode() + b'\t' + _b(name) + b'\n')
        r.git('commit', '-q', '-m', 'odd name')
        return r, v

    def test_ia_nfd_name_prints_escaped(self):
        r, v = self._committed('cafe\u0301.py', 'nfd0001')
        self.check(r.scan(), saved=['cafe\\u0301.py:2'], secrets=[v])

    def test_ia_kelvin_sign_name_prints_escaped(self):
        r, v = self._committed('\u212Aconf.py', 'kelvin01')
        self.check(r.scan(), saved=['\\u212aconf.py:2'], secrets=[v])

    def test_ia_nfc_name_still_prints_raw(self):
        r, v = self._committed('caf\u00e9.py', 'nfc00001')
        self.check(r.scan(), saved=['caf\u00e9.py:2'], secrets=[v])

    def test_m1_raw_non_utf8_byte_prints_as_xnn(self):
        r, v = self._committed(b'caf\xe9x.py', 'rawbyte1')
        self.check(r.scan(), saved=['caf\\xe9x.py:2'], secrets=[v])


# ---------------------------------------------------------------- Task 1b: registry files
class RegistryFilesCases(Base):
    """.npmrc / .pypirc tokens are scanned; .git-credentials is kept out (scanner and argo-it step 4)."""

    @staticmethod
    def _step4():
        """The stage-and-unstage part of argo-it PHASE 5b step 4 (ignore loop, git add -A, keep-out reset)."""
        with open(ARGO_IT, encoding='utf-8') as f:
            t = f.read()
        a = t.index('fail() { echo "SAVE FAILED')
        end = '|| fail "could not stage the changes"'
        return t[a:t.index(end, a) + len(end)]

    @staticmethod
    def _scanner():
        import importlib.util
        spec = importlib.util.spec_from_file_location('secret_scan_mod', SCRIPT)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod

    def test_npmrc_auth_token_hits(self):
        r = self.fresh()
        v = 'npm' + '_' + fake('npm0001')
        r.write('.npmrc', 'registry=https://registry.npmjs.org/\n//registry.npmjs.org/:_authToken=%s\n' % v)
        self.check(r.scan(), new=['.npmrc:2'], secrets=[v])

    def test_npmrc_auth_line_hits(self):
        r = self.fresh()
        v = fake('npm0002')
        r.write('.npmrc', '_auth=%s\n' % v)
        self.check(r.scan(), new=['.npmrc:1'], secrets=[v])

    def test_npmrc_plain_registry_is_clean(self):  # control: passes today
        r = self.fresh()
        r.write('.npmrc', 'registry=https://registry.npmjs.org/\n')
        self.check(r.scan())

    def test_npmrc_in_subfolder_hits(self):
        r = self.fresh()
        v = 'npm' + '_' + fake('npm0003')
        r.write('web/app/.npmrc', '//registry.npmjs.org/:_authToken=%s\n' % v)
        self.check(r.scan(), new=['web/app/.npmrc:1'], secrets=[v])

    def test_pypirc_password_hits(self):
        r = self.fresh()
        v = fake('pypi001')
        r.write('.pypirc', '[pypi]\nusername = __token__\npassword = %s\n' % v)
        self.check(r.scan(), new=['.pypirc:3'], secrets=[v])

    def test_pypirc_index_url_is_clean(self):  # control: passes today
        r = self.fresh()
        r.write('.pypirc', '[distutils]\nindex-url = https://pypi.org/simple\n')
        self.check(r.scan())

    def test_git_credentials_is_kept_out_of_the_scan(self):
        r = self.fresh()
        v = fake('gitcr001')
        # line 2 would hit if the file were scanned; kept out, it is never read
        r.write('.git-credentials', 'https://u:%s@github.com\n' % v + kv('PASS' + 'WORD', v))
        r.write('sub/.git-credentials', kv('PASS' + 'WORD', v))
        self.check(r.scan(), secrets=[v])

    def _run_step4(self, r):
        cp = subprocess.run(['bash', '-c', self._step4()], cwd=r.work, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
        self.assertEqual(cp.returncode, 0, cp.stderr[:300])
        return r.git('diff', '--cached', '--name-only').decode().split()

    def test_step4_leaves_untracked_git_credentials_unstaged(self):
        r = self.fresh()
        r.write('.git-credentials', 'https://u:%s@github.com\n' % fake('gitcr002'))
        r.write('sub/.git-credentials', 'https://u:%s@github.com\n' % fake('gitcr003'))
        r.write('keep.txt', 'ok\n')
        self.assertEqual(self._run_step4(r), ['.gitignore', 'keep.txt'])  # step 4 edits .gitignore itself

    def test_step4_unstages_tracked_git_credentials(self):
        r = self.fresh()
        r.write('.git-credentials', 'https://u:%s@github.com\n' % fake('gitcr004'))
        r.commit('tracked')
        r.write('.git-credentials', 'https://u:%s@github.com\n' % fake('gitcr005'))
        r.write('keep.txt', 'ok\n')
        self.assertEqual(self._run_step4(r), ['.gitignore', 'keep.txt'])  # step 4 edits .gitignore itself

    def test_both_keep_out_lists_name_git_credentials(self):
        self.assertIn(b'.git-credentials', self._scanner().KEEP_OUT)
        step4 = self._step4()
        self.assertIn("'.git-credentials'", step4)
        self.assertIn(":(top,glob)**/.git-credentials'", step4)

    def test_scanner_and_step4_keep_out_lists_match(self):  # control: passes today (both lack the new entry)
        mod = self._scanner()
        step4 = self._step4()
        loop = step4[step4.index('for p in'):step4.index('; do')].replace('\\\n', ' ')
        ignored = set(re.findall(r"'([^']+)'", loop))
        reset = set(re.findall(r"':\(top,glob\)\*\*/([^']+)'", step4))
        scanner = {p.decode() for p in mod.KEEP_OUT} | {'.aws/credentials'}
        # .env* is handled by its own grep line in step 4, not the loop
        self.assertEqual(ignored, scanner - {'.env*'})
        self.assertEqual(reset, scanner)


class RegistryFixRound1Cases(Base):
    """Task 1b fix round 1: registry ports, scope names, _auth only in config files, one keep-out list."""

    def _npmrc(self, text, **kw):
        r = self.fresh()
        r.write('.npmrc', text)
        self.check(r.scan(), **kw)

    def test_i1_registry_with_port_hits(self):
        for i, host in enumerate(['localhost:4873', 'nexus.corp.example:8081/repository/npm', 'my-reg:8443']):
            for name in ('_authToken', '_auth', '_password'):
                v = fake('port%d%s' % (i, name.strip('_')))
                with self.subTest(host=host, name=name):
                    self._npmrc('registry=https://%s/\n//%s/:%s=%s\n' % (host, host, name, v),
                                new=['.npmrc:2'], secrets=[v])

    def test_i1_registry_with_port_indented_hits(self):
        v = fake('port9indent')
        self._npmrc('  //localhost:4873/:_authToken=%s\n' % v, new=['.npmrc:1'], secrets=[v])

    def test_i1_same_lines_without_a_port_hit(self):  # control: passes today
        for name in ('_authToken', '_auth', '_password'):
            v = fake('noport' + name.strip('_'))
            with self.subTest(name=name):
                self._npmrc('//nexus.corp.example/:%s=%s\n' % (name, v), new=['.npmrc:1'], secrets=[v])

    def test_i1_port_lines_without_a_value_are_clean(self):  # control: passes today
        self._npmrc('//localhost:4873/:always-auth=true\nregistry=http://localhost:4873/\n')

    def _retrofit_block(self):
        with open(RETROFIT_IT, encoding='utf-8') as f:
            t = f.read()
        a = t.index('for p in', t.index('Save pre-retrofit state') - 2500)
        end = '|| fail "could not save the unsaved changes"'
        return t[a:t.index(end, a) + len(end)]

    def test_i3_retrofit_snapshot_lists_match_scanner(self):
        mod = RegistryFilesCases._scanner()
        blk = self._retrofit_block()
        loop = blk[:blk.index('; do')].replace('\\\n', ' ')
        ignored = set(re.findall(r"'([^']+)'", loop))
        reset = set(re.findall(r"':\(top,glob\)\*\*/([^']+)'", blk))
        scanner = {p.decode() for p in mod.KEEP_OUT} | {'.aws/credentials'}
        self.assertEqual(ignored, scanner - {'.env*'})
        self.assertEqual(reset, scanner)

    def test_i3_retrofit_snapshot_lists_match_argo_it_step4(self):
        step4 = RegistryFilesCases._step4()
        a = step4[step4.index('for p in'):step4.index('; do')].replace('\\\n', ' ')
        b = self._retrofit_block()
        b = b[:b.index('; do')].replace('\\\n', ' ')
        self.assertEqual(set(re.findall(r"'([^']+)'", a)), set(re.findall(r"'([^']+)'", b)))
        self.assertEqual(set(re.findall(r"':\(top,glob\)\*\*/([^']+)'", step4)),
                         set(re.findall(r"':\(top,glob\)\*\*/([^']+)'", self._retrofit_block())))

    def test_i3_operator_safety_names_git_credentials_twice(self):
        with open(OPERATOR_SAFETY, encoding='utf-8') as f:
            t = f.read()
        s1 = t[t.index('## 1.'):t.index('## 2.')]
        never = s1[s1.index('Credential and secret files'):s1.index('You may check')]
        ign = s1[s1.index('**Ignore patterns.**'):]
        ign = ign[:ign.index('\n\n')]
        self.assertIn('`.git-credentials`', never)
        self.assertIn('`.git-credentials`', ign)

    def test_m1_auth_is_a_secret_name_only_in_a_config_file(self):
        r = self.fresh()
        r.write('login.py', '_auth = "required-login"\n')
        r.write('web/state.js', 'const s = { _auth: "session-cookie" };\n')
        self.check(r.scan())

    def test_m1_auth_in_npmrc_still_hits(self):  # control: passes today
        v = fake('m1auth')
        self._npmrc('_auth=%s\n' % v, new=['.npmrc:1'], secrets=[v])

    def test_m2_scope_name_is_not_a_secret_name(self):
        v = fake('m2scope')
        self._npmrc('@acme-token:registry=https://npm.pkg.github.com/\n'
                    '@team-secret:registry=https://npm.pkg.github.com/\n'
                    '//npm.pkg.github.com/:_authToken=%s\n' % v, new=['.npmrc:3'], secrets=[v])

    def test_m3_environment_reference_is_clean(self):  # control: passes today
        self._npmrc('//registry.npmjs.org/:_authToken=%s\n' % ('$' + '{NPM_' + 'TOKEN}'))

    def test_m3_npmrc_in_an_unsent_commit_hits_under_saved(self):  # control: passes today
        r = self.fresh()
        v = fake('m3saved')
        r.write('.npmrc', 'registry=https://registry.npmjs.org/\n//registry.npmjs.org/:_authToken=%s\n' % v)
        r.commit('add npmrc')
        self.check(r.scan(), saved=['.npmrc:2'], secrets=[v])


class KeepOutInUnsentCommitCases(Base):
    """Task 1b fix round 1 (owner's call on I2): a keep-out file that an unsent commit adds or changes is a
    saved hit, by name only -- step 4 would push it, and its content is never read or printed."""

    @staticmethod
    def _body(name, tag):
        v = fake(tag)
        # no NAME = VALUE line, so only the file name can make this a hit
        if name.endswith('.git-credentials'):
            return 'https://%s:%s@%s\n' % ('u', v, 'github.com'), v
        return v + '\n', v

    def _unsent(self, name, tag):
        r = self.fresh()
        r.branch()
        body, v = self._body(name, tag)
        r.write(name, body)
        r.commit('add ' + name)
        return r, v

    def test_i2_git_credentials_in_an_unsent_commit_is_a_saved_hit(self):
        r, v = self._unsent('.git-credentials', 'i2gitcr01')
        self.check(r.scan(), saved=['.git-credentials:1'], secrets=[v])

    def test_i2_nested_id_rsa_in_an_unsent_commit_is_a_saved_hit(self):
        r, v = self._unsent('config/id_rsa', 'i2idrsa01')
        self.check(r.scan(), saved=['config/id_rsa:1'], secrets=[v])

    def test_i2_pem_in_an_unsent_commit_is_a_saved_hit(self):
        r, v = self._unsent('certs/server.pem', 'i2pem0001')
        self.check(r.scan(), saved=['certs/server.pem:1'], secrets=[v])

    def test_i2_several_keep_out_patterns_each_hit_by_name(self):
        names = ['.aws/credentials', 'a/b/tls.key', 'id_ed25519', 'x.p12', 'c.pfx',
                 'login.keychain-db', 'gcp-credentials.json', 'my-service-account.json', 'data.db',
                 'db.sqlite3', 'sub/.netrc']
        r = self.fresh()
        r.branch()
        vs = []
        for i, n in enumerate(names):
            body, v = self._body(n, 'i2many%02d' % i)
            r.write(n, body)
            vs.append(v)
        r.commit('many')
        self.check(r.scan(), saved=sorted(n + ':1' for n in names), secrets=vs)

    def test_i2_hit_is_line_1_whatever_the_file_holds(self):
        r = self.fresh()
        r.branch()
        vs = [fake('i2long001'), fake('i2long002')]
        r.write('id_rsa', '# header\n\n' + ''.join('%s\n' % v for v in vs))
        r.commit('long')
        self.check(r.scan(), saved=['id_rsa:1'], secrets=vs)

    def test_i2_an_already_pushed_netrc_changed_in_an_unsent_commit_is_a_hit(self):
        r = self.fresh()
        r.write('.netrc', 'machine example.com\n')
        r.commit('netrc')
        r.push()
        r.branch()
        v = fake('i2netrc01')
        r.write('.netrc', 'machine example.com\n' + v + '\n')
        r.commit('change netrc')
        self.check(r.scan(), saved=['.netrc:1'], secrets=[v])

    def test_i2_deleting_a_pushed_keep_out_file_is_not_a_hit(self):  # control: passes today
        r = self.fresh()
        body, v = self._body('id_rsa', 'i2delete1')
        r.write('id_rsa', body)
        r.commit('key')
        r.push()
        r.branch()
        r.git('rm', '-q', 'id_rsa')
        r.git('commit', '-q', '-m', 'remove key')
        self.check(r.scan(), secrets=[v])

    def test_i2_env_example_in_an_unsent_commit_is_not_a_name_hit(self):  # control: passes today
        r = self.fresh()
        r.branch()
        r.write('.env.example', 'API_URL=http://localhost:8000\n')
        r.commit('example')
        self.check(r.scan())

    def test_i2_env_example_lines_are_still_checked(self):  # control: passes today
        r = self.fresh()
        r.branch()
        v = fake('i2envfile1')
        r.write('.env.example', 'API_URL=http://localhost:8000\nAPI_KEY=%s\n' % v)
        r.commit('example')
        self.check(r.scan(), saved=['.env.example:2'], secrets=[v])

    def test_i2_unsaved_and_new_keep_out_files_still_do_not_appear(self):  # control: passes today
        r = self.fresh()
        r.write('.netrc', 'machine example.com\n')
        r.commit('netrc')
        r.push()
        r.branch()
        vs = []
        for i, n in enumerate(['.git-credentials', 'config/id_rsa', 'certs/server.pem']):
            body, v = self._body(n, 'i2new%04d' % i)
            r.write(n, body)                        # new, not committed
            vs.append(v)
        v = fake('i2edit001')
        r.write('.netrc', 'machine example.com\n' + v + '\n')   # unsaved edit of a pushed keep-out file
        vs.append(v)
        self.check(r.scan(), secrets=vs)


class ArgoItRegistryStopCases(Base):
    """Task 1b fix round 1 (owner's call on I4): a hit in .npmrc / .pypirc is never opened and never moved.
    argo-it step 3e stops, names the file and line, and sends DevOps after a pipeline secret."""

    NPM_TOKEN = '$' + '{NPM_' + 'TOKEN}'

    def _doc(self):
        return ArgoItWiringCases._doc(self)

    def _section(self):
        return ArgoItWiringCases._section(self)

    def _flat(self):
        return re.sub(r'\s+', ' ', self._section())

    def _stop(self, sec=None):
        """The registry-stop block: from the paragraph that first names .npmrc up to the next bold heading."""
        sec = self._section() if sec is None else sec
        paras = sec.split('\n\n')
        for i, p in enumerate(paras):
            if '.npmrc' in p:
                break
        else:
            self.fail('3e has no rule for a hit in .npmrc / .pypirc')
        block = [p]
        for q in paras[i + 1:]:
            if q.startswith('**'):
                break
            block.append(q)
        return sec.index(p), re.sub(r'\s+', ' ', '\n\n'.join(block))

    def test_i4_rule_names_both_files_and_stops_before_the_move_path(self):
        sec = self._section()
        at, blk = self._stop(sec)
        flat = self._flat()
        self.assertIn('.pypirc', blk)
        self.assertRegex(blk, r'(?i)\bstop')
        self.assertLess(at, sec.index('**Otherwise'), 'the registry stop comes after the move branch')
        self.assertLess(flat.index('.npmrc'), flat.index('open each picked line yourself'))
        self.assertLess(flat.index('.npmrc'), flat.index('Which should I move'))
        self.assertRegex(blk, r'(?i)\b(first|before|instead|takes? (precedence|priority)|overrides?)\b',
                         'the rule does not say it wins over the move path')

    def test_i4_rule_applies_under_any_label_and_any_folder(self):
        _, blk = self._stop()
        self.assertRegex(blk, r'(?i)\b(any|every|each|whichever|all)\b[^.]{0,30}\blabels?\b|== saved|== unsaved|== new')
        self.assertRegex(blk, r'(?i)\b(any|every|whatever)\b[^.]{0,30}\b(folders?|director\w+|path)\b')

    def test_i4_rule_never_opens_or_moves_the_file(self):
        _, blk = self._stop()
        self.assertRegex(blk, r"(?i)\b(never|don't|do not|not)\b[^.]{0,40}\b(open|read)")
        for bad in ('open each picked line yourself', 'Which should I move', 'os.getenv', 'process.env', '.env '):
            self.assertNotIn(bad, blk, 'registry stop reaches the move path: %r' % bad)
        self.assertNotRegex(blk, r'(?i)\bmove (it|them|the value|every|each)\b(?![^.]*\b(DevOps|pipeline)\b)')

    def test_i4_stop_message_names_file_and_line_and_says_nothing_was_saved_or_sent(self):
        _, blk = self._stop()
        self.assertRegex(blk, r'line \[N\] of \[file\]')
        self.assertRegex(blk, r"(?i)I haven't (moved, )?saved or sent anything")
        self.assertRegex(blk, r"(?i)steps? 4 and later don't run|steps 4 and later")

    def test_i4_stop_message_sends_the_user_to_devops_for_a_pipeline_secret(self):
        _, blk = self._stop()
        self.assertRegex(blk, r'(?i)DevOps')
        self.assertRegex(blk, r'(?i)pipeline secret')
        self.assertRegex(blk, r'(?i)registry (login|token|password|credential)')
        self.assertIn(self.NPM_TOKEN, blk)

    def test_i4_other_files_still_use_the_move_path(self):  # control: passes today
        sec = self._flat()
        self.assertIn('open each picked line yourself', sec)
        self.assertIn('Which should I move', sec)
        self.assertIn('**Otherwise', sec)


class RegistryFixRound2Cases(Base):
    """Task 1b fix round 2: a saved registry login doesn't loop; plain words for .pypirc; .yarnrc.yml is a
    registry file; operator-safety's names-only check; a never-read file is never opened; I2 edges."""

    def _doc(self):
        return ArgoItWiringCases._doc(self)

    def _section(self):
        return ArgoItWiringCases._section(self)

    _stop = ArgoItRegistryStopCases._stop

    # --- 1. a registry hit already in saved history must not loop -----------------------------------
    def test_r2_registry_stop_covers_a_login_already_in_saved_history(self):
        _, blk = self._stop()
        self.assertIn('saved, not sent', blk, 'the registry stop never mentions the saved label')
        self.assertRegex(blk, r"(?i)already in your saved history")
        self.assertRegex(blk, r"(?i)wouldn't take it out of what gets sent")
        self.assertRegex(blk, r"(?i)help remove it from the saved history")
        self.assertRegex(blk, r"(?i)I haven't saved or sent anything new")

    def test_r2_saved_history_guidance_is_tied_to_the_saved_label(self):
        _, blk = self._stop()
        i = blk.find('saved history')
        self.assertNotEqual(i, -1, 'no saved-history guidance in the registry stop')
        self.assertIn('saved, not sent', blk[max(0, i - 400):i + 400],
                      'the saved-history guidance is not tied to a hit under the saved label')

    def test_r2_pipeline_secret_message_stays_for_other_labels(self):  # control: passes today
        _, blk = self._stop()
        self.assertRegex(blk, r'(?i)pipeline secret')
        self.assertIn('$' + '{NPM_' + 'TOKEN}', blk)
        self.assertRegex(blk, r'(?i)run /argo-it again')

    # --- 2. .pypirc: plain, correct words ------------------------------------------------------------
    def test_r2_registry_gloss_is_not_download_only(self):
        _, blk = self._stop()
        # .pypirc holds upload logins (pip never reads it); an .npmrc token also publishes
        if re.search(r'(?i)\bdownload', blk):
            self.assertRegex(blk, r'(?i)\b(publish|upload)', 'the gloss says download and never publish/upload')
        self.assertNotRegex(blk, r'(?i)to download (its|your|the) code librar')

    # --- 3. .yarnrc.yml is a registry file too -------------------------------------------------------
    def test_r2_yarnrc_yml_token_line_hits(self):  # control: passes today (YAML config rule)
        r = self.fresh()
        v = fake('yarn0001')
        r.write('.yarnrc.yml', 'npmRegistryServer: "https://registry.npmjs.org"\n' + kv('npmAuth' + 'Token', v, ': ', ''))
        self.check(r.scan(), new=['.yarnrc.yml:2'], secrets=[v])

    def test_r2_3e_stop_rule_names_yarnrc_yml(self):
        _, blk = self._stop()
        self.assertIn('.yarnrc.yml', blk)
        self.assertRegex(blk, r'(?i)never open')

    def test_r2_operator_safety_names_yarnrc_yml_beside_npmrc(self):
        with open(OPERATOR_SAFETY, encoding='utf-8') as f:
            t = f.read()
        s1 = t[t.index('## 1.'):t.index('## 2.')]
        never = s1[s1.index('Credential and secret files'):s1.index('You may check')]
        line = [l for l in never.splitlines() if '.npmrc' in l]
        self.assertTrue(line, 'no .npmrc line in the never list')
        self.assertIn('.yarnrc.yml', line[0], 'the never-read list does not name .yarnrc.yml beside .npmrc')

    # --- 4. operator-safety's names-only grep catches the colon form ---------------------------------
    def test_r2_names_only_check_matches_password_colon_and_equals(self):
        with open(OPERATOR_SAFETY, encoding='utf-8') as f:
            t = f.read()
        s1 = t[t.index('## 1.'):t.index('## 2.')]
        para = re.sub(r'\s+', ' ', s1[s1.index('**Ignore patterns.**'):])
        m = re.search(r"grep (-[a-zA-Z]+) '([^']+)'", para)
        self.assertTrue(m, 'no grep example in the Ignore patterns paragraph')
        td = tempfile.TemporaryDirectory()
        self.addCleanup(td.cleanup)
        for name, sep in (('colon', ': '), ('equals', ' = ')):
            v = fake('grep' + name)
            p = os.path.join(td.name, name + '.pypirc')
            with open(p, 'w') as fh:
                fh.write('[pypi]\n' + kv('pass' + 'word', v, sep, ''))
            with self.subTest(form=name):
                cp = subprocess.run(['grep', m.group(1), '-E', m.group(2), p] if m.group(1) != '-lsE'
                                    else ['grep', '-lsE', m.group(2), p],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                self.assertEqual(cp.stdout.decode().strip(), p, 'names-only check missed the %s form' % name)
                self.assertNotIn(v.encode(), cp.stdout)

    # --- 5. a hit on a never-read file is never opened -----------------------------------------------
    def test_r2_reading_rule_says_keep_out_and_registry_hits_are_never_opened(self):
        flat = re.sub(r'\s+', ' ', self._section())
        a = flat.index('**Exit 1**')
        bullet = flat[a:flat.index('**Anything else**', a)]
        self.assertIn('open it from there', bullet)
        self.assertRegex(bullet, r"(?i)keep-out|step 4's (list|keep)", 'the reading rule does not name step 4\'s keep-out list')
        self.assertRegex(bullet, r'(?i)registry|\.npmrc', 'the reading rule does not name registry files')
        self.assertRegex(bullet, r"(?i)\bnever (be )?(open|read)|\b(don't|do not|not) (open|read)",
                         'the reading rule does not say such a hit is never opened')

    # --- 6. I2 edges (controls: these may pass today) ------------------------------------------------
    def _body(self, name, tag):
        return KeepOutInUnsentCommitCases._body(name, tag)

    def test_r2_i2_keep_out_file_arriving_through_a_merge_commit(self):  # control
        r = self.fresh()
        body, v = self._body('id_rsa', 'r2merge01')
        r.git('checkout', '-q', '-b', 'side')
        r.write('id_rsa', body)
        r.commit('add key on side')
        r.git('checkout', '-q', '-b', 'feat', 'main')
        r.write('other.txt', 'ok\n')
        r.commit('other')
        r.git('merge', '--no-ff', '-q', 'side', '-m', 'merge side')
        self.check(r.scan(), saved=['id_rsa:1'], secrets=[v])

    def test_r2_i2_rename_into_a_keep_out_name(self):  # control
        r = self.fresh()
        body, v = self._body('id_rsa', 'r2rename1')
        r.write('notes.txt', body)
        r.commit('notes')
        r.push()
        r.branch()
        r.git('mv', 'notes.txt', 'id_rsa')
        r.git('commit', '-q', '-m', 'rename to key')
        self.check(r.scan(), saved=['id_rsa:1'], secrets=[v])

    def test_r2_i2_force_added_keep_out_file_that_gitignore_covers(self):  # control
        r = self.fresh()
        r.branch()
        body, v = self._body('certs/server.pem', 'r2force01')
        r.write('.gitignore', 'certs/server.pem\n')
        r.write('certs/server.pem', body)
        r.git('add', '.gitignore')
        r.git('add', '-f', 'certs/server.pem')
        r.git('commit', '-q', '-m', 'force add')
        self.check(r.scan(), saved=['certs/server.pem:1'], secrets=[v])

    def test_r2_i2_pypirc_token_line_in_an_unsent_commit_hits_under_saved(self):  # control
        r = self.fresh()
        r.branch()
        v = fake('r2pypirc1')
        r.write('.pypirc', '[pypi]\nusername = __token__\n' + kv('pass' + 'word', v, ' = ', ''))
        r.commit('add pypirc')
        self.check(r.scan(), saved=['.pypirc:3'], secrets=[v])


class EnvFilesInUnsentCommitCases(Base):
    """Task 1b fix round 2 (owner's call): .env* files in an unsent commit are checked line by line,
    not hit by name; keys, certificates, credential files and databases still hit by name."""

    def _unsent(self, rel, text):
        r = self.fresh()
        r.branch()
        r.write(rel, text)
        r.commit('add ' + rel)
        return r

    def test_env_production_public_setting_only_is_clean(self):
        r = self._unsent('.env.production', 'NEXT_PUBLIC_API_URL=https://api.example.test\n')
        self.check(r.scan())

    def test_env_production_secret_line_hits_by_line_not_name(self):
        v = fake('envprod01')
        r = self._unsent('.env.production', 'NEXT_PUBLIC_API_URL=https://api.example.test\nAPI_KEY=%s\n' % v)
        self.check(r.scan(), saved=['.env.production:2'], secrets=[v])

    def test_nested_env_local_secret_line_hits_by_line(self):
        v = fake('envloc001')
        r = self._unsent('frontend/.env.local', '# local\nDEBUG=1\nAPI_KEY=%s\n' % v)
        self.check(r.scan(), saved=['frontend/.env.local:3'], secrets=[v])

    def test_env_sample_placeholders_are_not_a_name_hit(self):
        r = self._unsent('.env.sample', 'API_URL=http://localhost:8000\nAPI_KEY=changeme\nOTHER_KEY=\n')
        res = r.scan()
        self.assertNotIn('.env.sample:1', res.lines)

    def test_controls_still_hit_by_name(self):  # control: passes today
        names = ['id_rsa', 'server.pem', '.git-credentials', 'app.db']
        r = self.fresh()
        r.branch()
        vs = []
        for i, n in enumerate(names):
            v = fake('envctl%02d' % i)
            r.write(n, 'https://u:%s@github.com\n' % v if n == '.git-credentials' else v + '\n')
            vs.append(v)
        r.commit('controls')
        self.check(r.scan(), saved=sorted(n + ':1' for n in names), secrets=vs)


def _brackets(flat):
    """(start, end) of every balanced [...] span in a flattened message template."""
    out, stack = [], []
    for i, ch in enumerate(flat):
        if ch == '[':
            stack.append(i)
        elif ch == ']' and stack:
            out.append((stack.pop(), i + 1))
    return out


class EnvKeyFilesAndOverlapCases(Base):
    """Task 1b fix round 3 (owner's call, after review 3): .env.keys / .env.me hit by name; a secret word
    anywhere in a .env* setting name is secret-named; .env* names that are also key/cert/db names fail closed;
    the saved-history stop says the other hits need moving too and never says 'run /argo-it again'."""

    def _unsent(self, rel, text):
        r = self.fresh()
        r.branch()
        r.write(rel, text)
        r.commit('add ' + rel)
        return r

    @staticmethod
    def _line(name, v):
        return '%s=%s\n' % (name, v)

    # --- 1. dotenvx / dotenv-vault key files hit by name -------------------------------------------
    def test_env_keys_with_only_a_private_key_line_hits_by_name(self):
        v = fake('envkeys01')
        r = self._unsent('.env.keys', self._line('DOTENV_PRIVATE_' + 'KEY_PRODUCTION', v))
        self.check(r.scan(), saved=['.env.keys:1'], secrets=[v])

    def test_nested_env_keys_hits_by_name(self):
        v = fake('envkeys02')
        r = self._unsent('app/.env.keys', self._line('DOTENV_PRIVATE_' + 'KEY_PRODUCTION', v))
        self.check(r.scan(), saved=['app/.env.keys:1'], secrets=[v])

    def test_env_me_hits_by_name(self):
        v = fake('envme00001')
        r = self._unsent('.env.me', self._line('DOTENV_ME', v))
        self.check(r.scan(), saved=['.env.me:1'], secrets=[v])

    def test_nested_env_me_hits_by_name(self):
        v = fake('envme00002')
        r = self._unsent('app/.env.me', self._line('DOTENV_ME', v))
        self.check(r.scan(), saved=['app/.env.me:1'], secrets=[v])

    # --- 2. secret words anywhere in a .env* setting name --------------------------------------------
    def _env_hit(self, name, tag):
        v = fake(tag)
        r = self._unsent('.env.production', 'NEXT_PUBLIC_API_URL=https://api.example.test\n' + self._line(name, v))
        self.check(r.scan(), saved=['.env.production:2'], secrets=[v])

    def test_env_password_word_in_the_middle_of_a_name_hits(self):
        self._env_hit('DB_' + 'PASSWORD' + '_PROD', 'envwide01')

    def test_env_secret_word_in_the_middle_of_a_name_hits(self):
        self._env_hit('STRIPE_' + 'SECRET' + '_LIVE', 'envwide02')

    def test_env_token_word_in_the_middle_of_a_name_hits(self):
        self._env_hit('GITHUB_' + 'TOKEN' + '_CI', 'envwide03')

    def test_env_private_key_word_in_the_middle_of_a_name_hits(self):
        self._env_hit('DOTENV_' + 'PRIVATE_KEY' + '_PRODUCTION', 'envwide04')

    def test_env_public_setting_stays_clean(self):  # control: passes today
        r = self._unsent('.env.production', 'NEXT_PUBLIC_API_URL=https://api.example.test\n')
        self.check(r.scan())

    def test_env_password_min_length_hits_the_accepted_cost(self):
        r = self._unsent('.env.production', 'NEXT_PUBLIC_API_URL=https://api.example.test\nPASSWORD_MIN_LENGTH=8\n')
        self.check(r.scan(), saved=['.env.production:2'])

    def test_wide_name_rule_is_env_only_a_py_file_keeps_today_result(self):  # control: passes today
        v = fake('pycontrol1')
        r = self._unsent('settings.py', kv('DB_' + 'PASSWORD' + '_PROD', v))
        self.check(r.scan(), secrets=[v])

    # --- 3. .env* names that are also key / certificate / database names fail closed -----------------
    def test_env_pem_key_and_db_names_hit_by_name(self):
        names = ['.env.pem', '.env.key', '.env.db']
        r = self.fresh()
        r.branch()
        vs = []
        for i, n in enumerate(names):
            v = fake('envovl%02d' % i)
            r.write(n, v + '\n')
            vs.append(v)
        r.commit('overlap names')
        self.check(r.scan(), saved=sorted(n + ':1' for n in names), secrets=vs)

    # --- 4 / 5. the registry stop's saved-history bracket --------------------------------------------
    def _flat_stop(self):
        _, blk = ArgoItRegistryStopCases._stop(self)
        return blk

    def _doc(self):
        return ArgoItWiringCases._doc(self)

    def _section(self):
        return ArgoItWiringCases._section(self)

    def _saved_bracket(self, flat):
        spans = [(a, b) for a, b in _brackets(flat)
                 if flat[a:b].startswith('[If') and 'already in your saved history' in flat[a:b]]
        self.assertTrue(spans, 'no [If ...] bracket holds the saved-history guidance')
        return min(spans, key=lambda ab: ab[1] - ab[0])

    def test_saved_history_stop_also_tells_that_the_other_hit_needs_moving_too(self):
        flat = self._flat_stop()
        a, b = self._saved_bracket(flat)
        self.assertIn('needs moving too', flat[a:b], 'the saved-history bracket does not say the other hit needs moving too')

    def test_run_argo_it_again_never_appears_in_the_saved_history_bracket_or_the_tail(self):
        flat = self._flat_stop()
        a, b = self._saved_bracket(flat)
        self.assertNotRegex(flat[a:b], r'(?i)run /argo-it again', 'saved-history bracket says run /argo-it again')
        hits = [m.start() for m in re.finditer(r'(?i)run /argo-it again', flat)]
        self.assertTrue(hits, 'the not-saved bracket lost its "run /argo-it again"')
        spans = _brackets(flat)
        for h in hits:
            self.assertFalse(a <= h < b)
            inside = [s for s in spans if s[0] <= h < s[1]]
            self.assertTrue(inside, 'run /argo-it again sits in the shared text, outside any bracket')
            self.assertNotIn('already in your saved history', flat[min(inside, key=lambda s: s[1] - s[0])[0]:
                                                                 min(inside, key=lambda s: s[1] - s[0])[1]])
        self.assertNotRegex(flat[b:], r'(?i)run /argo-it again')

    # --- 6. merge edges ------------------------------------------------------------------------------
    def test_evil_merge_that_adds_a_keep_out_file_hits_by_name(self):  # control: may pass today
        r = self.fresh()
        v = fake('evilkeep01')
        r.branch('side')
        r.write('side.txt', 'side\n')
        r.commit('side')
        r.git('checkout', '-q', 'main')
        r.git('merge', '-q', '--no-ff', '--no-commit', 'side')
        r.write('id_rsa', v + '\n')
        r.git('add', 'id_rsa')
        r.git('commit', '-q', '-m', 'evil merge')
        self.check(r.scan(), saved=['id_rsa:1'], secrets=[v])

    def test_pending_merge_with_a_keep_out_file_from_the_other_side_hits_by_name(self):  # control: may pass today
        r = self.fresh()
        v = fake('pendkeep01')
        r.branch('side')
        r.write('id_rsa', v + '\n')
        r.commit('side key')
        r.git('checkout', '-q', 'main')
        r.write('other.txt', 'ok\n')
        r.commit('main edit')
        r.git('merge', '-q', '--no-ff', '--no-commit', 'side')
        self.assertTrue(os.path.exists(os.path.join(r.work, '.git', 'MERGE_HEAD')))
        self.check(r.scan(), saved=['id_rsa:1'], secrets=[v])

    def test_env_sample_placeholders_scan_is_clean(self):
        r = self._unsent('.env.sample', 'API_URL=http://localhost:8000\nAPI_KEY=changeme\nOTHER_KEY=\n')
        self.check(r.scan())


class EnvExampleFloorAndTemplatesCases(Base):
    """Task 1b fix round 4 (owner's call after review 4): short values in .env.example pass (the 8-character
    floor stays there only) while the wide name rule still applies; make-it's own templates give no hit on
    their ENFORCE_SECRETS line; an empty value with an inline comment is empty; the registry stop's loop
    test has no hole; its rotation line covers every value; an outside-registry hit is named once."""

    CLEAN = ('ENFORCE_SECRETS=false\n' 'ENFORCE_SECRETS=true\n'
             'AI_RATE_LIMIT_TOKENS_PER_MINUTE=50000\n' 'TOKEN_TTL=60\n')
    HEAD = 'LOG_LEVEL=info\n'

    def _ex(self, label, text, rel='.env.example'):
        """A repo with `text` in rel, under the given label. Line 1 of text is always HEAD."""
        r = self.fresh()
        if label == L_UNSAVED:
            r.write(rel, self.HEAD)
            r.commit('base')
            r.push()
            r.write(rel, text)
        elif label == L_NEW:
            r.write(rel, text)
        else:
            r.branch()
            r.write(rel, text)
            r.commit('add ' + rel)
        return r

    @staticmethod
    def _want(label, lines):
        return {L_UNSAVED: 'unsaved', L_NEW: 'new', L_SAVED: 'saved'}[label], lines

    def _clean_case(self, label):
        r = self._ex(label, self.HEAD + self.CLEAN)
        self.check(r.scan())

    def _mixed_case(self, label):
        v = fake('exfloor' + label[3:5])
        text = self.HEAD + self.CLEAN + 'DB_' + 'PASSWORD' + '_PROD=' + v + '\n'
        k, lines = self._want(label, ['.env.example:6'])
        self.check(self._ex(label, text).scan(), secrets=[v], **{k: lines})

    def _hit_case(self, label):  # control: passes today
        v = fake('exhit' + label[3:5])
        text = self.HEAD + 'DB_' + 'PASSWORD' + '_PROD=' + v + '\n'
        k, lines = self._want(label, ['.env.example:2'])
        self.check(self._ex(label, text).scan(), secrets=[v], **{k: lines})

    # --- 1. the value floor in .env.example only ----------------------------------------------------
    def test_env_example_short_values_are_clean_as_an_unsaved_edit(self):
        self._clean_case(L_UNSAVED)

    def test_env_example_short_values_are_clean_as_a_new_file(self):
        self._clean_case(L_NEW)

    def test_env_example_short_values_are_clean_in_an_unsent_commit(self):
        self._clean_case(L_SAVED)

    def test_env_example_long_mid_name_secret_hits_alone_as_an_unsaved_edit(self):
        self._mixed_case(L_UNSAVED)

    def test_env_example_long_mid_name_secret_hits_alone_as_a_new_file(self):
        self._mixed_case(L_NEW)

    def test_env_example_long_mid_name_secret_hits_alone_in_an_unsent_commit(self):
        self._mixed_case(L_SAVED)

    def test_env_example_long_mid_name_secret_hits_as_an_unsaved_edit(self):  # control: passes today
        self._hit_case(L_UNSAVED)

    def test_env_example_long_mid_name_secret_hits_as_a_new_file(self):  # control: passes today
        self._hit_case(L_NEW)

    def test_env_example_long_mid_name_secret_hits_in_an_unsent_commit(self):  # control: passes today
        self._hit_case(L_SAVED)

    # --- 2. make-it's own templates ------------------------------------------------------------------
    def _template_case(self, scaffold):
        src = os.path.join(HERE, '..', 'scaffolds', scaffold, '.env.example')
        self.assertTrue(os.path.isfile(src), 'missing template: %s' % src)
        with open(src, 'rb') as f:
            data = f.read()
        enf = [i + 1 for i, ln in enumerate(data.splitlines()) if ln.startswith(b'ENFORCE_SECRETS')]
        self.assertTrue(enf, '%s has no ENFORCE_SECRETS line' % scaffold)
        r = self.fresh(remote=False)
        r.write('.env.example', data)
        r.commit('template as-is')
        res = r.scan()
        for n in enf:
            self.assertNotIn('.env.example:%d' % n, res.lines,
                             '%s: the ENFORCE_SECRETS line (%d) is a hit' % (scaffold, n))

    def test_fastapi_nextjs_template_enforce_secrets_line_is_not_a_hit(self):
        self._template_case('fastapi-nextjs')

    def test_nextjs_fullstack_template_enforce_secrets_line_is_not_a_hit(self):
        if not os.path.isfile(os.path.join(HERE, '..', 'scaffolds', 'nextjs-fullstack', '.env.example')):
            self.skipTest('no nextjs-fullstack scaffold')
        self._template_case('nextjs-fullstack')

    # --- 3. an empty value with an inline comment is empty --------------------------------------------
    def test_env_production_empty_value_with_inline_comment_is_clean(self):
        r = self.fresh()
        r.branch()
        r.write('.env.production', 'LOG_LEVEL=info\n' + 'SMTP_' + 'PASSWORD' + '= # set in the pipeline\n')
        r.commit('add .env.production')
        self.check(r.scan())

    def _doc(self):
        return ArgoItWiringCases._doc(self)

    def _section(self):
        return ArgoItWiringCases._section(self)

    def _flat_stop(self):
        return ArgoItRegistryStopCases._stop(self)[1]

    # --- 4. the loop test's hole ----------------------------------------------------------------------
    @staticmethod
    def _again_outside_no_hit_bracket(flat):
        """Every 'run /argo-it again' in the registry stop that is NOT inside the bracket that opens
        '[If no hit sits under `== saved, not sent ==`'."""
        spans = [(a, b) for a, b in _brackets(flat) if flat.startswith('[If no hit sits under `== saved', a)]
        stray = []
        for m in re.finditer(r'(?i)run /argo-it again', flat):
            if not any(a <= m.start() < b for a, b in spans):
                stray.append(m.start())
        return spans, stray

    def test_run_argo_it_again_sits_only_in_the_no_saved_hit_bracket(self):  # control: passes today
        flat = self._flat_stop()
        spans, stray = self._again_outside_no_hit_bracket(flat)
        self.assertEqual(len(spans), 1, 'expected one "[If no hit sits under == saved" bracket')
        self.assertTrue(re.search(r'(?i)run /argo-it again', flat[spans[0][0]:spans[0][1]]))
        self.assertEqual(stray, [], 'run /argo-it again sits outside the no-saved-hit bracket')

    def test_the_loop_check_flags_it_inside_the_shared_other_hits_bracket(self):  # proves the check
        flat = self._flat_stop()
        a, b = self._again_outside_no_hit_bracket(flat)[0][0]
        moved = flat[a:b].replace(' then run /argo-it again.', '')
        mutated = flat[:a] + moved + flat[b:]
        self.assertNotEqual(mutated, flat)
        self.assertIn('one per other hit].]', mutated)
        mutated = mutated.replace('one per other hit].]', 'one per other hit]. Then run /argo-it again.]', 1)
        _, stray = self._again_outside_no_hit_bracket(mutated)
        self.assertTrue(stray, 'the check does not flag "run /argo-it again" in the shared other-hits bracket')

    # --- 5. the rest of review 3 M3 -------------------------------------------------------------------
    def test_registry_stop_rotation_line_covers_every_value_not_only_the_login(self):
        flat = self._flat_stop()
        sents = [s for s in re.split(r'(?<=[.?!])\s+', flat) if re.search(r'(?i)have it changed', s)]
        self.assertTrue(sents, 'no "have it changed" line in the registry stop')
        for s in sents:
            self.assertNotRegex(s, r'(?i)\bthis login\b', 'the rotation line covers only the login')
            self.assertRegex(s, r'(?i)\b(these|them|every|each|all|values)\b|\b(login|token|password) or\b|\bor (a |the )?(password|secret|value)',
                             'the rotation line does not say it covers every value found')

    def test_registry_stop_names_an_outside_registry_hit_once_in_the_saved_case(self):
        flat = self._flat_stop()
        others = [(a, b) for a, b in _brackets(flat) if flat.startswith('[If there are other hits', a)]
        self.assertEqual(len(others), 1)
        a, b = others[0]
        opener = flat[a:flat.index(':', a)]
        skips_saved = re.search(r'(?i)\b(no hit|not|none|nothing|neither)\b[^:]*== saved', opener) is not None
        moving_too = 'needs moving too' in flat
        self.assertFalse(not skips_saved and moving_too,
                         'in the saved case a hit outside a registry file is named in "I also found" and again '
                         'in the "needs moving too" bracket')


class HashValueAndTemplateSetCases(Base):
    """Task 1b fix round 5: a value that starts with # is a value; make-it's templates give exactly one
    hit (POSTGRES_PASSWORD, owned by another card); no wording of 'try /argo-it again' in the saved bracket."""

    HEAD = 'LOG_LEVEL=info\n'
    NAME = 'DB_' + 'PASSWORD'

    def _ex(self, label, text, rel='.env.example'):
        return EnvExampleFloorAndTemplatesCases._ex(self, label, text, rel)

    def _hash_case(self, label, sep, rel='.env.example'):
        v = '#' + fake('hashval' + label[3:5])
        text = self.HEAD + self.NAME + sep + v + '\n'
        k, lines = EnvExampleFloorAndTemplatesCases._want(label, [rel + ':2'])
        self.check(self._ex(label, text, rel).scan(), secrets=[v], **{k: lines})

    # --- 1. a value starting with # is a value ----------------------------------------------------
    def test_hash_value_after_space_hits_as_an_unsaved_edit(self):
        self._hash_case(L_UNSAVED, '= ')

    def test_hash_value_after_space_hits_as_a_new_file(self):
        self._hash_case(L_NEW, '= ')

    def test_hash_value_after_space_hits_in_an_unsent_commit(self):
        self._hash_case(L_SAVED, '= ')

    def test_hash_value_after_tab_hits_as_an_unsaved_edit(self):
        self._hash_case(L_UNSAVED, '=\t')

    def test_hash_value_after_tab_hits_as_a_new_file(self):
        self._hash_case(L_NEW, '=\t')

    def test_hash_value_after_tab_hits_in_an_unsent_commit(self):
        self._hash_case(L_SAVED, '=\t')

    def test_hash_value_with_spaced_equals_hits_as_an_unsaved_edit(self):
        self._hash_case(L_UNSAVED, ' = ')

    def test_hash_value_with_spaced_equals_hits_as_a_new_file(self):
        self._hash_case(L_NEW, ' = ')

    def test_hash_value_with_spaced_equals_hits_in_an_unsent_commit(self):
        self._hash_case(L_SAVED, ' = ')

    def test_hash_value_in_env_production_in_an_unsent_commit_hits(self):
        self._hash_case(L_SAVED, '= ', '.env.production')

    def test_hash_value_with_tab_in_env_production_in_an_unsent_commit_hits(self):
        self._hash_case(L_SAVED, '=\t', '.env.production')

    def test_bare_hash_comment_after_empty_is_still_empty(self):  # control: passes today
        r = self.fresh()
        r.branch()
        r.write('.env.production', self.HEAD + 'SMTP_' + 'PASSWORD' + '= # set in the pipeline\n')
        r.commit('add .env.production')
        self.check(r.scan())

    # --- 2. make-it's templates: the whole hit set ----------------------------------------------------
    def _template_set(self, scaffold):  # control: passes today
        src = os.path.join(HERE, '..', 'scaffolds', scaffold, '.env.example')
        self.assertTrue(os.path.isfile(src), 'missing template: %s' % src)
        with open(src, 'rb') as f:
            data = f.read()
        pg = [i + 1 for i, ln in enumerate(data.splitlines()) if ln.startswith(b'POSTGRES_' + b'PASSWORD')]
        self.assertEqual(len(pg), 1, '%s: expected one POSTGRES_PASSWORD line' % scaffold)
        r = self.fresh(remote=False)
        r.write('.env.example', data)
        r.commit('template as-is')
        self.check(r.scan(), saved=['.env.example:%d' % pg[0]])

    def test_fastapi_nextjs_template_hit_set_is_only_the_postgres_password_line(self):
        self._template_set('fastapi-nextjs')

    def test_nextjs_fullstack_template_hit_set_is_only_the_postgres_password_line(self):
        self._template_set('nextjs-fullstack')

    # --- 3. no retry in any words in the saved-history bracket --------------------------------------
    RETRY = re.compile(r'(?i)\b(re-?run|retry|run|try|start|use|call|invoke|launch)\b[^.\]]*?/argo-it'
                       r'|/argo-it\b[^.\]]*?\b(again|once more|another time|a second time|afterwards?|later)\b')

    def _bracket(self, flat):
        return EnvKeyFilesAndOverlapCases._saved_bracket(self, flat)

    _doc = EnvKeyFilesAndOverlapCases._doc
    _section = EnvKeyFilesAndOverlapCases._section

    def test_saved_history_bracket_never_tells_the_user_to_retry_argo_it(self):  # guard: passes today
        flat = EnvExampleFloorAndTemplatesCases._flat_stop(self)
        a, b = self._bracket(flat)
        self.assertIsNone(self.RETRY.search(flat[a:b]), 'saved-history bracket tells the user to retry /argo-it')

    def test_the_retry_check_flags_other_wordings_inside_the_bracket(self):  # proves the check
        flat = EnvExampleFloorAndTemplatesCases._flat_stop(self)
        a, b = self._bracket(flat)
        for words in ('Then try /argo-it once more.', 'Run /argo-it again.', 'Then rerun /argo-it.',
                      'You can retry /argo-it.', 'Start /argo-it over.'):
            mutated = flat[:b - 1] + ' ' + words + flat[b - 1:]
            a2, b2 = self._bracket(mutated)
            self.assertIsNotNone(self.RETRY.search(mutated[a2:b2]), 'not flagged: %s' % words)


class AdversarialRound1TestsCases(Base):
    """Task 1b adversarial round 1: npmrc key junk, pypirc name case, NULs in config files, multi-line
    .env values.  Names and values are joined at run time (GitGuardian scans this file)."""

    HEAD = 'LOG_LEVEL=info\n'
    AUTH = '//registry.npmjs.org/:' + '_auth' + 'Token'

    def _each_label(self, rel, head, text, hit, secrets):
        """The same file under all three labels; `text` begins with `head`, the hit is rel:hit."""
        for label in (L_UNSAVED, L_NEW, L_SAVED):
            with self.subTest(label=label):
                r = self.fresh()
                if label == L_UNSAVED:
                    r.write(rel, head)
                    r.commit('base')
                    r.push()
                    r.write(rel, text)
                elif label == L_NEW:
                    r.write(rel, text)
                else:
                    r.branch()
                    r.write(rel, text)
                    r.commit('add ' + rel)
                key = {L_UNSAVED: 'unsaved', L_NEW: 'new', L_SAVED: 'saved'}[label]
                kw = {key: ['%s:%d' % (rel, hit)]}
                self.check(r.scan(), secrets=secrets, **kw)

    # --- 1. npm ends a key at ; or # and reads a trailing [] as an array --------------------------------
    def test_npmrc_key_junk_after_auth_token_hits_under_every_label(self):
        for i, junk in enumerate((';ci=', '#ci=', '[]=')):
            v = fake('npmjunk%d' % i)
            with self.subTest(junk=junk):
                head = 'registry=https://registry.npmjs.org/\n'
                self._each_label('.npmrc', head, head + self.AUTH + junk + v + '\n', 2, [v])

    def test_npmrc_plain_auth_token_still_hits_under_every_label(self):  # control: passes today
        v = fake('npmplain')
        head = 'registry=https://registry.npmjs.org/\n'
        self._each_label('.npmrc', head, head + self.AUTH + '=' + v + '\n', 2, [v])

    # --- 2. configparser lowercases option names --------------------------------------------------------
    def _pypirc(self, name, v, label):
        text = '[pypi]\nusername = __token__\n%s = %s\n' % (name, v)
        r = self.fresh()
        if label == L_NEW:
            r.write('.pypirc', text)
            self.check(r.scan(), new=['.pypirc:3'], secrets=[v])
        else:
            r.branch()
            r.write('.pypirc', text)
            r.commit('add pypirc')
            self.check(r.scan(), saved=['.pypirc:3'], secrets=[v])

    def test_pypirc_mixed_case_password_name_hits(self):
        for name in ('Pass' + 'Word', 'pass' + 'WORD'):
            for label in (L_NEW, L_SAVED):
                with self.subTest(name=name, label=label):
                    self._pypirc(name, fake('pypi' + name[:4]), label)

    def test_pypirc_lowercase_password_still_hits(self):  # control: passes today
        for label in (L_NEW, L_SAVED):
            with self.subTest(label=label):
                self._pypirc('pass' + 'word', fake('pypictl'), label)

    # --- 3. one NUL in a comment must not hide a config file --------------------------------------------
    def test_npmrc_with_nul_in_a_comment_hits_new_and_saved(self):
        v = fake('nulnpm')
        text = '; build\x00cache\n' + self.AUTH + '=' + v + '\n'
        for label in (L_NEW, L_SAVED):
            with self.subTest(label=label):
                r = self.fresh()
                if label == L_NEW:
                    r.write('.npmrc', text)
                    self.check(r.scan(), new=['.npmrc:2'], secrets=[v])
                else:
                    r.branch()
                    r.write('.npmrc', text)
                    r.commit('add npmrc')
                    self.check(r.scan(), saved=['.npmrc:2'], secrets=[v])

    def test_env_production_with_nul_in_a_comment_hits_saved(self):
        v = fake('nulenvprod1234')
        r = self.fresh()
        r.branch()
        r.write('.env.production', '# build\x00note\n' + 'DB_' + 'PASSWORD' + '=' + v + '\n')
        r.commit('add env')
        self.check(r.scan(), saved=['.env.production:2'], secrets=[v])

    def test_real_binary_file_is_still_skipped(self):  # control: passes today
        v = fake('binpng1234567')
        r = self.fresh()
        r.write('logo.png', b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\n' + _b(kv('PASS' + 'WORD', v)))
        self.check(r.scan())

    # --- 4. a quoted value that spans lines in .env.example ---------------------------------------------
    def test_env_example_multiline_quoted_value_hits(self):
        for q, name in (('"', 'DB_' + 'PASSWORD' + '_PROD'), ("'", 'STRIPE_' + 'SECRET' + '_KEY')):
            v = fake('multiline24chars%s' % ('dq' if q == '"' else 'sq'))
            text = self.HEAD + '%s=%s\n%s\n%s\n' % (name, q, v, q)
            with self.subTest(quote=q):
                self._each_label('.env.example', self.HEAD, text, 2, [v])

    def test_env_production_multiline_quoted_value_still_hits_saved(self):  # control: passes today
        v = fake('multiline24charsctl')
        r = self.fresh()
        r.branch()
        r.write('.env.production', self.HEAD + 'DB_' + 'PASSWORD' + '_PROD="\n%s\n"\n' % v)
        r.commit('add env')
        self.check(r.scan(), saved=['.env.production:2'], secrets=[v])

    def test_env_example_enforce_secrets_false_stays_clean(self):  # control: passes today
        r = self.fresh()
        r.write('.env.example', self.HEAD + 'ENFORCE_SECRETS=false\n')
        self.check(r.scan())


class Round7TestsCases(Base):
    """Task 1b fix round 7: nothing on stderr; quoted npmrc keys; backtick values; NULs in pypirc/yarnrc.
    Names and values are joined at run time (GitGuardian scans this file)."""

    AUTH = '//registry.npmjs.org/:' + '_auth' + 'Token'
    CLEAN = 'registry=https://registry.npmjs.org/\n'

    def _labels(self, rel, text, hit, secrets, labels=(L_UNSAVED, L_NEW, L_SAVED), head=None):
        for label in labels:
            with self.subTest(label=label, rel=rel):
                r = self.fresh()
                if label == L_UNSAVED:
                    r.write(rel, head if head is not None else self.CLEAN)
                    r.commit('base')
                    r.push()
                    r.write(rel, text)
                elif label == L_NEW:
                    r.write(rel, text)
                else:
                    r.branch()
                    r.write(rel, text)
                    r.commit('add ' + rel)
                key = {L_UNSAVED: 'unsaved', L_NEW: 'new', L_SAVED: 'saved'}[label]
                self.check(r.scan(), secrets=secrets, **{key: ['%s:%d' % (rel, hit)]})

    def _scan_strict(self, r):
        cp = subprocess.run([sys.executable, '-W', 'error', SCRIPT, '--repo', r.work],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
        return Result(cp, 0)

    # --- 1. a warning on stderr breaks argo-it 3e's "every line is a label or file:line" ----------------
    # (fails on 3.13+, where re.split(pattern, s, 1) warns; may pass on 3.9)
    def test_scan_writes_nothing_to_stderr_and_survives_python_W_error(self):
        v = fake('stderrnpm')
        for label in (L_UNSAVED, L_NEW, L_SAVED):
            for hit in (False, True):
                with self.subTest(label=label, hit=hit):
                    text = self.CLEAN + (self.AUTH + '=' + v + '\n' if hit else '')
                    r = self.fresh()
                    if label == L_UNSAVED:
                        r.write('.npmrc', self.CLEAN)
                        r.commit('base')
                        r.push()
                    elif label == L_SAVED:
                        r.branch()
                    r.write('.npmrc', text)
                    if label == L_SAVED:
                        r.commit('add npmrc')
                    key = {L_UNSAVED: 'unsaved', L_NEW: 'new', L_SAVED: 'saved'}[label]
                    for res in (r.scan(), self._scan_strict(r)):
                        self.assertEqual(res.err, b'')
                        self.assertEqual(res.code, 1 if hit else 0)
                        self.check(res, secrets=[v], **({key: ['.npmrc:2']} if hit else {}))

    # --- 2. npm's ini parser strips quotes around a key --------------------------------------------------
    def test_npmrc_quoted_auth_token_key_hits_under_every_label(self):
        for i, q in enumerate(('"', "'")):
            v = fake('npmquote%d' % i)
            with self.subTest(quote=q):
                self._labels('.npmrc', self.CLEAN + q + self.AUTH + q + '=' + v + '\n', 2, [v])

    # --- 3. Node dotenv reads a backtick value that runs over lines --------------------------------------
    def test_env_example_backtick_multiline_value_hits_new_and_saved(self):
        v = fake('backtick24chars')
        head = 'LOG_LEVEL=info\n'
        text = head + 'DB_' + 'PASSWORD' + '_PROD=`\n' + v + '\n`\n'
        self._labels('.env.example', text, 2, [v], labels=(L_NEW, L_SAVED))

    # --- 4. a commented-out token is still in the file that gets sent -----------------------------------
    def test_npmrc_commented_out_token_hits_under_every_label(self):  # guard if it passes today
        v = fake('npmcomment')
        self._labels('.npmrc', self.CLEAN + '# ' + self.AUTH + '=' + v + '\n', 2, [v])

    # --- 5. one NUL in a comment must not hide .pypirc / .yarnrc.yml ------------------------------------
    def test_pypirc_with_nul_in_a_comment_hits_new_and_saved(self):
        v = fake('nulpypirc')
        text = '; build\x00cache\n' + 'pass' + 'word = ' + v + '\n'
        self._labels('.pypirc', text, 2, [v], labels=(L_NEW, L_SAVED))

    def test_yarnrc_yml_with_nul_in_a_comment_hits_new_and_saved(self):
        v = fake('nulyarnrc')
        text = '# build\x00cache\n' + 'npmAuth' + 'Token: ' + v + '\n'
        self._labels('.yarnrc.yml', text, 2, [v], labels=(L_NEW, L_SAVED))


class AdversarialRound2TestsCases(Base):
    """Task 1b adversarial round 2: npmrc colon forms, a quoted value that runs on in 3e's move, never-read
    exports in 3e, .pypirc continuation lines, ${X?} inside npm keys.  Names and values are joined at run time
    (GitGuardian scans this file)."""

    AUTH, CLEAN = Round7TestsCases.AUTH, Round7TestsCases.CLEAN
    _labels = Round7TestsCases._labels
    _doc, _section = ArgoItWiringCases._doc, ArgoItWiringCases._section

    @staticmethod
    def _f(tag, n=40):
        return (fake(tag) + '0123456789abcdef' * 4)[:n]

    # --- 1. a quoted value after `NAME:` in .npmrc hit before this task (missed since 05d58d7) -----------------
    def test_1_npmrc_colon_forms_hit_new_and_saved(self):
        parts = dict(a=self.AUTH, t='_auth' + 'Token', p='_pass' + 'word', n='npmAuth' + 'Token',
                     r='$' + '{NPM_' + 'TOKEN}', o='to' + 'ken')
        forms = ('{a}: "{v}"', '{t}: "{v}"', '{p}: "{v}"', '{n}: "{v}"', "{a}: '{v}'", '{a} := "{v}"',
                 '{a}={r}  ; old {o}: "{v}"')
        for i, form in enumerate(forms):
            v = self._f('colon%d' % i)
            with self.subTest(form=form):
                self._labels('.npmrc', self.CLEAN + form.format(v=v, **parts) + '\n', 2, [v], labels=(L_NEW, L_SAVED))

    # --- 2. 3e: a named line that opens a quoted value which closes on a later line --------------------------
    RUNS_ON = re.compile(r'(?i)quot.{0,200}?\b(later|next|following|another)\b.{0,20}?\blines?\b'
                         r'|\b(later|next|following)\b.{0,20}?\blines?\b.{0,200}?quot')
    CLOSING = re.compile(r'(?i)\bclos(e|es|ing)\b.{0,20}?quot|quot.{0,40}?\bclos(e|es|ing)\b')
    ALL_OF_IT = re.compile(r'(?i)\ball of it\b|\bthe whole (value|thing)\b|\bthe entire value\b|\bevery line\b'
                           r'|\ball (of )?(those|these|the) lines\b')

    def _move_paras(self):
        sec = self._section()
        a, b = sec.index('**Otherwise'), sec.index('**If ALL checks pass')
        return [re.sub(r'\s+', ' ', p) for p in sec[a:b].split('\n\n')]

    def test_2_move_runs_a_quoted_value_on_to_its_closing_quote(self):
        # reading (b): move only line 2 (`KEY="`), the value stays on line 3, and the rescan exits 0
        paras = [p for p in self._move_paras() if self.RUNS_ON.search(p) and self.CLOSING.search(p)]
        self.assertTrue(paras, "3e's move path never says that a value opening with a quote on the named line runs "
                               "on to its closing quote on a later line")
        self.assertTrue(any(self.ALL_OF_IT.search(p) for p in paras),
                        "3e's move path does not say all of a value that runs on is moved")

    def test_2_cannot_open_stop_does_not_cover_a_line_that_opens_a_quoted_value(self):
        # reading (a): `KEY="` holds nothing that looks like a secret, so the can't-open stop and its rename advice
        for p in self._move_paras():
            if re.search(r'(?i)nothing on (that|the) line', p):
                self.assertRegex(p, r'(?i)quot|runs? on|later line|next line',
                                 "the can't-open stop still covers a line that opens a quoted value which runs on")

    def test_2_moving_all_of_a_multiline_value_leaves_a_clean_rescan(self):  # control: passes today
        head, name, v = 'LOG_LEVEL=info\n', 'DB_' + 'PASSWORD' + '_PROD', self._f('multi', 24)
        for label, key in ((L_UNSAVED, 'unsaved'), (L_NEW, 'new')):
            with self.subTest(label=label):
                r = self.fresh()
                if label == L_UNSAVED:
                    r.write('.env.example', head)
                    r.commit('base')
                    r.push()
                r.write('.env.example', head + name + '="\n' + v + '\n"\n')
                self.check(r.scan(), secrets=[v], **{key: ['.env.example:2']})
                r.write('.env.example', head + name + '=\n')  # lines 2-4 moved, all of it
                self.check(r.scan(), secrets=[v])

    # --- 3. 3e never opens the other files operator-safety section 1 never reads -----------------------------
    PM = re.compile(r'(?i)password[- ]manager')

    def test_3_reading_rule_never_opens_password_manager_exports_or_browser_stores(self):
        flat = re.sub(r'\s+', ' ', self._section())
        a = flat.index('**Exit 1**')
        rule = flat[a:flat.index('**Anything else**', a)]
        self.assertRegex(rule, self.PM, "3e's never-open exception leaves out password-manager exports")
        self.assertRegex(rule, r'(?i)browser profile', "3e's never-open exception leaves out browser profiles")
        self.assertRegex(rule, r'(?i)cookie', "3e's never-open exception leaves out cookie stores")

    def test_3_a_hit_in_one_stops_before_the_move_ask(self):
        sec = self._section()
        texts = []
        for p in sec[:sec.index('Which should I move')].split('\n\n'):
            f = re.sub(r'\s+', ' ', p)
            if '**Exit 1**' in f:  # that paragraph also holds the could-not-check STOP: only its Exit 1 bullet
                f = f[f.index('**Exit 1**'):f.index('**Anything else**')]
            if self.PM.search(f):
                texts.append(f)
        self.assertTrue(texts, '3e names no password-manager export before the move ask')
        self.assertTrue(any(re.search(r'(?i)\bstops?\b', f)
                            and re.search(r"(?i)\b(never|don't|do not|not)\b.{0,60}?\b(open|read)", f) for f in texts),
                        'a hit in a password-manager export or browser store does not stop before the move ask')

    # --- 4. configparser reads an indented continuation line into the value ----------------------------------
    PYPIRC_HEAD = '[distutils]\nindex-servers = pypi\n\n[pypi]\nusername = __token__\n'

    def _pypirc(self, text, found):
        import configparser
        cp = configparser.RawConfigParser()
        cp.read_string(text)
        self.assertIn(found, cp.get('pypi', 'pass' + 'word'))  # what twine reads holds the token
        self._labels('.pypirc', text, 6, [found], labels=(L_NEW, L_SAVED))

    def test_4_pypirc_password_on_an_indented_continuation_line_hits_new_and_saved(self):
        v = 'py' + 'pi-' + self._f('pypicont')
        self._pypirc(self.PYPIRC_HEAD + 'pass' + 'word =\n    ' + v + '\n', v)

    def test_4_pypirc_password_prefix_then_the_rest_on_a_continuation_line_hits_new_and_saved(self):
        rest = self._f('pypisplit')
        self._pypirc(self.PYPIRC_HEAD + 'pass' + 'word = ' + 'py' + 'pi-' + '\n    ' + rest + '\n', rest)

    def test_4_pypirc_index_servers_continuation_list_stays_clean(self):  # control: passes today
        text = '[distutils]\nindex-servers =\n    pypi\n    testpypi\n\n[pypi]\nusername = __token__\n'
        for label in (L_NEW, L_SAVED):
            with self.subTest(label=label):
                r = self.fresh()
                if label == L_SAVED:
                    r.branch()
                r.write('.pypirc', text)
                if label == L_SAVED:
                    r.commit('add pypirc')
                self.check(r.scan())

    # --- 5. npm runs env-replace on keys: an unset ${X?} becomes '' ------------------------------------------
    def test_5_npmrc_key_split_by_an_unset_env_reference_hits_under_every_label(self):
        e = '$' + '{CI_UNSET?}'
        for i, key in enumerate(('_authTok' + e + 'en', '_au' + e + 'th', '_pass' + e + 'word')):
            v = self._f('envkey%d' % i)
            with self.subTest(key=key):
                self._labels('.npmrc', self.CLEAN + '//registry.npmjs.org/:' + key + '=' + v + '\n', 2, [v])


class AdversarialRound3TestsCases(Base):
    """Task 1b adversarial round 3, owner's call: a .pypirc line that hit under the pre-task reading (base,
    1676fdb~1) still hits, so a commented-out token after a `WORD:` prefix is caught again.  Names and values are
    joined at run time (GitGuardian scans this file)."""

    _labels = Round7TestsCases._labels
    _f = staticmethod(AdversarialRound2TestsCases._f)
    PW, REF = 'pass' + 'word', '$' + '{PYPI_' + 'TOKEN}'
    HEAD = AdversarialRound2TestsCases.PYPIRC_HEAD + PW + ' = ' + REF + '\n'  # 6 lines: twine reads the ${...}

    # --- 1. `# old: password = "<T>"` in .pypirc hit at base; missed since 536ae85 ---------------------------
    FORMS = ('# old: {n} = "{v}"', '# note: {n} = "{v}"', '; was: {n} = "{v}"', '# TODO: {n}: "{v}"')
    NAMES = (PW, 'to' + 'ken', 'sec' + 'ret', 'pass' + 'wd', 'p' + 'wd')

    def test_1_pypirc_commented_out_token_after_a_word_prefix_hits_under_every_label(self):
        for i, form in enumerate(self.FORMS):
            for j, n in enumerate(self.NAMES):
                v = 'py' + 'pi-' + self._f('pyn%d%d' % (i, j))
                with self.subTest(form=form, name=n):
                    self._labels('.pypirc', self.HEAD + form.format(n=n, v=v) + '\n', 7, [v], head=self.HEAD)

    # --- 2. differential: every .pypirc line the source-code reading hits still hits --------------------------
    # Base read .pypirc as source code, exactly as head reads any non-config file (checked on 3,016,440 lines), so
    # each shape's twin in `notes.txt` is base's reading, with no git history needed (CI checks out one commit).
    def _hits(self, r):
        cp = subprocess.run([sys.executable, SCRIPT, '--repo', r.work],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300)
        self.assertIn(cp.returncode, (0, 1), 'stderr=%r' % cp.stderr[:300])
        return cp, {x for x in cp.stdout.decode('utf-8').splitlines() if not x.startswith('== ')}

    def _shapes(self):
        names = (self.PW, 'Pass' + 'Word', 'to' + 'ken', 'p' + 'wd', 'client_' + 'sec' + 'ret')
        prefixes = ('', '    ', '# ', '#', '; ', ';', '# old: ', '# note: ', '; was: ', '# TODO: ', 'note: ',
                    'old: ', '# prev=', '# backup:', 'username=x;', '# rotated 2026-10-01: ',
                    self.PW + ' = ' + self.REF + '  ; old ', '; old to' + 'ken: ')
        # ponytail: quoted only -- base read .pypirc as source code, which never hits an unquoted value
        shapes = [p + n + s + q + '{v}' + q for p in prefixes for n in names
                  for s in (' = ', '=', ': ', ':', ' := ') for q in ('"', "'")]
        return shapes + [  # real-world .pypirc lines
            '[distutils]', 'index-servers =', 'index-servers = pypi testpypi', '    pypi', '[pypi]', '[testpypi]',
            'repository = https://upload.pypi.org/legacy/', 'repository: https://test.pypi.org/legacy/',
            'username = __token__', self.PW + ' = ' + self.REF, self.PW + ' = {v}', self.PW + ':{v}',
            self.PW + ' = {v}  ; rotated', self.PW + ' =\n    {v}', self.PW + ' = ' + 'py' + 'pi-\n    {v}',
            '; old to' + 'ken: "{v}"', self.PW + ' = ' + self.REF + '  ; old to' + 'ken: "{v}"']

    def test_2_every_pypirc_line_its_source_code_twin_hits_still_hits_new_and_saved(self):
        v = 'py' + 'pi-' + self._f('pydiff')
        shapes = self._shapes()
        r = self.fresh()
        r.branch()
        for i, shape in enumerate(shapes):
            for name in ('.pypirc', 'notes.txt'):  # the same line as registry config and as source code
                r.write('d%04d/%s' % (i, name), shape.replace('{v}', v) + '\n')  # not format: REF holds braces
        for label in (L_NEW, L_SAVED):
            if label == L_SAVED:
                r.commit('add pypirc files')
            with self.subTest(label=label):
                cp, now = self._hits(r)
                self.no_leak(Result(cp, 0), [v])
                was = {x.replace('/notes.txt:', '/.pypirc:') for x in now if '/notes.txt:' in x}
                # base hit 722 of these shapes: a narrower source-code reading would shrink both sides alike
                self.assertGreaterEqual(len(was), 722, "the source-code reading narrowed below base's 722 hits")
                lost = sorted(was - now)
                if lost:
                    self.fail('%d of %d source-code hits are missed in .pypirc, e.g. %s' % (
                        len(lost), len(was), [shapes[int(x[1:5])] + ' @' + x.rsplit(':', 1)[1] for x in lost[:12]]))

    # --- 3. controls -------------------------------------------------------------------------------------------
    def test_3_pypirc_env_reference_password_alone_stays_clean_under_every_label(self):  # control: passes today
        for text in (self.HEAD, self.PW + ' = ' + self.REF + '\n'):
            for label in (L_UNSAVED, L_NEW, L_SAVED):
                with self.subTest(label=label, lines=text.count('\n')):
                    r = self.fresh()
                    if label == L_UNSAVED:
                        r.write('.pypirc', '[pypi]\n')
                        r.commit('base')
                        r.push()
                    elif label == L_SAVED:
                        r.branch()
                    r.write('.pypirc', text)
                    if label == L_SAVED:
                        r.commit('add pypirc')
                    self.check(r.scan())


class ArgoItFirstSendScanCases(Base):
    """Task 3: PHASE 5's first send runs secret-scan.py after step 2 and before the step-3 ask, reads it as 3e
    does, and stops on a hit under == saved, not sent == (the only label this send carries: step 4 pushes saved
    changes only).  Each prose check reads its own sentence or rule; the polarity control proves each one fails
    on its plain opposite.  Values are joined at run time (GitGuardian scans this file)."""

    ASK = "I've generated your deployment pipeline"
    PICK = '**What would you like to do?**'
    FENCE = r'^```bash\n(.*?)^```'
    GENERATED = {'env/dev/kustomization.yaml': 'resources:\n  - backend.yaml\n',
                 'env/prod/kustomization.yaml': 'resources:\n  - backend.yaml\n',
                 '.github/workflows/build-and-deploy.yml': 'name: build-and-deploy\non: push\n',
                 'ONBOARDING-K8S.md': '# Onboarding\n'}
    NEG = r"(?:don't|doesn't|do not|does not|never|no need to|not|won't|will not|can't|cannot)"
    NOT_SHOWN = (r"(?i)\b(?:don't|do not|never|without|no need to)\s+(?:show|showing|ask|asking|give|giving|offer"
                 r"|offering|reach|reaching|go on to|going on to)\b[^.]{0,40}?\b(?:step[- ]?3|ask|pick|question|options?)\b"
                 r"|\bstep[- ]?3(?:'s)?(?:\s+(?:ask|pick|question))?\s+(?:isn't|is not|never|won't be|doesn't|does not)\s+"
                 r"(?:shown|asked|run|given|offered|happen)"
                 r"|\bsteps?\s+3\s+(?:and later|onwards?|and on|through \d|to \d|-\d)\s+(?:don't|do not|never|won't)\s+run"
                 r"|\bskip(?:s|ping)?\s+steps?\s+3\b"
                 r"|\b(?:the|that)\s+ask\s+(?:isn't|is not|never|won't be)\s+(?:shown|asked|given)")
    SENT_NONE = (r"(?i)\bnothing\s+(?:is|was|gets|has been|will be)\s+sent\b|\bnothing\s+(?:leaves|goes out)\b"
                 r"|\bsend(?:s|ing)?\s+nothing\b|\b(?:don't|do not|won't|will not|never|can't)\s+send\b"
                 r"|\bhaven't\s+(?:saved or\s+)?sent\s+anything\b|\bwithout sending\b")
    NEVER_SAY = (r"(?i)\bgit push\b|\bpush(?:ed|es|ing)?\b|\bcommit(?:s|ted)?\b|\bmerge\b|deploy branch|\bkubectl\b"
                 r"|\bnamespace\b|\bpods?\b|\bmanifests?\b|\bcontainers?\b|Docker image|CI pipeline|Argo CD sync")

    # --- reading PHASE 5 ------------------------------------------------------------------------------------
    def _phase(self):
        doc = ArgoItWiringCases._doc(self)
        i = doc.find('<!-- PHASE 5: DEPLOY')
        self.assertNotEqual(i, -1, 'argo-it.md: no "PHASE 5: DEPLOY" comment')
        j = doc.find('</step>', i)
        self.assertNotEqual(j, -1, 'argo-it.md: PHASE 5 has no closing </step>')
        return doc[i:j]

    def _fences(self, p):
        return [(m.start(), m.end(), m.group(1)) for m in re.finditer(self.FENCE, p, re.M | re.S)]

    def _step_block(self, p, n):
        """(start, end, code) of the first ```bash block after PHASE 5's '**n. ' heading."""
        h = re.search(r'^\*\*%d\. ' % n, p, re.M)
        self.assertTrue(h, 'PHASE 5: no "**%d." heading' % n)
        for f in self._fences(p):
            if f[0] > h.start():
                return f
        self.fail('PHASE 5: no ```bash block after step %d' % n)

    def _ask_at(self, p):
        k = p.find(self.PICK)
        self.assertNotEqual(k, -1, 'PHASE 5: the step-3 pick %r is gone' % self.PICK)
        a = p.rfind(self.ASK, 0, k)
        self.assertNotEqual(a, -1, 'PHASE 5: the step-3 ask %r is gone' % self.ASK)
        return a - 1 if p[a - 1] == '"' else a

    def _scan(self, p):
        hits = [f for f in self._fences(p) if 'secret-scan.py' in f[2]]
        self.assertTrue(hits, 'PHASE 5 has no ```bash block that runs secret-scan.py: the first send is never scanned')
        return hits[0]

    def _prose(self, p=None):
        """PHASE 5 (or `p`) from the end of step 2's block to the step-3 ask, code removed: where the scan's reading
        and its stops must sit, so the agent meets them before the ask."""
        p = p or self._phase()
        return re.sub(self.FENCE, '', p[self._step_block(p, 2)[1]:self._ask_at(p)], flags=re.M | re.S)

    @staticmethod
    def _flat(t):
        return re.sub(r'\s+', ' ', t).strip()

    def _units(self, prose):
        """Paragraphs and list items, each flattened."""
        return [self._flat(x) for x in re.split(r'\n\s*\n|\n(?=[ \t]*(?:[-*]|\d+\.)\s)', prose) if x.strip()]

    @staticmethod
    def _sentences(unit):
        return [s for s in re.split(r'(?<=[.!?])["\]*)]*\s+', unit) if s]

    def _all_sentences(self, prose):
        return [s for u in self._units(prose) for s in self._sentences(u)]

    def _stops(self, t):
        """Some 'stop' in t that isn't negated ('doesn't stop it', 'not stop')."""
        return any(not re.search(r'(?i)\b' + self.NEG + r'\s+(?:\w+\s+)?$', t[:m.start()])
                   for m in re.finditer(r'(?i)\bstop', t))

    def _rule(self, prose, starts, needs, what):
        """The first rule (a unit matching `starts`, run on to the next bold heading) that meets every
        (regex or callable, message) in `needs`; else fail with the closest miss."""
        units = self._units(prose)
        miss = 'PHASE 5 has no rule for %s' % what
        for i, u in enumerate(units):
            if not starts(u):
                continue
            blk = [u]
            for v in units[i + 1:]:
                if re.match(r'(?:[-*]\s+)?\*\*', v):
                    break
                blk.append(v)
            b = ' '.join(blk)
            bad = [m for need, m in needs if not (need(b) if callable(need) else re.search(need, b))]
            if not bad:
                return b
            miss = 'PHASE 5, %s: %s' % (what, bad[0])
        self.fail(miss)

    # --- the prose checks (each proven against its plain opposite in the polarity control) -------------------
    def _saved_hit_stops(self, prose):
        return self._rule(prose, lambda u: L_SAVED in u and re.search(r'(?i)\bhits?\b', u) and self._stops(u), [
            (self.NOT_SHOWN, "it doesn't say the step-3 ask isn't shown"),
            (self.SENT_NONE, "it doesn't say nothing is sent"),
            (re.escape("in a change you already saved but haven't sent"), "the stop doesn't use 3e's wording"),
            (r'line \[N\] of \[file\]', 'the stop does not name each hit as line [N] of [file]'),
            (lambda b: not re.search(r'(?i)Which should I move|I can move|into your local settings file|os\.getenv'
                                     r'|process\.env', b), 'a saved hit is offered a move: the only option is stop'),
        ], 'a hit under %s' % L_SAVED)

    def _generated_is_a_mistake(self, prose):
        saved = self._saved_hit_stops(prose)
        mis = r"(?i)\bmistake\b|\b(?:my|argo-it's|our) (?:side|fault)\b|\bbug\b"
        for u in self._units(prose):
            if re.search(r'(?i)generat|\bstep 1\b|\bjust (?:made|wrote|created|saved)\b', u) and re.search(mis, u):
                break
        else:
            self.fail("PHASE 5: a hit in a file argo-it just generated is not called argo-it's mistake")
        for s in self._sentences(u):
            if re.search(mis, s):
                self.assertNotRegex(s, r"(?i)\b(?:not|isn't|is not|no|wasn't)\s+(?:a\s+|my\s+|argo-it's\s+|our\s+)?"
                                       r"(?:mistake|bug|fault)\b|\b(?:go(?:es)? on|move on|continue|proceed|carry on)\b",
                                    'the generated-file sentence lets the send go on: %r' % s)
        self.assertTrue(self._stops(u) or u in saved, 'the generated-file rule does not stop: %r' % u)

    def _only_saved_counts(self, prose):
        ss = self._all_sentences(prose)
        only = any(re.search(r'(?i)\bonly\b[^.]{0,40}' + re.escape(L_SAVED) + r'[^.]{0,80}\b(?:counts?|stops?'
                             r'|matters?|holds?|blocks?)\b', s) for s in ss)
        negv = (r"(?i)\b(?:don't|doesn't|do not|does not|never|won't|will not|aren't|isn't|are not|is not)\s+"
                r"(?:\w+\s+){0,3}?(?:count|counted|stop|stops|block|blocks|hold|holds|matter)\b")
        others = all(any(lab in s and re.search(negv, s) for s in ss) for lab in (L_UNSAVED, L_NEW))
        self.assertTrue(only or others, 'PHASE 5 does not say only hits under %s count (this send carries saved '
                                        'changes only), or that hits under %s / %s do not stop it'
                        % (L_SAVED, L_UNSAVED, L_NEW))

    def _fails_closed(self, prose):
        self._rule(prose, lambda u: (re.search(r"(?i)\bexit 2\b|any other exit|anything else|anything but"
                                               r"|couldn't check|could not check", u) and self._stops(u)), [
            (self.SENT_NONE, "it doesn't say nothing is sent"),
            (re.escape("I couldn't check your changes for secrets"), "it doesn't use 3e's could-not-check message"),
        ], "a scan that couldn't check (exit 2, a timeout, a missing label)")
        ss = self._all_sentences(prose)
        self.assertTrue(any(re.search(r'(?i)\d+[- ]second time-?out|\bwith an? time-?out|time-?out of \d|time limit', s)
                            for s in ss), 'PHASE 5 does not give the scan a timeout')
        self.assertFalse(any(re.search(r'(?i)\bno time-?out|without (?:a |any )?time-?out|never times? out', s)
                             for s in ss), 'PHASE 5 runs the scan with no timeout')
        self.assertTrue(any(re.search(r'\b3e\b', s) and re.search(r'(?i)\b(?:as|same|like|per|follows?|exactly)\b', s)
                            and not re.search(r'(?i)\bunlike\b|\bdifferent|\binstead of\b', s) for s in ss),
                        "PHASE 5 does not read the scan's result by 3e's rules")

    def _never_quotes_a_hit(self, prose):
        for s in self._all_sentences(prose):
            if re.search(r"(?i)\b(?:never|don't|do not|not|nothing|no)\b", s):
                continue
            self.assertNotRegex(s, r'(?i)\b(?:quote|quoting|repeat|echo|print|display|show|paste)\b(?:\s+\S+){0,5}?\s+'
                                   r'(?:lines?|values?|contents?|text)\b(?!\s*\[N\])',
                                'PHASE 5 tells the agent to show a hit line or value: %r' % s)

    def _plain_words(self, prose):
        qs = re.findall(r'"(I[^"]{20,})"', self._flat(prose))
        self.assertTrue(qs, 'PHASE 5: the scan gives the user no stop message')
        for q in qs:
            q = re.sub(r'--\s*only if[^\]]*\]', ']', re.sub(r'\[(?:If|if|Only|only)\b[^:\]]*:', '[', q))
            self.assertNotRegex(q, self.NEVER_SAY, 'a stop message uses a word from the NEVER-say list: %r' % q)

    # --- running PHASE 5's blocks as written ----------------------------------------------------------------
    def _run(self, cwd, shell):
        need_shell(shell)
        code = self._scan(self._phase())[2]
        self.assertIn(INSTALLED, code, 'the PHASE 5 scan does not make the call 3e makes (%s)' % INSTALLED)
        cp = subprocess.run([shell, '-c', code.replace(INSTALLED, SCRIPT)], cwd=cwd, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=180)
        return Result(cp, 0)

    def _prep(self, r, hooks=None):
        """The fixture's own settings for PHASE 5's plain `git`: a name, no signing, and its own hooks folder (an
        empty one unless a test brings a hook), so this machine's hooks play no part."""
        if hooks is None:
            hooks = os.path.join(r.root, 'no-hooks')
            os.makedirs(hooks, exist_ok=True)
        for k, v in (('user.name', 't'), ('user.email', 't@t'), ('commit.gpgsign', 'false'), ('core.hooksPath', hooks)):
            r.git('config', k, v)

    def _generate(self, r, extra=None):
        """argo-it's generated files (plus `extra`), written but unsaved, as PHASE 5 finds them. Returns their names."""
        files = dict(self.GENERATED)
        files.update(extra or {})
        for rel, text in files.items():
            r.write(rel, text)
        return sorted(files)

    def _save_block(self, p):
        """(start, end, code) of argo-it's save: the one ```bash block in PHASE 5 (or `p`) that runs `git commit`.
        It saves on "Send it" now (owner, 2026-10-19, after review 3), so it no longer has to sit before the ask."""
        saves = [f for f in self._fences(p) if re.search(r'\bgit\s+(?:(?:-c\s+\S+|--no-replace-objects)\s+)*commit\b',
                                                         '\n'.join(l for l in f[2].splitlines()
                                                                   if not l.lstrip().startswith('#')))]
        self.assertEqual(len(saves), 1, "PHASE 5: argo-it's files aren't saved by one ```bash block (%d found)"
                         % len(saves))
        return saves[0]

    @staticmethod
    def _files_filled(code, files):
        """`code` with its files placeholder (a `{...}` whose name holds "file") filled with `files`, by name."""
        return re.sub(r'(?<!\$)\{([A-Za-z_][\w-]*)\}',
                      lambda m: ' '.join(files) if 'file' in m.group(1).lower() else m.group(0), code)

    def _step1(self, r, extra=None):
        """argo-it's generated files (plus `extra`), then PHASE 5's save block as written (its files placeholder
        filled with them, by name; a `{...}` naming a commit -- head, commit or sha -- filled with HEAD: the save runs
        right after a check that saw HEAD, as on "Send it"). Returns the commit it saved: the id it prints last, else
        HEAD (owner, after review 6: the save is built with git's low-level commands and moves no branch). That commit
        sits on HEAD and holds each of argo-it's files as it is on disk."""
        self._prep(r)
        files = self._generate(r, extra)
        head = r.git('rev-parse', 'HEAD').strip().decode()
        code = re.sub(r'(?<!\$)\{([A-Za-z_][\w-]*)\}', lambda m: head if re.search(r'(?i)head|commit|sha', m.group(1))
                      else m.group(0), self._files_filled(self._save_block(self._phase())[2], files))
        self.assertNotRegex(code, r'(?<!\$)\{[A-Za-z_][\w-]*\}', 'an unknown placeholder in the save block: %r' % code)
        cp = subprocess.run(['bash', '-c', code], cwd=r.work, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
        self.assertEqual(cp.returncode, 0, 'the save did not run: %r' % cp.stderr[:300])
        out = cp.stdout.decode().split()
        sha = out[-1] if out and re.fullmatch(r'[0-9a-f]{40,64}', out[-1]) else r.git('rev-parse', 'HEAD').strip().decode()
        self.assertEqual(r.git('rev-parse', sha + '^').strip().decode(), head, "argo-it's save doesn't sit on HEAD")
        for f in files:
            with open(r.path(f), 'rb') as fh:
                self.assertEqual(r.git('cat-file', 'blob', '%s:%s' % (sha, f)), fh.read(),
                                 "argo-it's save doesn't hold %s as it is on disk" % f)
        return sha

    def _both(self, cwd, **kw):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                self.check(self._run(cwd, shell), **kw)

    # --- 1. where the scan runs, and how it is read -------------------------------------------------------
    def test_1a_scan_runs_after_step_2_and_before_the_step_3_ask(self):
        p = self._phase()
        start, end, _ = self._scan(p)
        self.assertGreater(start, self._step_block(p, 2)[1], 'the scan runs before step 2 is done')
        self.assertLess(end, self._ask_at(p), 'the scan runs after the step-3 ask is shown')

    def test_1b_scan_block_runs_as_written_and_surfaces_every_exit_under_bash_and_zsh(self):
        self._both(self.fresh().work)  # clean: the three labels, exit 0
        with tempfile.TemporaryDirectory() as td:
            for shell in ('bash', 'zsh'):
                with self.subTest(shell=shell, where='not a repo'):
                    res = self._run(os.path.realpath(td), shell)
                    self.assertEqual(res.code, 2, 'exit 2 swallowed: out=%r err=%r' % (res.out, res.err[:200]))
        for ln in self._scan(self._phase())[2].splitlines():
            if 'secret-scan.py' in ln and not ln.lstrip().startswith('#'):
                self.assertNotRegex(ln, r'\|\||;\s*true|\|\s*\w|\bset \+e|&\s*$', 'masks the exit: %r' % ln)

    def test_1c_result_is_read_by_3e_rules_and_anything_else_stops_with_nothing_sent(self):
        self._fails_closed(self._prose())

    # --- 2. only saved-not-sent hits count ----------------------------------------------------------------
    def test_2_unsaved_and_new_hits_are_listed_but_do_not_stop_the_first_send(self):
        r = self.fresh()
        u, n = fake('unsavedfirst1'), fake('newfilefirst2')
        r.append('app.py', kv('PASS' + 'WORD', u))
        r.write('config.py', kv('TO' + 'KEN', n))
        self._step1(r)  # its `git add` names only argo-it's files: the edit and config.py stay unsaved
        self._both(r.work, unsaved=['app.py:2'], new=['config.py:1'], secrets=[u, n])
        self._only_saved_counts(self._prose())

    # --- 3. a saved hit stops, in 3e's words; a generated file is argo-it's mistake ------------------------
    def test_3a_saved_hit_hides_the_ask_sends_nothing_and_uses_3e_wording(self):
        self._saved_hit_stops(self._prose())

    def test_3b_hit_in_a_file_argo_it_just_generated_is_checked_before_the_save_and_called_argo_its_mistake(self):
        v = fake('generated9876')
        rel = 'env/dev/app-config.yaml'
        r = self.fresh()
        self._generate(r, {rel: 'apiVersion: v1\nkind: ConfigMap\ndata:\n  ' + kv('DB_' + 'PASS' + 'WORD', v, sep=': ')})
        self._both(r.work, new=[rel + ':4'], secrets=[v])  # checked before argo-it saves (owner, 2026-10-19): new
        self._generated_is_a_mistake(self._prose())

    def test_3c_stops_never_quote_a_hit_and_speak_plain_words(self):
        self._scan(self._phase())
        prose = self._prose()
        self._never_quotes_a_hit(prose)
        self._plain_words(prose)

    # --- 4. the ask still names the other unsent saved changes ---------------------------------------------
    def test_4_control_step_3_ask_still_names_the_other_unsent_saved_changes(self):  # control: passes today
        p = self._phase()
        self.assertIn('git log --oneline HEAD --not ', self._step_block(p, 2)[2])  # against what GitHub has (call A)
        ask = self._flat(p[self._ask_at(p):p.find(self.PICK)])
        # argo-it saves after step 2's list now (owner, 2026-10-19), so the list holds only the user's own changes
        self.assertRegex(ask, r'(?i)\[If step 2 listed (?:any )?saved changes\b')
        self.assertRegex(ask, r"(?i)this also sends the \[M\] other saved changes you haven't sent yet")

    # --- 5. no path in PHASE 5 reaches a push without the scan --------------------------------------------
    def test_5a_every_push_and_every_jump_in_phase_5_sits_behind_the_scan(self):
        p = self._phase()
        start, end, _ = self._scan(p)
        ask = self._ask_at(p)
        pushes = [f[0] + m.start() for f in self._fences(p) for m in re.finditer(r'(?m)^\s*git\s+push\b', f[2])]
        self.assertTrue(pushes, 'PHASE 5 has no git push to walk to')
        for at in pushes:
            self.assertGreater(at, max(end, ask), 'a git push in PHASE 5 comes before the scan or the step-3 ask')
        prose = re.sub(self.FENCE, lambda m: ' ' * len(m.group(0)), p, flags=re.M | re.S)
        for m in re.finditer(r'(?i)\b(?:go(?:es)?|skip(?:s|ping)?|jump(?:s)?|return(?:s)?|continue(?:s)?|proceed(?:s)?'
                             r'|move(?:s)? on|head(?:s)?)\s+(?:back\s+|straight\s+|on\s+|directly\s+|right\s+)?to\s+'
                             r'(?:the\s+)?step[- ]?(\d)', prose):
            if m.start() < start:
                self.assertLess(int(m.group(1)), 3, 'jumps past the scan: %r' % m.group(0))
        backs = [m.start() for m in re.finditer(r'go back to the step-3 pick', prose)]
        self.assertEqual(len(backs), 2, 'options 2 and 3 no longer go back to the step-3 pick')
        self.assertTrue(all(b > ask for b in backs))

    def test_5b_control_nothing_outside_phase_5_enters_it_past_step_2(self):  # control: passes today
        doc = ArgoItWiringCases._doc(self)
        p = self._phase()
        rest = doc.replace(p, '')
        self.assertNotRegex(rest, r'(?i)PHASE 5(?![bc0-9])[^.\n]{0,60}\bsteps?[- ]?[3-9]|step-3 pick|Option 1 \(send')

    # --- 6. an older unsent commit holds a secret: the scan names it, the text stops -----------------------
    def test_6_older_unsent_commit_with_a_secret_is_listed_as_saved_and_routes_to_the_stop(self):
        v = fake('olderunsent42')
        r = self.fresh()
        r.append('app.py', kv('API_' + 'KEY', v))
        r.commit('older change, never sent')
        self._step1(r)
        self._both(r.work, saved=['app.py:2'], secrets=[v])
        self._saved_hit_stops(self._prose())

    # --- polarity: each prose check passes a plain reading and fails its plain opposite ----------------------
    GOOD = '\n'.join((
        '**2b. Check what this send carries for secrets** -- the same check PHASE 5b step 3e runs:',
        '',
        'Run it from the project root with a 120-second timeout, and read the result exactly as 3e does.',
        'Only hits under `== saved, not sent ==` count here: this send carries saved changes only, so a hit',
        "under `== unsaved edits ==` or `== new files ==` doesn't stop it.",
        '',
        "- **Anything else** (3e's could-not-check case: exit 2, a timeout, a label missing or repeated): stop --",
        "  don't show the step-3 ask. Tell the user:",
        '',
        "  \"I couldn't check your changes for secrets, so I haven't sent anything. [the reason, in plain words]\"",
        '',
        "**If any hit sits under `== saved, not sent ==`: stop here.** Don't show the step-3 ask; nothing is",
        'sent. Name each hit only by its file and line number, and never show or quote any part of the line.',
        '',
        "\"I found what looks like a password or secret key in a change you already saved but haven't sent yet:",
        '**line [N] of [file]**. [If the file is one I generated in step 1: That one is a mistake on my side,',
        "not something you did.] Secrets should never be saved in code, so I won't send this.\"",
        ''))

    def test_7_control_prose_checks_are_polarity_bound(self):  # control: passes today
        checks = {
            '_only_saved_counts': [(
                'Only hits under `== saved, not sent ==` count here: this send carries saved changes only, so a hit\n'
                "under `== unsaved edits ==` or `== new files ==` doesn't stop it.",
                'Hits under `== saved, not sent ==`, `== unsaved edits ==` and `== new files ==` all count here, so a\n'
                'hit under any of them stops it too.')],
            '_saved_hit_stops': [
                ("stop here.** Don't show the step-3 ask; nothing is\nsent.",
                 'name it in the step-3 ask and let the user pick.** Then show the\nstep-3 ask.'),
                ("stop here.** Don't show the step-3 ask; nothing is\nsent.",
                 'stop here.** Then show the step-3 ask anyway and send it.'),
                ('in a change you already saved but', 'in a change you just made but')],
            '_generated_is_a_mistake': [(
                'That one is a mistake on my side,\nnot something you did.]',
                'That one is expected, not a mistake --\ngo on to step 3.]')],
            '_fails_closed': [
                (": stop --\n  don't show the step-3 ask.", ': go on to the step-3 ask anyway.'),
                ('with a 120-second timeout', 'with no timeout'),
                ('the same check PHASE 5b step 3e runs', 'a new check'),
                ("so I haven't sent anything.", 'so I sent it anyway.')],
            '_never_quotes_a_hit': [(
                'Name each hit only by its file and line number, and never show or quote any part of the line.',
                "Show the user each hit's line so they can see which one it is.")],
            '_plain_words': [("so I won't send this.", "so I won't push this commit.")],
        }
        for name, swaps in checks.items():
            check = getattr(self, name)
            with self.subTest(check=name, text='plain reading'):
                check(self.GOOD)
            for good, opposite in swaps:
                self.assertIn(good, self.GOOD)
                bad = self.GOOD.replace(good, opposite)
                if name == '_fails_closed' and good.startswith('the same check'):
                    bad = bad.replace('exactly as 3e does', 'unlike 3e does')
                with self.subTest(check=name, opposite=opposite):
                    with self.assertRaises(AssertionError):
                        check(bad)


# ArgoItFirstSendScanCases' helpers (not its tests, which would run twice), for the fix round below.
_FirstSend = type('_FirstSend', (object,), {k: v for k, v in ArgoItFirstSendScanCases.__dict__.items()
                                            if not k.startswith(('test', '__'))})


class ArgoItFirstSendFix1Cases(_FirstSend, Base):
    """Task 3 review 1: an ExternalSecret's `secretKey: SETTING_NAME` is a reference in YAML (owner, 2026-10-19), so
    argo-it's own template passes the first-send scan; Option 1 never pushes a local deploy branch 2b didn't scan;
    step 1 saves only argo-it's files; and 2b's go-on rule, its pointer to 3e, its re-run, its registry advice and
    its "whatever they say" are bound.  Prose checks are proven against their plain opposites in test_9.  Values
    and secret-named lines are joined at run time (GitGuardian scans this file)."""

    SK = 'secret' + 'Key'  # ESO's field: an ExternalSecret's `- secretKey: NAME` names a setting, not its value
    NAMES = ('DATABASE_' + 'PASSWORD', 'JWT_' + 'SECRET', 'S3_SECRET_ACCESS_' + 'KEY', 'DB_PASS_2')
    DEPLOY = 'deploy-nonprod'
    GO_ON = (r'(?i)\b(?:go(?:es)?|going|move[sd]?|carr(?:y|ies))\s+on\s+to\s+(?:the\s+)?step[- ]?3\b'
             r'|\b(?:continue|proceed)s?\s+(?:on\s+)?to\s+(?:the\s+)?step[- ]?3\b'
             r'|\bshow(?:s|ing)?\s+the\s+step[- ]?3\s+(?:ask|pick)\b')
    WIDE = (r"(?i)\bany (?:other )?(?:exit|result|code)\b|\btime-?outs?\b|\btime limit\b|\banything else\b|\bwhatever\b"
            r"|\bregardless\b|\bno matter\b|\beven (?:if|when|with)\b|\bor not\b|\bcould(?:n't| not) check\b")
    COPIED = (r'(?i)\bany other exit\b', r'(?i)\btime-?out\b',
              r'(?i)\blabels?\b[^.;)]{0,12}\b(?:missing|repeated)\b|\b(?:missing|repeated)\s+labels?\b',
              r'(?i)\bstray line\b|\bneither a label nor\b', r'(?i)\bexit 1 with no hits?\b')
    CLAUSE = (r'(?i)\bwhatever (?:they|the user) (?:says?|asks?(?: for)?|wants?)\b'
              r'|\beven if (?:they|the user) (?:says?|asks?|insists?|wants?)\b')

    def _negated(self, t, at):
        return re.search(r'(?i)(?:\b' + self.NEG + r'|\bwithout)\s+(?:\w+\s+){0,2}$', t[:at])

    # --- 1. Important 1: `secretKey: SETTING_NAME` in YAML is a reference --------------------------------------
    def _sk(self, values, dash=True):
        return ''.join('  %s%s: %s\n' % ('- ' if dash else '', self.SK, v) for v in values)

    def test_1a_secretkey_setting_name_in_yaml_is_no_hit_under_any_label(self):
        r = self.fresh()
        r.write('k8s/unsaved.yml', 'data:\n')
        r.commit('tracked')
        r.push()
        r.write('k8s/saved.yaml', 'data:\n' + self._sk(self.NAMES))
        r.commit('external secret, never sent')
        r.append('k8s/unsaved.yml', self._sk(self.NAMES))
        top = ''.join('%s: %s\n' % (self.SK, n) for n in self.NAMES)
        r.write('k8s/new.yaml', top + 'data:\n' + self._sk(self.NAMES))
        v = fake('MixedCase77')
        r.write('k8s/mixed.yaml', 'data:\n' + self._sk([self.NAMES[0], v]))  # the exemption is per value, not per file
        self.check(r.scan(), new=['k8s/mixed.yaml:3'], secrets=[v])

    def test_1b_control_other_secretkey_values_and_other_names_still_hit_in_yaml(self):  # control: passes today
        r = self.fresh()
        mixed = fake('MixedCase77')
        vals = [mixed, '2024' + '_1019_7788', 'DATABASE-' + 'PASSWORD', 'database_' + 'password_x']  # no letter, -, a-z
        names = ['secret_' + 'key', 'app' + 'SecretKey', 'SECRET_' + 'KEY']  # only the exact name `secretKey`
        r.write('k8s/unsaved.yml', 'data:\n')
        r.commit('tracked')
        r.push()
        r.write('k8s/saved.yaml', 'data:\n' + self._sk([mixed]))
        r.commit('never sent')
        r.append('k8s/unsaved.yml', self._sk([mixed]))
        others = ''.join('  - %s: %s\n' % (n, self.NAMES[0]) for n in names)
        r.write('k8s/new.yaml', 'data:\n' + self._sk(vals) + others)
        self.check(r.scan(), unsaved=['k8s/unsaved.yml:2'], new=['k8s/new.yaml:%d' % i for i in range(2, 9)],
                   saved=['k8s/saved.yaml:2'], secrets=[mixed])

    def test_1c_control_secretkey_setting_name_outside_yaml_still_hits(self):  # control: passes today
        r = self.fresh()
        n = self.NAMES[0]
        r.write('.env.production', '%s=%s\n' % (self.SK, n))
        r.commit('env, never sent')
        files = {'app.properties': '%s: %s\n' % (self.SK, n), 'settings.toml': kv(self.SK, n),
                 'setup.ini': '%s = %s\n' % (self.SK, n), 'config.py': kv(self.SK, n),
                 'config.json': '{"%s": "%s"}\n' % (self.SK, n)}
        for rel, text in files.items():
            r.write(rel, text)
        self.check(r.scan(), new=sorted(rel + ':1' for rel in files), saved=['.env.production:1'])

    def _external_secret(self, env, names):
        """argo-it's own ExternalSecret template (PHASE 2), its `- secretKey:` entry once per name, filled in."""
        m = re.search(r'^### \{app\}-external-secret\.yaml[^\n]*\n+```yaml\n(.*?)^```', ArgoItWiringCases._doc(self),
                      re.M | re.S)
        self.assertTrue(m, 'argo-it.md: no ExternalSecret template under "### {app}-external-secret.yaml"')
        t = m.group(1)
        self.assertIn('kind: ExternalSecret', t)
        i = t.find('- %s: {VAR_NAME}' % self.SK)
        self.assertNotEqual(i, -1, 'the ExternalSecret template has no "- %s: {VAR_NAME}" entry' % self.SK)
        i = t.rfind('\n', 0, i) + 1
        out = t[:i] + ''.join(t[i:].replace('{VAR_NAME}', n) for n in names)
        for k, v in (('{app}', 'myapp'), ('{env}', env), ('{namespace}', 'myteam-' + env), ('{team-name}', 'myteam'),
                     ('{secret_server_path}', 'apps/myapp/' + env)):
            out = out.replace(k, v)
        self.assertNotRegex(out, r'\{[A-Za-z_][\w-]*\}', 'a placeholder in the ExternalSecret template is not filled')
        return out

    def test_1d_argo_its_own_external_secret_passes_the_first_send_scan(self):
        names = self.NAMES + ('OIDC_CLIENT_' + 'SECRET',)
        r = self.fresh()
        files = {'env/%s/myapp-external-secret.yaml' % e: self._external_secret(e, names) for e in ('dev', 'prod')}
        self._generate(r, files)
        self._both(r.work)  # 2b checks before argo-it saves (owner, 2026-10-19): new files, and clean
        sha = self._step1(r, files)
        if ArgoItFirstSendFix5Cases._commit_call(self, need=False):  # the check of the commit the push sends (owner,
            for shell in ('bash', 'zsh'):  # after review 6): argo-it's save, saved and not sent, is clean too
                with self.subTest(shell=shell):
                    self.check(ArgoItFirstSendFix5Cases._check_commit(self, r.work, shell, sha))
        else:
            self._both(r.work)  # once saved (saved, not sent), as a check again before a push sees it: clean too

    # --- 2. Important 2: Option 1 pushes what 2b scanned, never a local deploy branch --------------------------
    def _fill(self, code, files=(), saved=None, mem=None):
        """PHASE 5's placeholders: the branches; a `{...}` the text said to remember (`mem`, by name: `_flow`); a
        `{...}` naming files (its name holds "file") = argo-it's files, by name; with `saved`, a `{...}` naming a commit
        (its name holds head, commit or sha) = `saved`. Any other placeholder fails."""
        for k, v in (('{deploy_branch}', self.DEPLOY), ('{current_branch}', 'main'), ('{previous_branch}', 'main'),
                     ('{manifest_dir}', 'env')):
            code = code.replace(k, v)
        if mem:
            code = re.sub(r'(?<!\$)\{([A-Za-z_][\w-]*)\}', lambda m: mem.get(m.group(1), m.group(0)), code)
        code = self._files_filled(code, files) if files else code
        if saved:
            code = re.sub(r'(?<!\$)\{([A-Za-z_][\w-]*)\}', lambda m: saved if re.search(
                r'(?i)head|commit|sha', m.group(1)) else m.group(0), code)
        self.assertNotRegex(code, r'(?<!\$)\{[A-Za-z_][\w-]*\}', 'an unknown placeholder in %r' % code)
        return code

    def _option_1(self, p):
        """(start, end, code) of Option 1's ```bash block."""
        i = p.find('**Option 1 (send')
        self.assertNotEqual(i, -1, 'PHASE 5: no "**Option 1 (send" block')
        for f in self._fences(p):
            if f[0] > i:
                return f
        self.fail('PHASE 5: no ```bash block after Option 1')

    def _origin(self, r, *args):
        return subprocess.run(['git', '--git-dir', os.path.join(r.root, 'origin')] + list(args),
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout

    def _ref(self, r, branch):
        return self._origin(r, 'rev-parse', '-q', '--verify', 'refs/heads/' + branch).strip().decode()

    def _sent_objects(self, r):
        return self._origin(r, 'cat-file', '--batch-all-objects', '--batch')

    def _counted(self, res, files, sub=''):
        """2b's result read as 3e reads it, then by the owner's rule (2026-10-19), as PHASE 5 words it: None = go on,
        else why it stops. A hit counts under == saved, not sent ==, or in any file the save will save (`files`, named
        from the project root, `sub` below the repo's top), whatever its label. A hit's path is printed from the repo's
        top: it is matched to `files` from there only if PHASE 5 says so (`_from_top`), else by the name as given; an
        escaped path (\\xNN, \\uXXXX) counts only if PHASE 5 says it does (`_escaped_counts`)."""
        labels = [L_UNSAVED, L_NEW, L_SAVED]
        ls = res.lines
        hits = [x for x in ls if x not in labels]
        if (res.code not in (0, 1) or [x for x in ls if x in labels] != labels or ls[:1] != [L_UNSAVED]
                or bool(hits) != (res.code == 1) or not all(re.match(r'.+:[0-9]+$', h) for h in hits)):
            return "couldn't check"
        if ls[ls.index(L_SAVED) + 1:]:
            return 'a hit counts'
        prose = re.sub(self.FENCE, '', self._phase(), flags=re.M | re.S)
        if any(re.search(r'\\x[0-9a-f]{2}|\\u[0-9a-f]{4}', h) for h in hits) and self._escaped_counts(prose):
            return 'a hit counts'
        base = sub.rstrip('/') + '/' if sub and self._from_top(prose) else ''
        if any(h.rsplit(':', 1)[0] in {base + f for f in files} for h in hits):
            return 'a hit counts'
        return None

    # --- reading PHASE 5's instructions as an agent does (`_flow`; each reader is polarity-bound in Fix2 test_5) ---
    TOP = (r"(?i)\b(?:the\s+)?repo(?:sitory)?'s\s+top(?:-level)?(?:\s+folder)?\b|\btop\s+(?:folder|level)\s+of\s+the\s+"
           r"repo|--show-toplevel")
    MARKER = r'`([A-Z][A-Z0-9]*(?: [A-Z0-9]+)+)`'  # a line a block prints, as the text names it: `SAVE FAILED`
    MARK_LINE = r'[A-Z][A-Z0-9]*(?: [A-Z0-9]+)+'
    NO_HIT = (r"(?i)(?:if|when|once)\s+(?:no\s+hits?\s+(?:counts?|stops?)|nothing\s+counts|(?:it|the check)(?:'s|\s+is"
              r"|\s+comes back)\s+clean)\b")
    STOP_BRANCH = (r"(?i)(?:if|when|on)\s+(?:a\s+|any\s+|the\s+)?(?:hits?\s+(?:counts?|stops?)|stop\b|check\s+stops"
                   r"|it\s+stops)")
    CHECK_AGAIN = (r"(?i)(?:^|[,:(]\s*|--\s*|\b(?:and|then|first|now|so)\s+)(?:run|re-?run|repeat)\s+(?:(?:2b's|the"
                   r"|this|that|its|the same)\s+)?(?:(?:step\s+)?2b(?:'s\s+(?:check|block))?|(?:secret\s+)?(?:check"
                   r"|scan))\s+(?:again|once more|a second time)\b")
    CHECK_AGAIN_P = r"(?i)\b(?:2b|the (?:secret )?check|this check|the scan)\s+(?:runs|is run|is re-?run)\s+again\b"
    REMEMBER = r'(?i)\bremember\s+(?P<what>[^;]{0,160}?)\s+as\s+`?\{(?P<name>[A-Za-z_][\w-]*)\}`?'
    # "remember `a` as `{X}` and `b` as `{Y}`": each "and `cmd` as `{Y}`" right after a REMEMBER
    REMEMBER_AND = r'\s*,?\s*(?:and\s+)?(?P<what>`git\s[^`]+`)\s+as\s+`?\{(?P<name>[A-Za-z_][\w-]*)\}`?'
    REASK = (r"(?i)\bshow\s+(?:the user\s+)?the\s+(?:step-3\s+)?(?:ask|pick)\s+(?:again|once more)\b"
             r"|\bask\s+(?:the user\s+)?(?:again|once more)\b")
    RESTART = (r"(?i)\b(?:start|run|begin|follow|go through|redo)\s+(?:this\s+)?Option 1\s+(?:again|over)\b"
               r"|\b(?:back to|from)\s+the\s+(?:top|start)\s+of\s+Option 1\b")
    BACK2 = (r"(?i)\b(?:run|re-?run|redo|repeat|follow|go through)\s+(?:(?:from|through)\s+)?step[- ]2\b"
             r"|\bback\s+to\s+step[- ]2\b|\bfrom\s+step[- ]2\b")
    RERUN = (r"(?i)\b(?:run|re-?run|try)\s+(?:this|that|the same|the save|2c's|its)\s+(?:save\s+)?block\s+again\b"
             r"|\b(?:run|re-?run)\s+2c\s+again\b")
    # "write `{deploy_branch}` ... to `$(git rev-parse --git-dir)/x`": the agent's file tool puts a branch name in a file,
    # so no shell command ever holds it (owner, after review 6: every branch name is read into a quoted variable)
    WRITE = (r"(?i)\b(?:write|store|put)\s+(?:the\s+\w+\s+branch's\s+name,?\s+)?`?\{(?P<name>[\w-]*branch[\w-]*)\}`?"
             r"[^.;`]{0,80}?\b(?:to|in|into)\s+(?:the\s+file\s+)?`(?P<path>[^`]+)`")

    def _from_top(self, prose):
        """PHASE 5 says a hit is matched to the files the save names by its path from the repo's top folder."""
        for s in self._all_sentences(prose):
            m = re.search(self.TOP, s)
            if m and not re.search(r"(?i)\b(?:not|never|isn't|rather than|instead of)\b[^,.;()]{0,30}$",
                                   s[:m.start()]) and re.search(
                    r"(?i)\bin (?:a|any|one of the|the) files?\b[^.]{0,60}?\b(?:2c|save|saves|saved)\b"
                    r"|\b(?:argo-it's|generated)\b[^.]{0,30}\bfiles?\b|\b2c\b", s):
                return True
        return False

    def _escaped_counts(self, prose):
        """PHASE 5 says a hit whose path holds \\xNN or \\uXXXX counts (or stops this send)."""
        neg = (r"(?i)\b(?:doesn't|does not|don't|do not|never|won't|isn't|is not|aren't|not)\s+(?:\w+\s+){0,2}?"
               r"(?:count|stop)")
        return any(re.search(r'\\xNN|\\uXXXX', s) and re.search(r'(?i)\bcounts?\b|\bstops?\b', s)
                   and not re.search(neg, s) for s in self._all_sentences(prose))

    def _option_at(self, p, n):
        """(start, end) of PHASE 5's "**Option n (" section."""
        i = p.find('**Option %d (' % n)
        self.assertNotEqual(i, -1, 'PHASE 5: no "**Option %d (" section' % n)
        ends = [k for k in (p.find('**Option ', i + 2), p.find('\n**5. ', i)) if k != -1]
        return i, min(ends) if ends else len(p)

    @staticmethod
    def _git_does(code, verb):
        # `git -c k=v verb` and `git --no-replace-objects verb` too
        return re.search(r'(?m)^[^#\n]*\bgit\s+(?:(?:-c\s+\S+|--no-replace-objects)\s+)*(?:%s)\b' % verb, code)

    def _script(self, p, a, b):
        """PHASE 5 from a to b as the agent meets it, in order: ('fence', code) and ('say', clause, scope). A clause is a
        sentence or `;` part of the prose, with ** and the quoted messages to the user taken out. scope: None (read on
        the way), 'skip' (a branch `_flow` doesn't take: an "If ..." it can't decide), or the markers (`MARKER`) the
        clause is the rule for -- from the clause that names them to an "Otherwise", a bold heading or a block."""
        items, pos, scope = [], a, None
        for f in [f for f in self._fences(p) if a <= f[0] < b] + [(b, b, None)]:
            prose = re.sub(r'"(?:I|Pushed|Your)[^"]{20,}"', ' . ', p[pos:f[0]])
            for u in self._units(prose):
                if re.match(r'(?:[-*]\s+)?\*\*', u):
                    scope = None
                for s in self._sentences(u.replace('**', '')):
                    for c in (x.strip() for x in s.split('; ')):
                        if not c or c == '.':
                            continue
                        ms = frozenset(re.findall(self.MARKER, c))
                        if ms:
                            scope = ms
                        elif re.match(r'(?i)(?:otherwise|else)\b', c):
                            scope = None
                        elif scope is None and re.match(r'(?i)(?:if|when|once|unless)\b', c) and not re.match(
                                self.NO_HIT, c):
                            items.append(('say', c, 'skip'))
                            if not re.match(self.STOP_BRANCH, c):
                                scope = 'skip'
                            continue
                        items.append(('say', c, scope))
                if scope == 'skip':
                    scope = None
            if f[2] is not None:
                items.append(('fence', f[2]))
                scope = None
            pos = f[1]
        return items

    def _instr(self, c, rule=False):
        """The instructions in clause `c` that `_flow` acts on, in order: remember (a `{...}`, and each "and `cmd` as
        `{...}`" after it), check (run 2b again), write (a branch name put in a file by the agent's file tool), and in a
        marker's rule (`rule`) also restart (Option 1 again), reask (the step-3 ask again), step2 (run step 2 again) and
        rerun (this block)."""
        out = []
        for m in re.finditer(self.REMEMBER, c):
            if self._negated(c, m.start()):
                continue
            out.append((m.start(), 'remember', m))
            more = re.compile(self.REMEMBER_AND).match(c, m.end())
            while more:
                out.append((more.start(), 'remember', more))
                more = re.compile(self.REMEMBER_AND).match(c, more.end())
        out += [(m.start(), 'check', m) for m in re.finditer(self.CHECK_AGAIN, c)]
        out += [(m.start(), 'write', m) for m in re.finditer(self.WRITE, c) if not self._negated(c, m.start())]
        if rule:
            out += [(m.start(), 'check', m) for m in re.finditer(self.CHECK_AGAIN_P, c)]
            out += [(m.start(), k, m) for k, rx in (('restart', self.RESTART), ('reask', self.REASK), ('step2', self.BACK2),
                                                    ('rerun', self.RERUN))
                    for m in re.finditer(rx, c) if not self._negated(c, m.start())]
        return sorted(out, key=lambda x: x[0])

    def _flow(self, r, shell, files, between=None, hooks=None, after_check=None, picks=(1,), after_pick=None, sub='',
              after_guard=None, after_first_check=None, after_save=None, before_push=None, unreadable=False):
        """PHASE 5 followed as written (`_script`): every ```bash block before the step-3 ask, in order, and the prose
        between them; at the ask, the text from the ask to Option 1 (what to remember there), then `between` (what the
        user does while the agent waits); then each pick in `picks` (1 = Send it), its Option's section followed the
        same way, and `after_pick(n)` after a pick that goes back to the ask (2, 3). Option 2's docker/kubectl blocks
        don't run here; one with `git` in it does.
        - A block that runs secret-scan.py is a check, run as written (its placeholders filled: a commit id it is
          given is what it read, else HEAD); a clause that says to run 2b (the check) again runs 2b's block. Each is
          read by `_counted`; a stop ends the flow. `after_check` (one callable, or a list fired one per check) runs
          right after a clean check once the ask has been shown; the first one also runs right before the save block if
          no check ran before it -- the moment between the check and argo-it's save. `after_guard` (one callable, or a
          list fired one per run of the save block) runs right before the save block, even after a clean check: the
          moment after Option 1's guards and before argo-it's save. `after_first_check` runs once, right after the
          first clean check before the ask is shown. `after_save` (one callable, or a list fired one per save) runs right
          after argo-it's save block saved (exit 0, no marker); `before_push` (the same) right before a block that
          pushes. `unreadable`: a check run after argo-it's save in this pick can't be read (as a timeout or a garbled
          result would be), so 3e's third bullet covers it.
        - The save block is the one that runs `git commit` (or `git commit-tree`); what it saved is the commit id it
          printed last, else HEAD after it.
        - "remember ... as `{X}`" fills {X}: with what the `git ...` command it names prints (its stdout: `HEAD` in a
          repo with no commits yet), with the commit id the block before it printed (its last line), or with HEAD there
          and then. "write `{..branch..}` ... to `path`" writes that placeholder's value (`_fill`'s), alone on a line, to
          that file (the path as the shell expands it), as the agent's file tool would.
        - A block that prints a marker line (`SAVED SINCE THE CHECK`) is handled by the text's rule for it: a check
          again and what to remember, then this block again (rerun), Option 1 again (restart), or the step-3 ask again
          (reask: with "run step 2 again", step 2 and 2b run again first), which takes the next pick in `picks`; a rule
          that does none of these is a stop (`failed`). Any other block that fails after the pick stops the flow.
        Returns a dict: start (HEAD before), refs (origin's refs before), ask (head, refs, status at the first ask, or
        None), asks (each ask shown), scanned (what the last check read), res (its result), results (every check's
        result, in order), saved (what argo-it's save saved), stopped (why, or None), failed (the marker of the rule
        that stopped it), sent (the last push block's run), trace, outputs, mem."""
        need_shell(shell)
        self._prep(r, hooks)
        p = self._phase()
        ask = self._ask_at(p)
        opt1 = self._option_at(p, 1)[0]
        scan = self._scan(p)[2]
        self.assertIn(INSTALLED, scan, 'the PHASE 5 check does not make the call 3e makes (%s)' % INSTALLED)
        cwd = os.path.join(r.work, sub) if sub else r.work

        def head():
            return subprocess.run(GIT + ['rev-parse', '-q', '--verify', 'HEAD'], cwd=r.work, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE).stdout.strip().decode()

        def sh(code):
            return subprocess.run([shell, '-c', code], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  timeout=180)
        st = {'start': head(), 'refs': self._origin(r, 'for-each-ref'), 'ask': None, 'asks': [], 'scanned': None,
              'res': None, 'results': [], 'saved': None, 'stopped': None, 'failed': None, 'sent': None, 'trace': [],
              'outputs': [], 'mem': {}}
        def as_list(x):
            return list(x) if isinstance(x, (list, tuple)) else [x] if x else []
        queue, guard_q, first_q = as_list(after_check), as_list(after_guard), as_list(after_first_check)
        save_q, push_q = as_list(after_save), as_list(before_push)
        fired, last, seen, back2, pick_saved = [], [None], {}, [False], [False]

        def hook(at_save=False):
            if queue and not (at_save and fired):
                fired.append(1)
                queue.pop(0)()

        def check(code=None):
            run = self._fill(code, files, mem=st['mem']) if code else scan
            ids = re.findall(r'\b[0-9a-f]{40,64}\b', '\n'.join(l for l in run.splitlines()
                                                               if not l.lstrip().startswith('#')))
            st['scanned'] = ids[-1] if ids else head()
            st['res'] = Result(sh(run.replace(INSTALLED, SCRIPT)), 0)
            if unreadable and pick_saved[0]:
                st['res'] = Result(subprocess.CompletedProcess([], 0, b'== new files ==\n== unsaved edits ==\n'
                                                                      b'== saved, not sent ==\n', b''), 0)
            st['stopped'] = self._counted(st['res'], files, sub)
            st['results'].append(st['res'])
            st['trace'].append(('check', st['scanned']))
            if not st['stopped'] and st['ask'] is not None:
                hook()
            elif not st['stopped'] and first_q:
                first_q.pop(0)()
            return not st['stopped']

        def remember(c, m):
            what, name = m.group('what'), m.group('name')
            cmd = re.search(r'`(git\s[^`]+)`', what)
            if cmd:
                st['mem'][name] = sh(cmd.group(1)).stdout.decode().strip()
            elif re.search(r'(?i)\bprint(?:s|ed)?\b|^(?:it|that|this|the (?:commit )?id|that id|this id|its id)$', what):
                out = last[0].stdout.decode().split() if last[0] else []
                self.assertTrue(out and re.fullmatch(r'[0-9a-f]{40,64}', out[-1]), 'PHASE 5 says "%s", but the block '
                                'before it prints no commit id (its last line: %r)' % (c, out[-1:]))
                st['mem'][name] = out[-1]
            elif re.search(r'\bHEAD\b', what):
                st['mem'][name] = head()
            else:
                self.fail('PHASE 5 says to remember %r as {%s}, but not where it comes from' % (what, name))

        def write(m):
            path = sh('printf "%%s" "%s"' % m.group('path')).stdout.decode()
            value = self._fill('{%s}' % m.group('name'), mem=st['mem'])
            with open(os.path.join(cwd, path), 'w') as f:
                f.write(value + '\n')

        def say(c, rule=False, fence_checks=False):
            """Act on clause c; returns (go on?, the ways on it names: rerun / restart / reask / step2)."""
            ways = []
            for _, kind, m in self._instr(c, rule):
                if kind == 'remember':
                    remember(c, m)
                elif kind == 'write':
                    write(m)
                elif kind == 'check':
                    if not fence_checks and not check():
                        return False, ways
                else:
                    ways.append(kind)
            return True, ways

        def follow(items, mark):
            rule = [it[1] for it in items if it[0] == 'say' and isinstance(it[2], frozenset) and mark in it[2]]
            if not rule:
                rule = [it[1] for it in self._script(p, 0, len(p)) if it[0] == 'say' and isinstance(it[2], frozenset)
                        and mark in it[2]]
            self.assertTrue(rule, 'a PHASE 5 block printed %s, and PHASE 5 has no rule for it' % mark)
            n0, ways = len(st['trace']), []
            for c in rule:
                if re.match(self.STOP_BRANCH, c):
                    continue
                ok, ks = say(c, True)
                if not ok:
                    return 'stopped'
                ways += ks
            back2[0] = 'step2' in ways
            for k in ways:
                if k in ('rerun', 'restart'):
                    return k
                if k in ('reask', 'step2'):
                    return 'reask'
            return 'rerun' if any(t[0] == 'check' for t in st['trace'][n0:]) else 'fail'

        def walk(items, n=None):
            i = 0
            while i < len(items):
                it = items[i]
                if it[0] == 'say':
                    nxt = items[i + 1] if i + 1 < len(items) else None
                    if it[2] is None and not say(it[1], fence_checks=bool(
                            nxt and nxt[0] == 'fence' and 'secret-scan.py' in nxt[1]))[0]:
                        return 'stopped'
                    i += 1
                    continue
                code = it[1]
                if 'secret-scan.py' in code:
                    self.assertIn(INSTALLED, code, 'a PHASE 5 check does not make the call 3e makes (%s)' % INSTALLED)
                    if not check(code):
                        return 'stopped'
                    i += 1
                    continue
                if n == 2 and not re.search(r'\bgit\b', code):
                    i += 1
                    continue
                if self._git_does(code, 'commit'):
                    if guard_q:
                        guard_q.pop(0)()
                    hook(at_save=True)
                if self._git_does(code, 'push') and push_q:
                    push_q.pop(0)()
                cp = sh(self._fill(code, files, mem=st['mem']))
                last[0] = cp
                st['outputs'].append((code, cp))
                marks = [l for l in cp.stdout.decode().splitlines() if re.fullmatch(self.MARK_LINE, l)]
                if self._git_does(code, 'push'):
                    st['sent'] = cp
                    st['trace'].append(('push', cp.returncode))
                elif self._git_does(code, 'commit') and cp.returncode == 0 and not marks:
                    out = cp.stdout.decode().split()
                    st['saved'] = out[-1] if out and re.fullmatch(r'[0-9a-f]{40,64}', out[-1]) else head()
                    st['trace'].append(('save', st['saved']))
                    pick_saved[0] = n is not None
                    if save_q:
                        save_q.pop(0)()
                if marks:
                    m = marks[-1]
                    st['trace'].append(('printed', m))
                    seen[m] = seen.get(m, 0) + 1
                    if seen[m] > 3:
                        st['stopped'] = 'the flow loops: %s, again and again' % m
                        return 'stopped'
                    k = follow(items, m)
                    if k == 'rerun':
                        continue
                    if k == 'fail':
                        st['failed'] = m
                    return k
                if cp.returncode and n is not None:
                    if not self._git_does(code, 'push'):
                        st['stopped'] = 'a block after the pick failed'
                    return 'stopped'
                i += 1
            return 'done'

        def at_the_ask():
            a = {'head': head(), 'refs': self._origin(r, 'for-each-ref'),
                 'status': r.git('status', '--porcelain', '-uall').decode(),
                 'branch': r.git('branch', '--show-current').decode().strip()}
            st['asks'].append(a)
            st['ask'] = st['ask'] or a
            st['trace'].append(('ask', a['head']))
            return walk(self._script(p, ask, opt1)) == 'done'

        if walk(self._script(p, 0, ask)) != 'done' or not at_the_ask():
            return st
        if between:
            between()
        for n in picks:
            items = self._script(p, *self._option_at(p, n))
            for _ in range(4):
                st['trace'].append(('pick', n))
                k = walk(items, n)
                if k != 'restart':
                    break
            else:
                st['stopped'] = 'the flow loops: the pick again and again'
                return st
            if k == 'reask':
                if (back2[0] and walk(self._script(p, 0, ask)) != 'done') or not at_the_ask():
                    return st
                continue
            if k != 'done' or n in (1, 4):
                return st
            if after_pick:
                after_pick(n)
        return st

    def _sends_what_was_checked(self, r, st, files):
        """The commit sent is what the check read, or that plus argo-it's save of `files` (nothing else)."""
        if st['saved'] != st['scanned']:
            self.assertEqual(r.git('rev-parse', st['saved'] + '^').strip().decode(), st['scanned'],
                             "the commit sent is not the one checked plus argo-it's save")
            self.assertEqual(r.git('diff', '--name-only', st['scanned'], st['saved']).decode().split(), sorted(files),
                             "argo-it's save holds more than its own files")

    def test_2a_option_1_never_pushes_a_local_deploy_branch_2b_did_not_scan(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                v = fake('localonly' + shell)
                r = self.fresh()
                r.git('checkout', '-q', '-b', self.DEPLOY)  # left by an earlier failed push, or made by the user
                r.write('leak.py', kv('API_' + 'KEY', v))
                r.commit('local only, never sent')
                r.git('checkout', '-q', 'main')
                st = self._flow(r, shell, self._generate(r))
                self.assertFalse(_b(v) in self._sent_objects(r),
                                 'Option 1 pushed a local %s that 2b never scanned: its fake key reached origin'
                                 % self.DEPLOY)
                if not st['stopped']:
                    self.assertEqual(self._ref(r, self.DEPLOY), st['saved'], "origin's %s is not the commit 2b "
                                     "checked plus argo-it's save" % self.DEPLOY)

    def test_2b_control_option_1_sets_up_the_deploy_branch_from_what_2b_scanned(self):  # control: passes today
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                files = self._generate(r)
                st = self._flow(r, shell, files)
                self.assertIsNone(st['stopped'], '2b stopped a clean first send')
                self._sends_what_was_checked(r, st, files)
                for ref in (self.DEPLOY, 'main'):
                    self.assertEqual(self._ref(r, ref), st['saved'], "origin's %s is not the commit 2b checked plus "
                                     "argo-it's save" % ref)

    # --- the prose checks (each proven against its plain opposite in test_9) ---------------------------------
    def _never_opens_a_hit(self, prose):
        ss = self._all_sentences(prose)
        self.assertTrue(any(re.search(r"(?i)\b(?:never|don't|do not)\s+open\b[^.]{0,20}\bhit(?:'s)?\s+files?\b", s)
                            for s in ss), "PHASE 5 doesn't say never open a hit's file here")
        for s in ss:
            for m in re.finditer(r'(?i)\bopen\b[^.]{0,20}\bhit', s):
                self.assertTrue(self._negated(s, m.start()), "PHASE 5 tells the agent to open a hit's file: %r" % s)

    def _goes_on_only_when_clean(self, prose):
        ons = []
        for u in self._units(prose):
            ss = self._sentences(u)
            ons += [' '.join(ss[:k + 1]) for k, s in enumerate(ss) for m in re.finditer(self.GO_ON, s)
                    if not self._negated(s, m.start())]
        self.assertTrue(ons, 'PHASE 5: no rule goes on to step 3 when the check is clean')
        self.assertEqual(len(ons), 1, 'PHASE 5: more than one rule goes on to step 3: %r' % ons)
        c = ons[0]  # the go-on rule, from its paragraph's start to the end of its go-on sentence
        self.assertFalse(self._stops(c), 'the clean path stops: %r' % c)
        self.assertRegex(c, r'(?i)\bno\b[^.]{0,30}\bhits?\b[^.]{0,30}' + re.escape(L_SAVED),
                         'the go-on rule does not require no hit under %s: %r' % (L_SAVED, c))
        self.assertRegex(c, r'(?i)\bexit 0\b', 'the go-on rule does not name exit 0: %r' % c)
        self.assertLessEqual(set(re.findall(r'(?i)\bexits?(?: codes?)?\s+(\d+)', c)), {'0', '1'},
                             'the go-on rule goes on at an exit other than 0 or 1: %r' % c)
        self.assertNotRegex(c, self.WIDE, 'the go-on rule widens its condition: %r' % c)
        self.assertRegex(c, r'(?i)\bthree labels\b|\b3e\b',
                         "the go-on rule drops 3e's condition that the three labels print each once, in order: %r" % c)

    def _could_not_check_rule(self, prose):
        return self._rule(prose, lambda u: (re.search(r"(?i)\bexit 2\b|any other exit|anything else|anything but"
                                                      r"|couldn't check|could not check", u) and self._stops(u)), [
            (re.escape("I couldn't check your changes for secrets"), "it doesn't use 3e's could-not-check message"),
        ], "a scan that couldn't check")

    def _points_at_3e_list(self, prose):
        b = self._could_not_check_rule(prose)
        self.assertRegex(b, r'\b3e\b', "2b's could-not-check rule does not point at 3e's list: %r" % b)
        copied = [c for c in self.COPIED if re.search(c, b)]
        self.assertLess(len(copied), 2, "2b copies 3e's could-not-check list instead of pointing at it: %r" % b)
        for s in self._all_sentences(prose):
            if re.search(r'(?i)\bexit 0\s+(?:is|=|means)\s+(?:clean|a pass)\b', s):
                self.assertRegex(s, r'(?i)\bthree labels\b', "2b's summary of 3e drops its three labels: %r" % s)

    def _rescans_after_a_save(self, text):
        ck = r'(?:2b|this check|the (?:secret )?(?:check|scan))'
        for s in self._all_sentences(text):
            if (re.search(r'(?i)\b(?:sav(?:e|es|ed|ing)|commit(?:s|ted)?)\b[^.]{0,40}\bafter\s+' + ck + r'\b', s)
                    and re.search(r'(?i)\b(?:run|re-?run|repeat)\s+(?:\w+\s+){0,2}?' + ck + r'\s+again\b'
                                  r'|\bre-?run\s+' + ck + r'\b', s)
                    and re.search(r'(?i)\bbefore\b[^.]{0,30}\b(?:step 4|the push|pushing|sending|send(?:s|ing)?'
                                  r'|option 1|it is sent|anything is sent)\b', s)
                    and not re.search(r"(?i)\b(?:no need to|needn't|don't|do not|never|without|skip(?:s|ping)?)\b"
                                      r"[^.]{0,15}\b(?:run|re-?run|repeat)", s)):
                return
        self.fail('PHASE 5 does not run 2b again when anything is saved after it, before step 4 sends')

    def _registry_advice(self, prose):
        flat = self._flat(prose)
        for f in ('.npmrc', '.pypirc', '.yarnrc.yml'):
            self.assertIn(f, flat, '2b does not name registry files (%s) as 3e does' % f)
        self.assertTrue(any(re.search(r'(?i)\bregistry login\b[^.]*\bpipeline secret\b|\bpipeline secret\b[^.]*'
                                      r'\bregistry login\b', s)
                            and not re.search(r"(?i)\b(?:not|never|don't|do not|instead of|rather than)\b[^.]{0,30}"
                                              r"\bpipeline secret\b", s)
                            for s in self._all_sentences(prose)),
                        "a registry-login hit under saved loses 3e's advice to keep the login in a pipeline secret")

    def _holds_whatever_they_say(self, prose):
        def good(s):
            return (re.search(self.CLAUSE, s) and not re.search(r'(?i)\bunless\b', s)
                    and not any(not self._negated(s, m.start()) for m in re.finditer(self.GO_ON, s))
                    and (self._stops(s) or re.search(self.SENT_NONE, s) or re.search(r'(?i)\b(?:holds?|stands?)\b', s)))
        general = r"(?i)\b(?:both|either|neither|every|each|all|these|any|2b's)\b[^.]{0,20}\bstops?\b"
        if any(good(s) and re.search(general, s) for s in self._all_sentences(prose)):
            return
        for what, b in (('could-not-check stop', self._could_not_check_rule(prose)),
                        ('saved-hit stop', self._saved_hit_stops(prose))):
            self.assertTrue(any(good(s) for s in self._sentences(b)),
                            "2b's %s doesn't hold whatever they say, as 3e's stops do" % what)

    # --- 3-8. the Minors ----------------------------------------------------------------------------------
    def test_3_only_a_clean_result_goes_on_and_a_hits_file_is_never_opened(self):
        prose = self._prose()
        self._never_opens_a_hit(prose)  # a pin: passes today
        self._goes_on_only_when_clean(prose)

    def test_4_2b_points_at_3es_could_not_check_list_instead_of_copying_it(self):
        self._points_at_3e_list(self._prose())

    def test_5_step_1_saves_only_argo_its_files_never_the_users_other_staged_changes(self):
        r = self.fresh()
        r.write('notes.md', '# my plan\n')
        r.append('app.py', 'debug = True\n')
        r.git('add', 'notes.md', 'app.py')
        sha = self._step1(r)
        got = set(r.git('diff-tree', '--no-commit-id', '--name-only', '-r', sha).decode().split())
        self.assertEqual(got, set(self.GENERATED), "step 1 saved the user's staged files: %r"
                         % sorted(got - set(self.GENERATED)))
        self.assertEqual(set(r.git('diff', '--cached', '--name-only').decode().split()), {'app.py', 'notes.md'},
                         "step 1 changed what the user had staged")

    def test_6_anything_saved_after_2b_is_checked_again_before_the_push(self):
        self._rescans_after_a_save(re.sub(self.FENCE, '', self._phase(), flags=re.M | re.S))

    def test_7_a_registry_login_hit_under_saved_keeps_3es_pipeline_secret_advice(self):
        self._registry_advice(self._prose())

    def test_8_2bs_stops_hold_whatever_they_say(self):
        self._holds_whatever_they_say(self._prose())

    # --- 9. polarity: each new prose check passes a plain reading and fails its plain opposite ---------------
    GOOD2 = '\n'.join((
        '**2b. Check what this send carries for secrets** -- the same check PHASE 5b step 3e runs:',
        '',
        'Run it from the project root with a 120-second timeout, and read the result exactly as 3e does.',
        'Only hits under `== saved, not sent ==` count here. Name each hit only by its file and line number,',
        "and never open a hit's file here.",
        '',
        "- **Anything else** (any result 3e's third bullet covers): STOP -- don't show the step-3 ask;",
        '  nothing is sent. Tell the user:',
        '',
        "  \"I couldn't check your changes for secrets, so I haven't sent anything. [the reason, in plain words]\"",
        '',
        "**If any hit sits under `== saved, not sent ==`: stop here.** Don't show the step-3 ask; nothing is",
        'sent; offer nothing else. Tell the user:',
        '',
        "\"I found what looks like a password or secret key in a change you already saved but haven't sent yet:",
        '**line [N] of [file]**. Secrets should never be saved in code, so I won\'t send this. [If a hit is in a',
        '`.npmrc`, `.pypirc` or `.yarnrc.yml` file: Ask your DevOps team to keep the registry login in a pipeline',
        'secret instead.]"',
        '',
        'Both stops hold whatever they say: never send past either one.',
        '',
        '**If no hit sits under `== saved, not sent ==`** (exit 0 or exit 1 with the three labels each once, in',
        'order): go on to step 3.',
        '',
        'If anything is saved after 2b, run 2b again before step 4.',
        ''))

    def test_9_control_new_prose_checks_are_polarity_bound(self):  # control: passes today
        go_on = '**If no hit sits under `== saved, not sent ==`**'
        checks = {
            '_never_opens_a_hit': [
                ("and never open a hit's file here.", "and open each hit's file here to check the line."),
                ("and never open a hit's file here.", 'and that is all.')],
            '_goes_on_only_when_clean': [
                ('(exit 0 or exit 1 with the three labels each once, in\norder)', '(any exit, or a timeout)'),
                ('each once, in\norder)', 'each once, in\norder, or a timeout)'),
                ('(exit 0 or exit 1 with the three labels', '(exit 0, 1 or exit 2 with the three labels'),
                ('(exit 0 or exit 1 with the three labels each once, in\norder)',
                 '(exit 0, or exit 1 with every hit under the other two labels)'),
                (go_on, 'If every saved hit is in a file argo-it generated: go on to step 3 and send it.\n\n' + go_on),
                ('go on to step 3.', 'stop here.'),
                ('go on to step 3.', 'stop here, then go on to step 3.')],
            '_points_at_3e_list': [
                ("(any result 3e's third bullet covers)",
                 "(3e's could-not-check case: any other exit, a timeout, a label missing or repeated, a stray line, "
                 "exit 1 with no hit)"),
                ("(any result 3e's third bullet covers)", '(any other result)'),
                ('exactly as 3e does.', 'exactly as 3e does (exit 0 is clean, exit 1 is hits, anything else stops).')],
            '_rescans_after_a_save': [
                ('run 2b again before step 4.', "there's no need to run 2b again before step 4."),
                ('run 2b again before step 4.', 'go straight to step 4.')],
            '_registry_advice': [
                ('keep the registry login in a pipeline\nsecret instead.',
                 'move the registry login into your .env file.'),
                ('`.npmrc`, `.pypirc` or `.yarnrc.yml` file', '`.npmrc` file')],
            '_holds_whatever_they_say': [
                ('Both stops hold whatever they say: never send past either one.', ''),
                ('Both stops hold whatever they say: never send past either one.',
                 'Both stops hold unless they say send it anyway.'),
                ('Both stops hold whatever they say: never send past either one.',
                 'Whatever they say, go on to step 3 if they insist.'),
                ('Both stops hold whatever they say: never send past either one.',
                 'The saved-hit stop holds whatever they say: never send past it.')],
        }
        for name, swaps in checks.items():
            check = getattr(self, name)
            with self.subTest(check=name, text='plain reading'):
                check(self.GOOD2)
            for good, opposite in swaps:
                self.assertIn(good, self.GOOD2)
                with self.subTest(check=name, opposite=opposite):
                    with self.assertRaises(AssertionError):
                        check(self.GOOD2.replace(good, opposite))


# ArgoItFirstSendFix1Cases' helpers (not its tests), for adversarial round 1 below.
_FirstSendFix1 = type('_FirstSendFix1', (object,), {k: v for k, v in ArgoItFirstSendFix1Cases.__dict__.items()
                                                    if not k.startswith(('test', '__'))})


def _refuse_every_push(r):
    """The fixture's origin refuses every push (a pre-receive hook in its own hooks folder): a send without the rights
    to send. It was a push address pointing nowhere; the owner's call B (after adversarial round 3) refuses a push
    address that differs from the fetch address before the ask, so that fixture can no longer reach the push."""
    hooks = os.path.join(r.root, 'origin-hooks')
    os.makedirs(hooks, exist_ok=True)
    path = os.path.join(hooks, 'pre-receive')
    with open(path, 'w') as f:
        f.write('#!/bin/sh\nexit 1\n')
    os.chmod(path, 0o755)
    subprocess.run(['git', '--git-dir', os.path.join(r.root, 'origin'), 'config', 'core.hooksPath', hooks], check=True)


class ArgoItFirstSendAdv1Cases(_FirstSendFix1, _FirstSend, Base):
    """Task 3 adversarial round 1 and the owner's calls after it (2026-10-19): a YAML `secretKey:` value that is more
    than a setting name is checked as before; PHASE 5's check runs after step 2's lookup and before argo-it saves, and
    its stops say "I haven't saved or sent anything"; a hit counts under saved or in any file the save will save,
    whatever its label; the save names argo-it's files one by one; Option 1 sends only what was checked plus argo-it's
    save; a failed push is never followed by "Pushed!". `_flow` follows PHASE 5 as written (`_fill` names the
    placeholders it fills). Prose checks are proven against their plain opposites in test_6. Values and secret-named
    lines are joined at run time (GitGuardian scans this file)."""

    CAPS = 'CORRECT' + 'HORSE'  # a capitals first word long enough to hit alone, as it did on 371bfc6
    FAILED = (r"(?i)\b(?:if|when|should)\b[^.]{0,40}?\bpush(?:es)?\b[^.]{0,40}?\b(?:fails?|failed|(?:is|are|gets?) "
              r"refused|(?:does|did)(?:n't| not) (?:work|go through)|exits? (?:with )?(?:anything but|other than|non-?zero"
              r"|an error))\b")
    SENT_OR_NOT = (r"(?i)\bnothing (?:was|is|has been|got) sent\b|\b(?:wasn't|was not|weren't|were not|isn't|is not"
                   r"|hasn't been|haven't been) sent\b|\b(?:didn't|did not|couldn't|could not|haven't|have not) sen[dt]\b"
                   r"|\bnothing (?:is|went|has gone) live\b|\bnothing is deploying\b")
    NEXT = r'(?i)\bwhat to do next\b|\brun /argo-it again\b'
    IN_A_SAVED_FILE = (r"(?i)\bin (?:a|any|one of the|the) files?\b[^.]{0,60}?(?:\b2c\b|\bstep \w+|\bthe save\b|\bI(?:'m| am"
                       r"| will|'ll)? (?:about to |going to )?save\b|\bargo-it (?:is about to |will )save\b|\bwill save\b"
                       r"|\bis about to save\b|\b(?:is|are) about to be saved\b)")
    ANY_LABEL = (r'(?i)\bwhatever (?:its|the|their) labels?\b|\bunder any (?:of the )?labels?\b|\bwhichever label\b'
                 r'|\bunder (?:every|all|each) labels?\b|\bany label\b')

    # --- 1. Critical: a `secretKey:` value that is more than a setting name hits, as on 371bfc6 -------------------
    def _3e(self, cwd, shell):
        """PHASE 5b's 3e block, run as written under `shell` (the installed path swapped for this repo's script)."""
        need_shell(shell)
        block = ArgoItWiringCases('test_old_inline_scan_is_gone')._block()
        self.assertIn(INSTALLED, block, '3e does not make the call it made (%s)' % INSTALLED)
        cp = subprocess.run([shell, '-c', block.replace(INSTALLED, SCRIPT)], cwd=cwd, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=180)
        return Result(cp, 0)

    def _every_path(self, r, **kw):
        with self.subTest(path='scanner'):
            self.check(r.scan(), **kw)
        for shell in ('bash', 'zsh'):
            with self.subTest(path='2b', shell=shell):
                self.check(self._run(r.work, shell), **kw)
            with self.subTest(path='3e', shell=shell):
                self.check(self._3e(r.work, shell), **kw)

    def _shapes(self, tail):
        """(name, YAML) whose line-2 `secretKey:` value YAML reads as a capitals word and more."""
        sk, c = self.SK, self.CAPS
        return [('flow-map', 'kind: Secret\njwt: { %s: %s battery %s }\n' % (sk, c, tail)),
                ('list-item', 'data:\n  - %s: %s battery staple %s\n' % (sk, c, tail)),
                ('multi-line', 'jwt:\n  %s: %s\n    batterystaple%s\n' % (sk, c, tail)),  # YAML: "CAPS batterystaple..."
                ('quote-escape', "jwt:\n  %s: '%s''s %s'\n" % (sk, c, tail)),  # YAML: "CAPS's ..."
                ('space', 'jwt:\n  %s: %s battery staple %s\n' % (sk, c, tail)),
                ('tab', 'jwt:\n  %s: %s\tbattery %s\n' % (sk, c, tail))]

    def test_1a_a_secretkey_value_that_is_more_than_a_setting_name_hits_under_every_label_on_2b_and_3e(self):
        tail = fake('horse')
        shapes = self._shapes(tail)
        r = self.fresh()
        for name, text in shapes:
            r.write('k8s/unsaved/%s.yaml' % name, text.split('\n', 1)[0] + '\n')
        r.commit('tracked')
        r.push()
        for name, text in shapes:
            r.write('k8s/saved/%s.yaml' % name, text)
        r.commit('never sent')
        for name, text in shapes:
            r.write('k8s/unsaved/%s.yaml' % name, text)
            r.write('k8s/new/%s.yaml' % name, text)
        kw = {lab: ['k8s/%s/%s.yaml:2' % (lab, n) for n, _ in shapes] for lab in ('unsaved', 'new', 'saved')}
        self._every_path(r, secrets=[self.CAPS + ' battery', tail], **kw)

    def test_1b_control_a_secretkey_setting_name_plain_or_quoted_is_no_hit_under_any_label_on_2b_and_3e(self):
        n, j = self.NAMES[0], self.NAMES[1]  # control: passes today
        text = 'data:\n' + ''.join('  - %s: %s\n' % (self.SK, v) for v in (n, '"%s"' % n, "'%s'" % n, '"%s"' % j, "'%s'" % j))
        text += 'jwt:\n  %s: %s\n  %s: "%s"\n' % (self.SK, j, self.SK, j)
        r = self.fresh()
        r.write('k8s/unsaved.yaml', 'data:\n')
        r.commit('tracked')
        r.push()
        r.write('k8s/saved.yaml', text)
        r.commit('never sent')
        r.write('k8s/unsaved.yaml', text)
        r.write('k8s/new.yaml', text)
        self._every_path(r)

    # --- 2. Important: a commit saved during the step-3 wait never goes out unchecked ---------------------------
    def test_2_a_commit_saved_during_the_step_3_wait_never_reaches_origin(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                v = fake('waitsave' + shell)
                r = self.fresh()
                main0 = self._ref(r, 'main')

                def user_saves():  # VS Code's Commit button, or `git commit` in another terminal, while the agent waits
                    r.write('settings.py', kv('API_' + 'KEY', v))
                    r.commit('my change')
                st = self._flow(r, shell, self._generate(r), between=user_saves)
                self.assertIsNotNone(st['ask'], 'the clean check stopped the send: %r' % (st['res'] and st['res'].lines))
                self.assertFalse(_b(v) in self._sent_objects(r), "Option 1 sent a commit saved after the check: its "
                                 "fake key reached origin (the check didn't run again, and the push wasn't the commit "
                                 "that was checked)")
                for ref, before in ((self.DEPLOY, ''), ('main', main0)):
                    if self._ref(r, ref) != before:
                        self.assertEqual(self._ref(r, ref), st['saved'], "origin's %s is not the commit checked plus "
                                         "argo-it's save" % ref)

    # --- 3. Important and the owner's "check before saving" -----------------------------------------------------
    def _checks_before_saving(self, p):
        # `git fetch [options] origin`: the owner's call A (after adversarial round 3) fetches with its own options
        fetch = [f for f in self._fences(p) if re.search(r'\bgit fetch(?:\s+--?[\w=-]*)*\s+origin\b', f[2])]
        self.assertTrue(fetch, "PHASE 5: no ```bash block runs step 2's `git fetch origin`")
        scan, save = self._scan(p), self._save_block(p)
        self.assertGreater(scan[0], fetch[0][1], "the check runs before step 2's lookup (`git fetch`), so its "
                                                 "'saved, not sent' isn't current")
        self.assertLess(scan[1], save[0], 'the check runs after argo-it saves its files: a hook that sends every save '
                                          'sends an older unsent secret before the check')
        prose = re.sub(self.FENCE, '', p[fetch[0][1]:self._ask_at(p)], flags=re.M | re.S)
        for s in self._all_sentences(prose):
            self.assertNotRegex(s, r'(?i)\b(?:runs?|run it|checks?|checked)\s+(?:\w+\s+){0,3}?after\s+(?:step 1\b|the save'
                                   r'\b|argo-it saves|I save|saving)|\bjust saved are checked\b',
                                'PHASE 5 still says the check runs after the save: %r' % s)

    def test_3a_the_check_runs_after_the_fetch_and_before_argo_it_saves(self):
        self._checks_before_saving(self._phase())

    def test_3b_a_hook_that_sends_every_save_never_sends_an_older_unsent_secret(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                v = fake('hooksend' + shell)
                r = self.fresh()
                r.append('app.py', kv('API_' + 'KEY', v))
                r.commit('older change, never sent')
                hooks = os.path.join(r.root, 'hooks')  # this fixture's own hooks folder (core.hooksPath), nowhere else
                os.makedirs(hooks)
                with open(os.path.join(hooks, 'post-commit'), 'w') as f:
                    f.write('#!/bin/sh\ngit push -q origin HEAD\n')  # the user's "auto-sync": every save is sent
                os.chmod(os.path.join(hooks, 'post-commit'), 0o755)
                st = self._flow(r, shell, self._generate(r), hooks=hooks)
                self.assertFalse(_b(v) in self._sent_objects(r), "argo-it's save fired the user's send-every-save hook "
                                 "before the check: the older commit's fake key reached origin")
                self.assertEqual(st['stopped'], 'a hit counts', 'the older unsent secret did not stop the send')
                self.assertEqual(self._origin(r, 'for-each-ref'), st['refs'], "something was sent before the stop, so "
                                 "\"I haven't saved or sent anything\" isn't true")
                self.assertEqual(r.git('rev-parse', 'HEAD').strip().decode(), st['start'], "argo-it saved before the "
                                 "check stopped, so \"I haven't saved or sent anything\" isn't true")

    def _stops_say_nothing_saved(self, prose):
        for what, b in (('saved-hit stop', self._saved_hit_stops(prose)),
                        ('could-not-check stop', self._could_not_check_rule(prose))):
            self.assertIn("I haven't saved or sent anything", b,
                          "2b's %s doesn't say 3e's \"I haven't saved or sent anything\"" % what)
            self.assertNotRegex(b, r'(?i)\bstays? saved\b|\bsetup files I made stay\b', "2b's %s still says the setup "
                                "files stay saved, but nothing is saved before the check now" % what)

    def test_3c_both_of_2bs_stops_say_i_havent_saved_or_sent_anything(self):
        self._stops_say_nothing_saved(self._prose())

    def test_3d_control_a_hit_in_a_file_argo_it_is_about_to_save_is_its_mistake_and_stops(self):  # control
        prose = self._prose()
        self._generated_is_a_mistake(prose)
        self.assertIn('That one is a mistake on my side', self._flat(prose))

    # --- 4. the coordinator's calls: what counts, and a save by name --------------------------------------------
    def _hit_in_a_saved_file_counts(self, prose):
        neg = r"(?i)\b(?:doesn't|does not|don't|do not|never|isn't|is not|aren't|won't|not)\s+(?:\w+\s+){0,2}?(?:count|stop)"
        self.assertTrue(any(re.search(self.IN_A_SAVED_FILE, s) and re.search(self.ANY_LABEL, s)
                            and re.search(r'(?i)\bcounts?\b|\bstops?\b', s) and not re.search(neg, s)
                            for s in self._all_sentences(prose)),
                        "PHASE 5 doesn't say a hit in a file the save will save counts, whatever its label")

    def test_4a_a_hit_in_a_file_the_save_names_stops_the_send_before_the_save_whatever_its_label(self):
        cm = 'apiVersion: v1\nkind: ConfigMap\ndata:\n'
        rel = 'env/dev/app-config.yaml'
        for shell in ('bash', 'zsh'):
            for label in ('new', 'unsaved'):
                with self.subTest(shell=shell, label=label):
                    v = fake(label + 'gen' + shell)
                    r = self.fresh()
                    if label == 'unsaved':  # an earlier run's file, sent; the user's unsaved edit adds a key
                        r.write(rel, cm)
                        r.commit('an earlier run')
                        r.push()
                    st = self._flow(r, shell, self._generate(r, {rel: cm + '  ' + kv('DB_' + 'PASS' + 'WORD', v, sep=': ')}))
                    self.assertFalse(_b(v) in self._sent_objects(r), 'the fake key reached origin')
                    self.assertEqual(st['stopped'], 'a hit counts', "a hit in a file argo-it's save names didn't stop")
                    self.assertEqual(r.git('rev-parse', 'HEAD').strip().decode(), st['start'], "argo-it saved the file "
                                     "before the check stopped, so \"I haven't saved or sent anything\" isn't true")
                    self.check(st['res'], secrets=[v], **{label: [rel + ':4']})
        with self.subTest(what='text'):
            self._hit_in_a_saved_file_counts(self._prose())

    def _save_names_files(self, p):
        """Every command in the save block that takes files in -- `git add`, `git update-index`, `git hash-object`, and
        `git commit` with paths (not `git commit-tree`, which takes a tree: owner, after review 6) -- names argo-it's
        files one by one (or a loop variable over them), never the whole tree, a folder or a pattern."""
        code = '\n'.join(l for l in self._save_block(p)[2].splitlines() if not l.lstrip().startswith('#'))
        loops = re.findall(r'\bfor\s+(\w+)\s+in\s+\{[\w-]*file[\w-]*\}', code, re.I)
        for v in loops:  # "$f" over argo-it's files is one of them, by name
            code = re.sub(r'"\$\{?%s\}?"' % v, '{generated_file}', code)
        code = re.sub(r'"(?:[^"\\]|\\.)*"|\'[^\']*\'', '""', code)
        cmds = re.findall(r'\bgit\s+(?:(?:-c\s+\S+|--no-replace-objects)\s+)*(add|commit|update-index|hash-object)'
                          r'(?![\w-])([^;&|\n]*)', code)
        self.assertTrue(cmds, "the save block takes in none of argo-it's files by name (git add, update-index, "
                              "hash-object)")
        for sub, args in cmds:
            paths, after, prev = [], False, None
            for t in args.split():
                t, prev = (t.rsplit(',', 1)[-1] if prev == '--cacheinfo' else t), t  # mode,blob,path: the path
                if t == '--':
                    after = True
                elif not after and t.startswith('-'):
                    self.assertFalse(t in ('--all', '--update', '--again', '--stdin-paths') or re.fullmatch(
                        r'-[A-Za-z]*%s[A-Za-z]*' % {'commit': 'a', 'add': '[Au]', 'update-index': 'g'}.get(sub, '\0'), t),
                        'the save takes the whole tree or whole folders: git %s %s' % (sub, t))
                elif t != '""':
                    paths.append(t)
            self.assertTrue(paths, "git %s names none of argo-it's files" % sub)
            for t in paths:
                self.assertTrue(re.fullmatch(r'\{[\w-]*file[\w-]*\}', t, re.I) or re.search(r'[^/]\.[A-Za-z0-9]+$', t)
                                and not re.search(r'[*?\[]', t),
                                "the save names a folder or a pattern, not argo-it's files one by one: git %s ... %s"
                                % (sub, t))

    def test_4b_the_save_names_argo_its_files_one_by_one_and_never_takes_the_users_files_in_its_folders(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                v1, v2 = fake('ciedit' + shell), fake('cinew' + shell)
                r = self.fresh()
                r.write('.github/workflows/ci.yml', 'name: ci\non: push\n')
                r.commit('their own CI')
                r.push()
                r.append('.github/workflows/ci.yml', kv('API_' + 'KEY', v1, sep=': '))  # the user's unsaved edit
                r.write('.github/workflows/nightly.yml', kv('API_' + 'KEY', v2, sep=': '))  # and their own new file
                files = self._generate(r)
                st = self._flow(r, shell, files)
                saved = r.git('diff', '--name-only', st['start'], 'HEAD').decode().split()
                self.assertEqual(saved, files, "argo-it's save took the user's own files: %r" % sorted(set(saved) - set(files)))
                self.assertFalse(_b(v1) in self._sent_objects(r) or _b(v2) in self._sent_objects(r),
                                 "the user's own unsaved work under .github/workflows/ was sent")
                self.assertIsNone(st['stopped'], "hits only in files the save doesn't name stopped the send: %r"
                                  % (st['res'] and st['res'].lines))
                self.assertEqual(self._ref(r, 'main'), st['saved'])
                self.assertEqual(r.git('status', '--porcelain', '--', '.github').decode().splitlines(),
                                 [' M .github/workflows/ci.yml', '?? .github/workflows/nightly.yml'],
                                 "the user's own files under .github/workflows/ weren't left as they were")
        with self.subTest(what='text'):
            self._save_names_files(self._phase())

    # --- 5. Minor: a refused push is never followed by "Pushed!" --------------------------------------------------
    def _failed_push_rule(self, p):
        i = p.find('**Option 1 (send')
        self.assertNotEqual(i, -1, 'PHASE 5: no "**Option 1 (send" block')
        j = p.find('**Option 2', i)
        sec = re.sub(self.FENCE, '', p[i:j if j != -1 else len(p)], flags=re.M | re.S)

        def quotes(b):
            return [re.sub(r'--\s*only if[^\]]*\]', ']', re.sub(r'\[(?:If|if|Only|only)\b[^:\]]*:', '[', q))
                    for q in re.findall(r'"(I[^"]{20,})"', b)]
        blk = self._rule(sec, lambda u: re.search(self.FAILED, u), [
            (lambda b: quotes(b), 'it gives the user no message'),
            (lambda b: any(re.search(self.SENT_OR_NOT, q) for q in quotes(b)), "it doesn't say what was and wasn't sent"),
            (lambda b: any(re.search(self.NEXT, q) for q in quotes(b)), 'it gives no next step'),
            (lambda b: not any(re.search(self.NEVER_SAY, q) for q in quotes(b)), 'its message uses a NEVER-say word'),
            (lambda b: not re.search(r'(?i)\b(?:then|and|still|also)\s+say\b[^.]{0,10}"?Pushed!|\bsay\b[^.]{0,10}'
                                     r'"?Pushed!"?\s*anyway', b), 'it still says "Pushed!"'),
        ], 'a push that fails (no push rights, say)')
        flat = self._flat(sec)
        k = flat.find('Pushed!')
        if k != -1:
            told = re.search(r"(?i)\b(?:never|don't|do not|not)\b[^.]{0,20}\b(?:say|tell|show)\b[^.]{0,10}\"?Pushed!"
                             r"|\binstead of\b[^.]{0,10}\"?Pushed!", blk)
            gated = re.search(r'(?i)\b(?:if|when|once|only (?:if|when|once))\b[^.]{0,40}\b(?:both|every|all|each|the)\s+'
                              r'push(?:es)?\b[^.]{0,30}\b(?:work(?:s|ed)?|succeed(?:s|ed)?|went through|go(?:es)? through)'
                              r'\b', flat[max(0, k - 300):k])
            self.assertTrue(told or gated, '"Pushed!" can follow a failed push: the failure rule doesn\'t say never to '
                                           'say it, and "Pushed!" isn\'t only for a push that worked')

    def test_5_a_refused_push_is_never_followed_by_pushed(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                _refuse_every_push(r)
                st = self._flow(r, shell, self._generate(r))
                self.assertIsNone(st['stopped'], 'a clean first send stopped: %r' % (st['res'] and st['res'].lines))
                self.assertNotEqual(st['sent'].returncode, 0, "a refused push looks like it worked: Option 1 exits 0")
                self.assertEqual(self._origin(r, 'for-each-ref'), st['refs'])
        with self.subTest(what='text'):
            self._failed_push_rule(self._phase())

    # --- 6. polarity: each new prose check passes a plain reading and fails its plain opposite ----------------
    LOOKUP = '\n'.join((
        '**2. Check whether the deploy branch exists:**',
        '',
        '```bash',
        'git fetch origin {deploy_branch} 2>/dev/null || true',
        'git log --oneline HEAD --not --remotes',
        '```',
        '', ''))
    CHECK = '\n'.join((
        '**2b. Secret check on what step 4 will send** -- the same check as PHASE 5b step 3e, run before I save',
        'anything, as 3e is:',
        '',
        '```bash',
        'python3 ' + INSTALLED,
        '```',
        '',
        'Run it from the project root with a 120-second timeout, and read the result exactly as 3e does. A hit',
        'counts here when it sits under `== saved, not sent ==`, or when it is in a file 2c will save, whatever its',
        "label. Other hits under `== unsaved edits ==` or `== new files ==` don't stop this send.",
        '',
        "- **Anything else** (any result 3e's third bullet covers): STOP -- don't show the step-3 ask; nothing is",
        '  sent. Tell the user:',
        '',
        "  \"I couldn't check your changes for secrets, so I haven't saved or sent anything. [the reason]\"",
        '',
        '**If any hit counts (under `== saved, not sent ==`, or in a file 2c will save): stop here.** Don\'t show the',
        'step-3 ask; nothing is sent. Tell the user:',
        '',
        "\"I found what looks like a password or secret key in a change you already saved but haven't sent yet:",
        '**line [N] of [file]**. [If the file is one argo-it generated: That one is a mistake on my side, not',
        "something you did.] Secrets should never be saved in code, so I won't send this. I haven't saved or sent",
        'anything. What to do next: ask your DevOps team for help."',
        '',
        '**If no hit counts:** go on to 2c, then step 3.',
        '', ''))
    SAVE = '\n'.join((
        '**2c. Save the generated files, one by one:**',
        '',
        '```bash',
        'git add -- {generated_files}',
        'git commit -m "Add K8s manifests" -- {generated_files}',
        '```',
        '', ''))
    REST = '\n'.join((
        '**3. Ask the user what they want to do:**',
        '',
        "\"I've generated your deployment pipeline and saved it in your project folder.",
        '',
        '**What would you like to do?**',
        '',
        '1. **Send it -- deploys to {hostname}**"',
        '',
        '**4. Execute based on user choice:**',
        '',
        '**Option 1 (send -- CI deploys automatically):**',
        '',
        '```bash',
        'git push origin {saved_head}:refs/heads/{current_branch}',
        '```',
        '',
        '**If either push fails, never say "Pushed!".** Tell the user: "I couldn\'t send your setup to GitHub, so',
        'nothing was sent and nothing is deploying. [the reason, in plain words] What to do next: [the fix], then',
        'run /argo-it again."',
        '',
        '"Pushed! Here\'s what happens next."',
        '',
        '**Option 2 (local test):** nothing is sent.',
        ''))

    def test_6_control_new_prose_checks_are_polarity_bound(self):  # control: passes today
        good = self.LOOKUP + self.CHECK + self.SAVE + self.REST
        gated = good.replace('never say "Pushed!".**', 'tell the user.**').replace(
            '"Pushed! Here', '**If both pushes worked:** "Pushed! Here')
        checks = {
            '_checks_before_saving': (lambda t: t, [
                (good, self.LOOKUP + self.SAVE + self.CHECK + self.REST),
                (good, self.CHECK + self.LOOKUP + self.SAVE + self.REST),
                ('run before I save\nanything, as 3e is:',
                 'run after\nstep 1 so the files argo-it just saved are checked too:')]),
            '_stops_say_nothing_saved': (self._prose, [
                ("I haven't saved or sent\nanything.",
                 'The setup files I made stay saved in your project folder, but nothing has been sent.'),
                ("so I haven't saved or sent anything. [the reason]",
                 "so I haven't sent anything; the setup files I made stay saved. [the reason]")]),
            '_hit_in_a_saved_file_counts': (self._prose, [
                ('A hit\ncounts here when it sits under `== saved, not sent ==`, or when it is in a file 2c will save, '
                 'whatever its\nlabel.', 'Only hits under `== saved, not sent ==` count here.'),
                ('whatever its\nlabel.', 'but only under\n`== saved, not sent ==`.'),
                ('A hit\ncounts here when', "A hit\ndoesn't count here when")]),
            '_save_names_files': (lambda t: t, [
                ('{generated_files}', 'env/ .github/workflows/ ONBOARDING-K8S.md'),
                ('git add -- {generated_files}', 'git add -A'),
                ('{generated_files}', '{manifest_dir}/dev'),
                ('-m "Add K8s manifests"', '-am "Add K8s manifests"')]),
            '_failed_push_rule': (lambda t: t, [
                ('**If either push fails, never say "Pushed!".** Tell the user: "I couldn\'t send your setup to GitHub, so\n'
                 'nothing was sent and nothing is deploying. [the reason, in plain words] What to do next: [the fix], then\n'
                 'run /argo-it again."\n\n', ''),
                (' What to do next: [the fix], then\nrun /argo-it again.', ''),
                ('never say "Pushed!".', 'say "Pushed!" anyway.'),
                ('never say "Pushed!".**', 'tell the user.**'),
                ("I couldn't send your setup to GitHub", "I couldn't push your commit to GitHub"),
                ("I couldn't send your setup to GitHub, so\nnothing was sent and nothing is deploying.",
                 'I ran into a problem with GitHub just now.')]),
        }
        for name, (view, swaps) in checks.items():
            check = getattr(self, name)
            for text, label in ((good, 'plain reading'), (gated, 'plain reading, "Pushed!" only after a push that worked')):
                with self.subTest(check=name, text=label):
                    check(view(text))
            for old, opposite in swaps:
                self.assertIn(old, good)
                with self.subTest(check=name, opposite=opposite[:60]):
                    with self.assertRaises(AssertionError):
                        check(view(good.replace(old, opposite)))



# ArgoItFirstSendAdv1Cases' helpers (not its tests), for fix round 2 below.
_FirstSendAdv1 = type('_FirstSendAdv1', (object,), {k: v for k, v in ArgoItFirstSendAdv1Cases.__dict__.items()
                                                    if not k.startswith(('test', '__'))})


class ArgoItFirstSendFix2Cases(_FirstSendAdv1, _FirstSendFix1, _FirstSend, Base):
    """Task 3 review 3 and the owner's call after it (2026-10-19): save on "Send it". Nothing is saved or sent before
    the user's pick, and the ask says so; on Send it the check runs again, argo-it saves its files by name, and the push
    sends exactly the commit that holds that check's HEAD plus the save; a HEAD that moved between that check and the
    save sends the flow back to the check. `_flow` follows PHASE 5 as written, through each branch it defines (a moved
    HEAD, a refused first or second push, a check that can't run). Prose checks and the readers `_flow` uses are proven
    against their plain opposites in test_5. Values and secret-named lines are joined at run time (GitGuardian scans
    this file)."""

    CM = 'apiVersion: v1\nkind: ConfigMap\ndata:\n'
    REL = 'env/dev/app-config.yaml'  # a generated file; a key in it sits at line 4
    SAVED_NONE = (r"(?i)\bnothing\s+(?:has\s+been|is|was|'s)\s+(?:yet\s+)?(?:saved|sent)\s+or\s+(?:saved|sent)\b"
                  r"|\b(?:not|n't)\s+(?:been\s+|yet\s+)?(?:saved|sent)\s+or\s+(?:saved|sent)\b"
                  r"|\bneither\s+saved\s+nor\s+sent\b")
    NOT_SAVED = (r"(?i)\bnot\s+(?:yet\s+)?saved\b|\bunsaved\b|\b(?:isn't|aren't|is not|are not|haven't been|hasn't been)"
                 r"\s+(?:yet\s+)?saved\b|\bnothing\s+(?:is\s+|gets\s+|has\s+been\s+)?saved\b|\bwithout\s+saving\b")
    KEEP_UNSAVED = NOT_SAVED + r'|\buntil\b[^.]{0,40}\bSend it\b|\bonly\s+on\b[^.]{0,20}\bSend it\b'
    SAVED_CLAIM = (r"(?i)\b(?:I've|I have|and)\s+(?:already\s+)?saved\s+(?:it|them|this|these|the files|your \w+"
                   r"|everything)\b|\b(?:stays?|remains?|kept|(?:files?|they|everything)\s+(?:are|is))\s+saved\b"
                   r"|\bsaved\s+(?:it\s+|them\s+)?in\s+(?:your|the)\s+project\s+folder\b")
    SAVE_DO = (r"(?i)\b(?:save|commit)\s+(?:the|your|its|my|argo-it's|this|that|these|those)?\s*(?:fix(?:es)?|changes?"
               r"|files?|it|them|edits?)\b")
    SWAP = (r"(?i)\b(?:in place of|instead of)\s+\"I haven't saved or sent anything\"|\bsave\s+is\s+already\s+made\b"
            r"|\balready\s+saved\s+(?:the|its|argo-it's|these|my)\s+(?:setup\s+)?files\b")
    EXCL = (r"(?i)\b(?:other\s+than|except(?:\s+for)?|besides|apart\s+from|not\s+counting|leaving\s+out|beyond)\b"
            r"[^\]]{0,60}?(?:\b(?:argo-it's|its|my)\s+(?:own\s+)?(?:earlier\s+|last\s+|previous\s+)?(?:save|commit"
            r"|setup files|files)\b|\bAdd K8s manifests\b)")
    SLOT = r'\[[^\[\]]*\bfiles?\b[^\[\]]*\]'
    EARLIER = (r"(?i)\bre-?run\b|\b(?:argo-it's|its|my)\s+(?:own\s+)?(?:earlier|last|previous)\s+(?:save|run|send)\b"
               r"|\b(?:from|since|on|in|at)\s+(?:last time|the last run|an? (?:earlier|previous|last) run)\b"
               r"|\balready\s+saved\b|\bsaved\s+(?:last time|before|earlier)\b")

    # --- fixtures --------------------------------------------------------------------------------------------------
    def _keyed(self, v):
        """argo-it's generated ConfigMap holding a fake key at line 4 (argo-it's own mistake)."""
        return {self.REL: self.CM + '  ' + kv('DB_' + 'PASS' + 'WORD', v, sep=': ')}

    def _gen(self, r, sub='', extra=None):
        """argo-it's files (plus `extra`) written unsaved under the project root `sub`; their names from there."""
        files = dict(self.GENERATED)
        files.update(extra or {})
        for rel, text in files.items():
            r.write(os.path.join(sub, rel) if sub else rel, text)
        return sorted(files)

    def _send_hook(self, r):
        """The fixture's own hooks folder (core.hooksPath, nowhere else) with the user's "auto-sync": every save is
        sent."""
        hooks = os.path.join(r.root, 'hooks')
        os.makedirs(hooks, exist_ok=True)
        path = os.path.join(hooks, 'post-commit')
        with open(path, 'w') as f:
            f.write('#!/bin/sh\ngit push -q origin HEAD\n')
        os.chmod(path, 0o755)
        return hooks

    def _refuse(self, r, ref):
        """The fixture's origin refuses a push to `ref` (a pre-receive hook in its own hooks folder)."""
        hooks = os.path.join(r.root, 'origin-hooks')
        os.makedirs(hooks, exist_ok=True)
        path = os.path.join(hooks, 'pre-receive')
        with open(path, 'w') as f:
            f.write('#!/bin/sh\nwhile read old new ref; do [ "$ref" = "%s" ] && exit 1; done\nexit 0\n' % ref)
        os.chmod(path, 0o755)
        self._origin(r, 'config', 'core.hooksPath', hooks)

    def _unborn(self):
        """A work repo with no commits yet, and an empty bare origin."""
        td = tempfile.TemporaryDirectory()
        self.addCleanup(td.cleanup)
        r = Repo.__new__(Repo)
        r.test, r.root = self, os.path.realpath(td.name)
        r.work = os.path.join(r.root, 'work')
        Repo._git(r.root, 'init', '-q', '--bare', 'origin')
        Repo._git(r.root, 'init', '-q', '-b', 'main', 'work')
        r.git('remote', 'add', 'origin', os.path.join(r.root, 'origin'))
        return r

    def _head(self, r):
        return subprocess.run(GIT + ['rev-parse', '-q', '--verify', 'HEAD'], cwd=r.work, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE).stdout.strip().decode()

    # --- what a flow must show ---------------------------------------------------------------------------------------
    def _nothing_before_the_pick(self, st, files, sub=''):
        """At the step-3 ask: no commit made, origin unchanged, argo-it's files still unsaved new files."""
        self.assertIsNotNone(st['ask'], 'the flow stopped before the step-3 ask: %r %r'
                             % (st['stopped'], st['res'] and st['res'].lines))
        self.assertEqual(st['ask']['head'], st['start'], 'argo-it saved before the user picked: a commit was made '
                         'before the step-3 ask')
        self.assertEqual(st['ask']['refs'], st['refs'], 'something was sent before the user picked')
        for f in files:
            self.assertIn('?? %s%s' % (sub + '/' if sub else '', f), st['ask']['status'].splitlines(),
                          "argo-it's %s isn't an unsaved new file at the step-3 ask" % f)

    def _sent_on_send_it(self, r, st, files, sub='', refs=None):
        """After "Send it": a check, then argo-it's save of exactly its files on top of the HEAD that check saw, then the
        push of that save: origin's `refs` are that commit."""
        self.assertIn(('pick', 1), st['trace'], 'the flow never reached "Send it": %r %r' % (st['stopped'], st['failed']))
        t = st['trace'][st['trace'].index(('pick', 1)):]
        saves = [i for i, e in enumerate(t) if e[0] == 'save']
        self.assertTrue(saves, 'on "Send it" argo-it never saved its files: %r %r' % (st['stopped'], st['failed']))
        s = saves[-1]
        checks = [e for e in t[:s] if e[0] == 'check']
        self.assertTrue(checks, "on \"Send it\" the check doesn't run again before argo-it's save")
        self.assertEqual(r.git('rev-parse', t[s][1] + '^').strip().decode(), checks[-1][1],
                         "argo-it's save doesn't sit on the HEAD the check saw")
        self.assertEqual(r.git('diff', '--name-only', checks[-1][1], t[s][1]).decode().split(),
                         sorted((sub + '/' if sub else '') + f for f in files), "argo-it's save holds more than its files")
        self.assertTrue([e for e in t[s:] if e[0] == 'push'], 'nothing is pushed after the save')
        for ref in refs or ('main', self.DEPLOY):
            self.assertEqual(self._ref(r, ref), t[s][1], "origin's %s is not the commit the check saw plus argo-it's "
                             "save" % ref)

    # --- the prose checks (each proven against its plain opposite in test_5) -----------------------------------------
    def _neg(self, s, at):
        return self._negated(s, at) or re.search(r'(?i)\bnothing\s+$', s[:at])

    def _ask_text(self, p):
        a = self._ask_at(p)
        e = p.find('**4. ', a)
        return p[a:e if e != -1 else len(p)]

    # argo-it's files are already saved: the one condition under which a "saved" said about them is true now
    FILES_SAVED = (r"(?i)\balready\s+saved\b|\b(?:are|is|were|stay|remain)\s+(?:already\s+)?(?:saved|tracked)\b"
                   r"|\bgit ls-files\b")

    def _minus_rerun(self, t):
        """t without the brackets where a "saved" is true: an innermost "[cond: ...]" whose condition (its text before
        the first ':') says argo-it's files are already saved (`FILES_SAVED`, not negated). A bracket keyed on a re-run
        alone, or on step 2 listing argo-it's earlier save, no longer counts: after a refused second push the files are
        saved and step 2 lists nothing, and after an earlier "Not now" a re-run has nothing saved (coordinator, after
        review 5: "saved" or "sent" only when that is true now)."""
        def drop(m):
            b = m.group(0)[1:-1]
            cond = b[:b.find(':')] if ':' in b else ''
            return ' ' if any(not self._neg(cond, x.start()) for x in re.finditer(self.FILES_SAVED, cond)) else m.group(0)
        return re.sub(r'\[[^\[\]]*\]', drop, t)

    def _ask_says_nothing_saved(self, ask):
        ss = self._sentences(self._flat(ask))
        self.assertTrue(ss and re.search(self.SAVED_NONE, ss[0]), "the step-3 ask doesn't open by saying nothing has "
                        "been saved or sent: %r" % ss[:1])
        for s in self._all_sentences(self._minus_rerun(ask)):
            for m in re.finditer(self.SAVED_CLAIM, s):
                self.assertTrue(self._neg(s, m.start()), 'the step-3 ask says the files are saved: %r' % s)
        opt4 = [u for u in self._units(ask) if re.match(r'4\.\s+\*\*Not now\b', u)]
        self.assertTrue(opt4, 'the step-3 ask has no "4. **Not now**" option')
        self.assertRegex(opt4[0], self.NOT_SAVED, "the ask's \"Not now\" doesn't say the files aren't saved: %r" % opt4[0])
        self.assertRegex(opt4[0], self.SENT_NONE, "the ask's \"Not now\" doesn't say nothing is sent: %r" % opt4[0])

    def _not_now_says_unsaved(self, sec):
        prose = re.sub(self.FENCE, '', sec, flags=re.M | re.S)
        flat = self._flat(prose)
        self.assertRegex(flat, self.NOT_SAVED, "Option 4 (not now) doesn't say the files aren't saved yet: %r" % flat)
        self.assertRegex(flat, r'(?i)\bfolder\b', "Option 4 doesn't say the files stay in the project folder: %r" % flat)
        self.assertRegex(flat, self.SENT_NONE, "Option 4 doesn't say nothing was sent: %r" % flat)
        for s in self._all_sentences(self._minus_rerun(prose)):
            for m in re.finditer(self.SAVED_CLAIM, s):
                self.assertTrue(self._neg(s, m.start()), 'Option 4 says the files are saved: %r' % s)

    def _try_and_show_save_nothing(self, p):
        for n in (2, 3):
            sec = p[slice(*self._option_at(p, n))]
            for f in self._fences(sec):
                self.assertFalse(self._git_does(f[2], 'add|commit|push|stash'), 'Option %d saves or sends: %r' % (n, f[2]))
            prose = re.sub(self.FENCE, '', sec, flags=re.M | re.S)
            self.assertRegex(self._flat(prose), self.KEEP_UNSAVED, "Option %d doesn't say it works on the unsaved files "
                             "(nothing is saved)" % n)
            for s in self._all_sentences(prose):
                for m in re.finditer(self.SAVE_DO, s):
                    self.assertTrue(self._neg(s, m.start()), 'Option %d saves: %r' % (n, s))
        for s in self._all_sentences(re.sub(self.FENCE, '', p, flags=re.M | re.S)):
            if re.search(r'(?i)\boption 2\b|\blocal try\b|\btry it on this computer\b', s) and re.search(r'(?i)\bfix', s):
                self.assertRegex(s, self.KEEP_UNSAVED, "a fix after option 2's local try isn't kept unsaved until "
                                 "\"Send it\": %r" % s)
                for m in re.finditer(r'(?i)\b(?:is|are|gets?|was|were)\s+saved\b|\bsav(?:e|es|ed)\s+(?:it|the fix'
                                     r'|its fix|that fix|your fix)\b', s):
                    self.assertTrue(self._neg(s, m.start()), "a fix after option 2's local try is saved before "
                                    "\"Send it\": %r" % s)

    def _no_rerun_swap(self, p):
        prose = re.sub(self.FENCE, '', p, flags=re.M | re.S)
        for s in self._all_sentences(prose):
            for m in re.finditer(self.SWAP, s):
                self.assertTrue(self._neg(s, m.start()), "PHASE 5 still swaps a stop to \"I haven't sent anything\", "
                                "but argo-it saves nothing before the save on \"Send it\": %r" % s)
        sec = re.sub(self.FENCE, '', p[slice(*self._option_at(p, 1))], flags=re.M | re.S)
        self.assertTrue(any(re.search(self.CHECK_AGAIN, s) and re.search(
            r"(?i)\bthe same way\b|\bas 2b\b|\b2b's (?:stops?|reading|rules|words)\b|\bas written\b", s)
            for s in self._all_sentences(sec)), "Option 1 doesn't read its check again as 2b reads it (2b's stops, in "
                                               "2b's words)")

    def _partial_push_message(self, sec, mark):
        b = self._rule(re.sub(self.FENCE, '', sec, flags=re.M | re.S), lambda u: '`%s`' % mark in u, [],
                       'a block that prints %s' % mark)
        qs = re.findall(r'"(I[^"]{20,})"', b)
        self.assertTrue(any('{deploy_branch}' in q and re.search(r'(?i)\bset up\b|\bwent through\b|\bis (?:now )?on '
                                                                 r'GitHub\b', q) and re.search(r'(?i)\bnothing else\b', q)
                            for q in qs),
                        "when only the first push went through, the message doesn't say only {deploy_branch} was set "
                        "up and nothing else was sent: %r" % qs)

    def _mistake_names_its_file(self, prose):
        """The words the stop says about argo-it's mistake (its "[If ...:" condition left out, the rest of its bracket
        kept) name the file it is in."""
        b = self._saved_hit_stops(prose)
        found = 0
        for q in re.findall(r'"(I[^"]{20,})"', b):
            for mm in re.finditer('mistake on my side', q):
                found += 1
                k, depth, a = mm.start(), 0, None
                for i in range(k - 1, -1, -1):  # the bracket it sits in, if any
                    if q[i] == ']':
                        depth += 1
                    elif q[i] == '[':
                        if not depth:
                            a = i
                            break
                        depth -= 1
                if a is None:
                    a, e = q.rfind('. ', 0, k) + 1, q.find('. ', k)
                else:
                    depth, e = 0, -1
                    for i in range(a + 1, len(q)):
                        if q[i] == '[':
                            depth += 1
                        elif q[i] == ']':
                            if not depth:
                                e = i
                                break
                            depth -= 1
                part = q[a:e if e != -1 else len(q)]
                c = part.find(':')
                said = part[c + 1:] if -1 < c < k - a else part
                self.assertRegex(said, self.SLOT, "the stop doesn't say which file is argo-it's mistake: %r" % said)
        self.assertTrue(found, 'the stop has no "mistake on my side" sentence')

    def _ask_excludes_own_save(self, ask):
        m = re.search(r'\[(?:If|if)\b([^:\]]*):\s*This also sends the \[M\] other saved changes', self._flat(ask))
        self.assertTrue(m, 'the step-3 ask has no "[If step 2 listed ...: This also sends the [M] other saved changes" '
                           'bracket')
        self.assertRegex(m.group(1), self.EXCL, "the ask can call argo-it's own earlier save \"the other saved changes "
                         "you haven't sent yet\": its bracket doesn't leave it out: %r" % m.group(1))

    def _send_it_reads(self, t):
        """What `_flow` acts on in Option 1 of `t`: the instructions read on the way, and SAVED SINCE THE CHECK's rule."""
        items = [it for it in self._script(t, *self._option_at(t, 1)) if it[0] == 'say']
        way = [k for it in items if it[2] is None for _, k, _ in self._instr(it[1])]
        rule = [k for it in items if isinstance(it[2], frozenset) and 'SAVED SINCE THE CHECK' in it[2]
                for _, k, _ in self._instr(it[1], True)]
        return way, rule

    def _checks_before_it_saves(self, t):
        self.assertEqual(self._send_it_reads(t)[0][:2], ['remember', 'check'], 'Option 1 does not remember HEAD and '
                         'then run the check again before it saves')

    def _moved_head_goes_back_to_the_check(self, t):
        """SAVED SINCE THE CHECK's rule goes back to a check, with HEAD remembered before that check, never after
        (coordinator, after review 4): "remember HEAD, then check, then this block again"; or Option 1 again, or step 2,
        2b and the step-3 ask again, whose own checks remember HEAD first (`_checks_before_it_saves`, `_flow`)."""
        ks = self._send_it_reads(t)[1]
        ends = [i for i, k in enumerate(ks) if k in ('rerun', 'restart', 'reask', 'step2')]
        self.assertTrue(ends, 'a moved HEAD neither runs the check again nor shows the step-3 ask again: %r' % ks)
        if ks[ends[0]] == 'rerun':
            way = ks[:ends[0]]
            self.assertIn('check', way, 'a moved HEAD saves again without running the check again: %r' % ks)
            at = len(way) - 1 - way[::-1].index('check')
            self.assertTrue('remember' in way[:at] and 'remember' not in way[at + 1:], 'a moved HEAD runs the check '
                            'again, but HEAD is not remembered before that check, or is remembered after it: %r' % ks)

    # --- 1. save on "Send it" (owner, after review 3; review 3 Important 2) ------------------------------------------
    def test_1a_a_send_every_save_hook_sends_nothing_before_the_pick_and_send_it_checks_saves_and_sends_that_commit(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                files = self._gen(r)
                st = self._flow(r, shell, files, hooks=self._send_hook(r))
                self._nothing_before_the_pick(st, files)
                self._sent_on_send_it(r, st, files)

    def test_1b_the_ask_not_now_try_it_and_show_me_say_nothing_is_saved_yet(self):
        p = self._phase()
        with self.subTest(what='the ask'):
            self._ask_says_nothing_saved(self._ask_text(p))
        with self.subTest(what='Option 4'):
            self._not_now_says_unsaved(p[slice(*self._option_at(p, 4))])
        with self.subTest(what='Options 2 and 3'):
            self._try_and_show_save_nothing(p)

    def test_1c_try_it_first_then_show_me_the_files_then_not_now_save_and_send_nothing(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                files = self._gen(r)
                st = self._flow(r, shell, files, hooks=self._send_hook(r), picks=(2, 3, 4))
                self._nothing_before_the_pick(st, files)
                self.assertEqual(self._head(r), st['start'], "a pick other than Send it saved argo-it's files")
                self.assertEqual(self._origin(r, 'for-each-ref'), st['refs'], 'a pick other than Send it sent something')
                status = r.git('status', '--porcelain', '-uall').decode().splitlines()
                self.assertEqual(sorted(l for l in status if l[3:] in files), sorted('?? ' + f for f in files))

    def test_1d_a_fix_after_try_it_first_stays_unsaved_and_send_it_checks_it(self):
        # review 3 Important 2's second input: argo-it's own fix after the local try holds a fake key
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                v = fake('tryfix' + shell)
                r = self.fresh()
                files = self._gen(r, extra={self.REL: self.CM})
                st = self._flow(r, shell, files, hooks=self._send_hook(r), picks=(2, 1),
                                after_pick=lambda n: r.write(self.REL, self._keyed(v)[self.REL]))
                self.assertFalse(_b(v) in self._sent_objects(r), "argo-it's fix after the local try was sent: its fake "
                                 "key reached origin")
                self.assertEqual(st['stopped'], 'a hit counts', 'on "Send it" the check did not stop on the fix: %r'
                                 % (st['res'] and st['res'].lines))
                self.assertIn(('pick', 1), st['trace'][:-1], 'the stop came before "Send it"')
                self.assertEqual(self._head(r), st['start'], 'argo-it saved before the check that stopped')
                self.assertEqual(self._origin(r, 'for-each-ref'), st['refs'], 'something was sent before the stop')
                self.check(st['res'], new=[self.REL + ':4'], secrets=[v])

    def test_1e_send_it_runs_the_check_again_and_a_check_that_cannot_run_stops_with_nothing_saved_or_sent(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()

                def unreadable():  # while the agent waits: the check can't run now (an unreadable MERGE_HEAD, exit 2)
                    with open(os.path.join(r.work, '.git', 'MERGE_HEAD'), 'w') as f:
                        f.write('not a commit\n')
                st = self._flow(r, shell, self._gen(r), between=unreadable)
                self.assertEqual(st['stopped'], "couldn't check", 'on "Send it" the check did not run again, or its '
                                 'exit 2 did not stop the send: %r' % ((st['res'] and (st['res'].code, st['res'].lines)),))
                self.assertEqual(st['res'].code, 2)
                self.assertEqual(self._head(r), st['start'], "argo-it saved though the check couldn't run")
                self.assertEqual(self._origin(r, 'for-each-ref'), st['refs'], "something was sent though the check "
                                 "couldn't run")

    # --- 2. review 3 Important 1: the HEAD the check saw is what gets saved and sent ----------------------------------
    def test_2a_a_commit_saved_between_the_check_and_argo_its_save_never_reaches_origin(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                v = fake('gapsave' + shell)
                r = self.fresh()
                mine = []

                def user_saves():  # the user saves their own file (another terminal), between the check and the save
                    r.write('settings.py', kv('API_' + 'KEY', v))
                    r.git('add', '--', 'settings.py')
                    r.git('commit', '-q', '-m', 'my change')
                    mine.append(self._head(r))
                st = self._flow(r, shell, self._gen(r), after_check=user_saves)
                self.assertTrue(mine, 'the flow never reached the moment between the check and the save: %r %r'
                                % (st['stopped'], st['failed']))
                self.assertFalse(_b(v) in self._sent_objects(r), "a commit saved between the check and argo-it's save "
                                 "was sent unchecked: its fake key reached origin")
                self.assertEqual(st['stopped'], 'a hit counts', 'the moved HEAD did not send the flow back to the '
                                 'check: %r %r' % ((st['res'] and st['res'].lines), st['failed']))
                self.assertEqual(self._origin(r, 'for-each-ref'), st['refs'], 'something was sent')
                self.assertEqual(self._head(r), mine[0], "argo-it saved on top of a commit no check saw")
                self.check(st['res'], saved=['settings.py:1'], secrets=[v])

    def test_2b_after_a_clean_commit_between_the_check_and_the_save_the_check_runs_again_and_that_is_what_is_sent(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                mine = []

                def user_saves():
                    r.write('notes.md', '# my plan\n')
                    r.git('add', '--', 'notes.md')
                    r.git('commit', '-q', '-m', 'my notes')
                    mine.append(self._head(r))
                files = self._gen(r)
                st = self._flow(r, shell, files, after_check=user_saves, picks=(1, 1))
                self.assertTrue(mine, 'the flow never reached the moment between the check and the save')
                self.assertIsNone(st['stopped'], 'a clean commit between the check and the save stopped the send: %r'
                                  % st['stopped'])
                self.assertIsNone(st['failed'])
                self.assertIn(('check', mine[0]), st['trace'], 'the check never ran again on the commit saved after it')
                self._sent_on_send_it(r, st, files)

    # --- 3. the recovery and failure text, driven through each branch (review 3 Minor 1) -----------------------------
    def test_3a_in_a_project_below_the_repos_top_a_hit_is_matched_to_argo_its_files_by_its_path_from_the_top(self):
        sub = 'apps/web'
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell, what='a fake key in a generated file'):
                v = fake('subdir' + shell)
                r = self.fresh()
                st = self._flow(r, shell, self._gen(r, sub, self._keyed(v)), sub=sub)
                self.assertFalse(_b(v) in self._sent_objects(r), "a hit in argo-it's file, printed from the repo's top, "
                                 "wasn't matched to it: its fake key reached origin")
                self.assertEqual(st['stopped'], 'a hit counts')
                self.assertEqual(self._head(r), st['start'])
                self.check(st['res'], new=[sub + '/' + self.REL + ':4'], secrets=[v])
            with self.subTest(shell=shell, what='clean'):
                r = self.fresh()
                files = self._gen(r, sub)
                st = self._flow(r, shell, files, sub=sub)
                self._nothing_before_the_pick(st, files, sub)
                self._sent_on_send_it(r, st, files, sub)

    def test_3b_no_stop_says_argo_its_save_is_already_made_and_send_it_reads_its_check_as_2b_does(self):
        self._no_rerun_swap(self._phase())

    def test_3c_a_refused_first_push_sends_nothing_and_never_goes_on_to_the_second(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                files = self._gen(r)
                self._refuse(r, 'refs/heads/' + self.DEPLOY)
                st = self._flow(r, shell, files)
                self.assertIsNotNone(st['sent'], 'Option 1 never pushed: %r %r' % (st['stopped'], st['failed']))
                self.assertNotEqual(st['sent'].returncode, 0, 'a refused first push looks like it worked')
                self.assertEqual(self._origin(r, 'for-each-ref'), st['refs'], 'the first push was refused and the '
                                 'second still went out')
                self.assertTrue(st['failed'], "the refused push isn't handled by a rule PHASE 5 names")
                self._nothing_before_the_pick(st, files)

    def test_3d_a_refused_second_push_says_only_the_deploy_branch_was_set_up(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                files = self._gen(r)
                main0 = self._ref(r, 'main')
                self._refuse(r, 'refs/heads/main')
                st = self._flow(r, shell, files)
                self.assertTrue(st['failed'], "the refused second push isn't handled by a rule PHASE 5 names: %r"
                                % st['stopped'])
                self.assertEqual(self._ref(r, self.DEPLOY), st['saved'], 'the first push did not set up %s from what '
                                 "was checked plus argo-it's save" % self.DEPLOY)
                self.assertEqual(self._ref(r, 'main'), main0)
                p = self._phase()
                self._partial_push_message(p[slice(*self._option_at(p, 1))], st['failed'])
                self._nothing_before_the_pick(st, files)

    # --- 4. review 3's other Minors ------------------------------------------------------------------------------------
    def test_4a_a_first_deploy_in_a_repo_with_no_commits_yet_is_checked_and_reaches_the_ask(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell, what='clean'):
                r = self._unborn()
                st = self._flow(r, shell, self._gen(r), picks=())
                self.assertIsNotNone(st['ask'], 'a clean first deploy in a repo with no commits yet stops before the ask: '
                                     '%r %r' % (st['stopped'], st['res'] and (st['res'].code, st['res'].lines)))
                self.check(st['res'])
                self.assertEqual((st['ask']['head'], st['ask']['refs']), ('', b''))
            with self.subTest(shell=shell, what='a fake key in a generated file'):
                v = fake('unborn' + shell)
                r = self._unborn()
                st = self._flow(r, shell, self._gen(r, extra=self._keyed(v)), picks=())
                self.assertEqual(st['stopped'], 'a hit counts', 'the check in a repo with no commits yet did not stop on '
                                 'a hit: %r' % ((st['res'] and (st['res'].code, st['res'].lines)),))
                self.check(st['res'], new=[self.REL + ':4'], secrets=[v])

    def test_4b_an_escaped_hit_path_stops_even_in_argo_its_own_folders(self):
        sub = 'apps/we\tb'  # a tab in the project folder's name: the scanner prints it as \x09
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                v = fake('escaped' + shell)
                r = self.fresh()
                st = self._flow(r, shell, self._gen(r, sub, self._keyed(v)), sub=sub)
                self.assertFalse(_b(v) in self._sent_objects(r), 'a hit whose path is escaped was read as not counting: '
                                 'its fake key reached origin')
                self.assertEqual(st['stopped'], 'a hit counts')
                self.assertEqual(self._head(r), st['start'])
                self.check(st['res'], new=['apps/we\\x09b/' + self.REL + ':4'], secrets=[v])

    def test_4c_when_an_older_unsent_hit_and_a_hit_in_argo_its_file_stop_together_the_stop_names_argo_its_file(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                v1, v2 = fake('oldmix' + shell), fake('genmix' + shell)
                r = self.fresh()
                r.append('app.py', kv('API_' + 'KEY', v1))
                r.commit('older change, never sent')
                st = self._flow(r, shell, self._gen(r, extra=self._keyed(v2)))
                self.assertEqual(st['stopped'], 'a hit counts')
                self.check(st['res'], new=[self.REL + ':4'], saved=['app.py:2'], secrets=[v1, v2])
                self.assertEqual(self._head(r), st['start'])
                self.assertEqual(self._origin(r, 'for-each-ref'), st['refs'])
        with self.subTest(what='text'):
            self._mistake_names_its_file(self._prose())

    def test_4d_the_ask_never_calls_argo_its_own_earlier_save_the_users_unsent_changes(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                _refuse_every_push(r)
                first = self._flow(r, shell, self._gen(r))  # Send it; the push is refused
                self.assertTrue(first['saved'] and first['sent'] and first['sent'].returncode,
                                'the first run did not save and then fail to send: %r %r' % (first['stopped'],
                                                                                            first['failed']))
                # owner, after review 6: the save moves no branch until a copy is on GitHub, so nothing of argo-it's is
                # saved here after a refused push, and the re-run's list can't call it the user's
                self.assertEqual(self._head(r), first['start'], 'a refused push left argo-it\'s save on the branch here')
                st = self._flow(r, shell, self._gen(r), picks=())  # /argo-it again: up to the step-3 ask
                listed = [l.split()[0] for code, cp in st['outputs'] if 'git log --oneline' in code
                          for l in cp.stdout.decode().splitlines() if l.strip()]
                self.assertFalse(any(first['saved'].startswith(x) for x in listed), "step 2's list names argo-it's "
                                 "own save: %r" % listed)
                self._nothing_before_the_pick(st, self.GENERATED)
        with self.subTest(what='text'):
            self._ask_excludes_own_save(self._ask_text(self._phase()))

    # --- 5. polarity: each new prose check and reader passes a plain reading and fails its plain opposite -------------
    GOOD3 = '\n'.join((
        "**2b. Secret check** -- read the result exactly as 3e does. A hit counts here when it sits under",
        '`== saved, not sent ==`, or when it is in a file the save on "Send it" will save (one of argo-it\'s generated',
        "files, by its path from the repo's top folder), whatever its label. A hit whose path holds `\\xNN` or",
        "`\\uXXXX` counts too: its name can't be matched safely.",
        '',
        '**If any hit counts (under `== saved, not sent ==`, or in a file the save will save): stop here.** Don\'t',
        'show the step-3 ask; nothing is sent. Tell the user:',
        '',
        '"I found what looks like a password or secret key on **line [N] of [file]**. [If a hit sits under',
        "`== saved, not sent ==`: The one in **[file]** is in a change you already saved but haven't sent yet.] [If a",
        'hit is in a file argo-it generated: **[file]** is one of the setup files I made. That one is a mistake on my',
        'side, not something you did.]',
        "Secrets should never be saved in code, so I won't send this. I haven't saved or sent anything.\"",
        '',
        '**3. Ask the user what they want to do:**',
        '',
        "\"I've generated your deployment pipeline -- it's ready in your project folder, and nothing has been saved",
        'or sent yet.',
        '',
        "[If step 2 listed saved changes other than argo-it's own earlier save of these files: This also sends the [M]",
        "other saved changes you haven't sent yet, which touch [what they touch].]",
        '',
        '**What would you like to do?**',
        '',
        '1. **Send it -- deploys to {hostname}** -- I save these files and send them',
        '2. **Try it on this computer first** -- nothing is saved or sent',
        '3. **Show me the files first** -- nothing is saved or sent',
        '4. **Not now** -- the files stay in your project folder, not saved yet; nothing is sent"',
        '',
        '**4. Execute based on user choice:**',
        '',
        "**Option 1 (send):** Remember `git rev-parse HEAD` as `{checked_head}`, then run 2b's check again and read it",
        'the same way.',
        '',
        '```bash',
        '[ "$(git rev-parse HEAD)" = "{checked_head}" ] || { echo "SAVED SINCE THE CHECK"; exit 3; }',
        'git commit -q -m "Add K8s manifests" -- {generated_files}',
        'git rev-parse HEAD',
        '```',
        '',
        'If the block prints `SAVED SINCE THE CHECK`, remember the new `git rev-parse HEAD` as `{checked_head}`, then',
        'run 2b again; if no hit counts, run this block again. Otherwise remember the commit id it prints',
        'as `{saved_head}`.',
        '',
        '```bash',
        'git push origin {saved_head}:refs/heads/{deploy_branch} || { echo "PUSH 1 FAILED"; exit 1; }',
        'git push origin {saved_head}:refs/heads/main || { echo "PUSH 2 FAILED"; exit 1; }',
        '```',
        '',
        '**If either push fails** (the block prints `PUSH 1 FAILED` or `PUSH 2 FAILED`), never say "Pushed!". Tell the',
        'user:',
        '',
        '"I couldn\'t send your setup to GitHub, so [nothing was sent / if the first one went through: only the copy the',
        'deployment system watches, `{deploy_branch}`, was set up there, and nothing else was sent]. What to do next:',
        '[the fix], then run /argo-it again."',
        '',
        '**Option 2 (local test):** it works on the unsaved files: nothing is saved. A fix after the local try stays',
        'unsaved until "Send it".',
        '',
        '**Option 3 (show the files):** describe each file; nothing is saved or sent.',
        '',
        '**Option 4 (not now):** say the files stay in the project folder, not saved yet, and nothing was sent.',
        '',
        '**5. Report success:**',
        ''))

    def test_5_control_new_prose_checks_and_readers_are_polarity_bound(self):  # control: passes today
        def prose(t):
            return re.sub(self.FENCE, '', t, flags=re.M | re.S)

        def sec(n):
            return lambda t: t[slice(*self._option_at(t, n))]
        g = self.GOOD3
        checks = {
            '_ask_says_nothing_saved': (self._ask_text, [
                ('and nothing has been saved\nor sent yet.', "and I've saved it there -- nothing has been sent yet."),
                ("it's ready in your project folder, and nothing has been saved\nor sent yet.",
                 "it's saved in your project folder -- nothing has been sent yet."),
                ('4. **Not now** -- the files stay in your project folder, not saved yet; nothing is sent',
                 '4. **Not now** -- everything stays saved in your project folder; nothing is sent')]),
            '_not_now_says_unsaved': (sec(4), [
                ('say the files stay in the project folder, not saved yet, and nothing was sent.',
                 'say the files are saved in the project folder and nothing was sent.'),
                ('not saved yet, and nothing was sent', 'and nothing was sent')]),
            '_try_and_show_save_nothing': (lambda t: t, [
                ('A fix after the local try stays\nunsaved until "Send it".', 'A fix after the local try is saved, then '
                                                                             'checked.'),
                ('describe each file; nothing is saved or sent.', 'describe each file, then save them.'),
                ('it works on the unsaved files: nothing is saved.', 'save the files first, then run the local try.')]),
            '_no_rerun_swap': (lambda t: t, [
                ('the same way.\n\n```bash', "the same way. On a stop, say \"I haven't sent anything\" in place of \"I "
                                            "haven't saved or sent anything\", since 2c's save is already made.\n\n```bash"),
                ("then run 2b's check again and read it\nthe same way.", "then run 2b's check again.")]),
            '_partial_push_message': (lambda t: (sec(1)(t), 'PUSH 2 FAILED'), [
                ('[nothing was sent / if the first one went through: only the copy the\ndeployment system watches, '
                 '`{deploy_branch}`, was set up there, and nothing else was sent]', 'nothing was sent')]),
            '_mistake_names_its_file': (prose, [
                ('**[file]** is one of the setup files I made. That one', 'That one')]),
            '_ask_excludes_own_save': (self._ask_text, [
                ("[If step 2 listed saved changes other than argo-it's own earlier save of these files:",
                 '[If step 2 listed saved changes:'),
                ("[If step 2 listed saved changes other than argo-it's own earlier save of these files:",
                 "[If step 2 listed saved changes, argo-it's own earlier save among them:")]),
            '_from_top': (prose, [
                ("by its path from the repo's top folder", 'by its path from the project root'),
                ("by its path from the repo's top folder", "not by its path from the repo's top folder")]),
            '_escaped_counts': (prose, [
                ("counts too: its name can't be matched safely.", "doesn't count: its name can't be matched."),
                ("A hit whose path holds `\\xNN` or\n`\\uXXXX` counts too: its name can't be matched safely.", '')]),
            '_checks_before_it_saves': (lambda t: t, [
                ("then run 2b's check again", "there's no need to run 2b's check again"),
                ("Remember `git rev-parse HEAD` as `{checked_head}`, then run 2b's check again and read it\nthe same way.",
                 "Run 2b's check again and read it the same way, then remember `git rev-parse HEAD` as\n"
                 "`{checked_head}`.")]),
            '_moved_head_goes_back_to_the_check': (lambda t: t, [
                ('then\nrun 2b again; if no hit counts, run', "and don't run 2b again; run"),
                ('remember the new `git rev-parse HEAD` as `{checked_head}`, then\nrun 2b again; if no hit counts, run this '
                 'block again.', 'run 2b again; if no hit counts, remember the new\n`git rev-parse HEAD` as `{checked_head}` '
                 'and run this block again.'),
                ('remember the new `git rev-parse HEAD` as `{checked_head}`, then\nrun', 'keep `{checked_head}`, then\nrun'),
                ('run this block again.', 'stop.')]),
        }
        bools = ('_from_top', '_escaped_counts')
        for name, (view, swaps) in checks.items():
            fn = getattr(self, name)

            def check(t, fn=fn, view=view, name=name):
                v = view(t)
                if name in bools:
                    self.assertTrue(fn(v))
                elif isinstance(v, tuple):
                    fn(*v)
                else:
                    fn(v)
            with self.subTest(check=name, text='plain reading'):
                check(g)
            for old, opposite in swaps:
                self.assertIn(old, g)
                with self.subTest(check=name, opposite=opposite[:60]):
                    with self.assertRaises(AssertionError):
                        check(g.replace(old, opposite))



# ArgoItFirstSendFix2Cases' helpers (not its tests), for fix round 3 below.
_FirstSendFix2 = type('_FirstSendFix2', (object,), {k: v for k, v in ArgoItFirstSendFix2Cases.__dict__.items()
                                                    if not k.startswith(('test', '__'))})


class ArgoItFirstSendFix3Cases(_FirstSendFix2, _FirstSendAdv1, _FirstSendFix1, _FirstSend, Base):
    """Task 3 review 4 and the coordinator's calls after it (2026-10-19): HEAD is remembered before every check, the
    retry's too; a moved HEAD or a switched branch since the ask sends the flow back to step 2, 2b and the step-3 ask,
    which names what is new, and nothing is sent the ask didn't name; the save holds only argo-it's files (a user's own
    pre-commit hook can stage more), else it stops and says so; step 2's fetch prunes; an escaped hit's stop points at
    3e's escaped-name sentences; the messages are true on a re-run after a refused push, after the user's own hook already
    sent the save, and for a setup file the user edited while the ask waited. Prose checks and readers are proven against
    their plain opposites in test_7. Values and secret-named lines are joined at run time (GitGuardian scans this file)."""

    SENT_NO = ArgoItFirstSendScanCases.SENT_NONE + r"|\b(?:not|n't)\s+(?:been\s+|yet\s+)?sent\b"
    SAVED_NEG = r"(?i)(?:\b(?:not|nothing|never|no)\b|n't\b)(?:\s+\w+){0,3}\s+$"
    NAMING = r"(?i)\bnam(?:e|es|ing)\b[^.;]{0,60}?\b(?:new|changed|branch|commits?|saves?|what)\b"
    ESC = r"\\xNN|\\uXXXX|(?i:\bescaped\b|\bunusual character\b)"
    NEXT_STEP = r"(?i)\bnext step\b|\bwhat to do next\b|\bplain names?\b"
    ORIGIN_CHECK = r"\bgit\s+ls-remote\b|\bgit\s+branch\s+(?:-r|--remotes)\s+--contains\b"
    ALREADY_SENT = (r"(?i)\balready\b[^.\]]{0,40}?\b(?:sent|on GitHub|reached GitHub|went (?:out|through))\b"
                    r"|\b(?:sent|went out)\b[^.\]]{0,20}?\balready\b")
    NARROW = (r"(?i)\bfirst check\b|\b2b's (?:first )?check\b|\bbefore the ask\b|\bat the ask\b|\boption 2\b"
              r"|\bthe local try\b|\bfix(?:es)? I (?:made|wrote)\b|\bmy (?:own )?fix\b"
              r"|\bI (?:wrote|put) (?:it|the line|that line|the value)\b|\bunchanged\b|\bas I (?:made|wrote) it\b"
              r"|\bnot (?:changed|edited)\b|\bhasn't changed\b")
    CHANGED_AFTER = (r"(?i)\b(?:changed|edited)\b[^.\]]{0,40}?\b(?:after|since)\s+(?:I|argo-it)\s+(?:made|wrote|generated"
                     r"|created)\s+it\b|\b(?:changed|edited)\b[^.\]]{0,40}?\b(?:while (?:I|you|the ask|argo-it) "
                     r"(?:was |were )?(?:wait|waited|waiting|waits)\b|during the wait\b|since the ask\b"
                     r"|after the (?:first )?check\b)")
    ONLY_WHEN = (r"(?i)\bmistake on my side\b[^.]{0,120}\bonly\s+(?:when|if)\b|\bonly\s+(?:when|if)\b[^.]{0,120}"
                 r"\bmistake on my side\b|\bin place of\b[^.]{0,40}\bmistake on my side\b")

    # --- fixtures --------------------------------------------------------------------------------------------------
    def _add_all_hook(self, r):
        """The fixture's own hooks folder (core.hooksPath, nowhere else) with the user's "format, then re-add"
        pre-commit: it stages everything in the project."""
        hooks = os.path.join(r.root, 'hooks')
        os.makedirs(hooks, exist_ok=True)
        path = os.path.join(hooks, 'pre-commit')
        with open(path, 'w') as f:
            f.write('#!/bin/sh\ngit add -A\n')
        os.chmod(path, 0o755)
        return hooks

    def _commit_one(self, r, rel, text, msg, mine):
        """The user saves only `rel` (another terminal, or their editor's Commit button); its id goes on `mine`."""
        r.write(rel, text)
        r.git('add', '--', rel)
        r.git('commit', '-q', '-m', msg)
        mine.append(self._head(r))

    def _off_origin(self, r, how, tag):
        """A fake key saved and sent once, then taken off origin (DevOps' cleanup), objects and all. This clone isn't
        refetched, so a branch it still tracks says the key's commit was sent. Returns the key."""
        v = fake('offorigin' + tag)
        c0 = r.git('rev-parse', 'HEAD').strip().decode()
        r.write('settings.py', kv('API_' + 'KEY', v))
        r.commit('my key')
        if how == 'deleted':  # sent to a branch of its own, which origin then drops
            r.git('push', '-q', 'origin', 'HEAD:refs/heads/wip')
            self._origin(r, 'update-ref', '-d', 'refs/heads/wip')
        else:  # sent to main, which origin then rewinds
            r.push()
            self._origin(r, 'update-ref', 'refs/heads/main', c0)
        self._origin(r, 'gc', '-q', '--prune=now')
        self.assertFalse(_b(v) in self._sent_objects(r), 'fixture: the key is still on origin after it was taken off')
        return v

    # --- what a flow must show ---------------------------------------------------------------------------------------
    def _asks_again(self, r, st, files, new=None):
        """On "Send it", the flow went back to step 2 and 2b and showed the step-3 ask again before anything was saved
        or sent, and step 2's list there names `new` (the change saved since the ask), so the ask names it."""
        t = st['trace']
        self.assertIn(('pick', 1), t, 'the flow never reached "Send it": %r %r' % (st['stopped'], st['failed']))
        k = t.index(('pick', 1))
        again = [i for i, e in enumerate(t) if e[0] == 'ask' and i > k]
        self.assertTrue(again, 'on "Send it", the flow never showed the step-3 ask again: %r %r %r'
                        % (st['stopped'], st['failed'], [e for e in t[k:] if e[0] != 'check']))
        seg = t[k:again[0]]
        self.assertFalse([e for e in seg if e[0] in ('save', 'push')], 'argo-it saved or sent before the user picked '
                         'again: %r' % seg)
        self.assertTrue([e for e in seg if e[0] == 'check'], '2b did not run again before the ask was shown again')
        self.assertEqual(self._origin(r, 'for-each-ref'), st['refs'], 'something was sent before the user picked again')
        for f in files:
            self.assertIn('?? ' + f, st['asks'][1]['status'].splitlines(), "argo-it's %s isn't an unsaved new file "
                          "when the ask is shown again" % f)
        logs = [cp for code, cp in st['outputs'] if 'git log --oneline' in code]
        self.assertGreaterEqual(len(logs), 2, "step 2 didn't run again before the ask was shown again")
        if new:
            listed = [l.split()[0] for l in logs[-1].stdout.decode().splitlines() if l.strip()]
            self.assertTrue(any(new.startswith(x) for x in listed), "step 2's list, when the ask is shown again, "
                            "doesn't name the change saved since the ask: %r" % listed)

    # --- the prose checks (each proven against its plain opposite in test_7) ------------------------------------------
    def _cands(self, t):
        """Where a rule or a message part sits: t's sentences, and each innermost [...] in it, flattened."""
        return self._all_sentences(t) + re.findall(r'\[([^\[\]]*)\]', self._flat(t))

    def _says(self, rx, s):
        """s says rx, not negated."""
        return any(not self._neg(s, m.start()) for m in re.finditer(rx, s))

    def _reask_names_what_is_new(self, t):
        self.assertTrue(any((self._says(self.REASK, s) or self._says(self.BACK2, s)) and self._says(self.NAMING, s)
                            for s in self._all_sentences(t)),
                        "PHASE 5 never shows the step-3 ask again naming what is new (the change saved, or the branch "
                        "switched to, since the ask)")

    def _escaped_stop_points_at_3e(self, prose):
        self.assertTrue(any(re.search(self.ESC, c) and self._says(r'\b3e\b', c) and re.search(self.NEXT_STEP, c)
                            for c in self._cands(prose)),
                        "a stop on a hit whose path holds \\xNN or \\uXXXX doesn't point at 3e's escaped-name sentences "
                        "and their next step")

    def _says_saved_on_a_rerun(self, u):
        return any(re.search(self.EARLIER, c) and re.search(self.SENT_NO, c) and any(
            not re.search(self.SAVED_NEG, c[:m.start()]) for m in re.finditer(r'(?i)\bsaved\b', c))
            for c in self._cands(u))

    def _rerun_says_saved(self, p):
        units = self._units(self._ask_text(p))
        opt4 = [u for u in units if re.match(r'4\.\s+\*\*Not now\b', u)]
        self.assertTrue(opt4, 'the step-3 ask has no "4. **Not now**" option')
        sec4 = re.sub(self.FENCE, '', p[slice(*self._option_at(p, 4))], flags=re.M | re.S)
        for what, u in (("the step-3 ask's opening", units[0]), ('the ask\'s "Not now"', opt4[0]), ('Option 4', sec4)):
            self.assertTrue(self._says_saved_on_a_rerun(u), "%s has no re-run wording (argo-it's earlier save listed "
                            "in step 2): the files are saved from last time, but nothing has been sent: %r"
                            % (what, self._flat(u)))

    def _failed_push_checks_github(self, sec):
        code = '\n'.join(l for f in self._fences(sec) for l in f[2].splitlines() if not l.lstrip().startswith('#'))
        prose = re.sub(self.FENCE, '', sec, flags=re.M | re.S)
        self.assertTrue(re.search(self.ORIGIN_CHECK, code) or any(self._says(self.ORIGIN_CHECK, s)
                                                                  for s in self._all_sentences(prose)),
                        "Option 1 never looks at what GitHub already holds (`git ls-remote origin`) before it says "
                        "nothing was sent")
        b = self._rule(prose, lambda u: re.search(self.FAILED, u) or '`PUSH 1 FAILED`' in u, [], 'a push that fails')
        self.assertTrue(any(self._says(self.ALREADY_SENT, c) for c in self._cands(b)),
                        "a failed push never says that the project's own setup already sent the save: %r" % b)

    @staticmethod
    def _part_around(q, k):
        """(start, end, in a bracket?) of the innermost [...] in q around position k, else of the sentence there."""
        depth, a = 0, None
        for i in range(k - 1, -1, -1):
            if q[i] == ']':
                depth += 1
            elif q[i] == '[':
                if not depth:
                    a = i
                    break
                depth -= 1
        if a is None:
            e = q.find('. ', k)
            return q.rfind('. ', 0, k) + 1, e if e != -1 else len(q), False
        depth = 0
        for i in range(a + 1, len(q)):
            if q[i] == '[':
                depth += 1
            elif q[i] == ']':
                if not depth:
                    return a, i + 1, True
                depth -= 1
        return a, len(q), True

    def _mistake_only_when_mine(self, t):
        """A hit in a setup file the user changed after argo-it made it isn't called argo-it's mistake: some stop says
        the file changed after argo-it made it, and "mistake on my side" is said only when argo-it's own check or fix
        put the line there (its bracket's condition narrows), or with that other cause beside it."""
        self.assertTrue(any(self._says(self.CHANGED_AFTER, c) and not self._says(r'(?i)\bmistake on my side\b', c)
                            for c in self._cands(t)),
                        "no stop says that a setup file argo-it made changed after it made it (the user's edit while "
                        "the ask waited) without calling it argo-it's mistake")
        outside = re.sub(r'"(?:I|Pushed|Your)[^"]{20,}"', ' . ', t)
        if any(re.search(self.ONLY_WHEN, s) for s in self._all_sentences(outside)):
            return
        found = 0
        for q in re.findall(r'"(I[^"]{20,})"', self._flat(t)):
            for mm in re.finditer(r'mistake on my side', q):
                found += 1
                a, e, br = self._part_around(q, mm.start())
                part, k = q[a:e], mm.start() - a
                c = part.find(':')
                cond = part[:c] if br and -1 < c < k else ''
                s1 = part.find('. ', k)
                sent = part[part.rfind('. ', 0, k) + 1:s1 if s1 != -1 else len(part)]
                self.assertTrue(re.search(self.NARROW, cond) or re.search(self.NARROW, sent)
                                or re.search(self.CHANGED_AFTER, sent),
                                "\"mistake on my side\" is said for any hit in a setup file argo-it made, even one the "
                                "user changed after argo-it made it: %r" % part)
        self.assertTrue(found, 'the stop has no "mistake on my side" sentence')

    # --- 1. review 4 Important 1: HEAD is remembered before the retry's check too -------------------------------------
    def test_1_a_save_made_right_after_the_retrys_check_never_reaches_origin(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                v = fake('retrygap' + shell)
                r = self.fresh()
                mine = []
                st = self._flow(r, shell, self._gen(r), picks=(1, 1), after_check=[
                    lambda: self._commit_one(r, 'notes.md', '# my plan\n', 'my notes', mine),  # after the Send-it check
                    lambda: self._commit_one(r, 'settings.py', kv('API_' + 'KEY', v), 'my key', mine)])  # the retry's
                self.assertEqual(len(mine), 2, "the flow never reached the moment right after the retry's check: %r %r"
                                 % (st['stopped'], st['failed']))
                self.assertFalse(_b(v) in self._sent_objects(r), "a save made right after the retry's check was sent "
                                 "unchecked: its fake key reached origin (HEAD was remembered after that check)")
                self.assertEqual(st['stopped'], 'a hit counts', 'the second save did not send the flow back to a check '
                                 'that stops on it: %r %r' % ((st['res'] and st['res'].lines), st['failed']))
                self.check(st['res'], saved=['settings.py:1'], secrets=[v])
                self.assertEqual(self._origin(r, 'for-each-ref'), st['refs'], 'something was sent')

    # --- 2. review 4 Important 2: the save holds only argo-it's files --------------------------------------------------
    def test_2_a_users_pre_commit_hook_that_stages_everything_never_sends_their_unsaved_keys(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                v1, v2 = fake('hookedit' + shell), fake('hooknew' + shell)
                r = self.fresh()
                r.append('app.py', kv('API_' + 'KEY', v1))  # the user's unsaved edit
                r.write('cfg.py', kv('TO' + 'KEN', v2))  # and their own new file: neither is part of this send
                files = self._gen(r)
                st = self._flow(r, shell, files, hooks=self._add_all_hook(r))
                self._nothing_before_the_pick(st, files)
                sent = self._sent_objects(r)
                self.assertFalse(_b(v1) in sent or _b(v2) in sent, "the user's own pre-commit hook staged their files "
                                 "into argo-it's save, and it was sent: a fake key reached origin")
                # owner, after review 6: no hook runs on argo-it's save, so it holds only argo-it's files and is sent
                # (SAVE HELD MORE goes away); the user's own files stay as they were
                self.assertFalse(st['stopped'] or st['failed'], '%r %r' % (st['stopped'], st['failed']))
                self._sent_on_send_it(r, st, files)
                self.assertEqual(r.git('status', '--porcelain', '--', 'app.py', 'cfg.py').decode().splitlines(),
                                 [' M app.py', '?? cfg.py'], "the user's own files aren't as they were")
                t = st['trace']
                k = len([e for e in t[:max(i for i, e in enumerate(t) if e[0] == 'save')] if e[0] == 'check'])
                self.check(st['results'][k - 1], unsaved=['app.py:2'], new=['cfg.py:1'], secrets=[v1, v2])  # Send it's
                for res in st['results'] + [Result(cp, 0) for _, cp in st['outputs']]:  # check before the save
                    self.no_leak(res, [v1, v2])

    # --- 3. review 4 Important 3: a change saved, or a branch switched, since the ask ---------------------------------
    def test_3_a_change_saved_or_a_branch_switched_since_the_ask_shows_the_ask_again_naming_what_is_new(self):
        for shell in ('bash', 'zsh'):
            for case in ('a commit while the ask waits', 'a branch switch while the ask waits',
                         'a commit between the Send-it check and the save'):
                with self.subTest(shell=shell, case=case):
                    r = self.fresh()
                    files = self._gen(r)
                    mine = []

                    def commit():
                        self._commit_one(r, 'notes.md', '# my plan\n', 'my notes', mine)
                    if 'branch' in case:
                        kw = {'between': lambda: r.git('checkout', '-q', '-b', 'experiment')}
                    else:
                        kw = {'between': commit} if case.endswith('waits') else {'after_check': commit}
                    st = self._flow(r, shell, files, **kw)
                    self.assertIsNotNone(st['ask'], 'the clean check stopped before the ask: %r' % st['stopped'])
                    if 'commit' in case:
                        self.assertTrue(mine, 'the user never saved their change: %r' % st['stopped'])
                    self._asks_again(r, st, files, mine[0] if mine else None)
        with self.subTest(what='text'):
            self._reask_names_what_is_new(re.sub(self.FENCE, '', self._phase(), flags=re.M | re.S))

    # --- 4. review 4's Minors 1 and 2 ----------------------------------------------------------------------------------
    def test_4a_an_escaped_hit_alone_stops_with_3es_escaped_name_sentences_and_their_next_step(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                v = fake('escalone' + shell)
                r = self.fresh()
                r.write('no\tes/cfg.py', kv('API_' + 'KEY', v))  # the user's own new file, not part of this send
                st = self._flow(r, shell, self._gen(r))
                self.assertFalse(_b(v) in self._sent_objects(r))
                self.assertIsNone(st['ask'], 'an escaped hit did not stop before the step-3 ask')
                self.assertEqual(st['stopped'], 'a hit counts')
                self.check(st['res'], new=['no\\x09es/cfg.py:1'], secrets=[v])
        with self.subTest(what='text'):
            self._escaped_stop_points_at_3e(self._prose())

    def test_4b_a_rerun_after_a_refused_push_says_argo_its_files_are_saved_from_last_time(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                _refuse_every_push(r)
                first = self._flow(r, shell, self._gen(r))  # Send it; the push is refused
                self.assertTrue(first['saved'] and first['sent'] and first['sent'].returncode,
                                'the first run did not save and then fail to send: %r %r' % (first['stopped'],
                                                                                            first['failed']))
                st = self._flow(r, shell, self._gen(r), picks=())  # /argo-it again, up to the step-3 ask
                self.assertIsNotNone(st['ask'], 'the re-run stopped before the ask: %r' % st['stopped'])
                # owner, after review 6: the save moves no branch until a copy is on GitHub, so after a refused first
                # push argo-it's files are still unsaved at the re-run's ask ("nothing has been saved or sent yet" is
                # true); Fix4 test_4c drives the re-run after a refused second push, where they are saved
                self.assertEqual(self._head(r), first['start'], "a refused push left argo-it's save on the branch here")
                self._nothing_before_the_pick(st, self.GENERATED)
        with self.subTest(what='text'):
            self._rerun_says_saved(self._phase())

    def test_4c_a_refused_first_push_after_the_users_hook_already_sent_the_save_is_told_truly(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                files = self._gen(r)
                self._refuse(r, 'refs/heads/' + self.DEPLOY)
                st = self._flow(r, shell, files, hooks=self._send_hook(r))
                self.assertTrue(st['failed'], "the refused first push isn't handled by a rule PHASE 5 names: %r"
                                % st['stopped'])
                # owner, after review 6: no hook runs on argo-it's save, so the user's send-every-save hook never
                # sends it, and "nothing was sent" is true here
                self.assertEqual(self._origin(r, 'for-each-ref'), st['refs'], "the user's send-every-save hook sent "
                                 "argo-it's save")
        with self.subTest(what='text'):
            p = self._phase()
            self._failed_push_checks_github(p[slice(*self._option_at(p, 1))])

    def test_4d_a_setup_file_the_user_edited_while_the_ask_waited_is_not_called_argo_its_mistake(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                v = fake('waitedit' + shell)
                r = self.fresh()
                files = self._gen(r, extra={self.REL: self.CM})
                st = self._flow(r, shell, files, between=lambda: r.write(self.REL, self._keyed(v)[self.REL]))
                self.assertIsNotNone(st['ask'], "2b's first check stopped, though argo-it's file was clean then")
                self.assertFalse(_b(v) in self._sent_objects(r))
                self.assertEqual(st['stopped'], 'a hit counts', 'the Send-it check did not stop on the edited file')
                self.assertIn(('pick', 1), st['trace'])
                self.check(st['res'], new=[self.REL + ':4'], secrets=[v])
        with self.subTest(what='text'):
            self._mistake_only_when_mine(re.sub(self.FENCE, '', self._phase(), flags=re.M | re.S))

    # --- 5. review 4 Minor 3: step 2's fetch prunes ------------------------------------------------------------------
    def test_5_a_key_taken_off_origin_never_goes_back_through_a_stale_origin_branch(self):
        for shell in ('bash', 'zsh'):
            for how in ('deleted', 'rewound'):
                with self.subTest(shell=shell, origin=how):
                    r = self.fresh()
                    v = self._off_origin(r, how, how + shell)
                    st = self._flow(r, shell, self._gen(r))
                    self.assertFalse(_b(v) in self._sent_objects(r), "a key taken off origin was sent again: this "
                                     "clone's stale origin branch read its commit as already sent")
                    self.assertIsNone(st['ask'], "the key's commit, no longer on origin, didn't stop the send before "
                                      "the ask")
                    self.assertEqual(st['stopped'], 'a hit counts')
                    self.check(st['res'], saved=['settings.py:1'], secrets=[v])

    # --- 6. review 4 Minor 4: the harness's gaps -------------------------------------------------------------------------
    def test_6a_control_send_it_in_a_repo_with_no_commits_yet_saves_a_first_commit_of_argo_its_files_and_sends_it(self):
        # control: passes today -- the text was right; `_flow` now remembers what `git rev-parse HEAD` prints (`HEAD`)
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self._unborn()
                r.write('mine.txt', 'my notes\n')
                r.git('add', '--', 'mine.txt')  # the user's own staged file stays out of argo-it's save
                files = self._gen(r)
                st = self._flow(r, shell, files)
                self.assertFalse(st['stopped'] or st['failed'], 'Send it in a repo with no commits yet did not go '
                                 'through: %r %r %r' % (st['stopped'], st['failed'], st['mem']))
                s = st['saved']
                self.assertTrue(s, 'argo-it never saved its files')
                self.assertEqual(r.git('rev-list', '--parents', '-n', '1', s).decode().split(), [s],
                                 "argo-it's save isn't the repo's first commit")
                self.assertEqual(r.git('diff-tree', '--root', '-r', '--name-only', '--no-commit-id', s).decode().split(),
                                 files, "argo-it's first save holds more than its files")
                for ref in ('main', self.DEPLOY):
                    self.assertEqual(self._ref(r, ref), s, "origin's %s is not argo-it's save" % ref)
                self.assertIn('A  mine.txt', r.git('status', '--porcelain').decode().splitlines())

    def test_6b_send_its_two_readers_hold_on_argo_it_md(self):
        p = self._phase()
        with self.subTest(reader='_checks_before_it_saves'):
            self._checks_before_it_saves(p)
        with self.subTest(reader='_moved_head_goes_back_to_the_check'):
            self._moved_head_goes_back_to_the_check(p)

    # --- 7. polarity: each new prose check and reader passes a plain reading and fails its plain opposite -------------
    REASK_RULE = ('If the block prints `SAVED SINCE THE CHECK`, something was saved after the ask: run step 2 and 2b '
                  'again, then\nshow the step-3 ask again, naming what is new.')
    RERUN_RULE = ('If the block prints `SAVED SINCE THE CHECK`, remember the new `git rev-parse HEAD` as `{checked_head}`,'
                  '\nthen run 2b again; if no hit counts, run this block again.')
    UNSAFE_RULE = ('If the block prints `SAVED SINCE THE CHECK`, run 2b again; if no hit counts, remember the new\n'
                   '`git rev-parse HEAD` as `{checked_head}` and run this block again.')
    GOOD4 = '\n'.join((
        "**2b. Secret check** -- read the result exactly as 3e does. A hit whose path holds `\\xNN` or `\\uXXXX`",
        'counts too, whatever its label.',
        '',
        "**If any hit counts: stop here.** Don't show the step-3 ask; nothing is sent. Tell the user:",
        '',
        '"I found what looks like a password or secret key on **line [N] of [file]**. [If a hit in a file argo-it',
        "generated was found by 2b's first check, or a fix I made after the local try put it there: **[file]** is one",
        'of the setup files I made. That one is a mistake on my side, not something you did.] [If a hit in a file',
        "argo-it generated was found only by the check after 'Send it': **[file]** is one of the setup files I made,",
        "and it changed after I made it.] [If a hit's path holds `\\xNN` or `\\uXXXX`: say 3e's escaped-name",
        "sentences for it, and its next step.] Secrets should never be saved in code, so I won't send this. I",
        "haven't saved or sent anything.\"",
        '',
        '**3. Ask the user what they want to do:**',
        '',
        "\"I've generated your deployment pipeline -- it's ready in your project folder, and nothing has been saved",
        "or sent yet [on a re-run, with `git ls-files` listing argo-it's files: the files are saved from last",
        'time, but nothing has been sent yet].',
        '',
        '**What would you like to do?**',
        '',
        '1. **Send it -- deploys to {hostname}** -- I save these files and send them',
        '2. **Try it on this computer first** -- nothing is saved or sent',
        '3. **Show me the files first** -- nothing is saved or sent',
        '4. **Not now** -- the files stay in your project folder, not saved yet [on a re-run: saved last time, still',
        'not sent]; nothing is sent"',
        '',
        '**4. Execute based on user choice:**',
        '',
        "**Option 1 (send):** Remember `git rev-parse HEAD` as `{checked_head}`, then run 2b's check again and read it",
        'the same way.',
        '',
        '```bash',
        '[ "$(git rev-parse HEAD)" = "{checked_head}" ] || { echo "SAVED SINCE THE CHECK"; exit 3; }',
        'git commit -q -m "Add K8s manifests" -- {generated_files}',
        '[ "$(git diff-tree --root -r --name-only --no-commit-id HEAD)" = "{generated_files}" ] || { echo "SAVE HELD '
        'MORE"; exit 4; }',
        'git rev-parse HEAD',
        '```',
        '',
        REASK_RULE + ' If it prints `SAVE HELD MORE`, stop: nothing is sent. Tell the',
        'user:',
        '',
        "\"I stopped before sending anything: your project's own save step took in other files of yours along with",
        'the setup files I made, so nothing was sent. What to do next: ask your DevOps team to help, then run',
        '/argo-it again."',
        '',
        'Otherwise remember the commit id it prints as `{saved_head}`.',
        '',
        '```bash',
        'git push origin {saved_head}:refs/heads/{deploy_branch} || { echo "PUSH 1 FAILED"; exit 1; }',
        'git push origin {saved_head}:refs/heads/main || { echo "PUSH 2 FAILED"; exit 1; }',
        '```',
        '',
        '**If either push fails** (the block prints `PUSH 1 FAILED` or `PUSH 2 FAILED`), never say "Pushed!". First',
        'run `git ls-remote origin` to see what GitHub holds. Tell the user:',
        '',
        '"I couldn\'t send your setup to GitHub, so [nothing was sent / if GitHub already holds the save: your',
        "project's own setup already sent it to GitHub, so it may be deploying]. What to do next: [the fix], then run",
        '/argo-it again."',
        '',
        '**Option 2 (local test):** it works on the unsaved files: nothing is saved.',
        '',
        '**Option 3 (show the files):** describe each file; nothing is saved or sent.',
        '',
        "**Option 4 (not now):** say the files stay in the project folder, not saved yet [if they're already saved:",
        'the files are saved from last time], and nothing was sent.',
        '',
        '**5. Report success:**',
        ''))

    def test_7_control_new_prose_checks_and_readers_are_polarity_bound(self):  # control: passes today
        def prose(t):
            return re.sub(self.FENCE, '', t, flags=re.M | re.S)

        def sec(n):
            return lambda t: t[slice(*self._option_at(t, n))]
        g, rerun = self.GOOD4, self.GOOD4.replace(self.REASK_RULE, self.RERUN_RULE)
        opening = (" [on a re-run, with `git ls-files` listing argo-it's files: the files are saved from last\ntime, "
                   "but nothing has been sent yet]")
        checks = [
            ('_reask_names_what_is_new', g, prose, [
                (', naming what is new.', '.'),
                ('naming what is new', 'as it was before')]),
            ('_escaped_stop_points_at_3e', g, prose, [
                (" say 3e's escaped-name\nsentences for it, and its next step.", ' stop.'),
                (', and its next step', ''),
                ("say 3e's escaped-name", "don't use 3e's escaped-name")]),
            ('_rerun_says_saved', g, lambda t: t, [
                (opening, ''),
                ('the files are saved from last\ntime', 'the files are not saved'),
                (' [on a re-run: saved last time, still\nnot sent]', ''),
                (" [if they're already saved:\nthe files are saved from last time]", '')]),
            ('_failed_push_checks_github', g, sec(1), [
                (' First\nrun `git ls-remote origin` to see what GitHub holds.', ''),
                (" / if GitHub already holds the save: your\nproject's own setup already sent it to GitHub, so it may be "
                 "deploying", '')]),
            ('_mistake_only_when_mine', g, prose, [
                ("[If a hit in a file argo-it\ngenerated was found by 2b's first check, or a fix I made after the local try "
                 "put it there:", '[If a hit is in a file argo-it generated:'),
                (" [If a hit in a file\nargo-it generated was found only by the check after 'Send it': **[file]** is one "
                 "of the setup files I made,\nand it changed after I made it.]", ''),
                ('and it changed after I made it.]', 'and it changed after I made it. That one is a mistake on my side.]')]),
            ('_checks_before_it_saves', g, lambda t: t, [
                ("then run 2b's check again", "there's no need to run 2b's check again"),
                ("Remember `git rev-parse HEAD` as `{checked_head}`, then run 2b's check again and read it\nthe same way.",
                 "Run 2b's check again and read it the same way, then remember `git rev-parse HEAD` as\n"
                 "`{checked_head}`.")]),
            ('_moved_head_goes_back_to_the_check', g, lambda t: t, [
                (self.REASK_RULE, 'If the block prints `SAVED SINCE THE CHECK`, stop.')]),
            ('_moved_head_goes_back_to_the_check', rerun, lambda t: t, [
                (self.RERUN_RULE, self.UNSAFE_RULE),
                ('then run 2b again; if no hit counts, run', "and don't run 2b again; run"),
                ('remember the new `git rev-parse HEAD` as `{checked_head}`,\nthen', 'keep `{checked_head}`,\nthen'),
                ('run this block again.', 'stop.')]),
            ('_ask_says_nothing_saved', g, self._ask_text, [
                (opening, ' -- the files are saved from last\ntime, but nothing has been sent yet')]),
            ('_not_now_says_unsaved', g, sec(4), [
                (" [if they're already saved:\nthe files are saved from last time]", ', but the files are saved')]),
        ]
        for name, t, view, swaps in checks:
            fn = getattr(self, name)

            def check(x, fn=fn, view=view):
                v = view(x)
                return fn(*v) if isinstance(v, tuple) else fn(v)
            with self.subTest(check=name, text='plain reading'):
                check(t)
            for old, opposite in swaps:
                self.assertIn(old, t)
                with self.subTest(check=name, opposite=opposite[:60]):
                    with self.assertRaises(AssertionError):
                        check(t.replace(old, opposite))


# ArgoItFirstSendFix3Cases' helpers (not its tests), for fix round 4 below.
_FirstSendFix3 = type('_FirstSendFix3', (object,), {k: v for k, v in ArgoItFirstSendFix3Cases.__dict__.items()
                                                    if not k.startswith(('test', '__'))})


class ArgoItFirstSendFix4Cases(_FirstSendFix3, _FirstSendFix2, _FirstSendAdv1, _FirstSendFix1, _FirstSend, Base):
    """Task 3 review 5 and the coordinator's calls after it (2026-10-20, one authoritative gate): after argo-it's save
    and right before any push, 2b runs again on what will be sent, and a hit stops with nothing pushed; "what was sent"
    comes from which push went through, so the deploy branch argo-it's own first push set up is never read as "your
    setup already sent it"; SAVE HELD MORE takes argo-it's save back, says so when the save already went out and that
    the values in it must be changed, and a re-run never sends the files the user's hook took in; an escaped hit under
    saved keeps the history step; a pull or reset while the ask waits is "your branch changed"; the re-run and "Not now"
    words say "saved" / "sent" only when true; a branch name is never run as shell; a failed fetch stops; step 2's
    `git log` has a reading rule for a repo with no commits yet. The test_5 controls bind review 5's mutations M1, M7,
    M8 and M9 of the real text; test_3a and test_3c bind M10. Prose checks are proven against their plain opposites in
    test_6. Values and secret-named lines are joined at run time (GitGuardian scans this file)."""

    # a branch name git accepts that runs a harmless command (an empty file, in the fixture repo) if the shell reads it
    BRANCHES = ('x$(true>pwned1)', 'x`true>pwned2`', 'x"$(true>pwned3)"', "x'$(true>pwned4)'")
    FILES_SAVED_CLAIM = (r"(?i)\b(?:they(?:'re|\s+are)|(?:the|these|its|argo-it's|my)\s+(?:setup\s+)?files\s+(?:are|were"
                         r"|stay|remain))\s+(?:already\s+)?saved\b|\bsaved\s+(?:from\s+)?(?:last time|before|earlier"
                         r"|an? (?:earlier|previous|last) run)\b|\balready\s+saved\b|\b(?:stays?|remains?|kept)\s+saved\b")
    SENT_STATE = (r"(?i)\bnothing\s+(?:has\s+been|was|is|'s\s+been)\s+(?:yet\s+)?sent\b"
                  r"|\b(?:not|n't)\s+(?:been\s+|yet\s+)?sent\b")
    COPY_SENT = r"(?i)\bcopy\b[^.\]]{0,60}?\b(?:on|to|reached)\s+GitHub\b|\balready\s+on\s+GitHub\b|\bon\s+GitHub\s+already\b"
    TAKE_BACK = (r"(?i)\bgit\s+(?:reset|update-ref)\b|\btak(?:e|es|ing|en)\s+(?:\S+\s+){0,3}?back\b"
                 r"|\bundo(?:es|ne)?\s+(?:\S+\s+){0,2}?save\b")
    BRANCH_CHANGED = (r"(?i)\b(?:your|the)\s+(?:branch|saved changes|project's\s+(?:saved\s+)?(?:changes|history))\s+"
                      r"(?:has\s+|have\s+)?changed\b")
    SAVED_A_CHANGE = r"(?i)\ba\s+(?:new\s+)?change\s+(?:was|got|has been)\s+saved\b|\bsomething\s+(?:was|got)\s+saved\b"
    STEP2_LISTS = r"(?i)\bstep\s+2\b[^:\]]{0,60}\b(?:lists?|listed|names?|found|shows?)\b"
    HISTORY = r'(?i)\bremove it from the saved history\b'
    PLAIN_GATE = r'(?i)\bplain\s+(?:path|name)'
    SAVED_GATE = r'saved, not sent|(?i:\bunder saved\b|\bsaved history\b|\balready saved\b)'
    EXCL_DEPLOY = (r"(?i)\b(?:other than|except(?:\s+for)?|besides|apart from|aside from|not counting|leaving out|but not"
                   r"|outside)\b[^.;]{0,60}?(?:\{deploy_branch\}|\bdeploy branch\b|the copy the deployment system watches)"
                   r"|(?:\{deploy_branch\}|\bdeploy branch\b)[^.;]{0,60}?\b(?:doesn't|does not|never|won't)\s+count\b")
    ONLY_ASKED = r"(?i)\bonly\b[^.;]{0,80}?(?:\{asked_branch\}|the branch the (?:step-3 )?ask was shown on)"
    MASKED = r'\|\|\s*(?:true|:)\s*(?:$|[;#&|])|;\s*true\b'
    NO_COMMITS = r'(?i)\bno commits\b|\bfirst commit\b|\bunborn\b'
    NOTHING_LISTED = (r'(?i)\bnothing\s+(?:is\s+)?listed\b|\blists?\s+nothing\b|\bno saved changes\b|\bnothing to list\b'
                      r'|\bas\s+(?:an\s+)?empty\b')

    # --- fixtures --------------------------------------------------------------------------------------------------
    def _sent_refs(self, r):
        """origin's branches, {ref: commit id}."""
        out = self._origin(r, 'for-each-ref', '--format=%(objectname) %(refname)').decode().splitlines()
        return dict(reversed(l.split(' ', 1)) for l in out)

    def _changed(self, before, after):
        return {k for k in set(before) | set(after) if before.get(k) != after.get(k)}

    def _theirs_on_origin(self, r, tag):
        """Someone else's change, sent to origin's main from their own clone (this clone hasn't fetched it yet)."""
        none = os.path.join(r.root, 'no-hooks-other')
        os.makedirs(none, exist_ok=True)
        Repo._git(r.root, '-c', 'core.hooksPath=' + none, 'clone', '-q', os.path.join(r.root, 'origin'), 'other')
        other = os.path.join(r.root, 'other')
        with open(os.path.join(other, 'theirs.md'), 'w') as f:
            f.write('# theirs %s\n' % tag)
        Repo._git(other, '-c', 'core.hooksPath=' + none, 'add', '--', 'theirs.md')
        Repo._git(other, '-c', 'core.hooksPath=' + none, 'commit', '-q', '-m', 'their change')
        Repo._git(other, '-c', 'core.hooksPath=' + none, 'push', '-q', 'origin', 'HEAD:main')

    @staticmethod
    def _listed(st, k=-1):
        """What step 2's `git log` listed in its k-th run (the block's deploy-branch lookup prints a bare commit id, or
        GitHub's own line, `<id> refs/heads/<branch>`: coordinator, after adversarial round 2; and the save's tree as
        `tree <id>`: coordinator, fix round 7)."""
        cps = [cp for code, cp in st['outputs'] if 'git log --oneline' in code]
        return [l for l in cps[k].stdout.decode().splitlines()
                if l.strip() and not re.fullmatch(r'(?:tree\s+)?[0-9a-f]{40,64}(?:\s+refs/\S+)?', l)]

    def _snapshot(self, r, rels):
        out = {}
        for rel in rels:
            with open(r.path(rel), 'rb') as f:
                out[rel] = f.read()
        return out

    # --- reading the text ------------------------------------------------------------------------------------------
    @staticmethod
    def _conds_at(q, k):
        """The conditions of the brackets around position k of q, innermost first: a "[cond: ...]"'s text before its
        first ':' at its own depth when k is past it; None when k sits in that condition; '' for a bracket with none."""
        out, depth = [], 0
        for i in range(k - 1, -1, -1):
            if q[i] == ']':
                depth += 1
            elif q[i] == '[':
                if depth:
                    depth -= 1
                    continue
                d, colon = 0, -1
                for j in range(i + 1, len(q)):
                    if q[j] == '[':
                        d += 1
                    elif q[j] == ']':
                        if not d:
                            break
                        d -= 1
                    elif q[j] == ':' and not d:
                        colon = j
                        break
                out.append('' if colon == -1 else None if colon >= k else q[i + 1:colon])
        return out

    def _said(self, rx, s):
        """s says rx, not after a "not" / "nothing" / "n't" a few words before it."""
        return any(not re.search(self.SAVED_NEG, s[:m.start()]) for m in re.finditer(rx, s))

    def _rule_for(self, t, mark):
        """The rule for `mark` in t (code taken out, flattened, the quoted messages kept): from the sentence that names
        it to the next rule -- a sentence naming another marker, an "Otherwise", or a bold heading."""
        prose = self._flat(re.sub(self.FENCE, ' ', t, flags=re.M | re.S))
        masked = re.sub(r'"(?:I|Pushed|Your)[^"]{20,}"', lambda m: '"' + 'x' * (len(m.group(0)) - 2) + '"', prose)
        i = masked.find('`%s`' % mark)
        self.assertNotEqual(i, -1, 'PHASE 5 has no rule for %s' % mark)
        starts = [m.end() for m in re.finditer(r'[.!?]["\]]*\s+|\*\*', masked[:i])]
        a = starts[-1] if starts else 0
        m = re.compile(r'[.!?"\]]\s+(?=(?:If|When|On)\b[^.]{0,60}?`%s`|Otherwise\b)|\*\*' % self.MARK_LINE).search(
            masked, i + len(mark) + 2)
        e = len(masked) if not m else m.start() if masked[m.start()] == '*' else m.start() + 1
        return prose[a:e]

    def _last_check_owns_the_save(self, sec):
        """Option 1 (sec) runs a check on its way from argo-it's save to the first push, and it checks exactly the
        commit the push sends: a ```bash block between them runs secret-scan.py on the same `{...}` commit the first push
        block sends (owner, after review 6: "It checks exactly that commit ... It sends exactly that commit by id"). Was:
        a check there, plus a take-back on its stop (the take-backs go away: nothing is saved here before the send)."""
        save = self._save_block(sec)
        pushes = [f for f in self._fences(sec) if f[0] > save[0] and self._git_does(f[2], 'push')]
        self.assertTrue(pushes, "Option 1 has no push after argo-it's save")
        end = pushes[0][0]
        fenced = [f for f in self._fences(sec) if save[1] <= f[0] < end and 'secret-scan.py' in f[2]]
        self.assertTrue(fenced, "no ```bash block checks for secrets between argo-it's save and the push: the commit the "
                                "push sends is never checked")

        def code(f):
            return '\n'.join(l for l in f[2].splitlines() if not l.lstrip().startswith('#'))
        sent = set(re.findall(r'\bgit\s+push\s+\S+\s+"?\{([\w-]+)\}:', code(pushes[0])))
        named = set(re.findall(r'(?<!\$)\{([\w-]+)\}', code(fenced[-1])))
        self.assertTrue(sent, "the push doesn't send a commit by its id (`git push origin \"{id}:refs/heads/...\"`)")
        self.assertTrue(sent & named, "the last check doesn't check the commit the push sends: it checks %r, the push "
                                      "sends %r" % (sorted(named), sorted(sent)))

    def _deploy_line_never_reads_as_already_sent(self, sec):
        """The failed-push rule reads `git ls-remote` for `{saved_head}` only on a line argo-it's own pushes didn't
        make: never the deploy branch's line when the first push went through."""
        prose = re.sub(self.FENCE, '', sec, flags=re.M | re.S)
        b = self._rule(prose, lambda u: re.search(self.FAILED, u) or '`PUSH 1 FAILED`' in u, [], 'a push that fails')
        outside = re.sub(r'"(?:I|Pushed|Your)[^"]{20,}"', ' . ', b)
        reads = [s for s in self._all_sentences(outside) if '{saved_head}' in s and re.search(r'(?i)\bline\b|\bls-remote\b', s)
                 and re.search(r'(?i)\bhold|\bshow|\bprint|\bcontain', s)]
        code = '\n'.join(f[2] for f in self._fences(sec) if re.search(r'\bgit\s+ls-remote\b', f[2]))
        self.assertTrue(reads or code, "the failed-push rule never reads what GitHub holds")
        for s in reads:
            self.assertTrue(re.search(self.EXCL_DEPLOY, s) or re.search(self.ONLY_ASKED, s),
                            "the failed-push rule reads any line holding {saved_head} as \"your project's own setup "
                            "already sent it\" -- the deploy branch argo-it's own first push set up among them: %r" % s)
        if code and not reads:
            self.assertRegex(code, r'grep\s+-v[^\n]*\{deploy_branch\}|ls-remote\s+(?:-\S+\s+)*origin\s+"?refs/heads/'
                                   r'(?!\{deploy_branch\})', "the ls-remote block counts the deploy branch's line too")

    def _escaped_saved_keeps_the_history_step(self, prose):
        b = self._saved_hit_stops(prose)
        qs = re.findall(r'"(I[^"]{20,})"', b)
        hist = [(q, m.start()) for q in qs for m in re.finditer(self.HISTORY, q)]
        self.assertTrue(hist, "2b's stop has no next step to remove a hit from the saved history")
        for q, k in hist:
            for c in self._conds_at(q, k):
                if c and re.search(self.PLAIN_GATE, c):
                    self.assertRegex(c, self.SAVED_GATE, "an escaped hit under %s loses the history step: its gate is "
                                     "plain paths only: %r" % (L_SAVED, c))
        for q in qs:
            for br in re.findall(r'\[([^\[\]]*)\]', q):
                if re.search(self.ESC, br) and re.search(r'(?i)\bplain names?\b', br):
                    self.assertRegex(br, r'(?i)\brun /argo-it again\b', "the escaped-name next step is copied from 3e "
                                     "without its \"then run /argo-it again\": %r" % br)

    def _reask_says_branch_changed(self, ask):
        q = self._flat(ask)
        self.assertTrue(self._says(self.BRANCH_CHANGED, q), "the ask shown again has no \"your branch changed\" for a "
                        "pull or a reset while it waited: %r" % q)
        for m in re.finditer(self.SAVED_A_CHANGE, q):
            if self._neg(q, m.start()):
                continue
            conds = self._conds_at(q, m.start())
            if None in conds:
                continue
            self.assertTrue(any(c and re.search(self.STEP2_LISTS, c) for c in conds), "the ask shown again says a "
                            "change was saved whatever step 2 lists (a pull or a reset saves nothing): %r" % q)

    def _true_saved(self, u, what):
        """Each claim in u that argo-it's files are saved sits under a bracket whose condition says they are already
        saved; and a "not sent" said there has a "copy on GitHub" beside it (after a refused second push one is)."""
        q = self._flat(u)
        for m in re.finditer(self.FILES_SAVED_CLAIM, q):
            conds = self._conds_at(q, m.start())
            if re.search(self.SAVED_NEG, q[:m.start()]) or None in conds:
                continue
            self.assertTrue(any(c and self._says(self.FILES_SAVED, c) for c in conds), "%s says argo-it's files are "
                            "saved on a condition that doesn't say they are (a re-run after \"Not now\" has nothing "
                            "saved): %r" % (what, q))
        for m in re.finditer(self.SENT_STATE, q):
            conds = self._conds_at(q, m.start())
            if None not in conds and any(c and self._says(self.FILES_SAVED, c) for c in conds):
                self.assertTrue(self._says(self.COPY_SENT, q), "%s says nothing has been sent when argo-it's files are "
                                "saved, with no \"a copy is already on GitHub\" for a refused second push: %r" % (what, q))

    def _rerun_words_are_true(self, p):
        units = self._units(self._ask_text(p))
        opt4 = [u for u in units if re.match(r'4\.\s+\*\*Not now\b', u)]
        self.assertTrue(opt4, 'the step-3 ask has no "4. **Not now**" option')
        sec4 = re.sub(self.FENCE, '', p[slice(*self._option_at(p, 4))], flags=re.M | re.S)
        for what, u in (("the step-3 ask's opening", units[0]), ('the ask\'s "Not now"', opt4[0]), ('Option 4', sec4)):
            self._true_saved(u, what)

    def _fetch_failure_stops(self, p):
        lines = [l for l in self._step_block(p, 2)[2].splitlines() if self._git_does(l, 'fetch')]
        self.assertTrue(lines, 'step 2 no longer fetches')
        for l in lines:
            self.assertNotRegex(l.split(' #')[0], self.MASKED, "step 2's fetch goes on when it fails: %r" % l)
        marks = [m for l in lines for m in re.findall(r'\becho\s+["\']?(%s)' % self.MARK_LINE, l)]
        self.assertTrue(marks, "a failed fetch prints no line PHASE 5 has a rule for, so nothing stops on it: %r" % lines)
        rule = self._rule_for(p, marks[0])
        self.assertTrue(self._stops(rule) and re.search(self.NOT_SHOWN, rule), "a failed fetch doesn't stop before the "
                        "step-3 ask: %r" % rule)
        qs = re.findall(r'"(I[^"]{20,})"', rule)
        self.assertTrue(any(re.search(self.SENT_NONE, q) and re.search(self.NEXT, q) and not re.search(self.NEVER_SAY, q)
                            for q in qs), "a failed fetch isn't told plainly (nothing was saved or sent, and what to do "
                                          "next): %r" % qs)

    def _no_commits_log_rule(self, p):
        h, e = re.search(r'^\*\*2\. ', p, re.M), re.search(r'^\*\*2b\. ', p, re.M)
        self.assertTrue(h and e, 'PHASE 5: no "**2." or "**2b." heading')
        logs = [l for l in self._step_block(p, 2)[2].splitlines() if self._git_does(l, 'log')]
        self.assertTrue(logs, "step 2 no longer lists the saved changes (`git log`)")
        if all(re.search(r'\s2>\s*/dev/null\b', l.split(' #')[0]) for l in logs):
            return
        prose = re.sub(self.FENCE, '', p[h.start():e.start()], flags=re.M | re.S)
        self.assertTrue(any(re.search(r'\bgit log\b', s) and re.search(self.NO_COMMITS, s)
                            and re.search(self.NOTHING_LISTED, s) and not re.search(r"(?i)\bstop|\bcouldn't\b", s)
                            for s in self._all_sentences(prose)),
                        "in a repo with no commits yet step 2's `git log` prints an error, and nothing says to read it "
                        "as nothing listed")

    # --- 1. Important 1: the last check is right before the push, on what will be sent ------------------------------
    def test_1_a_key_saved_into_argo_its_file_after_the_send_it_check_never_reaches_origin(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell, what="the user's editor saves a key into argo-it's file after the check"):
                v = fake('editafter' + shell)
                r = self.fresh()
                files = self._gen(r, extra={self.REL: self.CM})
                st = self._flow(r, shell, files, after_check=lambda: r.write(self.REL, self._keyed(v)[self.REL]))
                self.assertFalse(_b(v) in self._sent_objects(r), "a setup file edited after the Send-it check was saved "
                                 "and sent unchecked: its fake key reached origin")
                self.assertEqual(st['stopped'], 'a hit counts', 'no check after the save stopped on the key: %r %r'
                                 % (st['stopped'], st['failed']))
                self.assertFalse([e for e in st['trace'] if e[0] == 'push'], 'argo-it pushed before the last check')
                self.assertEqual(self._origin(r, 'for-each-ref'), st['refs'], 'something was sent')
                self.assertEqual(st['scanned'], st['saved'], "the check that stopped didn't read argo-it's save, the "
                                 "commit the push would send")
                self.check(st['res'], saved=[self.REL + ':4'], secrets=[v])
            with self.subTest(shell=shell, what='clean: the last check reads the commit the push sends'):
                r = self.fresh()
                st = self._flow(r, shell, self._gen(r))
                self.assertFalse(st['stopped'] or st['failed'], 'a clean first send stopped: %r %r'
                                 % (st['stopped'], st['failed']))
                t = st['trace']
                pushes = [i for i, e in enumerate(t) if e[0] == 'push']
                self.assertTrue(pushes, 'a clean first send pushed nothing')
                saves = [i for i, e in enumerate(t[:pushes[0]]) if e[0] == 'save']
                self.assertTrue(saves, 'nothing was saved before the push')
                checks = [e for e in t[saves[-1]:pushes[0]] if e[0] == 'check']
                self.assertTrue(checks, "no check runs between argo-it's save and the push: %r" % t)
                self.assertEqual(checks[-1][1], st['saved'], "the last check before the push didn't read the commit "
                                 "the push sends")
                self.assertEqual(self._ref(r, 'main'), st['saved'])
        with self.subTest(what='text'):
            p = self._phase()
            self._last_check_owns_the_save(p[slice(*self._option_at(p, 1))])

    # --- 2. Important 2: what was sent comes from which push went through --------------------------------------------
    def test_2_a_refused_second_push_never_reads_the_deploy_branch_argo_it_just_set_up_as_already_sent(self):
        for shell in ('bash', 'zsh'):
            for how in ('protected main', 'detached HEAD'):
                with self.subTest(shell=shell, input=how):
                    r = self.fresh()
                    files = self._gen(r)
                    before = self._sent_refs(r)
                    if how == 'protected main':
                        self._refuse(r, 'refs/heads/main')
                    else:
                        r.git('checkout', '-q', '--detach')
                    st = self._flow(r, shell, files)
                    after = self._sent_refs(r)
                    if how == 'detached HEAD' and not [e for e in st['trace'] if e[0] == 'push']:
                        self.assertEqual(self._changed(before, after), set(), 'something was sent')
                        continue  # stopped before sending, with nothing sent: no message about a push to check
                    self.assertTrue(st['failed'], "the refused second push isn't handled by a rule PHASE 5 names: %r"
                                    % st['stopped'])
                    deploy = 'refs/heads/' + self.DEPLOY
                    self.assertEqual(self._changed(before, after), {deploy}, 'fixture: more than the deploy branch '
                                     'went out, or it did not')
                    self.assertEqual([k for k, v in after.items() if v == st['saved']], [deploy], "fixture: a line "
                                     "other than the deploy branch's holds argo-it's save on GitHub")
        with self.subTest(what='text'):
            p = self._phase()
            self._deploy_line_never_reads_as_already_sent(p[slice(*self._option_at(p, 1))])

    # --- 3. Important 3: SAVE HELD MORE takes argo-it's save back ----------------------------------------------------
    def test_3a_save_held_more_takes_argo_its_save_back_and_leaves_every_file_as_it_was(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell, repo='with commits'):
                v1, v2 = fake('heldedit' + shell), fake('heldnew' + shell)
                r = self.fresh()
                r.append('app.py', kv('API_' + 'KEY', v1))  # the user's unsaved edit
                r.write('cfg.py', kv('TO' + 'KEN', v2))  # and their own new file
                files = self._gen(r)
                snap = self._snapshot(r, ['app.py', 'cfg.py'] + files)
                st = self._flow(r, shell, files, hooks=self._add_all_hook(r))
                # owner, after review 6: no hook runs on argo-it's save (SAVE HELD MORE and its take-back go away), so
                # the save holds only argo-it's files and is sent, the branch here moves only to it, and every file
                # stays as it was
                self.assertFalse(st['stopped'] or st['failed'], '%r %r' % (st['stopped'], st['failed']))
                sent = self._sent_objects(r)
                self.assertFalse(_b(v1) in sent or _b(v2) in sent, 'a fake key reached origin')
                self._sent_on_send_it(r, st, files)
                self.assertEqual(self._head(r), st['saved'], 'the branch here is not what was sent')
                self.assertEqual(self._snapshot(r, sorted(snap)), snap, 'the send changed a file')
            with self.subTest(shell=shell, repo='no commits yet'):
                r = self._unborn()
                r.write('wip.py', '# my work in progress\n')
                files = self._gen(r)
                snap = self._snapshot(r, ['wip.py'] + files)
                st = self._flow(r, shell, files, hooks=self._add_all_hook(r))
                self.assertFalse(st['stopped'] or st['failed'], '%r %r' % (st['stopped'], st['failed']))
                s = st['saved']
                self.assertEqual(r.git('diff-tree', '--root', '-r', '--name-only', '--no-commit-id', s).decode().split(),
                                 files, "argo-it's first save holds more than its files")
                self.assertEqual(self._sent_refs(r), {'refs/heads/main': s, 'refs/heads/' + self.DEPLOY: s})
                self.assertEqual(self._head(r), s, 'the branch here is not what was sent')
                self.assertEqual(r.git('status', '--porcelain', '--', 'wip.py').decode(), '?? wip.py\n')
                self.assertEqual(self._snapshot(r, sorted(snap)), snap, 'the send changed a file')

    def test_3b_save_held_more_after_a_send_every_save_hook_says_it_went_out_and_its_values_must_be_changed(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                v1, v2 = fake('heldsent' + shell), fake('heldsentnew' + shell)
                r = self.fresh()
                r.append('app.py', kv('API_' + 'KEY', v1))
                r.write('cfg.py', kv('TO' + 'KEN', v2))
                files = self._gen(r)
                hooks = self._add_all_hook(r)
                self.assertEqual(self._send_hook(r), hooks)  # both hooks in the fixture's one hooks folder
                st = self._flow(r, shell, files, hooks=hooks)
                # owner, after review 6: neither hook runs on argo-it's save, so no widened save is made or sent (SAVE
                # HELD MORE and its "it already went out" message go away): only argo-it's files are sent
                self.assertFalse(st['stopped'] or st['failed'], '%r %r' % (st['stopped'], st['failed']))
                sent = self._sent_objects(r)
                self.assertFalse(_b(v1) in sent or _b(v2) in sent, "the user's hooks sent their files: a fake key "
                                 "reached origin")
                self._sent_on_send_it(r, st, files)

    def test_3c_a_rerun_after_save_held_more_never_sends_the_files_the_users_hook_took_in(self):
        for shell in ('bash', 'zsh'):
            for repo in ('with commits', 'no commits yet'):
                with self.subTest(shell=shell, repo=repo):
                    mark = 'halfdone' + shell + repo.split()[0]
                    r = self.fresh() if repo == 'with commits' else self._unborn()
                    if repo == 'with commits':
                        r.append('app.py', 'debug = True  # %s edit\n' % mark)  # the user's half-done edit
                    r.write('wip.py', '# %s wip\n' % mark)  # and their own new file
                    hooks = self._add_all_hook(r)
                    first = self._flow(r, shell, self._gen(r), hooks=hooks)
                    # owner, after review 6: the hook never runs on argo-it's save, so the first run sends only argo-it's
                    # files (no SAVE HELD MORE); the re-run then must not send the user's files either
                    self.assertFalse(first['stopped'] or first['failed'], '%r %r' % (first['stopped'], first['failed']))
                    again = self._flow(r, shell, self._gen(r), hooks=hooks, picks=(1, 1))  # /argo-it again, Send it
                    self.assertFalse(_b(mark) in self._sent_objects(r), "a re-run after %s sent the user's own files "
                                     "that their hook took into argo-it's save, unnamed: %r %r"
                                     % (first['failed'], again['stopped'], again['failed']))

    # --- 4. the Minors -------------------------------------------------------------------------------------------------
    def test_4a_an_escaped_hit_under_saved_keeps_the_history_step_and_the_rename_step_ends_with_run_argo_it_again(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                v = fake('escsaved' + shell)
                r = self.fresh()
                r.write('no\tes/cfg.py', kv('API_' + 'KEY', v))
                r.commit('my notes, never sent')
                st = self._flow(r, shell, self._gen(r))
                self.assertFalse(_b(v) in self._sent_objects(r))
                self.assertIsNone(st['ask'], 'an escaped hit under saved did not stop before the step-3 ask')
                self.assertEqual(st['stopped'], 'a hit counts')
                self.check(st['res'], saved=['no\\x09es/cfg.py:1'], secrets=[v])
        with self.subTest(what='text'):
            self._escaped_saved_keeps_the_history_step(self._prose())

    def test_4b_a_pull_or_a_reset_while_the_ask_waits_is_told_as_your_branch_changed(self):
        for shell in ('bash', 'zsh'):
            for how in ('reset', 'pull'):
                with self.subTest(shell=shell, what='a %s while the ask waits' % how):
                    r = self.fresh()
                    if how == 'reset':  # the user undoes a save they hadn't sent
                        r.write('notes.md', '# my plan\n')
                        r.commit('my notes, never sent')
                        between = lambda: r.git('reset', '-q', '--hard', 'HEAD~1')  # noqa: E731
                    else:  # the user pulls someone else's change
                        self._theirs_on_origin(r, shell)
                        between = lambda: r.git('pull', '-q', '--no-rebase', '--ff-only', 'origin', 'main')  # noqa: E731
                    files = self._gen(r)
                    st = self._flow(r, shell, files, between=between)
                    self._asks_again(r, st, files)
                    self.assertEqual(self._listed(st), [], 'fixture: step 2 lists a new save when the ask is shown again')
        with self.subTest(what='text'):
            self._reask_says_branch_changed(self._ask_text(self._phase()))

    def test_4c_the_rerun_and_not_now_words_say_saved_or_sent_only_when_that_is_true(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell, earlier='a refused second push'):
                r = self.fresh()
                self._refuse(r, 'refs/heads/main')
                first = self._flow(r, shell, self._gen(r))
                self.assertTrue(first['failed'] and self._ref(r, self.DEPLOY) == first['saved'], 'fixture: the first '
                                'run did not set up the deploy branch and then fail to send main: %r' % first['stopped'])
                st = self._flow(r, shell, self._gen(r), picks=())  # /argo-it again, up to the step-3 ask
                self.assertIsNotNone(st['ask'], 'the re-run stopped before the ask: %r' % st['stopped'])
                self.assertEqual(r.git('status', '--porcelain', '--', *self.GENERATED).decode(), '', "fixture: argo-it's "
                                 "files aren't saved at the re-run's ask")
                self.assertEqual(self._listed(st), [], "fixture: step 2 lists argo-it's earlier save, which its copy on "
                                 "GitHub's deploy branch keeps off the list")
            with self.subTest(shell=shell, earlier='Not now'):
                r = self.fresh()
                first = self._flow(r, shell, self._gen(r), picks=(4,))
                self.assertEqual(self._head(r), first['start'], '"Not now" saved something')
                st = self._flow(r, shell, self._gen(r), picks=())
                self.assertIsNotNone(st['ask'])
                for f in self.GENERATED:
                    self.assertIn('?? ' + f, st['ask']['status'].splitlines(), "fixture: argo-it's %s is saved after "
                                  '"Not now"' % f)
        with self.subTest(what='text'):
            self._rerun_words_are_true(self._phase())

    def test_4d_a_branch_name_holding_shell_syntax_is_never_run_and_the_guards_still_match(self):
        for shell in ('bash', 'zsh'):
            for name in self.BRANCHES:
                with self.subTest(shell=shell, branch=name):
                    r = self.fresh()
                    r.git('checkout', '-q', '-b', name)
                    files = self._gen(r)
                    st = self._flow(r, shell, files)
                    ran = [os.path.join(d, f) for d, _, fs in os.walk(r.root) for f in fs if f.startswith('pwned')]
                    self.assertFalse(ran, 'the branch name was read as shell text: %r' % ran)
                    self.assertFalse(st['stopped'] or st['failed'], 'the send stopped: %r %r' % (st['stopped'], st['failed']))
                    self.assertEqual(len(st['asks']), 1, "the guards don't match the branch name to itself, so the ask "
                                     "was shown again")
                    self.assertEqual(self._ref(r, name), st['saved'], "origin's %r is not argo-it's save" % name)
                    self.assertEqual(self._ref(r, self.DEPLOY), st['saved'])

    def test_4e_a_failed_fetch_stops_before_the_ask_with_nothing_saved_or_sent(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                v = self._off_origin(r, 'rewound', 'fetch' + shell)  # this clone's origin/main still holds the key
                r.git('remote', 'set-url', 'origin', os.path.join(r.root, 'no-such-origin'))  # fetching fails
                r.git('remote', 'set-url', '--push', 'origin', os.path.join(r.root, 'origin'))  # sending works
                st = self._flow(r, shell, self._gen(r))
                self.assertFalse(_b(v) in self._sent_objects(r), 'a failed fetch went on, a stale origin branch read '
                                 'the key as sent, and the key reached origin again')
                self.assertIsNone(st['ask'], 'a failed fetch did not stop before the step-3 ask')
                self.assertTrue(st['failed'] or st['stopped'])
                self.assertEqual(self._head(r), st['start'])
                self.assertEqual(self._origin(r, 'for-each-ref'), st['refs'])
        with self.subTest(what='text'):
            self._fetch_failure_stops(self._phase())

    def test_4f_step_2s_git_log_in_a_repo_with_no_commits_yet_has_a_reading_rule(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self._unborn()
                st = self._flow(r, shell, self._gen(r), picks=())
                self.assertIsNotNone(st['ask'], 'a clean first deploy with no commits yet stopped: %r' % st['stopped'])
                self.assertEqual(self._listed(st, 0), [])
        with self.subTest(what='text'):
            self._no_commits_log_rule(self._phase())

    # --- 5. binding controls: review 5's mutations M1, M7, M8 and M9 of the real text each fail one ----------------------
    def test_5a_control_a_save_right_before_argo_its_save_is_named_by_an_ask_before_it_is_sent(self):
        # control: passes today; M1 (no SAVED SINCE THE CHECK guard) and M9 (its rule skips step 2) fail it
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell, what='a clean save'):
                r = self.fresh()
                files = self._gen(r)
                mine = []
                st = self._flow(r, shell, files, after_guard=lambda: self._commit_one(r, 'notes.md', '# my plan\n',
                                                                                      'my notes', mine))
                self.assertTrue(mine, "the flow never reached the moment right before argo-it's save: %r %r"
                                % (st['stopped'], st['failed']))
                self._asks_again(r, st, files, mine[0])
            with self.subTest(shell=shell, what='a save holding a key'):
                v = fake('guardgap' + shell)
                r = self.fresh()
                mine = []
                st = self._flow(r, shell, self._gen(r), after_guard=lambda: self._commit_one(
                    r, 'settings.py', kv('API_' + 'KEY', v), 'my key', mine))
                self.assertTrue(mine)
                self.assertFalse(_b(v) in self._sent_objects(r), "a save right before argo-it's save was sent unchecked")
                self.assertEqual(st['stopped'], 'a hit counts')
                self.assertEqual(self._origin(r, 'for-each-ref'), st['refs'])

    def test_5b_control_a_save_right_after_2bs_first_check_is_named_by_an_ask_before_it_is_sent(self):
        # control: passes today; M8 ({asked_head} remembered after 2b's check, not before) fails it
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                files = self._gen(r)
                mine = []
                st = self._flow(r, shell, files, after_first_check=lambda: self._commit_one(
                    r, 'notes.md', '# my plan\n', 'my notes', mine))
                self.assertTrue(mine, "the flow never reached the moment right after 2b's first check")
                self._asks_again(r, st, files, mine[0])

    def test_5c_control_a_branch_switch_right_before_argo_its_save_sends_only_to_the_branch_the_ask_named(self):
        # control: passes today; M7 (push 2 back to `$(git branch --show-current)`) fails it
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                files = self._gen(r)
                before = self._sent_refs(r)
                st = self._flow(r, shell, files, after_guard=lambda: r.git('checkout', '-q', '-b', 'experiment'),
                                picks=(1, 1))
                # review 7 Minor 5: after a switch the send goes through, then a rule may tell the user argo-it's files
                # block the way back (Fix6 test_6), so only a stop fails here; both pushes are asserted below
                self.assertFalse(st['stopped'], '%r %r' % (st['stopped'], st['failed']))
                asked = 'refs/heads/' + st['asks'][-1]['branch']
                after = self._sent_refs(r)
                self.assertEqual(self._changed(before, after), {asked, 'refs/heads/' + self.DEPLOY}, 'the save went to '
                                 'a branch the ask never named: %r' % sorted(self._changed(before, after)))
                self.assertEqual(after[asked], st['saved'])

    # --- 6. polarity: each new prose check passes a plain reading and fails its plain opposite -------------------------
    GOOD5 = '\n'.join((
        '**2. Check whether the deploy branch exists:**',
        '',
        '```bash',
        'git fetch --prune origin 2>/dev/null || { echo "FETCH FAILED"; exit 1; }',
        'git log --oneline HEAD --not --remotes',
        '```',
        '',
        'In a repo with no commits yet, `git log` prints an error there: read it as nothing listed. If the block',
        "prints `FETCH FAILED`, stop -- don't show the step-3 ask; nothing is sent. Tell the user:",
        '',
        "\"I couldn't reach GitHub to see what's already there, so I haven't saved or sent anything. What to do next:",
        'check that this computer can reach GitHub, then run /argo-it again."',
        '',
        '**2b. Secret check** -- read the result exactly as 3e does.',
        '',
        "**If any hit counts (under `== saved, not sent ==`, or in a file the save will save): stop here.** Don't",
        'show the step-3 ask; nothing is sent. Tell the user:',
        '',
        '"I found what looks like a password or secret key on **line [N] of [file]**. [If a hit sits under',
        "`== saved, not sent ==`: The one in **[file]** is in a change you already saved but haven't sent yet.]",
        "Secrets should never be saved in code, so I won't send this. I haven't saved or sent anything. What to do",
        'next: [for a hit whose path holds `\\xNN` or `\\uXXXX`, not under `== saved, not sent ==`: give that file,',
        'and the folders it sits in, plain names, then run /argo-it again] [only if a hit under',
        '`== saved, not sent ==`, or a hit with a plain path, counts: ask your DevOps team to help [for a hit under',
        '`== saved, not sent ==`: remove it from the saved history before sending]]."',
        '',
        '**3. Ask the user what they want to do:**',
        '',
        "\"I've generated your deployment pipeline -- the files are in your project folder, and nothing has been saved",
        "or sent yet [if argo-it's files are already saved, in place of that: they're saved from last time [if step 2",
        'found the deploy branch holding them: , and a copy is already on GitHub / otherwise: , but nothing has been',
        'sent yet]]. [If this ask is shown again: Since I last asked, [your branch changed / you switched your project',
        "to **[branch]**], so I checked again.] Here's what's ready:",
        '',
        '**What would you like to do?**',
        '',
        '1. **Send it -- deploys to {hostname}** -- I save these files and send them',
        "4. **Not now** -- the files stay in your project folder, not saved yet [if they're already saved, in place",
        'of that: saved from last time]; nothing is sent"',
        '',
        '**4. Execute based on user choice:**',
        '',
        "**Option 1 (send):** Remember `git rev-parse HEAD` as `{checked_head}`, then run 2b's check again and read it",
        'the same way.',
        '',
        '```bash',
        '[ "$(git rev-parse HEAD)" = "{checked_head}" ] || { echo "SAVED SINCE THE CHECK"; exit 3; }',
        'git commit -q -m "Add K8s manifests" -- {generated_files}',
        '[ "$(git diff-tree --root -r --name-only --no-commit-id HEAD)" = "{generated_files}" ] || {',
        '  git reset -q --soft "{checked_head}"; echo "SAVE HELD MORE"; exit 4; }',
        'git rev-parse HEAD',
        '```',
        '',
        'If it prints `SAVE HELD MORE`, stop: argo-it took its save back, and nothing is sent. First run',
        '`git ls-remote origin` to see whether GitHub already holds that save. Tell the user:',
        '',
        "\"I stopped before sending anything: your project's own save step took in other files of yours along with",
        "the setup files I made, so I took that save back. [If GitHub already holds that save: Your project's own",
        'setup already sent it to GitHub when I saved it, so have the values in it changed.] What to do next: ask',
        'your DevOps team to help, then run /argo-it again."',
        '',
        "Otherwise remember the commit id it prints as `{saved_head}`. Then, right before any push, run 2b's check",
        "again and read it the same way: on a stop, take argo-it's save back first (`git reset -q --soft",
        "{checked_head}`), then use 2b's stop as written.",
        '',
        '```bash',
        'git push origin {saved_head}:refs/heads/{deploy_branch} || { echo "PUSH 1 FAILED"; exit 1; }',
        'git push origin {saved_head}:refs/heads/main || { echo "PUSH 2 FAILED"; exit 1; }',
        '```',
        '',
        '**If either push fails** (the block prints `PUSH 1 FAILED` or `PUSH 2 FAILED`), never say "Pushed!". First',
        'run `git ls-remote origin`: if a line other than `refs/heads/{deploy_branch}` (when the first push went',
        "through) holds `{saved_head}`, the project's own setup already sent the save. Tell the user:",
        '',
        '"I couldn\'t send your setup to GitHub, so [nothing was sent / if the first one went through: only',
        '`{deploy_branch}` was set up there, and nothing else was sent]. What to do next: [the fix], then run',
        '/argo-it again."',
        '',
        "**Option 4 (not now):** say the files stay in the project folder, not saved yet [if they're already saved,",
        'in place of that: saved from last time], and nothing was sent.',
        '',
        '**5. Report success:**',
        ''))

    def test_6_control_new_prose_checks_are_polarity_bound(self):  # control: passes today
        def sec(n):
            return lambda t: t[slice(*self._option_at(t, n))]
        g, g4 = self.GOOD5, self.GOOD4
        checks = [  # `_last_check_owns_the_save` moved to Fix5 test_7, on a text in the redesign's mechanism
            ('_deploy_line_never_reads_as_already_sent', g, sec(1), [
                ('if a line other than `refs/heads/{deploy_branch}` (when the first push went\nthrough) holds',
                 'if a line it prints holds')]),
            ('_escaped_saved_keeps_the_history_step', g, self._prose, [
                ('[only if a hit under\n`== saved, not sent ==`, or a hit with a plain path, counts:',
                 '[only if a hit with a plain path counts:'),
                ('plain names, then run /argo-it again]', 'plain names]')]),
            ('_reask_says_branch_changed', g, self._ask_text, [
                ('[your branch changed / you switched', "[a change was saved -- it's named below / you switched"),
                ('[your branch changed / you switched',
                 "[a change was saved -- it's named below / your branch changed / you switched")]),
            ('_rerun_words_are_true', g, lambda t: t, [
                ("[if argo-it's files are already saved, in place of that:",
                 "[on a re-run, with argo-it's own earlier save of these files listed in step 2, in place of that:"),
                (" [if step 2\nfound the deploy branch holding them: , and a copy is already on GitHub / otherwise: , but "
                 "nothing has been\nsent yet]", ', but nothing has been sent yet'),
                ("[if they're already saved, in place\nof that:", '[on a re-run, in place\nof that:'),
                ("[if they're already saved,\nin place of that:", '[on a re-run,\nin place of that:')]),
            ('_fetch_failure_stops', g, lambda t: t, [
                ('2>/dev/null || { echo "FETCH FAILED"; exit 1; }', '2>/dev/null || true'),
                ("stop -- don't show the step-3 ask; nothing is sent.", 'go on to the step-3 ask.'),
                ("\"I couldn't reach GitHub to see what's already there, so I haven't saved or sent anything. What to do "
                 "next:\ncheck that this computer can reach GitHub, then run /argo-it again.\"",
                 "\"I ran into a problem with GitHub while I was checking what's there.\"")]),
            ('_no_commits_log_rule', g, lambda t: t, [
                ('In a repo with no commits yet, `git log` prints an error there: read it as nothing listed. ', ''),
                ('read it as nothing listed.', "stop: I couldn't check.")]),
            # the re-run exemption, tightened (coordinator, after review 5): only a bracket on its true condition passes
            ('_ask_says_nothing_saved', g4, self._ask_text, [
                ("[on a re-run, with `git ls-files` listing argo-it's files:", '[on a re-run:'),
                ("[on a re-run, with `git ls-files` listing argo-it's files:",
                 "[on a re-run, with argo-it's own earlier save listed in step 2:")]),
            ('_not_now_says_unsaved', g4, sec(4), [
                ("[if they're already saved:\nthe files are", '[on a re-run:\nthe files are')]),
        ]
        for name, t, view, swaps in checks:
            fn = getattr(self, name)

            def check(x, fn=fn, view=view):
                v = view(x)
                return fn(*v) if isinstance(v, tuple) else fn(v)
            with self.subTest(check=name, text='plain reading'):
                check(t)
            for old, opposite in swaps:
                self.assertIn(old, t)
                with self.subTest(check=name, opposite=opposite[:60]):
                    with self.assertRaises(AssertionError):
                        check(t.replace(old, opposite))


# ArgoItFirstSendFix4Cases' helpers (not its tests), for fix round 5 below.
_FirstSendFix4 = type('_FirstSendFix4', (object,), {k: v for k, v in ArgoItFirstSendFix4Cases.__dict__.items()
                                                    if not k.startswith(('test', '__'))})


class ArgoItFirstSendFix5Cases(_FirstSendFix4, _FirstSendFix3, _FirstSendFix2, _FirstSendAdv1, _FirstSendFix1, _FirstSend,
                               Base):
    """Task 3 review 6 and the owner's redesign after it (2026-10-20, "save without hooks, send by id"; "only what
    origin has counts as sent"): on "Send it" argo-it builds its save with git's low-level commands (no hook runs, HEAD
    and the branch don't move), checks exactly that commit with secret-scan.py's new way to check one given commit (its
    content and every commit it reaches that origin lacks), sends it by id, and moves the branch here only by
    compare-and-swap; the scanner counts a commit as sent only when origin has it, for 3e too. Review 6's four failing
    paths are driven end to end under bash and zsh. The text checks are proven against their plain opposites in test_7.
    Values and secret-named lines are joined at run time (GitGuardian scans this file)."""

    MIRROR = 'origin-mirror'  # a second remote whose name starts like origin's: only origin counts as sent
    # deploy branch names git accepts that run a harmless command (an empty file, in the fixture repo) if a shell reads them
    DEPLOY_NAMES = ('d$(true>pwned5)', "d'$(true>pwned6)'")
    HOOK_TOLD = (r"(?i)\bpre-commit\s+hooks?\b|\b(?:checks?|steps?|hooks?)\s+(?:that\s+|which\s+)?(?:your\s+project\s+)?"
                 r"runs?\s+(?:whenever|when|each time|every time)\s+(?:you\s+save|something\s+is\s+saved|anything\s+is\s+"
                 r"saved|a\s+change\s+is\s+saved)\b|\bproject's\s+own\s+(?:save\s+)?(?:hooks?|checks?|steps?)\b")
    NOT_RUN = (r"(?i)\b(?:don't|do not|won't|will not|doesn't|does not|never|aren't|isn't|can't)\s+(?:\w+\s+){0,2}?"
               r"(?:run|runs)\b|\bskip(?:s|ped)?\b")
    ON_MINE = r"(?i)\bsetup\s+files\b|\bfiles\s+I\s+(?:made|generated|make)\b|\bgenerated\s+files\b"
    CHECK_DOES = (r"(?i)\b(?:my|argo-it's)\s+(?:own\s+)?(?:secret\s+)?check\b[^.;]{0,40}?\b(?:does|runs|still runs|is run"
                  r"|checks)\b|\bI\s+(?:still\s+)?check\s+(?:them|those files|these files|the setup files|it)\b[^.;]{0,30}"
                  r"\b(?:secrets?|passwords?|keys?)\b")
    COMMIT_CMD = r'\bgit\s+(?:(?:-c\s+\S+|--no-replace-objects)\s+)*commit(?![\w-])'
    TAKE_BACK_CMD = r'\bgit\s+reset\b[^\n`]*--soft\b|\bgit\s+update-ref\s+-d\b'
    BRANCH_PH = r'(?<!\$)\{[\w-]*branch[\w-]*\}'
    COMMIT_PH = r'(?<!\$)\{([\w-]*(?:head|commit|sha|id|save)[\w-]*)\}'
    BRANCH_LINES = (r"(?i)\bbranch\s+lines?\b|refs/heads/(?:…|\.\.\.|\*)|\bonly\b[^.;]{0,60}\brefs/heads/|--heads\b"
                    r"|\bbranches\b[^.;]{0,30}\b(?:only|not\s+`?HEAD`?)\b")
    SAVE_THEN_CHECK = (r"(?i)\b(?:sav(?:e|es|ing)|build(?:s|ing)?)\b.*?\bcheck(?:s|ing)?\b[^.;]{0,40}?\b(?:that|the|this"
                       r"|its|exactly|what)\b[^.;]{0,30}?\b(?:save|commit|sent|sends|send|push(?:es)?)\b.*?\bsend")
    SENT_YES = r"(?i)\bI\s+sent\s+(?:your|the)\s+setup\b|\byour\s+setup\s+is\s+(?:now\s+)?on\s+GitHub\b"
    NEWER = (r"(?i)\byour\s+(?:own\s+)?(?:saves?|changes?|copy(?:\s+here)?)\b[^.]{0,60}?\b(?:is|are)\s+newer\b"
             r"|\bnewer\s+than\s+what\s+I\s+sent\b")
    NOT_SENT_MINE = (r"(?i)\b(?:none of them|none of yours|nothing of yours)\s+(?:was|were|got)\s+sent\b"
                     r"|\b(?:they|those|your (?:own )?(?:saves?|changes?))\s+(?:weren't|were not|wasn't|was not)\s+sent\b")
    NOTHING_SENT = ArgoItFirstSendScanCases.SENT_NONE + r"|\bwith\s+nothing\s+(?:sent|pushed)\b"
    KEPT = (r"(?i)\bleft\b[^.]{0,30}\bas (?:they|it) (?:are|is|was|were)\b|\bkept\b|\bdidn't (?:change|touch|drop)\b"
            r"|\bnever dropped\b")
    # a way to bring the two together that sends nothing (review 7 Important 1: VS Code's Sync also sends)
    TOGETHER = r"(?i)\bbring\b[^.]{0,30}\btogether\b|\bcombine\b|\bget the latest\b|\bpull\b"
    # a next step that sends: a Sync, a push, a publish, a send, an upload -- the user's own saves would go out unchecked
    SENDS = r"(?i)\bsync(?:s|ed|ing)?\b|\b(?:push|publish|send|upload)(?:ing)?\b"
    # ...unless it is negated ("not Sync", "without sending") or only described ("which would also send", "before
    # sending", "I'll ... send")
    NOT_TOLD = (r"(?i)(?:(?:\b(?:not|never|no|without|nothing|avoid|instead of|rather than)\b|n't\b)(?:\s+[\w'-]+){0,3}"
                r"|\b(?:would|could|might|which|that|before|after|until|once|I'll|I will)\b(?:\s+[\w'-]+){0,3})\s*$")

    # --- fixtures --------------------------------------------------------------------------------------------------
    def _object_commit(self, r, parent, files):
        """A commit object holding `files` on top of `parent` (None: a first commit) and on no branch, built here with
        git's own plumbing: no hook runs and no ref moves."""
        with tempfile.TemporaryDirectory() as td:
            env = dict(os.environ, GIT_INDEX_FILE=os.path.join(td, 'index'))

            def g(*a, **kw):
                return subprocess.run(GIT + list(a), cwd=r.work, env=env, check=True, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, **kw).stdout.strip().decode()
            g('read-tree', parent) if parent else g('read-tree', '--empty')
            for rel, text in files.items():
                blob = g('hash-object', '-w', '--stdin', input=_b(text))
                g('update-index', '--add', '--cacheinfo', '100644,%s,%s' % (blob, rel))
            return g('commit-tree', *(['-p', parent] if parent else []), '-m', 'object', g('write-tree'))

    def _mirror(self, r):
        """A second remote (a bare repo in the fixture) named so a sloppy origin match would take it in too."""
        Repo._git(r.root, 'init', '-q', '--bare', 'mirror')
        r.git('remote', 'add', self.MIRROR, os.path.join(r.root, 'mirror'))

    def _branches(self, r):
        """The branches here, {ref: commit id}."""
        out = r.git('for-each-ref', '--format=%(objectname) %(refname)', 'refs/heads').decode().splitlines()
        return dict(reversed(l.split(' ', 1)) for l in out)

    def _hooks(self, r, scripts):
        """The fixture's own hooks folder (core.hooksPath, nowhere else) holding `scripts` ({hook name: body})."""
        hooks = os.path.join(r.root, 'hooks')
        os.makedirs(hooks, exist_ok=True)
        for name, body in scripts.items():
            path = os.path.join(hooks, name)
            with open(path, 'w') as f:
                f.write('#!/bin/sh\n' + body)
            os.chmod(path, 0o755)
        return hooks

    @staticmethod
    def _last_checked(st):
        """The commit the last check before the first push read (the last check, if nothing was pushed)."""
        t = st['trace']
        end = min([i for i, e in enumerate(t) if e[0] == 'push'] or [len(t)])
        checks = [e[1] for e in t[:end] if e[0] == 'check']
        return checks[-1] if checks else None

    def _sent_exactly_the_checked_commit(self, r, st, before, files, refs=('main',)):
        """Origin's `refs` and its deploy branch changed, and only they, each to the commit the last check read; that
        commit is the start (or none, in a repo with no commits yet) plus argo-it's `files`, nothing else."""
        sent = self._last_checked(st)
        self.assertTrue(sent, 'no check ran before the push: %r' % st['trace'])
        after = self._sent_refs(r)
        want = {'refs/heads/' + b for b in refs + (self.DEPLOY,)}
        self.assertEqual(self._changed(before, after), want, 'origin changed on other branches than %r: %r'
                         % (sorted(want), sorted(self._changed(before, after))))
        for k in want:
            self.assertEqual(after[k], sent, "origin's %s is not the commit the last check read" % k)
        parents = r.git('rev-list', '--parents', '-n', '1', sent).decode().split()[1:]
        self.assertEqual(parents, [st['start']] if st['start'] else [], "the commit sent doesn't sit on the start")
        self.assertEqual(r.git('diff-tree', '--root', '-r', '--name-only', '--no-commit-id', sent).decode().split(),
                         sorted(files), "the commit sent holds more than argo-it's files")
        return sent

    # --- the scanner's new call, as the text makes it ---------------------------------------------------------------
    def _commit_call(self, p=None, need=True):
        """(command, placeholder) of the call PHASE 5 (or `p`) makes to check one given commit by its id: a
        secret-scan.py call, in a ```bash block or in `...` in the prose, that takes a `{...}` naming a commit."""
        p = p or self._phase()
        cands = [l.strip() for f in self._fences(p) for l in f[2].splitlines()
                 if 'secret-scan.py' in l and not l.lstrip().startswith('#')]
        prose = re.sub(self.FENCE, '', p, flags=re.M | re.S)
        cands += re.findall(r'`([^`\n]*secret-scan\.py[^`\n]*)`', prose)
        for c in cands:  # (Fix1 test_1d calls this with its own self: the pattern is read off this class)
            m = re.search(ArgoItFirstSendFix5Cases.COMMIT_PH, c)
            if INSTALLED in c and m:
                return c, m.group(1)
        if need:
            self.fail('PHASE 5 has no call that checks one given commit by its id (a %s call that takes a commit\'s '
                      '{placeholder}): argo-it\'s save is never checked as the commit the push sends' % INSTALLED)

    def _check_commit(self, cwd, shell, sha):
        """PHASE 5's call that checks one commit, run as written under `shell` on commit `sha`."""
        need_shell(shell)
        code, name = ArgoItFirstSendFix5Cases._commit_call(self)
        run = code.replace('{%s}' % name, sha).replace(INSTALLED, SCRIPT)
        self.assertNotRegex(run, r'(?<!\$)\{[A-Za-z_][\w-]*\}', 'an unknown placeholder in %r' % code)
        cp = subprocess.run([shell, '-c', run], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180)
        return Result(cp, 0)

    # --- the text checks (each proven against its plain opposite in test_7) ----------------------------------------
    def _quoted_sentences(self, p):
        """The sentences of PHASE 5's messages to the user (each "..." of 20 characters or more, code taken out)."""
        flat = self._flat(re.sub(self.FENCE, ' ', p, flags=re.M | re.S))
        return [s for q in re.findall(r'"([A-Z][^"]{20,})"', flat) for s in self._sentences(q)]

    def _hooks_told_once(self, p):
        told = [s for s in self._quoted_sentences(p) if self._says(self.HOOK_TOLD, s) and re.search(self.NOT_RUN, s)
                and re.search(self.ON_MINE, s) and self._says(self.CHECK_DOES, s)]
        self.assertEqual(len(told), 1, "the user isn't told, once, that their project's own pre-commit hooks don't run "
                                       "on the setup files argo-it made and that argo-it's secret check does: %r" % told)

    def _send_path(self, p):
        h = re.search(r'^\*\*1\. ', p, re.M)
        self.assertTrue(h, 'PHASE 5: no "**1." heading')
        return p[h.start():self._option_at(p, 2)[0]]

    def _no_commit_and_no_take_back(self, p):
        sec = self._send_path(p)
        code = [l for f in self._fences(sec) for l in f[2].splitlines() if not l.lstrip().startswith('#')]
        prose = re.sub(self.FENCE, ' ', sec, flags=re.M | re.S)
        code += [m.group(1) for m in re.finditer(r'`([^`\n]+)`', prose) if not re.search(
            r"(?i)(?:\b(?:never|not|no|without|instead of|rather than)\b|n't\b)[^.;]{0,40}$", prose[:m.start()])]
        for l in code:
            self.assertNotRegex(l, self.COMMIT_CMD, "PHASE 5's send path still runs `git commit`, with the user's own "
                                                    "hooks live: %r" % l)
            self.assertNotRegex(l, self.TAKE_BACK_CMD, "PHASE 5's send path still takes a save back: %r" % l)

    def _branch_names_in_variables(self, p):
        for f in self._fences(p):
            for l in f[2].splitlines():
                if l.lstrip().startswith('#'):
                    continue
                c = l.split(' #')[0]
                self.assertNotRegex(c, self.BRANCH_PH, 'a branch name is pasted into shell text: %r' % l)
                for m in re.finditer(r'(?:refs/heads/|\borigin/)\$', c):
                    self.assertEqual(c[:m.start()].count('"') % 2, 1, 'a branch name read into a variable is used '
                                     'unquoted: %r' % l)

    def _failed_push_reads_branch_lines(self, sec):
        prose = re.sub(self.FENCE, '', sec, flags=re.M | re.S)
        b = self._rule(prose, lambda u: re.search(self.FAILED, u) or '`PUSH 1 FAILED`' in u, [], 'a push that fails')
        outside = re.sub(r'"(?:I|Pushed|Your)[^"]{20,}"', ' . ', b)
        reads = [s for s in self._all_sentences(outside) if re.search(self.COMMIT_PH, s)
                 and re.search(r'(?i)\bline\b|\bls-remote\b', s) and re.search(r'(?i)\bhold|\bshow|\bprint|\bcontain', s)]
        for s in reads:
            self.assertRegex(s, self.BRANCH_LINES, "the failed-push rule counts every line `git ls-remote origin` prints, "
                             "origin's `HEAD` line among them, so the deploy branch argo-it just set up can read as "
                             "\"your project's own setup already sent it\": %r" % s)
        for f in self._fences(sec):
            for l in f[2].splitlines():
                if re.search(r'\bgit\s+ls-remote\b', l) and not l.lstrip().startswith('#'):
                    self.assertRegex(l, r'--heads\b|refs/heads/', 'the ls-remote block reads origin\'s HEAD line: %r' % l)

    def _step1_checks_what_is_sent(self, p):
        h, e = re.search(r'^\*\*1\. ', p, re.M), re.search(r'^\*\*2\. ', p, re.M)
        self.assertTrue(h and e, 'PHASE 5: no "**1." or "**2." heading')
        ss = [s for s in self._sentences(self._flat(p[h.start():e.start()]).replace('**', '')) if 'Send it' in s]
        self.assertTrue(any(re.search(self.SAVE_THEN_CHECK, s) for s in ss), "step 1 still says Option 1 checks once "
                        "more, then saves and sends: it never says that the save is checked before it is sent: %r" % ss)

    def _last_check_stops_as_2b(self, sec):
        calls = [f for f in self._fences(sec) if 'secret-scan.py' in f[2] and re.search(self.COMMIT_PH, f[2])]
        self.assertTrue(calls, "Option 1 has no ```bash block that checks the commit the push sends by its id")
        nxt = [f[0] for f in self._fences(sec) if f[0] > calls[-1][0]]
        prose = self._flat(sec[calls[-1][1]:nxt[0] if nxt else len(sec)])
        for rx, what in ((r"(?i)\bas 3e (?:reads|does)\b|\b3e's (?:reading|rules)\b", "isn't read as 3e reads a result"),
                         (re.escape(L_SAVED), "doesn't name %s" % L_SAVED),
                         (r"(?i)\bthird bullet\b|\bcouldn't check\b|\bexit 2\b|\bany (?:other )?result\b",
                          "doesn't stop on a result it can't read"),
                         (self.NOTHING_SENT, "doesn't say nothing is sent"),
                         (r"(?i)\b2b's stop\b|I couldn't check your changes for secrets, so I haven't saved or sent "
                          r"anything", "doesn't stop in 2b's words")):
            self.assertRegex(prose, rx, 'the check of the commit the push sends %s: %r' % (what, prose))
        self.assertTrue(self._stops(prose), "a hit in the commit the push sends doesn't stop: %r" % prose)
        self.assertFalse(self._says(self.TAKE_BACK, prose), "the stop takes a save back, but nothing is saved here "
                                                            "before the send: %r" % prose)

    def _next_step_sends(self, q):
        """What the next step of message q (from its "What to do next", else all of q) tells the user to send: each
        Sync, push, publish, send or upload in it that isn't negated or only described."""
        k = re.search(r'(?i)\bwhat to do next\b', q)
        step = (q[k.end():] if k else q).replace('**', '')
        return [m.group(0) for m in re.finditer(self.SENDS, step) if not re.search(self.NOT_TOLD, step[:m.start()])]

    def _newer_than_sent_message(self, sec, mark):
        rule = self._rule_for(sec, mark)
        qs = re.findall(r'"(I[^"]{20,})"', rule)
        self.assertTrue(any(self._said(self.SENT_YES, q) and self._said(self.NEWER, q) and self._said(self.KEPT, q)
                            and re.search(self.NOT_SENT_MINE, q) and re.search(self.TOGETHER, q)
                            and not self._next_step_sends(q) and not re.search(self.NEVER_SAY, q) for q in qs),
                        "when the branch here moved after the check, the user isn't told plainly that the setup was "
                        "sent, that their own saves are newer than it and were kept and not sent, and how to bring the "
                        "two together without sending them (a pull, never a Sync, push or publish): %r" % qs)

    # --- 1. the scanner checks one given commit (owner, after review 6) ----------------------------------------------
    def test_1_the_scanner_checks_a_given_commit_and_every_commit_it_reaches_that_origin_lacks(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell, repo='with commits'):
                v1, v2, v3 = fake('reach' + shell), fake('own' + shell), fake('worktree' + shell)
                r = self.fresh()
                c0 = self._head(r)
                r.write('settings.py', kv('API_' + 'KEY', v1))
                r.commit('my key, never sent')
                c1 = self._head(r)  # HEAD now holds an unsent key
                r.append('app.py', kv('PASS' + 'WORD', v3))  # an unsaved edit: in no commit
                secrets = [v1, v2, v3]
                child = self._object_commit(r, c1, {'env/dev/kustomization.yaml': 'resources: []\n'})
                own = self._object_commit(r, c0, self._keyed(v2))
                clean = self._object_commit(r, c0, self.GENERATED)
                for sha, saved, what in ((c1, ['settings.py:1'], 'the unsent commit itself'),
                                         (child, ['settings.py:1'], 'a clean commit that reaches it'),
                                         (own, [self.REL + ':4'], "a key in the commit's own content, not HEAD's"),
                                         (clean, [], "a clean commit on origin's: clean, whatever HEAD and the edits "
                                                     "hold")):
                    with self.subTest(shell=shell, commit=what):
                        self.check(self._check_commit(r.work, shell, sha), saved=saved, secrets=secrets)
            with self.subTest(shell=shell, repo='no commits yet'):
                v = fake('root' + shell)
                r = self._unborn()
                self.check(self._check_commit(r.work, shell, self._object_commit(r, None, self._keyed(v))),
                           saved=[self.REL + ':4'], secrets=[v])
        with self.subTest(what="control: 3e's own call is unchanged"):  # passes today
            code = [l for l in ArgoItWiringCases('test_old_inline_scan_is_gone')._code().splitlines()
                    if 'secret-scan.py' in l]
            # call A on 3e (coordinator, 2026-10-24): 3e may name the refs that hold what GitHub has (`--sent GLOB`);
            # it still checks what step 4 will send, never one given commit
            self.assertEqual(len(code), 1, "3e's call changed: %r" % code)
            self.assertRegex(code[0], r"^python3 " + re.escape(INSTALLED) + r"(?: --sent '[^'\s]+')*$",
                             "3e's call changed: %r" % code)
            v1, v3 = fake('threee1'), fake('threee3')
            r = self.fresh()
            r.write('settings.py', kv('API_' + 'KEY', v1))
            r.commit('my key, never sent')
            r.append('app.py', kv('PASS' + 'WORD', v3))
            for shell in ('bash', 'zsh'):
                self.check(self._3e(r.work, shell), unsaved=['app.py:2'], saved=['settings.py:1'], secrets=[v1, v3])

    # --- 2. only what origin has counts as sent (owner, 2026-10-20) --------------------------------------------------
    def test_2_a_commit_only_a_second_remote_holds_is_saved_not_sent_for_3e_2b_and_the_commit_check(self):
        for shell in ('bash', 'zsh'):
            v = fake('mirror' + shell)
            r = self.fresh()
            self._mirror(r)
            r.write('settings.py', kv('API_' + 'KEY', v))
            r.commit('my key, sent to the mirror only')
            c1 = self._head(r)
            r.git('push', '-q', self.MIRROR, 'main')
            self.assertIn(('refs/remotes/%s/main' % self.MIRROR).encode(), r.git('for-each-ref'), 'fixture: no mirror')
            exp = {'saved': ['settings.py:1'], 'secrets': [v]}
            with self.subTest(shell=shell, call='the scanner'):
                self.check(r.scan(), **exp)
            with self.subTest(shell=shell, call="2b's block"):
                self.check(self._run(r.work, shell), **exp)
            with self.subTest(shell=shell, call="3e's block"):
                self.check(self._3e(r.work, shell), **exp)
            with self.subTest(shell=shell, call='the check of one commit'):
                self.check(self._check_commit(r.work, shell, self._object_commit(r, c1, self.GENERATED)), **exp)
            with self.subTest(shell=shell, what="step 2's list names a clean save only the mirror holds"):
                r = self.fresh()
                self._mirror(r)
                r.write('notes.md', '# my plan\n')
                r.commit('my notes, sent to the mirror only')
                mine = self._head(r)
                r.git('push', '-q', self.MIRROR, 'main')
                st = self._flow(r, shell, self._gen(r), picks=())
                self.assertIsNotNone(st['ask'], 'a clean first send stopped before the ask: %r' % st['stopped'])
                self.assertTrue(any(mine.startswith(l.split()[0]) for l in self._listed(st, 0)), "step 2's list leaves "
                                "out a save origin doesn't have, so the ask never names what Send it would send: %r"
                                % self._listed(st, 0))

    # --- 3. review 6's Important 1, its four paths -------------------------------------------------------------------
    def test_3a_a_send_every_save_hook_never_sends_a_key_typed_into_argo_its_file_after_the_send_it_check(self):
        for shell in ('bash', 'zsh'):
            for when in ('after_check', 'after_save'):
                with self.subTest(shell=shell, typed={'after_check': 'after the Send-it check',
                                                      'after_save': "right after argo-it's save"}[when]):
                    v = fake('hooklate' + shell + when)
                    r = self.fresh()
                    files = self._gen(r, extra={self.REL: self.CM})
                    here = self._branches(r)
                    st = self._flow(r, shell, files, hooks=self._send_hook(r),
                                    **{when: lambda: r.write(self.REL, self._keyed(v)[self.REL])})
                    self.assertFalse(_b(v) in self._sent_objects(r), "the key typed into argo-it's file after the "
                                     "check reached origin: %r %r" % (st['stopped'], st['failed']))
                    if when == 'after_check':  # it is in argo-it's save: the check of that commit stops on it
                        self.assertEqual(st['stopped'], 'a hit counts', 'no check stopped on the key in the save: %r %r'
                                         % ((st['res'] and st['res'].lines), st['failed']))
                        self.check(st['res'], saved=[self.REL + ':4'], secrets=[v])
                        self.assertEqual(self._origin(r, 'for-each-ref'), st['refs'], 'something reached origin, so '
                                         '"I haven\'t saved or sent anything" isn\'t true')
                        self.assertEqual(self._branches(r), here, 'a branch here moved, so "I haven\'t saved or sent '
                                         'anything" isn\'t true')

    def test_3b_a_send_every_save_hook_and_a_check_that_cannot_be_read_send_nothing_and_the_stop_is_true(self):
        for shell in ('bash', 'zsh'):
            for repo in ('with commits', 'no commits yet'):
                with self.subTest(shell=shell, repo=repo):
                    r = self.fresh() if repo == 'with commits' else self._unborn()
                    files = self._gen(r)
                    here = self._branches(r)
                    st = self._flow(r, shell, files, hooks=self._send_hook(r), unreadable=True)
                    self.assertIn(('pick', 1), st['trace'], 'the flow never reached "Send it": %r' % st['stopped'])
                    self.assertEqual(st['stopped'], "couldn't check", "no check of argo-it's save ran, or one that "
                                     "can't be read didn't stop: %r %r" % (st['stopped'], st['failed']))
                    self.assertEqual(self._origin(r, 'for-each-ref'), st['refs'], "something reached origin, so \"I "
                                     "couldn't check ... I haven't saved or sent anything\" isn't true")
                    self.assertEqual(self._branches(r), here, "a branch here moved, so \"I haven't saved ...\" isn't "
                                     "true")
                    status = r.git('status', '--porcelain', '-uall').decode().splitlines()
                    self.assertEqual(sorted(l for l in status if l[3:] in files), sorted('?? ' + f for f in files),
                                     "argo-it's files aren't left unsaved")
        with self.subTest(what='text'):
            p = self._phase()
            self._last_check_stops_as_2b(p[slice(*self._option_at(p, 1))])

    def test_3c_a_branch_switch_between_the_check_and_the_send_sends_exactly_the_checked_commit_and_moves_no_other_branch(
            self):
        for shell in ('bash', 'zsh'):
            for case in ('to a clean branch, with a key typed into a setup file after the Send-it check',
                         'to a branch holding an unsent key, right after the save',
                         'to a branch holding an unsent key, right before the push'):
                with self.subTest(shell=shell, switch=case):
                    v = fake('switch' + shell + case[:12].replace(' ', ''))
                    r = self.fresh()
                    if case.startswith('to a clean'):
                        r.git('branch', 'other')  # sent already: nothing unsent on it
                        files = self._gen(r, extra={self.REL: self.CM})
                        kw = {'after_check': lambda: r.write(self.REL, self._keyed(v)[self.REL]),
                              'after_save': lambda: r.git('checkout', '-q', 'other')}
                    else:
                        r.git('checkout', '-q', '-b', 'wip')
                        r.write('wip.py', kv('API_' + 'KEY', v))
                        r.commit('my work in progress, never sent')
                        r.git('checkout', '-q', 'main')
                        files = self._gen(r)
                        when = 'after_save' if 'after the save' in case else 'before_push'
                        kw = {when: lambda: r.git('checkout', '-q', 'wip')}
                    here, before = self._branches(r), self._sent_refs(r)
                    st = self._flow(r, shell, files, **kw)
                    self.assertFalse(_b(v) in self._sent_objects(r), 'a fake key reached origin: %r %r'
                                     % (st['stopped'], st['failed']))
                    now = self._branches(r)
                    self.assertEqual({k: v2 for k, v2 in now.items() if k != 'refs/heads/main'},
                                     {k: v2 for k, v2 in here.items() if k != 'refs/heads/main'},
                                     'a branch other than the one the ask was shown on moved')
                    if case.startswith('to a clean'):  # the key is in argo-it's save: its check stops
                        self.assertEqual(st['stopped'], 'a hit counts', '%r %r' % (st['stopped'], st['failed']))
                        self.assertEqual(self._sent_refs(r), before, 'something was sent')
                        self.assertEqual(now, here, 'a branch here moved')
                        continue
                    # review 7 Minor 5: the send goes through, then a rule may tell the user argo-it's files block the
                    # way back (Fix6 test_6), so only a stop fails here; the send itself is asserted just below
                    self.assertFalse(st['stopped'], "the switch stopped a send whose own commit is clean: %r %r"
                                     % (st['stopped'], st['failed']))
                    sent = self._sent_exactly_the_checked_commit(r, st, before, files)
                    self.assertEqual(now['refs/heads/main'], sent, 'the branch the ask was shown on was not moved to '
                                     'what was sent')
                    self.assertEqual(r.git('branch', '--show-current').decode().strip(), 'wip')

    def test_3d_a_save_of_the_users_own_right_after_the_check_is_never_dropped_or_sent_and_the_branch_here_stays(self):
        marks = []
        for shell in ('bash', 'zsh'):
            for when in ('after_save', 'before_push'):
                with self.subTest(shell=shell, saved={'after_save': "right after argo-it's save",
                                                      'before_push': 'right before the push'}[when]):
                    v = fake('mine' + shell + when)
                    r = self.fresh()
                    files = self._gen(r)
                    before, mine = self._sent_refs(r), []
                    st = self._flow(r, shell, files, **{when: lambda: self._commit_one(
                        r, 'mine.py', kv('API_' + 'KEY', v), 'my change', mine)})
                    self.assertTrue(mine, 'the flow never reached that moment: %r %r' % (st['stopped'], st['failed']))
                    self.assertFalse(_b(v) in self._sent_objects(r), "the user's own save was sent, unnamed")
                    self.assertNotEqual(self._origin(r, 'cat-file', '-t', mine[0]).strip(), b'commit',
                                        "the user's own save is on origin")
                    self.assertEqual(self._branches(r), {'refs/heads/main': mine[0]}, "the branch here was moved off "
                                     "the user's own save: it was dropped")
                    self._sent_exactly_the_checked_commit(r, st, before, files)
                    self.assertTrue(st['failed'], "the user isn't told their save is newer than what was sent: no rule "
                                    "named it: %r" % st['stopped'])
                    marks.append(st['failed'])
        with self.subTest(what='text'):
            p = self._phase()
            self._newer_than_sent_message(p[slice(*self._option_at(p, 1))], marks[0] if marks else 'BRANCH KEPT')

    # --- 4. no hook runs during argo-it's save -----------------------------------------------------------------------
    def test_4_no_hook_runs_during_argo_its_save_and_nothing_extra_is_sent(self):
        for shell in ('bash', 'zsh'):
            for repo in ('with commits', 'no commits yet'):
                with self.subTest(shell=shell, repo=repo):
                    v = fake('prehook' + shell + repo[:2])
                    r = self.fresh() if repo == 'with commits' else self._unborn()
                    hooks = self._hooks(r, {
                        'pre-commit': 'echo ran > "$(git rev-parse --git-dir)/pre-commit-ran"\n'
                                      "printf '%%s\\n' '%s' > hooked.py\ngit add -- hooked.py\n"
                                      % kv('API_' + 'KEY', v).strip(),
                        'post-commit': 'echo ran > "$(git rev-parse --git-dir)/post-commit-ran"\n'
                                       'git push -q origin HEAD\n'})
                    files = self._gen(r)
                    before = self._sent_refs(r)
                    st = self._flow(r, shell, files, hooks=hooks)
                    ran = [h for h in ('pre-commit', 'post-commit') if os.path.exists(os.path.join(
                        r.work, '.git', h + '-ran'))]
                    self.assertEqual(ran, [], "the user's own hooks ran during argo-it's save: %r" % ran)
                    self.assertFalse(os.path.exists(r.path('hooked.py')), 'the pre-commit hook ran')
                    self.assertFalse(_b(v) in self._sent_objects(r), "the hook's file reached origin")
                    self.assertFalse(st['stopped'] or st['failed'], '%r %r' % (st['stopped'], st['failed']))
                    self._sent_exactly_the_checked_commit(r, st, before, files)

    # --- 5. after a clean send ---------------------------------------------------------------------------------------
    def test_5_after_a_clean_send_origin_and_the_branch_here_hold_the_checked_commit_and_every_file_is_as_it_was(self):
        fmt = ("for f in $(git diff --cached --name-only --diff-filter=AM -- '*.yaml' '*.yml'); do\n"
               "  printf '# formatted\\n' >> \"$f\"; git add -- \"$f\"\ndone\n")  # the project's formatter, on each save
        for shell in ('bash', 'zsh'):
            for hooks in ('no hooks', 'a formatter the project runs on every save'):
                with self.subTest(shell=shell, hooks=hooks):
                    r = self.fresh()
                    r.append('app.py', 'debug = True\n')  # the user's unsaved edit
                    r.write('notes.md', '# my plan\n')
                    r.git('add', '--', 'notes.md')  # their staged new file
                    r.write('mine.txt', 'scratch\n')  # and an untracked one
                    files = self._gen(r)
                    mine = ['app.py', 'notes.md', 'mine.txt']
                    snap, before = self._snapshot(r, mine + files), self._sent_refs(r)
                    st = self._flow(r, shell, files, hooks=self._hooks(r, {'pre-commit': fmt}) if 'formatter' in hooks
                                    else None)
                    self.assertFalse(st['stopped'] or st['failed'], '%r %r' % (st['stopped'], st['failed']))
                    sent = self._sent_exactly_the_checked_commit(r, st, before, files)
                    self.assertEqual(self._branches(r), {'refs/heads/main': sent}, 'the branch here is not what was '
                                     'sent')
                    self.assertEqual(r.git('symbolic-ref', 'HEAD').strip(), b'refs/heads/main')
                    self.assertEqual(self._snapshot(r, sorted(snap)), snap, 'a file changed')
                    for f in files:
                        self.assertEqual(r.git('cat-file', 'blob', '%s:%s' % (sent, f)), snap[f], "argo-it's %s was "
                                         "sent other than as it is in the folder" % f)
                    self.assertEqual(r.git('status', '--porcelain', '--', *files).decode(), '', "argo-it's files don't "
                                     "show as saved and unchanged")
                    self.assertEqual(sorted(r.git('status', '--porcelain', '--', *mine).decode().splitlines()),
                                     [' M app.py', '?? mine.txt', 'A  notes.md'], "the user's own work isn't as it was")

    # --- 6. the text -------------------------------------------------------------------------------------------------
    def test_6a_the_user_is_told_once_that_their_pre_commit_hooks_dont_run_on_argo_its_files_and_its_check_does(self):
        self._hooks_told_once(self._phase())

    def test_6b_no_git_commit_and_no_take_back_remain_in_phase_5s_send_path(self):
        self._no_commit_and_no_take_back(self._phase())

    def test_6c_every_branch_name_is_read_into_a_quoted_variable_and_a_deploy_branch_name_runs_nothing(self):
        for shell in ('bash', 'zsh'):
            for name in self.DEPLOY_NAMES:
                with self.subTest(shell=shell, deploy_branch=name):
                    self.DEPLOY = name  # what `_fill` gives {deploy_branch}, for this test only
                    r = self.fresh()
                    files = self._gen(r)
                    before = self._sent_refs(r)
                    st = self._flow(r, shell, files)
                    ran = [os.path.join(d, f) for d, _, fs in os.walk(r.root) for f in fs if f.startswith('pwned')]
                    self.assertFalse(ran, 'the deploy branch name was read as shell text: %r' % ran)
                    self.assertFalse(st['stopped'] or st['failed'], '%r %r' % (st['stopped'], st['failed']))
                    self._sent_exactly_the_checked_commit(r, st, before, files)
        with self.subTest(what='text'):
            self._branch_names_in_variables(self._phase())

    def test_6d_the_failed_push_rule_reads_only_branch_lines_never_origins_head_line(self):
        p = self._phase()
        self._failed_push_reads_branch_lines(p[slice(*self._option_at(p, 1))])

    def test_6e_step_1_says_the_save_is_checked_before_it_is_sent(self):
        self._step1_checks_what_is_sent(self._phase())

    # --- 7. polarity: each new text check passes a plain reading and fails its plain opposite ------------------------
    GOOD6 = '\n'.join((
        "**1. Don't save the generated files yet:** nothing is saved or sent before the pick. Only on 'Send it' does",
        "Option 1 check once more, build argo-it's save of its files by name, check exactly that save, and send it.",
        '',
        '**2. Check whether the deploy branch exists.** Write `{deploy_branch}` alone on one line to',
        '`$(git rev-parse --git-dir)/argo-it-deploy-branch` with your file tool, never a shell command.',
        '',
        '```bash',
        'git fetch --prune origin || { echo "FETCH FAILED"; exit 1; }',
        'd="$(cat "$(git rev-parse --git-dir)/argo-it-deploy-branch")"',
        'git rev-parse --verify "origin/$d" 2>/dev/null',
        'git log --oneline HEAD --not --remotes=origin',
        '```',
        '',
        '**3. Ask the user what they want to do:**',
        '',
        "\"I've generated your deployment pipeline, and nothing has been saved or sent yet. Your project's own",
        "pre-commit hooks don't run on the setup files I made; my secret check does.",
        '',
        '**What would you like to do?**',
        '',
        '1. **Send it -- deploys to {hostname}**"',
        '',
        '**4. Execute based on user choice:**',
        '',
        "**Option 1 (send):** Otherwise build argo-it's save with git's low-level commands, so no hook runs:",
        '',
        '```bash',
        'tree="$(GIT_INDEX_FILE="$idx" git write-tree)"',
        'git commit-tree -p "{checked_head}" -m "Add K8s manifests" "$tree"',
        '```',
        '',
        'Remember the commit id it prints as `{saved_head}`. Then check exactly that commit:',
        '',
        '```bash',
        'python3 ' + INSTALLED + ' --commit {saved_head}',
        '```',
        '',
        "Read it as 3e reads a result. Any hit under `== saved, not sent ==`, or any result 3e's third bullet covers,",
        "stops here with nothing sent: use 2b's stop as written.",
        '',
        '```bash',
        'b="$(cat "$(git rev-parse --git-dir)/argo-it-asked-branch")"',
        'git push origin "{saved_head}:refs/heads/$d" || { echo "PUSH 1 FAILED"; exit 1; }',
        'git push origin "{saved_head}:refs/heads/$b" || { echo "PUSH 2 FAILED"; exit 1; }',
        'git update-ref "refs/heads/$b" "{saved_head}" "{checked_head}" || { echo "BRANCH KEPT"; exit 6; }',
        '```',
        '',
        '**If either push fails** (the block prints `PUSH 1 FAILED` or `PUSH 2 FAILED`), never say "Pushed!". First',
        'run `git ls-remote origin`: if a branch line (`refs/heads/…`) other than `refs/heads/{deploy_branch}` holds',
        "`{saved_head}`, the project's own setup already sent it. Tell the user: \"I couldn't send your setup to",
        'GitHub, so nothing was sent. What to do next: [the fix], then run /argo-it again."',
        '',
        'If it prints `BRANCH KEPT`, the user saved a change of their own after the check. Tell the user: "I sent your',
        'setup to GitHub, but you saved changes of your own after I checked, so your copy here is newer than what I',
        'sent -- I left your changes as they are, and none of them were sent. What to do next: bring the two',
        'together -- get the latest from GitHub into your project, then run /argo-it again."',
        '',
        '**Option 2 (local test):** nothing is saved.',
        ''))

    def test_7_control_new_text_checks_are_polarity_bound(self):  # control: passes today
        def sec(n):
            return lambda t: t[slice(*self._option_at(t, n))]
        g = self.GOOD6
        hooks = ("Your project's own\npre-commit hooks don't run on the setup files I made; my secret check does.")
        save = 'git commit-tree -p "{checked_head}" -m "Add K8s manifests" "$tree"'
        checks = [
            ('_hooks_told_once', lambda t: t, [
                (hooks, ''),
                ("don't run on the setup files I made", 'run on the setup files I made too'),
                ('; my secret check does.', '.'),
                ('my secret check does.', 'my secret check does. ' + hooks.replace('\n', ' ')),
                ('the setup files I made; my', 'everything; my')]),
            ('_no_commit_and_no_take_back', lambda t: t, [
                (save, save + '\ngit commit -q -m "Add K8s manifests" -- {generated_files}'),
                ('stops here with nothing sent:', 'stops here with nothing sent: take the save back\n'
                                                  '(`git reset -q --soft {checked_head}`), then'),
                ('stops here with nothing sent:', 'stops here with nothing sent: take the save back\n'
                                                  '(`git update-ref -d HEAD`), then'),
                ('git commit-tree -p', 'git -c core.hooksPath=/dev/null commit -q -m x && git commit-tree -p')]),
            ('_branch_names_in_variables', lambda t: t, [
                ('git rev-parse --verify "origin/$d"', 'git rev-parse --verify origin/{deploy_branch}'),
                ('"{saved_head}:refs/heads/$d"', '"{saved_head}:refs/heads/{deploy_branch}"'),
                ('"{saved_head}:refs/heads/$b"', '{saved_head}:refs/heads/$b'),
                ('git rev-parse --verify "origin/$d"', "git rev-parse --verify 'origin/{deploy_branch}'")]),
            ('_failed_push_reads_branch_lines', sec(1), [
                ('a branch line (`refs/heads/…`) other than', 'a line other than')]),
            ('_step1_checks_what_is_sent', lambda t: t, [
                ("check once more, build argo-it's save of its files by name, check exactly that save, and send it.",
                 "check once more, save argo-it's files by name and send."),
                ('check exactly that save, and send it.', 'and send it.')]),
            ('_last_check_stops_as_2b', sec(1), [
                ("stops here with nothing sent: use 2b's stop as written.", 'is fine: go on to the push.'),
                ("Read it as 3e reads a result.", 'Read it.'),
                (", or any result 3e's third bullet covers,", ''),
                ('with nothing sent', 'after the push'),
                ("use 2b's stop as written.", 'tell the user it went wrong.'),
                ("use 2b's stop as written.", "take the save back first, then use 2b's stop as written.")]),
            ('_newer_than_sent_message', lambda t: (sec(1)(t), 'BRANCH KEPT'), [
                (' What to do next: bring the two\ntogether -- get the latest from GitHub into your project, then run '
                 '/argo-it again.', ''),
                ('so your copy here is newer than what I\nsent -- ', 'so '),
                ('I left your changes as they are, and ', ''),
                (', and none of them were sent', ''),
                ('get the latest from GitHub into your project', 'merge your commits into the deploy branch'),
                ('I sent your\nsetup to GitHub, but you', 'You')]),
            # moved here from Fix4 test_6 (review 6's redesign: the last check reads the commit the push sends by id)
            ('_last_check_owns_the_save', sec(1), [
                ('python3 ' + INSTALLED + ' --commit {saved_head}', 'python3 ' + INSTALLED),
                ('python3 ' + INSTALLED + ' --commit {saved_head}', 'python3 ' + INSTALLED + ' --commit {checked_head}'),
                ('```bash\npython3 ' + INSTALLED + ' --commit {saved_head}\n```\n', '')]),
        ]
        for name, view, swaps in checks:
            fn = getattr(self, name)

            def check(x, fn=fn, view=view):
                v = view(x)
                return fn(*v) if isinstance(v, tuple) else fn(v)
            with self.subTest(check=name, text='plain reading'):
                check(g)
            for old, opposite in swaps:
                self.assertIn(old, g)
                with self.subTest(check=name, opposite=opposite[:60]):
                    with self.assertRaises(AssertionError):
                        check(g.replace(old, opposite))


# ArgoItFirstSendFix5Cases' helpers (not its tests), for fix round 6 below.
_FirstSendFix5 = type('_FirstSendFix5', (object,), {k: v for k, v in ArgoItFirstSendFix5Cases.__dict__.items()
                                                    if not k.startswith(('test', '__'))})


class ArgoItFirstSendFix6Cases(_FirstSendFix5, _FirstSendFix4, _FirstSendFix3, _FirstSendFix2, _FirstSendAdv1,
                               _FirstSendFix1, _FirstSend, Base):
    """Task 3 review 7 (on a7df993): the `BRANCH KEPT` next step brings the user's newer saves and the setup together
    without sending anything (a pull, never VS Code's Sync, a push or a publish), names the setup files to move aside,
    and sends the user back through /argo-it, so following it never puts an unchecked key on origin; however the branch
    here moved after the check, the message says only what is known; the move's index step is checked; argo-it's
    low-level save runs no hook of the project's; the failed-push states and a branch switch during the send are told
    truly. Review 6's N15-N18 and review 7's empty-re-run mutation (MT) each fail a control in test_7. Every drive runs
    under bash and zsh; the text checks are proven against their plain opposites in test_8. Values and secret-named
    lines are joined at run time (GitGuardian scans this file)."""

    PULLS = r"(?i)\bpull\b|\bget the latest\b"
    AGAIN = r"(?i)\brun\s+/argo-it\s+again\b"
    IN_THE_WAY = r"(?i)\bin the way\b|\boverwritten\b|\bblock(?:s|ed|ing)?\b"
    MOVE_OUT = r"(?i)\bmov(?:e|ing)\b[^.]{0,120}?\b(?:out of|aside|elsewhere|somewhere else)\b"
    # the setup files, named: the workflow file beside the user's own workflows, the files placeholder, or a slot for them
    NAMED = (r"build-and-deploy\.yml|\{generated_files\}|\[[^\[\]]*\bfiles?\b[^\[\]]*\b(?:by name|by their names|named"
             r"|listed|one by one)\b[^\[\]]*\]")
    YOU_SAVED = (r"(?i)\byou(?:'ve|\s+have)?\s+(?:just\s+|also\s+)?saved\b"
                 r"|\byou\s+made\s+(?:a\s+|some\s+)?(?:saves?|changes)\b")
    BRANCH_HERE = (r"(?i)\b(?:your|the)\s+branch(?:\s+here)?\s+(?:has\s+)?changed\b"
                   r"|\byour\s+copy(?:\s+here)?\s+(?:has\s+)?changed\b")
    # a condition that checks a fact about the branch here: what it holds on top of the commit checked, or what GitHub
    # lacks (a "[if you saved ...:" isn't one: a pull, an undone save and a project's hook look the same to it)
    FACT = (r"(?i)\b(?:builds?|built)\s+on\b|\bon top of\b|\bancestor\b|\bdescends?\b"
            r"|\bholds?\b[^:\]]{0,80}?\b(?:GitHub|origin)\s+(?:doesn't|does not|don't|lacks?)\b"
            r"|\b(?:aren't|are not|isn't|is not|weren't|were not|not)\s+(?:yet\s+)?(?:on GitHub|sent)\b|\bunsent\b"
            r"|`git\s+(?:log|merge-base|rev-list)\b|\bstep\s+2(?:'s)?\s+lists?\b")
    # "saved it on [the branch the ask was shown on]": the branch that now holds the setup, named
    SAVED_ON = r"(?i)\bsaved\b[^.]{0,40}?\bon\s+(?:\[[^\[\]]*\bbranch\b[^\[\]]*\]|(?<!\$)\{[\w-]*branch[\w-]*\})"
    BACK = r"(?i)\bswitch(?:es|ing)?\s+back\b|\bgo(?:ing)?\s+back\b|\bbefore\s+you\s+(?:switch|change|go)\b"
    LEAVES_OUT = (r"(?i)\bleaves?\s+(?:\w+\s+){0,3}?(?:out|off)\b|\b(?:doesn't|does not|don't|do not)\s+list\b"
                  r"|\b(?:isn't|is not)\s+(?:listed|on (?:the|that|step 2's) list)\b")
    LISTS = r"(?i)\b(?:lists?|listed|names?|shows?)\b"
    WHY_STOP = (r"(?i)\balready in your saved history\b[^.]{0,40}?\bmoving the value\b[^.]{0,40}?"
                r"\bwouldn't take it out\b")
    GEN_AS = (r"(?i)\bas\s+(?:one\s+)?in\s+a\s+file\s+argo-it\s+generated\b"
              r"|\bas\s+(?:one\s+in\s+)?argo-it's\s+(?:own\s+)?(?:file|mistake)\b")
    NOT_SAVED_CHANGE = r"(?i)\bnot\s+(?:as\s+)?(?:one\s+)?(?:in\s+)?a\s+change\s+you\s+already\s+saved\b"
    FIRST_PUSH = r"(?i)\bfirst\s+(?:push|one)\b|\bpush\s+1\b"
    OR_HELD = r"(?i)\bor\b[^.;]{0,100}?\b(?:before|earlier|last (?:time|run)|already|held)\b"

    # --- fixtures --------------------------------------------------------------------------------------------------
    def _their_branch(self, r, tag):
        """Someone else's work on a branch of its own on origin (`theirs`), sent from their own clone."""
        none = os.path.join(r.root, 'no-hooks-other')
        os.makedirs(none, exist_ok=True)
        other = os.path.join(r.root, 'other')

        def g(cwd, *a):
            return Repo._git(cwd, '-c', 'core.hooksPath=' + none, *a)
        g(r.root, 'clone', '-q', os.path.join(r.root, 'origin'), 'other')
        with open(os.path.join(other, 'theirs.md'), 'w') as f:
            f.write('# theirs %s\n' % tag)
        g(other, 'add', '--', 'theirs.md')
        g(other, 'commit', '-q', '-m', 'their change')
        g(other, 'push', '-q', 'origin', 'HEAD:refs/heads/theirs')

    def _push_marks(self, st):
        """The lines PHASE 5 names (`BRANCH KEPT`, ...) that the last block that pushes printed, in order."""
        outs = [cp for code, cp in st['outputs'] if self._git_does(code, 'push')]
        self.assertTrue(outs, 'no block pushed: %r %r' % (st['stopped'], st['failed']))
        return [l for l in outs[-1].stdout.decode().splitlines() if re.fullmatch(self.MARK_LINE, l)]

    def _sec1(self, p=None):
        p = p or self._phase()
        return p[slice(*self._option_at(p, 1))]

    def _told(self, sec, mark):
        """The messages ("I ...", flattened, ** taken out) of the rule for `mark` in sec: from the paragraph that names
        it, on through the paragraphs after it, to a bold heading or a paragraph that names another marker."""
        units = self._units(re.sub(self.FENCE, '', sec, flags=re.M | re.S))
        at = [i for i, u in enumerate(units) if '`%s`' % mark in u]
        self.assertTrue(at, 'PHASE 5 has no rule for %s' % mark)
        blk = [units[at[0]]]
        for u in units[at[0] + 1:]:
            if re.match(r'(?:[-*]\s+)?\*\*', u) or (not u.startswith('"') and re.search(self.MARKER, u)):
                break
            blk.append(u)
        return [q.replace('**', '') for q in re.findall(r'"(I[^"]{20,})"', ' '.join(blk))]

    def _told_all(self, sec, marks):
        return [q for m in marks for q in self._told(sec, m)]

    @staticmethod
    def _next_step(q):
        k = re.search(r'(?i)\bwhat to do next\b:?', q)
        return q[k.end():].strip() if k else ''

    @staticmethod
    def _unconditional(q):
        """q with each "[condition: ...]" taken out, innermost first: what the message says whatever the facts."""
        prev = None
        while prev != q:
            prev, q = q, re.sub(r'\[[^\[\]]*:[^\[\]]*\]', ' ', q)
        return q

    def _aside(self, r, err):
        """Move each file git names as in the way (a tab-indented line of `err`) out of the project folder."""
        rels = [l.strip() for l in err.splitlines() if l.startswith('\t')]
        self.assertTrue(rels, 'git names no file in the way: %r' % err[:300])
        for rel in rels:
            dst = os.path.join(r.root, 'aside', rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            os.replace(r.path(rel), dst)
        return rels

    def _follow(self, r, step, branch='main'):
        """The user follows next step `step` as it reads. A pull (VS Code's Pull: `git pull`, a merge) when it says pull
        or get the latest; when git refuses it because files are in the way and the step says to move them out, the
        files git names go to a folder outside the project and the pull runs again. A Sync, push or publish it tells
        them to make (`_next_step_sends`) is made too: VS Code's Sync is the pull, then a push. Returns what was sent."""
        sends = self._next_step_sends(step)
        self.assertTrue(re.search(self.PULLS, step) or sends, "the next step doesn't bring the user's saves and the "
                        "setup together: %r" % step)

        def pull():
            return subprocess.run(GIT + ['-c', 'pull.rebase=false', 'pull', '-q', '--no-edit', 'origin', branch],
                                  cwd=r.work, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        cp = pull()
        if cp.returncode:
            err = cp.stderr.decode()
            self.assertIn('would be overwritten', err, 'the pull failed: %r' % err[:300])
            self.assertTrue(any(re.search(self.IN_THE_WAY, s) and re.search(self.MOVE_OUT, s)
                                for s in self._sentences(step)), "the pull says files are in the way, and the next step "
                            "doesn't say to move them out of the project folder: %r" % step)
            self._aside(r, err)
            cp = pull()
            self.assertEqual(cp.returncode, 0, 'the pull failed again: %r' % cp.stderr[:300])
        if sends:
            subprocess.run(GIT + ['push', '-q', 'origin', 'HEAD:refs/heads/' + branch], cwd=r.work,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return sends

    def _is_ancestor(self, r, a, b='HEAD'):
        return subprocess.run(GIT + ['merge-base', '--is-ancestor', a, b], cwd=r.work, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE).returncode == 0

    # --- the text checks (each proven against its plain opposite in test_8) -----------------------------------------
    def _kept_next_step(self, sec, mark):
        """The next step after `mark` (the branch here moved after the check) brings the two together without sending
        anything (a pull: never a Sync, push or publish, which would send the user's own saves no check read), names
        the setup files to move out of the folder if the pull says they're in the way, and sends the user back through
        /argo-it, whose check reads their saves before anything goes out (review 7 Important 1)."""
        steps = [self._next_step(q) for q in self._told(sec, mark) if self._next_step(q)]
        self.assertTrue(steps, 'the message for %s gives the user no next step' % mark)
        for s in steps:
            self.assertFalse(self._next_step_sends(s), "%s's next step sends the user's own saves, which no check read "
                             "(%r): %r" % (mark, self._next_step_sends(s), s))
            self.assertRegex(s, self.PULLS, "%s's next step doesn't get the latest from GitHub (a pull): %r" % (mark, s))
            self.assertRegex(s, self.AGAIN, "%s's next step doesn't send the user back through /argo-it, whose check "
                             "reads their own saves: %r" % (mark, s))
            self.assertTrue(any(re.search(self.IN_THE_WAY, x) and re.search(self.MOVE_OUT, x) and re.search(self.NAMED, x)
                                for x in self._sentences(s)), "%s's next step doesn't name the setup files to move out "
                            "of the folder if the pull says they're in the way: %r" % (mark, s))

    def _kept_from_facts(self, qs, own=False):
        """The messages qs, for a branch here that moved after the check, say what is known. Unless it was the user's own
        newer save (`own`): they say the branch here changed, never "you saved", and say "newer" / "none of them were
        sent" only under a condition that checks a fact -- a pull, an undone save and a project's own pre-push hook
        move the branch too (review 7 Minor 1). With `own`, they can say the saves are newer and weren't sent."""
        self.assertTrue(qs, 'no message')
        if own:
            self.assertTrue(any(self._said(self.NEWER, q) and re.search(self.NOT_SENT_MINE, q) for q in qs),
                            "the user's own newer save isn't told as newer than what was sent, and not sent: %r" % qs)
            return
        self.assertTrue(any(self._said(self.BRANCH_HERE, self._unconditional(q)) for q in qs), "the message doesn't "
                        "say the branch here changed, whatever moved it: %r" % qs)
        for q in qs:
            for m in re.finditer(self.YOU_SAVED, q):
                self.assertTrue(re.search(self.SAVED_NEG, q[:m.start()]), "the message says the user saved, but a "
                                "pull, an undone save or a hook moved the branch here: %r" % q)
            for rx in (self.NEWER, self.NOT_SENT_MINE):
                for m in re.finditer(rx, q):
                    conds = self._conds_at(q, m.start())
                    if re.search(self.SAVED_NEG, q[:m.start()]) or None in conds:
                        continue
                    self.assertTrue(any(c and re.search(self.FACT, c) for c in conds), "the message says %r whatever "
                                    "moved the branch here (no condition that checks a fact): %r" % (m.group(0), q))

    def _busy_told(self, qs):
        """A move whose index step can't run (another program holds the index) is told plainly: the setup was sent,
        and what to do next (review 7 Minor 2)."""
        self.assertTrue(any(self._said(self.SENT_YES, q) and re.search(self.NEXT, q) and not re.search(self.NEVER_SAY, q)
                            for q in qs), "the user isn't told plainly that the setup was sent but couldn't be marked "
                                          "saved here, and what to do next: %r" % qs)

    def _refused_move_told(self, qs):
        """A refused second push plus a refused move: the user hears both -- only the deploy copy was set up, and the
        branch here changed, so argo-it left it as it is (review 7 Minor 4 (a))."""
        self.assertTrue(any('{deploy_branch}' in q and re.search(r'(?i)\bset up\b|\bwent through\b|\bis (?:now )?on '
                                                                 r'GitHub\b', q) and re.search(r'(?i)\bnothing else\b', q)
                            for q in qs), "the user isn't told only the deploy copy was set up: %r" % qs)
        self.assertTrue(any(self._said(self.KEPT, q) or self._said(self.BRANCH_HERE, q) for q in qs), "the user isn't "
                        "told the branch here changed and was left as it is, with the setup files not saved in it: %r"
                        % qs)

    def _deploy_line_never_counts(self, sec):
        """The failed-push rule leaves the deploy branch's line out of "it reached GitHub anyway" whenever it held the
        save before this push, not only when this run's first push went through: on a re-run whose second push is
        refused again, that line holds last run's save (review 7 Minor 4 (c))."""
        prose = re.sub(self.FENCE, '', sec, flags=re.M | re.S)
        b = self._rule(prose, lambda u: re.search(self.FAILED, u) or '`PUSH 1 FAILED`' in u, [], 'a push that fails')
        outside = re.sub(r'"(?:I|Pushed|Your)[^"]{20,}"', ' . ', b)
        reads = [s for s in self._all_sentences(outside) if re.search(self.COMMIT_PH, s)
                 and re.search(r'(?i)\bline\b|\bls-remote\b', s) and re.search(r'(?i)\bhold|\bshow|\bprint|\bcontain', s)]
        self.assertTrue(reads, 'the failed-push rule never reads which branch lines hold the save: %r' % b)
        for s in reads:
            self.assertRegex(s, self.EXCL_DEPLOY, "the failed-push rule counts the deploy branch's line: %r" % s)
            if re.search(self.FIRST_PUSH, s):
                self.assertRegex(s, self.OR_HELD, "the deploy line is left out only when this run's first push went "
                                 "through, so a re-run reads last run's copy there as \"it reached GitHub anyway\": %r" % s)

    def _switch_told(self, qs):
        """A branch switch during the send leaves argo-it's files in the folder as new files, blocking the way back: the
        user hears that the setup was sent and saved on the branch the ask named, and to move the setup files out of
        the folder before switching back (review 7 Minor 5)."""
        self.assertTrue(any(self._said(self.SENT_YES, q) and re.search(self.SAVED_ON, q) and re.search(self.MOVE_OUT, q)
                            and re.search(self.BACK, q) and re.search(self.NEXT, q) and not re.search(self.NEVER_SAY, q)
                            for q in qs), "after a switch to another branch during the send, the user isn't told "
                                          "plainly that the setup files must move out of the folder before they switch "
                                          "back to the branch that holds the setup: %r" % qs)

    def _rename_step_off_saved(self, prose):
        """2b's stop offers 3e's rename step (plain names, then /argo-it again) only for an escaped hit not under
        saved: a new name can't take a hit out of a save already made (review 6 N15)."""
        qs = re.findall(r'"(I[^"]{20,})"', self._saved_hit_stops(prose))
        found = 0
        for q in qs:
            for m in re.finditer(r'(?i)\bplain names?\b', q):
                esc = [c for c in self._conds_at(q, m.start()) if c and re.search(self.ESC, c)]
                if not esc:
                    continue
                found += 1
                self.assertTrue(any(re.search(r'(?i)\b(?:not|never|outside|except)\b[^:\]]{0,20}' + re.escape(L_SAVED), c)
                                    for c in esc), "2b's stop offers the rename step for an escaped hit under %s too: %r"
                                % (L_SAVED, esc))
        self.assertTrue(found, "2b's stop has no rename step for an escaped hit")

    def _otherwise_pairs(self, ask):
        """Each "[if C: A / otherwise: B]" in the ask whose halves say whether a copy is on GitHub, as (C, A, B); each
        half sits on its own condition: "leaves out" (GitHub has it) -> A says a copy is on GitHub, B that nothing was
        sent; "lists" -> the other way round (review 6 N16)."""
        pairs = []
        for body in re.findall(r'\[([^\[\]]*)\]', self._flat(ask)):
            if ':' not in body or not re.search(r'/\s*otherwise\s*:', body):
                continue
            cond, rest = body.split(':', 1)
            a, b = re.split(r'/\s*otherwise\s*:', rest, maxsplit=1)
            if re.search(self.COPY_SENT, a + b):
                pairs.append((cond, a, b))
        self.assertTrue(pairs, 'the ask has no "[if ...: a copy is on GitHub / otherwise: ...]" bracket')
        for cond, a, b in pairs:
            if re.search(self.LEAVES_OUT, cond):
                on, off = a, b
            else:
                self.assertRegex(cond, self.LISTS, 'the condition says neither: %r' % cond)
                on, off = b, a
            self.assertRegex(on, self.COPY_SENT, 'the half for "GitHub has it" doesn\'t say a copy is on GitHub: %r'
                             % ((cond, a, b),))
            self.assertRegex(off, self.SENT_STATE, 'the half for "GitHub lacks it" doesn\'t say nothing was sent: %r'
                             % ((cond, a, b),))
        return pairs

    def _saved_stop_says_why(self, prose):
        """2b's stop says 3e's "Because it's already in your saved history, moving the value now wouldn't take it out
        of what gets sent", for a hit under saved only (review 6 N17)."""
        qs = re.findall(r'"(I[^"]{20,})"', self._saved_hit_stops(prose))
        at = [(q, m.start()) for q in qs for m in re.finditer(self.WHY_STOP, q)]
        self.assertTrue(at, "2b's stop never says why moving the value now wouldn't help a hit already saved")
        for q, k in at:
            self.assertTrue(any(c and L_SAVED in c for c in self._conds_at(q, k)), "2b's stop says it for every hit, "
                            "not only one under %s: %r" % (L_SAVED, q))

    def _commit_check_reads_mine_as_mine(self, sec):
        """The check of the commit the push sends reads a hit in one of argo-it's files as one in a file argo-it
        generated, not as a change the user already saved: every hit it prints sits under saved (review 6 N18)."""
        calls = [f for f in self._fences(sec) if 'secret-scan.py' in f[2] and re.search(self.COMMIT_PH, f[2])]
        self.assertTrue(calls, 'Option 1 has no ```bash block that checks the commit the push sends by its id')
        nxt = [f[0] for f in self._fences(sec) if f[0] > calls[-1][0]]
        prose = self._flat(sec[calls[-1][1]:nxt[0] if nxt else len(sec)])
        self.assertTrue(any(re.search(self.GEN_AS, s) and re.search(self.NOT_SAVED_CHANGE, s)
                            for s in self._sentences(prose)), "the commit check doesn't read a hit in one of argo-it's "
                        "files as one in a file argo-it generated, not in a change the user already saved: %r" % prose)

    # --- 1. Important: BRANCH KEPT's next step, followed as written, never sends -----------------------------------
    def test_1_following_branch_kepts_next_step_with_review_6s_input_d_never_puts_the_users_key_on_origin(self):
        marks = []
        for shell in ('bash', 'zsh'):
            for when in ('after_save', 'before_push'):
                with self.subTest(shell=shell, saved={'after_save': "right after argo-it's save",
                                                      'before_push': 'right before the push'}[when]):
                    v = fake('kept' + shell + when)
                    r = self.fresh()
                    files = self._gen(r)
                    mine = []
                    st = self._flow(r, shell, files, **{when: lambda: self._commit_one(
                        r, 'mine.py', kv('API_' + 'KEY', v), 'my change', mine)})
                    self.assertTrue(mine and st['failed'], 'fixture: no rule named the newer save: %r %r'
                                    % (st['stopped'], st['failed']))
                    self.assertFalse(_b(v) in self._sent_objects(r), "fixture: argo-it's own send carried the key")
                    sec = self._sec1()
                    steps = [self._next_step(q) for q in self._told_all(sec, self._push_marks(st)) if self._next_step(q)]
                    self.assertTrue(steps, 'the user is given no next step')
                    self._follow(r, steps[0])
                    self.assertFalse(_b(v) in self._sent_objects(r), "following the next step put the user's key on "
                                     "GitHub, past argo-it's check: %r" % steps[0])
                    self.assertNotEqual(self._origin(r, 'cat-file', '-t', mine[0]).strip(), b'commit', "following the "
                                        "next step sent the user's own save, which no check read: %r" % steps[0])
                    self.assertTrue(self._is_ancestor(r, mine[0]) and self._is_ancestor(r, st['saved']), "the next step "
                                    "didn't bring the user's save and the setup together here: %r" % steps[0])
                    self.assertRegex(steps[0], self.AGAIN, "the next step doesn't send the user back through /argo-it")
                    again = self._flow(r, shell, files)  # /argo-it again: its check reads the user's own save first
                    self.assertEqual(again['stopped'], 'a hit counts', "/argo-it again didn't stop on the user's key: "
                                     '%r %r' % (again['stopped'], again['failed']))
                    self.assertIn('mine.py:1', again['res'].lines)
                    self.assertFalse(_b(v) in self._sent_objects(r))
                    marks.append(st['failed'])
        with self.subTest(what='text'):
            self._kept_next_step(self._sec1(), marks[0] if marks else 'BRANCH KEPT')

    # --- 2. Minor 1: however the branch here moved, the message says only what is known ----------------------------
    def test_2_branch_kept_is_told_from_facts_for_a_newer_save_an_undone_save_a_pull_a_reset_and_a_hook_save(self):
        hook = ('cat >/dev/null\necho saved >> hook-saves.txt\n'
                "git add -- hook-saves.txt && git commit -q -m 'a save the hook made' >/dev/null 2>&1\nexit 0\n")
        for shell in ('bash', 'zsh'):
            for case in ("the user's own newer save", 'an undone save', 'a pull', 'a reset',
                         "a pre-push hook of the project's that saves"):
                with self.subTest(shell=shell, moved_by=case):
                    r = self.fresh()
                    left, hooks, before_push = [], None, None
                    if case == 'an undone save':  # VS Code's Undo Last Commit, on a save already sent
                        r.write('notes.md', '# my plan\n')
                        r.commit('my notes')
                        r.push()
                    elif case in ('a pull', 'a reset'):
                        self._their_branch(r, shell)
                    elif case.startswith('a pre-push'):
                        hooks = self._hooks(r, {'pre-push': hook})
                    files = self._gen(r)
                    before = self._sent_refs(r)

                    def act(case=case):
                        if case.startswith("the user's"):
                            self._commit_one(r, 'mine.py', '# mine\n', 'my change', left)
                            return
                        if case == 'an undone save':
                            r.git('reset', '-q', '--soft', 'HEAD~1')
                        elif case == 'a pull':
                            r.git('pull', '-q', '--no-rebase', '--ff-only', 'origin', 'theirs')
                        elif case == 'a reset':  # the user's own fetch first: argo-it's touches no ref of theirs
                            r.git('fetch', '-q', 'origin')
                            r.git('reset', '-q', '--hard', 'origin/theirs')
                        left.append(self._head(r))
                    if not hooks:
                        before_push = act
                    st = self._flow(r, shell, files, hooks=hooks, before_push=before_push)
                    sent = self._sent_exactly_the_checked_commit(r, st, before, files)
                    here = self._branches(r)['refs/heads/main']
                    self.assertNotEqual(here, sent, 'fixture: the branch here was moved to what was sent')
                    if left:
                        self.assertEqual(here, left[-1], 'argo-it moved the branch here')
                    self.assertTrue(st['failed'], 'the branch here moved after the check, and the user hears "Pushed!"')
                    self._kept_from_facts(self._told_all(self._sec1(), self._push_marks(st)),
                                          own=case.startswith("the user's"))

    # --- 3. Minor 2: the move's index step is checked --------------------------------------------------------------
    def test_3_a_stale_index_lock_at_the_move_is_told_plainly_and_never_leaves_argo_its_files_staged_for_deletion(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                files = self._gen(r)
                before = self._sent_refs(r)
                lock = os.path.join(r.work, '.git', 'index.lock')  # left by a crashed git, or held by VS Code
                st = self._flow(r, shell, files, before_push=lambda: open(lock, 'w').close())
                self.assertTrue(os.path.exists(lock), 'fixture: the lock is gone')
                self._sent_exactly_the_checked_commit(r, st, before, files)
                self.assertTrue(st['failed'], "the index step couldn't run, and the user hears \"Pushed!\"")
                self._busy_told(self._told_all(self._sec1(), self._push_marks(st)))
                os.remove(lock)  # the other program is done
                status = r.git('status', '--porcelain', '--', *files).decode().splitlines()
                self.assertFalse([l for l in status if 'D' in l[:2]], "argo-it's files are left staged for deletion, "
                                 "so the user's next save takes them off the branch: %r" % status)

    # --- 4. Minor 3: argo-it's low-level save runs no hook of the project's -----------------------------------------
    def test_4_a_post_index_change_hook_that_adds_a_file_cannot_change_what_argo_its_save_holds_or_sends(self):
        hook = '[ -n "$ARGO_TEST_INNER" ] && exit 0\nARGO_TEST_INNER=1 git add -- extra.py >/dev/null 2>&1\nexit 0\n'
        for shell in ('bash', 'zsh'):
            for extra in ('clean', 'holding a key'):
                with self.subTest(shell=shell, extra_file=extra):
                    v = fake('pic' + shell + extra[:4])
                    r = self.fresh()
                    r.write('extra.py', kv('API_' + 'KEY', v) if extra != 'clean' else 'debug = True\n')  # the user's
                    files = self._gen(r)
                    before = self._sent_refs(r)
                    st = self._flow(r, shell, files, hooks=self._hooks(r, {'post-index-change': hook}))
                    self.assertFalse(_b(v) in self._sent_objects(r), "the hook's file reached origin")
                    self.assertFalse(st['stopped'] or st['failed'], "the hook changed argo-it's save, so its check "
                                     "stopped or a rule ended the send: %r %r" % (st['stopped'], st['failed']))
                    self._sent_exactly_the_checked_commit(r, st, before, files)

    # --- 5. Minor 4: the failed-push states are told truly ---------------------------------------------------------
    def test_5a_a_refused_second_push_and_a_refused_move_are_both_told(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                files = self._gen(r)
                self._refuse(r, 'refs/heads/main')
                mine = []
                st = self._flow(r, shell, files, before_push=lambda: self._commit_one(r, 'mine.py', '# mine\n',
                                                                                    'my change', mine))
                self.assertTrue(mine and st['failed'], '%r %r' % (st['stopped'], st['failed']))
                self.assertEqual(self._ref(r, self.DEPLOY), st['saved'], 'fixture: the deploy branch was not set up')
                self.assertEqual(self._ref(r, 'main'), st['start'], "fixture: origin's main changed")
                self.assertEqual(self._branches(r), {'refs/heads/main': mine[0]}, "the user's own save was dropped")
                marks = self._push_marks(st)
                self._refused_move_told(self._told_all(self._sec1(), marks))

    def test_5b_after_a_send_that_reached_github_anyway_the_rerun_is_told_truly_and_sends_nothing_twice(self):
        # the user's pre-push hook sends the commit itself, then fails: GitHub took the save, the push reports a failure
        hook = ('[ -n "$ARGO_TEST_INNER" ] && exit 0\nwhile read l s rr rs; do\n'
                '  ARGO_TEST_INNER=1 git push -q "$1" "$s:$rr" >/dev/null 2>&1 || exit 1\ndone\nexit 1\n')
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                r.git('push', '-q', 'origin', 'main:refs/heads/' + self.DEPLOY)  # the deploy copy is already there
                files = self._gen(r)
                first = self._flow(r, shell, files, hooks=self._hooks(r, {'pre-push': hook}))
                self.assertTrue(first['failed'], 'fixture: the push did not report a failure: %r' % first['stopped'])
                self.assertEqual(self._ref(r, 'main'), first['saved'], 'fixture: the save did not reach GitHub')
                after = self._sent_refs(r)
                st = self._flow(r, shell, files)  # /argo-it again, Send it, with the connection fine
                self.assertIsNotNone(st['ask'], 'the re-run stopped before the ask: %r' % st['stopped'])
                self.assertFalse([l for l in st['ask']['status'].splitlines() if l[3:] in files], "at the re-run's ask "
                                 "argo-it's files aren't saved here, so it says \"nothing has been saved or sent yet\" "
                                 "while GitHub's main holds them: %r" % st['ask']['status'])
                self.assertFalse(any(first['saved'].startswith(l.split()[0]) for l in self._listed(st, 0)),
                                 "step 2 lists the save GitHub already holds")
                self.assertFalse(st['stopped'] or st['failed'], 'the re-run did not end right: %r %r'
                                 % (st['stopped'], st['failed']))
                self.assertEqual(self._sent_refs(r), after, 'the re-run sent something new')

    def test_5c_on_a_rerun_whose_second_push_is_refused_again_the_deploy_line_is_never_read_as_reached_anyway(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                files = self._gen(r)
                self._refuse(r, 'refs/heads/main')
                first = self._flow(r, shell, files)
                self.assertTrue(first['failed'] and self._ref(r, self.DEPLOY) == first['saved'], 'fixture: %r'
                                % first['stopped'])
                st = self._flow(r, shell, files)  # /argo-it again; main is still refused
                self.assertTrue(st['failed'], 'fixture: %r' % st['stopped'])
                self.assertEqual(st['saved'], first['saved'], "fixture: the re-run built a new save")
                self.assertEqual(len([e for e in st['trace'] if e[0] == 'push']), 1, 'fixture: the re-run pushed twice')
                held = sorted(k for k, sha in self._sent_refs(r).items() if sha == st['saved'])
                self.assertEqual(held, ['refs/heads/' + self.DEPLOY], 'fixture: a branch line other than the deploy '
                                 "branch's holds the save")
        with self.subTest(what='text'):
            self._deploy_line_never_counts(self._sec1())

    # --- 6. Minor 5: a branch switch during the send ---------------------------------------------------------------
    def test_6_a_branch_switch_during_the_send_that_blocks_the_way_back_is_told_with_a_next_step_that_works(self):
        for shell in ('bash', 'zsh'):
            for when in ('after_save', 'before_push'):
                with self.subTest(shell=shell, switched={'after_save': "right after argo-it's save",
                                                         'before_push': 'right before the push'}[when]):
                    r = self.fresh()
                    r.git('checkout', '-q', '-b', 'wip')
                    r.write('wip.md', '# my work in progress\n')
                    r.commit('my work in progress, never sent')
                    r.git('checkout', '-q', 'main')
                    files = self._gen(r)
                    snap, before = self._snapshot(r, files), self._sent_refs(r)
                    st = self._flow(r, shell, files, **{when: lambda: r.git('checkout', '-q', 'wip')})
                    sent = self._sent_exactly_the_checked_commit(r, st, before, files)
                    self.assertEqual(self._branches(r)['refs/heads/main'], sent, 'fixture: main was not moved')
                    self.assertEqual(r.git('branch', '--show-current').decode().strip(), 'wip')
                    back = subprocess.run(GIT + ['checkout', '-q', 'main'], cwd=r.work, stdout=subprocess.PIPE,
                                          stderr=subprocess.PIPE)
                    if not back.returncode:
                        continue  # nothing blocks the way back
                    self.assertTrue(st['failed'], "argo-it's files block the way back to main, and the user hears "
                                    '"Pushed!" with no next step')
                    self._switch_told(self._told_all(self._sec1(), self._push_marks(st)))
                    self._aside(r, back.stderr.decode())  # the next step: the setup files out of the folder
                    self.assertEqual(subprocess.run(GIT + ['checkout', '-q', 'main'], cwd=r.work, stdout=subprocess.PIPE,
                                                    stderr=subprocess.PIPE).returncode, 0, 'the way back is still blocked')
                    self.assertEqual(r.git('status', '--porcelain', '--', *files).decode(), '')
                    self.assertEqual(self._snapshot(r, files), snap, "argo-it's files on main aren't as sent")

    # --- 7. binding controls: review 6's N15-N18 and review 7's MT each fail one --------------------------------------
    def test_7a_control_the_rename_step_is_offered_only_for_an_escaped_hit_not_under_saved(self):
        # control: passes today; N15 (", not under `== saved, not sent ==`," dropped) fails it
        self._rename_step_off_saved(self._prose())

    def test_7b_control_the_asks_copy_on_github_half_pairs_with_its_condition_on_two_reruns(self):
        # control: passes today; N16 (the opening's inner bracket with its halves swapped) fails it
        pairs = self._otherwise_pairs(self._ask_text(self._phase()))
        for shell in ('bash', 'zsh'):
            for earlier in ('a refused second push', 'a save of the setup files the user made and never sent'):
                with self.subTest(shell=shell, earlier=earlier):
                    r = self.fresh()
                    files = self._gen(r)
                    if earlier.startswith('a refused'):
                        self._refuse(r, 'refs/heads/main')
                        first = self._flow(r, shell, files)
                        self.assertTrue(first['failed'], 'fixture: %r' % first['stopped'])
                    else:
                        self._prep(r)
                        r.git('add', '--', *files)
                        r.git('commit', '-q', '-m', 'my own save of the setup')
                    st = self._flow(r, shell, files, picks=())
                    self.assertIsNotNone(st['ask'], 'the re-run stopped before the ask: %r' % st['stopped'])
                    self.assertFalse([l for l in st['ask']['status'].splitlines() if l[3:] in files], "fixture: argo-it's "
                                     "files aren't saved and unchanged at the re-run's ask")
                    save = r.git('log', '-1', '--format=%H', '--', *files).strip().decode()
                    listed = any(save.startswith(l.split()[0]) for l in self._listed(st, 0))
                    on_github = bool(r.git('branch', '-r', '--contains', save).strip())
                    self.assertEqual(on_github, earlier.startswith('a refused'), 'fixture')
                    for cond, a, b in pairs:
                        said = (b if listed else a) if re.search(self.LEAVES_OUT, cond) else (a if listed else b)
                        self.assertRegex(said, self.COPY_SENT if on_github else self.SENT_STATE, 'the ask says %r here, '
                                         'which is false' % said)

    def test_7c_control_2bs_stop_says_why_moving_a_value_already_saved_would_not_help(self):
        # control: passes today; N17 (2b's "Because it's already in your saved history ..." dropped) fails it
        self._saved_stop_says_why(self._prose())

    def test_7d_control_the_commit_check_reads_a_hit_in_argo_its_file_as_argo_its_not_as_a_saved_change(self):
        # control: passes today; N18 (the commit check's "reading a hit in one of argo-it's files as ..." dropped)
        self._commit_check_reads_mine_as_mine(self._sec1())

    def test_7e_control_a_rerun_with_argo_its_files_already_sent_sends_no_new_commit(self):
        # control: passes today; MT (the tree-equal shortcut removed: an empty commit, sent, starts a deploy) fails it
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                files = self._gen(r)
                first = self._flow(r, shell, files)
                self.assertFalse(first['stopped'] or first['failed'], '%r %r' % (first['stopped'], first['failed']))
                sent = self._sent_refs(r)
                st = self._flow(r, shell, files)  # /argo-it again, Send it, with nothing new
                self.assertFalse(st['stopped'] or st['failed'], '%r %r' % (st['stopped'], st['failed']))
                self.assertEqual(st['saved'], first['saved'], 'the re-run built a new save (an empty commit)')
                self.assertEqual(self._sent_refs(r), sent, 'the re-run sent a new commit, which starts a deployment')

    # --- 8. polarity: each new text check passes a plain reading and fails its plain opposite ------------------------
    GOOD7 = '\n'.join((
        '**2. Check whether the deploy branch exists.**',
        '',
        '```bash',
        'git fetch --prune origin || { echo "FETCH FAILED"; exit 1; }',
        'git log --oneline HEAD --not --remotes=origin',
        '```',
        '',
        '**2b. Secret check** -- read the result exactly as 3e does.',
        '',
        "**If any hit counts (under `== saved, not sent ==`, or in a file the save will save): stop here.** Don't",
        'show the step-3 ask; nothing is sent. Tell the user:',
        '',
        '"I found what looks like a password or secret key on **line [N] of [file]**. [If a hit sits under',
        "`== saved, not sent ==`: The one in **[file]** is in a change you already saved but haven't sent yet.]",
        "Secrets should never be saved in code, so I won't send this. [If a hit sits under `== saved, not sent ==`:",
        "Because it's already in your saved history, moving the value now wouldn't take it out of what gets sent --",
        "so I'm stopping here.] I haven't saved or sent anything. What to do next: [for a hit whose path holds",
        "`\\xNN` or `\\uXXXX`, not under `== saved, not sent ==`, 3e's next step for it: give that file, and the",
        'folders it sits in, plain names, then run /argo-it again] [only if a hit under `== saved, not sent ==`, or a',
        'hit with a plain path, counts: ask your DevOps team to help]."',
        '',
        '**3. Ask the user what they want to do:**',
        '',
        "\"I've generated your deployment pipeline -- the files are in your project folder, and nothing has been saved",
        "or sent yet [if argo-it's files are already saved, in place of that: they're saved from last time [if step 2's",
        'list leaves out that earlier save: , and a copy is already on GitHub / otherwise: , but nothing has been sent',
        "yet]]. Here's what's ready:",
        '',
        '**What would you like to do?**',
        '',
        '1. **Send it -- deploys to {hostname}**"',
        '',
        '**4. Execute based on user choice:**',
        '',
        "**Option 1 (send):** build argo-it's save:",
        '',
        '```bash',
        'tree="$(GIT_INDEX_FILE="$i" git -c core.hooksPath=/dev/null write-tree)"',
        'git commit-tree -p "{checked_head}" -m "Add K8s manifests" "$tree"',
        '```',
        '',
        'Remember the commit id it prints as `{saved_head}`. Check exactly that commit:',
        '',
        '```bash',
        'python3 ' + INSTALLED + ' --commit {saved_head}',
        '```',
        '',
        "Read it as 3e reads a result. Any hit stops here with nothing sent: use 2b's stop as written, reading a hit",
        "in one of argo-it's files as one in a file argo-it generated, not in a change you already saved.",
        '',
        '```bash',
        'git push origin "{saved_head}:refs/heads/$d" || { echo "PUSH 1 FAILED"; exit 1; }',
        'git push origin "{saved_head}:refs/heads/$b" || { move; echo "PUSH 2 FAILED"; exit 1; }',
        'move',
        '```',
        '',
        'If it prints `BRANCH KEPT`, the branch here changed after the check. Tell the user:',
        '',
        '"I sent your setup to GitHub, but your branch here changed after I checked (a save, say), so I left it as it',
        'is [if your branch here still builds on what I checked and holds saves that aren\'t on GitHub yet: -- those',
        'saves are newer than what I sent, and none of them were sent]. What to do next: get the latest from GitHub',
        'into your project without sending anything (in VS Code: Pull, not Sync, which would also send your changes).',
        'If it says some files are in the way, move these setup files out of your project folder first: [each of',
        "the setup files, by name]. Then run /argo-it again: I'll check your own changes and ask before sending them.\"",
        '',
        'If it prints `SAVED ON ANOTHER BRANCH`, the project here is on another branch now. Tell the user:',
        '',
        '"I sent your setup to GitHub and saved it on [the branch the ask was shown on], but your project here is on',
        'another branch, so the setup files I made are still in your project folder as new files. What to do next:',
        'before you switch back to [the branch the ask was shown on], move these setup files out of your project',
        'folder: [each of the setup files, by name]."',
        '',
        'If it prints `INDEX BUSY`, another program was busy with the project here. Tell the user:',
        '',
        '"I sent your setup to GitHub, but another program was busy with your project here, so I left your copy here',
        "as it was. What to do next: once it's done, get the latest from GitHub into your project (in VS Code: Pull),",
        'then run /argo-it again."',
        '',
        '**If either push fails** (the block prints `PUSH 1 FAILED` or `PUSH 2 FAILED`), never say "Pushed!". First',
        'run `git ls-remote --heads origin`: if a branch line (`refs/heads/…`) other than `refs/heads/{deploy_branch}`',
        'holds `{saved_head}`, it reached GitHub anyway. Tell the user:',
        '',
        '"I couldn\'t send your setup to GitHub, so [nothing was sent / if the first one went through: only the copy',
        'the deployment system watches, `{deploy_branch}`, was set up there, and nothing else was sent]. What to do',
        'next: [the fix], then run /argo-it again."',
        '',
        '**Option 2 (local test):** nothing is saved.',
        ''))

    def test_8_control_new_text_checks_are_polarity_bound(self):  # control: passes today
        def told(*marks):
            return lambda t: self._told_all(self._sec1(t), marks)
        g = self.GOOD7
        pull = ('get the latest from GitHub\ninto your project without sending anything (in VS Code: Pull, not Sync, which '
                'would also send your changes).')
        sends = [(pull, 'get the latest from GitHub\ninto your project (in VS Code: Sync Changes).'),
                 (pull, 'get the latest from GitHub\ninto your project, then push your changes to GitHub.'),
                 (pull, 'get the latest from GitHub\ninto your project and publish your branch.'),
                 (pull, 'pull the latest from GitHub\ninto your project, then send your changes.')]
        gate = ('[if your branch here still builds on what I checked and holds saves that aren\'t on GitHub yet: -- '
                'those\nsaves are newer than what I sent, and none of them were sent]')
        checks = [
            ('_kept_next_step', lambda t: (self._sec1(t), 'BRANCH KEPT'), sends + [
                (" Then run /argo-it again: I'll check your own changes and ask before sending them.", ''),
                ('[each of\nthe setup files, by name]', 'them'),
                ('If it says some files are in the way, move these setup files out of your project folder first: [each '
                 'of\nthe setup files, by name]. ', '')]),
            ('_newer_than_sent_message', lambda t: (self._sec1(t), 'BRANCH KEPT'), sends),
            ('_kept_from_facts', told('BRANCH KEPT'), [
                ('but your branch here changed after I checked (a save, say), so',
                 'but you saved changes of your own after I checked, so'),
                (gate, '-- your copy here is newer than what I sent, and none of them were sent'),
                ("[if your branch here still builds on what I checked and holds saves that aren't on GitHub yet:",
                 '[if it changed:'),
                ('your branch here changed after I checked', 'something happened after I checked')]),
            ('_busy_told', told('INDEX BUSY'), [
                ("What to do next: once it's done, get the latest from GitHub into your project (in VS Code: Pull),\n"
                 'then run /argo-it again.', 'Sorry.'),
                ('"I sent your setup to GitHub, but another program', '"I couldn\'t finish, as another program'),
                ('so I left your copy here\nas it was.', 'so I left your commit here\nas it was.')]),
            ('_refused_move_told', told('BRANCH KEPT', 'PUSH 2 FAILED'), [
                ('but your branch here changed after I checked (a save, say), so I left it as it\nis',
                 'and that went well'),
                ('only the copy\nthe deployment system watches, `{deploy_branch}`, was set up there, and nothing else '
                 'was sent', 'something was sent')]),
            ('_deploy_line_never_counts', self._sec1, [
                ('other than `refs/heads/{deploy_branch}`\nholds', 'other than `refs/heads/{deploy_branch}` (when the '
                                                                   'first push went through)\nholds'),
                ('other than `refs/heads/{deploy_branch}`\nholds', "other than `refs/heads/{deploy_branch}` (when this "
                                                                   "run's first push went through)\nholds"),
                ('a branch line (`refs/heads/…`) other than `refs/heads/{deploy_branch}`\nholds',
                 'a branch line (`refs/heads/…`)\nholds')]),
            ('_switch_told', told('SAVED ON ANOTHER BRANCH'), [
                (', move these setup files out of your project\nfolder: [each of the setup files, by name]', ''),
                ('before you switch back to [the branch the ask was shown on], ', ''),
                ('"I sent your setup to GitHub and saved it on [the branch the ask was shown on], but',
                 '"I sent your setup to GitHub, but'),
                ('What to do next:\nbefore', 'Commit your work\nbefore')]),
            ('_rename_step_off_saved', self._prose, [
                ("`\\xNN` or `\\uXXXX`, not under `== saved, not sent ==`, 3e's next step",
                 "`\\xNN` or `\\uXXXX`, 3e's next step")]),
            ('_otherwise_pairs', self._ask_text, [
                (', and a copy is already on GitHub / otherwise: , but nothing has been sent\nyet]',
                 ', but nothing has been sent\nyet / otherwise: , and a copy is already on GitHub]'),
                ('list leaves out that earlier save:', 'list names that earlier save:')]),
            ('_saved_stop_says_why', self._prose, [
                ("[If a hit sits under `== saved, not sent ==`:\nBecause it's already in your saved history, moving the "
                 "value now wouldn't take it out of what gets sent --\nso I'm stopping here.] ", ''),
                ("[If a hit sits under `== saved, not sent ==`:\nBecause it's already in your saved history, moving the "
                 "value now wouldn't take it out of what gets sent --\nso I'm stopping here.]",
                 "Because it's already in your saved history, moving the value now wouldn't take it out of what gets "
                 "sent --\nso I'm stopping here.")]),
            ('_commit_check_reads_mine_as_mine', self._sec1, [
                (", reading a hit\nin one of argo-it's files as one in a file argo-it generated, not in a change you "
                 "already saved.", '.'),
                ('as one in a file argo-it generated, not in a change you already saved',
                 'as one in a change you already saved')]),
        ]
        for name, view, swaps in checks:
            fn = getattr(self, name)

            def check(x, fn=fn, view=view):
                v = view(x)
                return fn(*v) if isinstance(v, tuple) else fn(v)
            with self.subTest(check=name, text='plain reading'):
                check(g)
            for old, opposite in swaps:
                self.assertIn(old, g)
                with self.subTest(check=name, opposite=opposite[:60]):
                    with self.assertRaises(AssertionError):
                        check(g.replace(old, opposite))
        with self.subTest(check='_deploy_line_never_counts', text='a first-push gate with an "or it held it before"'):
            self._deploy_line_never_counts(self._sec1(g.replace(
                'other than `refs/heads/{deploy_branch}`\nholds', 'other than `refs/heads/{deploy_branch}` (when the '
                'first push went through, or when it already held `{saved_head}` before this push)\nholds')))
        with self.subTest(check='_kept_from_facts', text="the user's own newer save"):
            self._kept_from_facts(told('BRANCH KEPT')(g), own=True)


# ArgoItFirstSendFix6Cases' helpers (not its tests), for adversarial round 2 below.
_FirstSendFix6 = type('_FirstSendFix6', (object,), {k: v for k, v in ArgoItFirstSendFix6Cases.__dict__.items()
                                                    if not k.startswith(('test', '__'))})


def _alts(*rxs):
    """One pattern matching any of rxs; a leading (?i) stays scoped to its own pattern."""
    return '|'.join('(?i:%s)' % x[4:] if x.startswith('(?i)') else '(?:%s)' % x for x in rxs)


class ArgoItFirstSendAdv2Cases(_FirstSendFix6, _FirstSendFix5, _FirstSendFix4, _FirstSendFix3, _FirstSendFix2,
                               _FirstSendAdv1, _FirstSendFix1, _FirstSend, Base):
    """Task 3 adversarial round 2 (on 0859bd2) and the calls after it (2026-10-24). The owner's "read GitHub every
    time": what was sent, after every send attempt and on every re-run, comes from a read of what GitHub has -- never
    from a push's exit code or a local `origin/...` ref -- and when GitHub can't be read the user hears "I couldn't
    tell what reached GitHub" with a next step that sends nothing; a re-run after GitHub took a save whose report was
    lost says so and doesn't loop. The coordinator's save-integrity calls: argo-it's save differs from the HEAD it
    checked by exactly its own files (a config-based hook on git 2.54, a `git replace`), else it stops with nothing sent
    and says so plainly; 2b reads argo-it's files that `.gitignore` hides; the deploy branch's existence is read from
    GitHub (a single-branch shallow clone has no `origin/<branch>`). Every drive runs under bash and zsh, on each git
    this machine has (the one the suite runs with, and the default one); the text checks are proven against their plain
    opposites in test_3. Values and secret-named lines are joined at run time (GitGuardian scans this file)."""

    # "I couldn't tell what reached GitHub" (owner, 2026-10-24)
    TELL = r"(?i)\b(?:couldn't|could not|can't|cannot)\s+tell\s+what\s+(?:reached|got to|made it to)\s+GitHub\b"
    # the read of GitHub failing (`git ls-remote` fails, GitHub can't be read or reached)
    UNREAD = (r"(?i)\b(?:git\s+ls-remote|(?:the|that|this|GitHub's)\s+read|GitHub)\b[^.;\]]{0,60}?\b(?:fails?|failed"
              r"|(?:can't|cannot|couldn't|could not)\s+be\s+(?:read|reached)|unreachable"
              r"|(?:isn't|is not|wasn't|was not)\s+(?:reachable|readable))\b"
              r"|\b(?:can't|cannot|couldn't|could not)\s+(?:read|reach)\s+GitHub\b")
    NOTHING_WAS = r"(?i)\bnothing\s+(?:was|has been|got|went)\s+(?:sent|out)\b"
    READ_OK = r"(?i)\b(?:worked|succeed(?:s|ed)?|answer(?:s|ed)|could\s+be\s+read|was\s+read)\b"
    # one safe next step: look at the repo's branches on GitHub, or run /argo-it again (which reads first)
    SAFE_NEXT = r"(?i)\blook\s+at\b[^.]{0,80}?\bbranch(?:es)?\b|\brun\s+/argo-it\s+again\b"
    # a read of what GitHub has, not of a local copy of it
    GH_READ = (r"\bgit\s+ls-remote\b|(?i:\bwhat\s+GitHub\s+(?:holds|has|shows)\b|\bGitHub(?:'s)?\s+(?:read|answer)\b"
               r"|\bread(?:s|ing)?\s+(?:of\s+)?GitHub\b|\bGitHub\s+(?:holds|has|shows|lists)\b)")
    ON_GITHUB = _alts(_FirstSendFix4.COPY_SENT, _FirstSendFix3.ALREADY_SENT,
                      r"(?i)\b(?:is|are|'s|'re)\s+(?:already\s+)?on\s+GitHub\b")
    WHAT_SENT = _alts(_FirstSendFix5.SENT_YES, r'Pushed!', _FirstSendAdv1.SENT_OR_NOT, _FirstSendFix4.COPY_SENT,
                      r'(?i)\breached\s+GitHub\b')
    # a rule's scope that covers every send attempt, not only a failed one
    EVERY = (r"(?i)\b(?:after|on|for)\s+(?:every|each|any)\s+(?:send|push)(?:\s+attempt)?\b"
             r"|\bwhatever\s+the\s+(?:block|push(?:es)?)\s+print(?:s|ed)\b|\bsuccess\s+or\s+fail(?:ure)?\b"
             r"|\bwhether\s+(?:or\s+not\s+)?(?:it|the\s+push|the\s+send|a\s+push|they)\s+(?:worked|went\s+through"
             r"|succeeded|failed)\b")
    LOCAL_REF = r'(?<![\w./-])origin/|\brefs/remotes/'
    # "something added files I didn't write" (coordinator, 2026-10-24)
    ADDED = (r"(?i)\badd(?:ed|s|ing)?\b[^.]{0,80}?\bfiles?\b[^.]{0,80}?\b(?:I|argo-it)\s+(?:didn't|did not|never|don't"
             r"|do not)\s+(?:write|make|generate|create)\b|\bfiles?\s+(?:that\s+)?(?:I|argo-it)\s+(?:didn't|did not"
             r"|never)\s+(?:write|make|generate|create)\b")
    ALREADY_SAVED_CHANGE = r"(?i)\ba\s+change\s+you\s+already\s+saved\b"
    QUOTE = r'"((?:I|Pushed|Your)[^"]{20,})"'

    # --- the gits this machine has -------------------------------------------------------------------------------
    def _gits(self):
        """(version, environment) for each git the suite can reach: the one it runs with, and the default one (no
        DEVELOPER_DIR: what a fresh Bash call of an agent gets on macOS) when that is another version."""
        out = []
        for env in (dict(os.environ), {k: v for k, v in os.environ.items() if k != 'DEVELOPER_DIR'}):
            cp = subprocess.run(['git', '--version'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            v = cp.stdout.decode().strip()
            if not cp.returncode and v not in [x for x, _ in out]:
                out.append((v, env))
        return out

    @staticmethod
    def _using(env):
        """os.environ is `env` inside the block, so every git the flow and the fixture run is that one."""
        from unittest import mock
        return mock.patch.dict(os.environ, env, clear=True)

    def _cfg_hook_git(self):
        """(version, environment) of a git that runs a hook set in a repo's config (`hook.<name>.event`, git 2.54+),
        found by running one; else the test is skipped, saying why."""
        gits = self._gits()
        for v, env in gits:
            with tempfile.TemporaryDirectory() as td:
                def g(*a):
                    return subprocess.run(['git'] + list(a), cwd=td, env=env, stdout=subprocess.PIPE,
                                          stderr=subprocess.PIPE)
                g('init', '-q')
                g('config', 'hook.probe.command', 'touch probe-ran; true')
                g('config', '--add', 'hook.probe.event', 'post-index-change')
                with open(os.path.join(td, 'f'), 'w') as fh:
                    fh.write('x\n')
                g('-c', 'core.hooksPath=/dev/null', 'update-index', '--add', '--', 'f')
                if os.path.exists(os.path.join(td, 'probe-ran')):
                    return v, env
        self.skipTest('needs a git that runs hooks set in a repo\'s config (`hook.<name>.event`, git 2.54+); this '
                      'machine has only %s (on macOS, the default git -- DEVELOPER_DIR unset -- is Xcode\'s)'
                      % ', '.join(v for v, _ in gits))

    # --- fixtures --------------------------------------------------------------------------------------------------
    def _network(self, r, passes, drop):
        """origin's receive-pack as the fixture's network gives it: the first `passes` pushes go through; then 'down':
        GitHub can't be reached for the next push or after it; 'after': the next push reaches GitHub, then the
        connection drops (GitHub took it; the push reports a failure), and GitHub can't be reached after it. origin is
        moved to origin.down while it is unreachable. Returns a function that brings it back."""
        live, down = os.path.join(r.root, 'origin'), os.path.join(r.root, 'origin.down')
        script = os.path.join(r.root, 'receive-pack.sh')
        lines = ['#!/bin/sh', "c='%s'" % os.path.join(r.root, 'receive-count'),
                 'n=$(($(cat "$c" 2>/dev/null || echo 0) + 1)); echo "$n" > "$c"',
                 '[ "$n" -le %d ] && exec git receive-pack "$@"' % passes]
        if drop == 'after':
            lines.append('git receive-pack "$@"')
        lines += ["mv '%s' '%s'" % (live, down), 'exit %d' % (1 if drop == 'after' else 128)]
        with open(script, 'w') as f:
            f.write('\n'.join(lines) + '\n')
        os.chmod(script, 0o755)
        r.git('config', 'remote.origin.receivepack', script)

        def back():
            os.replace(down, live)
            r.git('config', '--unset', 'remote.origin.receivepack')
        return back

    @staticmethod
    def _refs_at(git_dir):
        out = subprocess.run(['git', '--git-dir', git_dir, 'for-each-ref', '--format=%(objectname) %(refname)'],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.decode().splitlines()
        return dict(reversed(l.split(' ', 1)) for l in out)

    def _nr(self, r, *a):
        """git here, past any `git replace`: what the objects really hold."""
        return subprocess.run(GIT + ['--no-replace-objects'] + list(a), cwd=r.work, check=True, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE).stdout.decode()

    def _shallow(self, how):
        """A `git clone --depth 1` (single-branch) of an origin whose deploy branch already exists -- at an older main
        commit, or on unrelated history -- and whose main has moved on since."""
        r = self.fresh()
        if how.startswith('at an older'):
            r.git('push', '-q', 'origin', 'main:refs/heads/' + self.DEPLOY)
        else:
            c = self._object_commit(r, None, {'deploy.txt': 'unrelated\n'})
            r.git('push', '-q', 'origin', c + ':refs/heads/' + self.DEPLOY)
        r.write('app.py', BASE + 'x = 1\n')
        r.commit('newer')
        r.push()
        shutil.rmtree(r.work)
        Repo._git(r.root, 'clone', '-q', '--depth', '1', 'file://' + os.path.join(r.root, 'origin'), 'work')
        self.assertEqual(r.git('config', '--get-all', 'remote.origin.fetch').decode().split(),
                         ['+refs/heads/main:refs/remotes/origin/main'], 'fixture: not a single-branch clone')
        return r

    # --- reading Option 1 after its push -----------------------------------------------------------------------------
    def _push_block(self, sec):
        pushes = [f for f in self._fences(sec) if self._git_does(f[2], 'push')]
        self.assertTrue(pushes, 'Option 1 has no ```bash block that pushes')
        return pushes[0]

    def _after_push(self, sec):
        """Option 1 (sec) from the end of its first block that pushes: the rules for what the send did, flattened, code
        taken out; and the same with each message to the user blanked (positions kept)."""
        prose = self._flat(re.sub(self.FENCE, ' ', sec[self._push_block(sec)[1]:], flags=re.M | re.S))
        quotes = [(m.start(), m.end(), m.group(1)) for m in re.finditer(self.QUOTE, prose)]
        masked = prose
        for a, e, _ in quotes:
            masked = masked[:a] + ' ' * (e - a) + masked[e:]
        return prose, masked, quotes

    def _github_reads(self, r, sec, st):
        """The text's reads of GitHub after the push -- each `git ls-remote ...` in Option 1's prose after its first
        block that pushes, or on a line of a block after it -- run here as written: [(command, exit code)]."""
        after = sec[self._push_block(sec)[1]:]
        cmds = [l.strip() for f in self._fences(after) for l in f[2].splitlines()
                if re.search(r'\bgit\s+ls-remote\b', l) and not l.lstrip().startswith('#')]
        cmds += re.findall(r'`(git\s+ls-remote[^`\n]*)`', re.sub(self.FENCE, ' ', after, flags=re.M | re.S))
        out = []
        for c in cmds:
            cp = subprocess.run(['bash', '-c', self._fill(c, mem=st['mem'])], cwd=r.work, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=60)
            out.append((c, cp.returncode))
        return out

    def _alt_at(self, q, k):
        """The part of message q that holds position k: inside its innermost [...], the ' / '-separated alternative
        that holds k; else its sentence."""
        a, e, br = self._part_around(q, k)
        if not br:
            return q[a:e]
        parts, depth, start = [], 0, a + 1
        for i in range(a + 1, e - 1):
            if q[i] == '[':
                depth += 1
            elif q[i] == ']':
                depth -= 1
            elif not depth and q.startswith(' / ', i):
                parts.append((start, i))
                start = i + 3
        parts.append((start, e - 1))
        return next((q[s:t] for s, t in parts if s <= k < t), q[a:e])

    # --- the text checks (each proven against its plain opposite in test_3) ------------------------------------------
    def _unreadable_told(self, sec):
        """When GitHub can't be read after a send attempt, the text says "I couldn't tell what reached GitHub" -- never
        "nothing was sent" -- with a next step that sends nothing: look at the repo's branches on GitHub, or run /argo-it
        again, which reads first (owner, after adversarial round 2)."""
        prose, masked, quotes = self._after_push(sec)
        un = [m.start() for m in re.finditer(self.UNREAD, masked) if not self._neg(masked, m.start())]
        self.assertTrue(un, "after a send attempt, nothing says what to do when GitHub can't be read (`git ls-remote` "
                            "fails): the failed-push rule's last \"Otherwise\" tells the user nothing was sent")
        for m in re.finditer(self.NOTHING_WAS, masked):
            if self._neg(masked, m.start()):
                continue
            s0 = max(masked.rfind('. ', 0, m.start()), 0)
            if re.search(self.READ_OK, masked[s0:m.start()]):
                continue
            self.assertLess(un[0], m.start(), "the text reaches \"nothing was sent\" before it handles a GitHub it can't "
                            "read: %r" % masked[s0:m.end() + 1])
        tells = [(a, q, m.start()) for a, e, q in quotes for m in re.finditer(self.TELL, q) if not self._neg(q, m.start())]
        self.assertTrue(tells, "no message says \"I couldn't tell what reached GitHub\"")
        good = []
        for a, q, k in tells:
            alt = self._alt_at(q, k)
            self.assertFalse(self._says(self.NOTHING_WAS, alt) or self._says(self.SENT_NONE, alt), "\"I couldn't tell "
                             "what reached GitHub\" is said together with \"nothing was sent\": %r" % alt)
            prev = max([e for x, e, _ in quotes if e <= a] + [0])
            linked = (any(c and re.search(self.UNREAD, c) for c in self._conds_at(q, k))
                      or re.search(self.UNREAD, masked[prev:a]))
            step = self._next_step(q)
            if linked and step and re.search(self.SAFE_NEXT, step) and not self._next_step_sends(q):
                good.append(q)
        self.assertTrue(good, "\"I couldn't tell what reached GitHub\" isn't the message for a GitHub that can't be read, "
                              "or has no next step that sends nothing (look at the repo's branches on GitHub, or run "
                              "/argo-it again): %r" % [q for _, q, _ in tells])

    def _ask_on_github(self, ask, saved_here):
        """The step-3 ask's opening, on a re-run after argo-it's save reached GitHub, says a copy is on GitHub under a
        condition that reads GitHub (`git ls-remote`), and -- unless argo-it's files are saved here (`saved_here`) --
        not only when they are: a push GitHub took whose report was lost leaves them unsaved here. Then it never opens
        with "nothing has been saved or sent yet" (owner, after adversarial round 2)."""
        op = self._units(ask)[0]
        found = []
        for m in re.finditer(self.ON_GITHUB, op):
            conds = self._conds_at(op, m.start())
            if self._neg(op, m.start()) or None in conds or not any(c and re.search(self.GH_READ, c) for c in conds):
                continue
            if saved_here or not any(c and self._says(self.FILES_SAVED, c) for c in conds):
                found.append(m.group(0))
        self.assertTrue(found, "on a re-run after GitHub took argo-it's save, the ask's opening has no \"a copy is "
                               "already on GitHub\" chosen by a read of GitHub%s, so it says \"nothing has been saved or "
                               "sent yet\": %r" % ('' if saved_here else " when argo-it's files aren't saved here", op))

    def _no_local_origin_ref(self, p):
        """PHASE 5 never decides from a local `origin/...` ref: a single-branch clone has none for the deploy branch,
        and one can be stale; GitHub is read instead (coordinator, after adversarial round 2)."""
        for f in self._fences(p):
            for l in f[2].splitlines():
                if not l.lstrip().startswith('#'):
                    self.assertNotRegex(l.split(' #')[0], self.LOCAL_REF, "PHASE 5 reads a local origin/... ref, not "
                                        "GitHub: %r" % l)
        prose = re.sub(self.FENCE, ' ', p, flags=re.M | re.S)
        for m in re.finditer(r'`([^`\n]+)`', prose):
            if re.search(self.LOCAL_REF, m.group(1)) and not re.search(
                    r"(?i)(?:\b(?:never|not|no|without|instead of|rather than)\b|n't\b)[^.;]{0,40}$", prose[:m.start()]):
                self.fail('PHASE 5 tells the agent to read a local origin/... ref, not GitHub: %r' % m.group(0))

    def _messages_from_github(self, sec):
        """Every message after Option 1's push that says what was sent ("Pushed!", "I sent your setup", "nothing was
        sent", a copy set up on GitHub) is chosen from a read of what GitHub has: its own rule reads GitHub, or one rule
        before them all, for every send attempt, does -- never a push's exit code alone (owner, after adversarial
        round 2)."""
        prose, masked, quotes = self._after_push(sec)
        sent = [x for x in quotes if re.search(self.WHAT_SENT, x[2])]
        self.assertTrue(sent, "Option 1 tells the user nothing about what was sent")
        if any(re.search(self.GH_READ, s) and re.search(self.EVERY, s) for s in self._sentences(masked[:sent[0][0]])):
            return
        prev = 0
        for a, e, q in quotes:
            if (a, e, q) in sent:
                conds = re.findall(r'\[([^\[\]:]*):', q)
                self.assertTrue(re.search(self.GH_READ, masked[prev:a]) or any(re.search(self.GH_READ, c) for c in conds),
                                "a message about what was sent is chosen without a read of GitHub (only from what the "
                                "block printed): rule %r, message %r" % (masked[prev:a].strip()[-160:], q[:100]))
            prev = e

    def _rerun_ask_from_github(self, ask):
        """Whatever the step-3 ask's opening says under a condition about a copy on GitHub, or nothing sent, it chooses
        by a read of GitHub, never step 2's list or a local ref; and it has a copy-on-GitHub opening for argo-it's files
        unsaved here (owner, after adversarial round 2: every re-run ask comes from that read)."""
        op = self._units(ask)[0]
        for rx in (self.ON_GITHUB, self.SENT_STATE):
            for m in re.finditer(rx, op):
                conds = self._conds_at(op, m.start())
                if None in conds or not any(conds):
                    continue
                self.assertTrue(any(c and re.search(self.GH_READ, c) for c in conds), "the ask says %r on a condition "
                                "that doesn't read GitHub: %r" % (m.group(0), [c for c in conds if c]))
        self._ask_on_github(ask, False)

    def _held_more_told(self, qs):
        """A save that holds more than argo-it's files stops with a message that says plainly that something added
        files argo-it didn't write and that nothing was sent -- never "a change you already saved", which isn't true
        (coordinator, after adversarial round 2)."""
        self.assertTrue(qs, "the stop for a save that holds more than argo-it's files tells the user nothing")
        self.assertTrue(any(self._says(self.ADDED, q) and re.search(self.NOTHING_SENT, q) and not re.search(self.NEVER_SAY, q)
                            for q in qs), "the user isn't told plainly that something added files argo-it didn't write, "
                                          "and that nothing was sent: %r" % qs)
        for q in qs:
            self.assertFalse(self._says(self.ALREADY_SAVED_CHANGE, q), "the stop calls a file argo-it's save took in \"a "
                             "change you already saved\": untrue: %r" % q)

    # --- what a flow must show -----------------------------------------------------------------------------------------
    def _only_argo_its_files(self, r, st, before, files, extra, v=None):
        """Nothing but argo-it's files was saved or sent, read past any `git replace`: no ref that changed on origin and
        no branch here holds `extra`. Returns 'exact' (the save is the start plus argo-it's files, and it went out) or
        'stopped' (the save held more, and a stop sent nothing and said so plainly, never "a change you already
        saved")."""
        after = self._sent_refs(r)
        changed = self._changed(before, after)
        for ref in sorted(changed):
            self.assertNotIn(extra, self._origin(r, 'ls-tree', '-r', '--name-only', after[ref]).decode().split(),
                             "%s reached GitHub's %s, and the ask never named it" % (extra, ref))
        if v:
            self.assertFalse(_b(v) in self._sent_objects(r), "%s's key reached GitHub" % extra)
        for ref, sha in self._branches(r).items():
            if sha != st['start']:
                self.assertNotIn(extra, self._nr(r, 'diff', '--name-only', st['start'], sha).split(),
                                 '%s is saved on %s here' % (extra, ref))
        held = self._nr(r, 'diff', '--name-only', st['start'], st['saved']).split() if st['saved'] else None
        if held == sorted(files):
            self.assertFalse(st['stopped'] or st['failed'], '%r %r' % (st['stopped'], st['failed']))
            self.assertEqual({after[k] for k in changed}, {st['saved']}, "what went out isn't argo-it's save")
            return 'exact'
        self.assertFalse(changed, "argo-it's save held %r, and GitHub changed: %r" % (held, sorted(changed)))
        sec = self._sec1()
        if st['saved'] and st['stopped'] == 'a hit counts':  # the check of argo-it's save stopped on the file it took in
            calls = [f for f in self._fences(sec) if 'secret-scan.py' in f[2] and re.search(self.COMMIT_PH, f[2])]
            self.assertTrue(calls, 'Option 1 has no check of the commit it sends')
            nxt = [f[0] for f in self._fences(sec) if f[0] > calls[-1][0]]
            qs = re.findall(r'"(I[^"]{20,})"', self._flat(sec[calls[-1][1]:nxt[0] if nxt else len(sec)]))
            self.assertTrue(qs, "argo-it's save took in %s, and the check of that save stops on it in 2b's words: \"a "
                                "change you already saved\" -- untrue" % extra)
        else:  # a stop at the save itself (it printed a line, and no id) or after it: a rule's words
            self.assertTrue(st['failed'], "argo-it's save held %r, and no rule says so: %r" % (held, st['stopped']))
            qs = self._told(sec, st['failed'])
        self._held_more_told(qs)
        return 'stopped'

    # --- 1. read GitHub every time (owner) ------------------------------------------------------------------------------
    def test_1a_when_github_cant_be_read_after_push_1_went_through_the_user_hears_so_never_nothing_was_sent(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    with self.subTest(git=v, shell=shell):
                        r = self.fresh()  # no deploy branch on GitHub yet: push 1 sets it up
                        files = self._gen(r)
                        self._network(r, 1, 'down')
                        st = self._flow(r, shell, files)
                        down = self._refs_at(os.path.join(r.root, 'origin.down'))
                        self.assertEqual(down.get('refs/heads/' + self.DEPLOY), st['saved'], 'fixture: push 1 did not '
                                         'go through: %r %r' % (st['stopped'], st['failed']))
                        self.assertNotEqual(down.get('refs/heads/main'), st['saved'], 'fixture: push 2 went through')
                        self.assertTrue(st['failed'], 'push 2 failed, and the user hears "Pushed!"')
                        reads = self._github_reads(r, self._sec1(), st)
                        self.assertTrue(reads, 'Option 1 never reads GitHub after the send')
                        self.assertFalse([c for c, rc in reads if not rc], 'fixture: a read of GitHub worked while it '
                                         'was down: %r' % reads)
        with self.subTest(what='text'):
            self._unreadable_told(self._sec1())

    def test_1b_after_github_took_the_save_and_the_connection_dropped_the_rerun_says_so_and_does_not_loop(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    with self.subTest(git=v, shell=shell):
                        r = self.fresh()
                        r.git('push', '-q', 'origin', 'main:refs/heads/' + self.DEPLOY)  # the deploy copy is there
                        files = self._gen(r)
                        back = self._network(r, 0, 'after')
                        first = self._flow(r, shell, files)
                        down = self._refs_at(os.path.join(r.root, 'origin.down'))
                        self.assertEqual(down.get('refs/heads/main'), first['saved'], 'fixture: GitHub did not take '
                                         'the save: %r %r' % (first['stopped'], first['failed']))
                        self.assertTrue(first['failed'], 'fixture: the push did not report a failure')
                        back()
                        time.sleep(1.1)  # a save built on the re-run gets a new id, as it would on a later day
                        held = self._sent_refs(r)
                        st = self._flow(r, shell, files)  # /argo-it again, Send it, with the connection back
                        with self.subTest(what='no loop'):
                            refused = [e for e in st['trace'] if e[0] == 'push' and e[1]]
                            self.assertFalse(refused or st['stopped'], 'the re-run sends a new save and GitHub refuses '
                                             'it, so the user hears "nothing was sent" on every re-run: %r %r %r'
                                             % (refused, st['stopped'], st['failed']))
                            names = self._origin(r, 'ls-tree', '-r', '--name-only', 'refs/heads/main').decode().split()
                            self.assertTrue(set(files) <= set(names), "argo-it's files are gone from GitHub's main")
                            self.assertEqual(self._sent_refs(r).get('refs/heads/' + self.DEPLOY),
                                             held.get('refs/heads/' + self.DEPLOY), 'the deploy copy changed')
                        with self.subTest(what='the re-run says the save is on GitHub'):
                            if st['ask'] is None:
                                self.assertTrue(st['failed'], 'the re-run stopped before the ask: %r' % st['stopped'])
                                qs = self._told(self._phase(), st['failed'])
                                self.assertTrue(any(self._says(self.ON_GITHUB, q) for q in qs), "the re-run doesn't say "
                                                "argo-it's save is already on GitHub: %r" % qs)
                            else:
                                status = st['ask']['status'].splitlines()
                                self._ask_on_github(self._ask_text(self._phase()),
                                                    not [l for l in status if l[3:] in files])

    def test_1c_every_message_about_what_was_sent_and_every_rerun_ask_comes_from_a_read_of_github(self):
        p = self._phase()
        with self.subTest(what='no decision from a local origin/... ref'):
            self._no_local_origin_ref(p)
        with self.subTest(what='the messages after the send'):
            self._messages_from_github(self._sec1(p))
        with self.subTest(what='the re-run ask'):
            self._rerun_ask_from_github(self._ask_text(p))

    # --- 2. save integrity (coordinator) --------------------------------------------------------------------------------
    def test_2a_a_config_based_hook_on_git_2_54_never_gets_a_file_the_ask_didnt_name_saved_or_sent(self):
        v, env = self._cfg_hook_git()
        with self._using(env):
            for shell in ('bash', 'zsh'):
                for extra in ('clean', 'holding a key'):
                    with self.subTest(git=v, shell=shell, extra_file=extra):
                        k = fake('cfghook' + shell + extra[:4])
                        r = self.fresh()
                        r.write('extra.py', kv('API_' + 'KEY', k) if extra != 'clean' else 'debug = True\n')  # unsaved
                        r.git('config', 'hook.stager.command', 'git add -- extra.py; true')
                        r.git('config', '--add', 'hook.stager.event', 'post-index-change')
                        files = self._gen(r)
                        before = self._sent_refs(r)
                        st = self._flow(r, shell, files)
                        self._only_argo_its_files(r, st, before, files, 'extra.py', k)

    def test_2b_a_git_replace_of_the_checked_commit_never_changes_what_is_saved_or_sent(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    with self.subTest(git=v, shell=shell):
                        r = self.fresh()
                        head = self._head(r)
                        tree = r.git('rev-parse', self._object_commit(r, head, {'other.py': 'other = 1\n'})
                                     + '^{tree}').strip().decode()
                        parent = r.git('rev-parse', head + '^').strip().decode()
                        r.git('replace', head, r.git('commit-tree', '-p', parent, '-m', 'app, amended',
                                                     tree).strip().decode())
                        files = self._gen(r)
                        before = self._sent_refs(r)
                        st = self._flow(r, shell, files)
                        self.assertEqual(self._only_argo_its_files(r, st, before, files, 'other.py'), 'exact',
                                         "argo-it's save wasn't built on the commit it checked")

    def test_2c_a_key_in_argo_its_file_that_gitignore_hides_stops_2b_before_the_ask(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    with self.subTest(git=v, shell=shell):
                        k = fake('ignoredenv' + shell)
                        r = self.fresh()
                        r.write('.gitignore', 'env/\n')  # GitHub's Python template; `env` is argo-it's manifest_dir
                        r.commit('ignore env')
                        r.push()
                        files = self._gen(r, extra=self._keyed(k))
                        st = self._flow(r, shell, files)
                        self.assertFalse(_b(k) in self._sent_objects(r), 'the key reached GitHub')
                        self.assertIsNone(st['ask'], "2b didn't read %s, which `.gitignore` hides, so the step-3 ask "
                                          "was shown over a key in it" % self.REL)
                        self.assertEqual(st['stopped'], 'a hit counts')
                        self.assertIn(self.REL + ':4', st['results'][0].lines)
                        self.no_leak(st['results'][0], [k])

    def test_2d_in_a_single_branch_shallow_clone_the_deploy_branch_is_read_from_github_and_the_send_doesnt_loop(self):
        p = self._phase()
        pre = {f[2] for f in self._fences(p) if f[0] < self._ask_at(p)}
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    for how in ('at an older main commit', 'on unrelated history'):
                        with self.subTest(git=v, shell=shell, deploy_branch=how):
                            r = self._shallow(how)
                            deploy = self._ref(r, self.DEPLOY)
                            files = self._gen(r)
                            st = self._flow(r, shell, files)
                            self.assertIsNotNone(st['ask'], 'the flow stopped before the ask: %r' % st['stopped'])
                            seen = ' '.join([cp.stdout.decode() for code, cp in st['outputs'] if code in pre]
                                            + list(st['mem'].values()))
                            self.assertIn(deploy, seen, "step 2 doesn't see the deploy branch GitHub already holds (this "
                                          "clone has no origin/%s), so the ask says \"I'll also set up %s\"" %
                                          (self.DEPLOY, self.DEPLOY))
                            self.assertFalse(st['stopped'] or st['failed'], 'the send ended with %r %r, and every re-run '
                                             'takes the same path' % (st['stopped'], st['failed']))
                            self.assertEqual(self._ref(r, 'main'), st['saved'], "GitHub's main isn't argo-it's save")
                            self.assertEqual(self._ref(r, self.DEPLOY), deploy, "the deploy branch on GitHub changed")

    # --- 3. polarity: each new text check passes a plain reading and fails its plain opposite ----------------------------
    GOOD8 = '\n'.join((
        '**2. Check whether the deploy branch exists.**',
        '',
        '```bash',
        'git fetch --prune origin || { echo "FETCH FAILED"; exit 1; }',
        'd="$(cat "$(git rev-parse --git-dir)/argo-it-deploy-branch")"',
        'git ls-remote --heads origin "refs/heads/$d"   # GitHub\'s own answer: the deploy branch\'s line, or none',
        'git log --oneline HEAD --not --remotes=origin',
        '```',
        '',
        '**3. Ask the user what they want to do:**',
        '',
        "\"I've generated your deployment pipeline -- the files are in your project folder, and nothing has been saved",
        "or sent yet [if `git ls-remote origin` shows a branch holding argo-it's files as they are here, in place of",
        "that: a copy is already on GitHub from last time [if argo-it's files are already saved here: , and saved here",
        "too]]. Here's what's ready:",
        '',
        '**What would you like to do?**',
        '',
        '1. **Send it -- deploys to {hostname}**"',
        '',
        '**4. Execute based on user choice:**',
        '',
        "**Option 1 (send):** build argo-it's save, then check that it differs from the HEAD it checked by exactly",
        "argo-it's files:",
        '',
        '```bash',
        's="$(git --no-replace-objects commit-tree -p "{checked_head}" -m "Add K8s manifests" "$tree")"',
        '[ "$(git --no-replace-objects diff --name-only "{checked_head}" "$s")" = "$want" ] || { echo "SAVE HOLDS MORE"; '
        'exit 3; }',
        'echo "$s"',
        '```',
        '',
        'If it prints `SAVE HOLDS MORE`, stop -- nothing was sent. Tell the user:',
        '',
        "\"I stopped before sending anything: something on this computer added files I didn't write to the setup I was",
        "saving, so I haven't sent anything. What to do next: ask your DevOps team which setting adds files when git",
        'saves, then run /argo-it again."',
        '',
        'Otherwise remember the commit id it prints as `{saved_head}`, and send it:',
        '',
        '```bash',
        'git push origin "{saved_head}:refs/heads/$b" || echo "PUSH 2 FAILED"',
        '```',
        '',
        '**After the send, whatever the block printed,** first run `git ls-remote --heads origin`: every message about',
        "what was sent comes from what it shows. If it fails (GitHub can't be reached), tell the user:",
        '',
        "\"I couldn't tell what reached GitHub: I couldn't reach it just now. What to do next: look at your project's",
        'branches on GitHub, or run /argo-it again -- it reads GitHub first."',
        '',
        'Otherwise, if a branch line other than `refs/heads/{deploy_branch}` holds `{saved_head}`, tell the user:',
        '',
        '"Pushed! Here\'s what happens next: CI is building your container images now."',
        '',
        'Otherwise, nothing was sent. Tell the user:',
        '',
        "\"I couldn't send your setup to GitHub, so nothing was sent and nothing is deploying. What to do next: [the",
        'fix], then run /argo-it again."',
        '',
        '**Option 2 (local test):** nothing is saved.',
        ''))

    def test_3_control_new_text_checks_are_polarity_bound(self):  # control: passes today
        g = self.GOOD8
        gh_bracket = ("[if `git ls-remote origin` shows a branch holding argo-it's files as they are here, in place of\n"
                      "that: a copy is already on GitHub from last time [if argo-it's files are already saved here: , "
                      "and saved here\ntoo]]")
        under_saved = ("[if argo-it's files are already saved here, in place of that: they're saved from last time [if "
                       "`git ls-remote origin` shows a branch holding them: , and a copy is already on GitHub]]")
        from_list = ("[if argo-it's files are already saved here, in place of that: they're saved from last time [if step "
                     "2's list leaves out that earlier save: , and a copy is already on GitHub / otherwise: , but nothing "
                     "has been sent yet]]")
        tell = "I couldn't tell what reached GitHub: I couldn't reach it just now."
        stopped = ("I stopped before sending anything: something on this computer added files I didn't write to the setup I "
                   "was\nsaving, so I haven't sent anything.")
        checks = [
            ('_unreadable_told', self._sec1, [
                ("If it fails (GitHub can't be reached), tell the user:", 'Tell the user:'),
                (tell, "I couldn't send your setup to GitHub, so nothing was sent."),
                (tell, "I couldn't tell what reached GitHub, so nothing was sent."),
                ("look at your project's\nbranches on GitHub, or run /argo-it again -- it reads GitHub first.",
                 'push your setup\nagain from VS Code.'),
                ('**After the send, whatever the block printed,**', 'Otherwise, nothing was sent. **After the send,**')]),
            ('_ask_on_github', lambda t: (self._ask_text(t), False), [
                ("if `git ls-remote origin` shows a branch holding argo-it's files as they are here, in place of\nthat:",
                 "if step 2's list leaves out argo-it's earlier save, in place of\nthat:"),
                (gh_bracket, under_saved)]),
            ('_no_local_origin_ref', lambda t: t, [
                ('git ls-remote --heads origin "refs/heads/$d"', 'git rev-parse --verify "origin/$d"')]),
            ('_messages_from_github', self._sec1, [
                ('**After the send, whatever the block printed,**', '**If the push fails,**'),
                ('whatever the block printed', 'if every push worked')]),
            ('_rerun_ask_from_github', self._ask_text, [(gh_bracket, from_list), (gh_bracket, under_saved)]),
            ('_held_more_told', lambda t: self._told(self._sec1(t), 'SAVE HOLDS MORE'), [
                ("something on this computer added files I didn't write to the setup I was\nsaving, so ", ''),
                (stopped, "I stopped: the one in extra.py is in a change you already saved but haven't sent yet, so I "
                 "haven't sent anything."),
                (stopped, "I stopped before sending anything: something on this computer added files I didn't write, in "
                 "a change you already saved, so I haven't sent anything.")]),
        ]
        for name, view, swaps in checks:
            fn = getattr(self, name)

            def check(x, fn=fn, view=view):
                v = view(x)
                return fn(*v) if isinstance(v, tuple) else fn(v)
            with self.subTest(check=name, text='plain reading'):
                check(g)
            for old, opposite in swaps:
                self.assertIn(old, g)
                with self.subTest(check=name, opposite=opposite[:60]):
                    with self.assertRaises(AssertionError):
                        check(g.replace(old, opposite))
        with self.subTest(check='_ask_on_github', text="the copy-on-GitHub half under \"saved here\", for files saved"):
            self._ask_on_github(self._ask_text(g.replace(gh_bracket, under_saved)), True)


# ArgoItFirstSendAdv2Cases' helpers (not its tests), for fix round 7 below.
_FirstSendAdv2 = type('_FirstSendAdv2', (object,), {k: v for k, v in ArgoItFirstSendAdv2Cases.__dict__.items()
                                                    if not k.startswith(('test', '__'))})


class ArgoItFirstSendFix7Cases(_FirstSendAdv2, _FirstSendFix6, _FirstSendFix5, _FirstSendFix4, _FirstSendFix3,
                               _FirstSendFix2, _FirstSendAdv1, _FirstSendFix1, _FirstSend, Base):
    """Task 3 re-review 9 (on ba69085) and the coordinator's calls after it (fix round 7): a failed read of GitHub is
    never "no such branch" -- the block prints its FETCH FAILED label and pushes nothing, so the existing deploy branch
    is never moved -- and a branch counts only by its exact name, never one that merely ends in it; the ask's "holds
    argo-it's files as they are here" is one tree, the one step 2 prints as `tree <id>` and the save holds, compared
    with each GitHub line's own tree; a failed read at a re-run's start, with argo-it's files saved here, says "I
    couldn't tell what reached GitHub" and never "I haven't saved or sent anything". Every drive runs under bash and
    zsh, on each git this machine has; the text checks are proven against their plain opposites in test_4. Values and
    secret-named lines are joined at run time (GitGuardian scans this file)."""

    # the condition of the ask's copy-on-GitHub half (call 2): step 2's printed tree, each line's own tree, compared
    STEP2_TREE = r"(?i)\bstep\s+2\b[^\]]{0,80}?\btree\b|\btree\b[^\]]{0,80}?\bstep\s+2\b"
    LINE_TREE = r'\brev-parse\b[^\]]{0,80}?(?:\^\{tree\}|:["`\s])'
    EQUALS = r"(?i)\bequals?\b|\bthe\s+same\s+as\b|\bmatch(?:es)?\b"
    # a reading by names or by `git diff`, which calls an older copy, or one an untracked change differs from, "a copy"
    BY_NAME = r"(?i)\bls-tree\b|\bgit\s+diff\b|\bsame\s+(?:file\s+)?names?\b|\bby\s+(?:its\s+|their\s+)?names?\b"
    # what a stop says about saves: "I haven't saved ...", and the setup files saved here
    HAVENT_SAVED = (r"(?i)\bhaven't\s+saved\b|\bnothing\s+(?:has\s+been|is|was|'s\s+been)\s+saved\b"
                    r"|\bnothing\s+(?:has\s+been\s+)?saved\s+or\s+sent\b")
    SAVED_HERE = (r"(?i)\bsaved\b[^.\]]{0,60}?\b(?:here|on\s+this\s+computer)\b"
                  r"|\b(?:here|on\s+this\s+computer)\b[^.\]]{0,40}?\bsaved\b")
    NOT_SAVED_HERE = _FirstSendFix2.NOT_SAVED + r"|\bno\b[^:\]]{0,30}\bsaves?\b|\bnone\b"

    # --- fixtures --------------------------------------------------------------------------------------------------
    def _save_tree(self, r, files):
        """The tree argo-it's save holds, built here: HEAD's own tree (past any `git replace`) plus argo-it's files as
        they are on disk, in a temporary index; no commit."""
        with tempfile.TemporaryDirectory() as td:
            env = dict(os.environ, GIT_INDEX_FILE=os.path.join(td, 'index'))

            def g(*a):
                return subprocess.run(GIT + ['--no-replace-objects', '-c', 'core.hooksPath=/dev/null'] + list(a),
                                      cwd=r.work, env=env, check=True, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE).stdout.decode().strip()
            g('read-tree', 'HEAD')
            g('update-index', '--add', '--', *files)
            return g('write-tree')

    def _before_the_ask(self, st):
        """What PHASE 5's blocks before the step-3 ask printed (step 2's, 2b's), in order."""
        p = self._phase()
        pre = {f[2] for f in self._fences(p) if f[0] < self._ask_at(p)}
        return '\n'.join(cp.stdout.decode() for code, cp in st['outputs'] if code in pre)

    def _when_saved_here(self, q, k):
        """Whether the words at position k of message q are said when argo-it's files are saved here: no condition
        around them; or the innermost one says the files are saved (an "otherwise" half: says they aren't)."""
        conds = self._conds_at(q, k)
        if None in conds:
            return False
        inner = next((c for c in conds if c), None)
        if inner is None:
            return True
        if re.match(r'(?i)\s*otherwise\b', self._alt_at(q, k)):
            return bool(re.search(self.NOT_SAVED_HERE, inner)) and not self._says(self.FILES_SAVED, inner)
        return self._says(self.FILES_SAVED, inner)

    # --- the text checks (each proven against its plain opposite in test_4) ------------------------------------------
    def _tree_decides(self, ask):
        """The ask's copy-on-GitHub half for argo-it's files unsaved here is chosen by one tree: step 2's printed
        `tree <id>` compared with each GitHub line's own tree (`git --no-replace-objects rev-parse -q --verify
        <line id>^{tree}`), never by names or a `git diff`, which read an older copy, or one an untracked change here
        differs from, as "as they are here" (coordinator, fix round 7, call 2)."""
        op = self._units(ask)[0]
        found = []
        for m in re.finditer(self.ON_GITHUB, op):
            conds = self._conds_at(op, m.start())
            if self._neg(op, m.start()) or None in conds or any(c and self._says(self.FILES_SAVED, c) for c in conds):
                continue
            found.append(' '.join(c for c in conds if c))
        self.assertTrue(found, "the ask's opening has no copy-on-GitHub half for argo-it's files unsaved here: %r" % op)
        for cs in found:
            for rx, what in ((self.STEP2_TREE, "step 2's printed `tree <id>`"),
                             (self.LINE_TREE, "each line's own tree (`rev-parse ... <line id>^{tree}`)"),
                             (self.EQUALS, 'that the two are equal')):
                self.assertRegex(cs, rx, "the ask's \"as they are here\" isn't decided by one tree: its condition "
                                 "doesn't name %s: %r" % (what, cs))
            self.assertNotRegex(cs, self.BY_NAME, "the ask's \"as they are here\" is read by names or a diff: %r" % cs)

    def _read_fail_told(self, qs):
        """A stop on a failed read of GitHub, with argo-it's files saved here, says "I couldn't tell what reached
        GitHub", says what is saved on this computer, gives a next step that sends nothing, and never says "I haven't
        saved ..." (coordinator, fix round 7, call 3)."""
        self.assertTrue(qs, 'the stop on a failed read of GitHub tells the user nothing')
        for q in qs:
            for m in re.finditer(self.HAVENT_SAVED, q):
                self.assertFalse(self._when_saved_here(q, m.start()), "the stop says %r when argo-it's files are saved "
                                 "on this computer: %r" % (m.group(0), q))
        told = [q for q in qs for m in re.finditer(self.TELL, q)
                if not self._neg(q, m.start()) and self._when_saved_here(q, m.start())]
        self.assertTrue(told, "the stop on a failed read of GitHub doesn't say \"I couldn't tell what reached GitHub\": "
                              "%r" % qs)
        self.assertTrue(any(self._when_saved_here(q, m.start()) for q in qs for m in re.finditer(self.SAVED_HERE, q)
                            if not re.search(self.SAVED_NEG, q[:m.start()])),
                        "the stop doesn't say plainly that argo-it's files are saved on this computer: %r" % qs)
        self.assertTrue(any(self._next_step(q) and re.search(self.SAFE_NEXT, self._next_step(q))
                            and not self._next_step_sends(q) for q in told),
                        "the stop has no next step that sends nothing (look at the branches on GitHub, or run /argo-it "
                        "again): %r" % told)

    # --- 1. a failed read is never "no such branch"; a branch counts by its exact name (call 1) ---------------------
    def test_1a_a_github_read_that_fails_after_step_2_never_moves_the_deploy_branch_and_prints_fetch_failed(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    for when, said in (('between', 'while the ask waits'), ('before_push', 'right before the push')):
                        with self.subTest(git=v, shell=shell, read_fails=said):
                            r = self.fresh()
                            r.git('push', '-q', 'origin', 'HEAD~1:refs/heads/' + self.DEPLOY)  # at an ancestor of main
                            files = self._gen(r)
                            before = self._sent_refs(r)

                            def unreadable(r=r):  # reads of GitHub fail from here on; a push still works
                                r.git('config', 'remote.origin.uploadpack', 'false')
                            st = self._flow(r, shell, files, **{when: unreadable})
                            self.assertIsNotNone(st['ask'], 'fixture: the flow stopped before the ask: %r'
                                                 % st['stopped'])
                            self.assertNotEqual(subprocess.run(GIT + ['ls-remote', '--heads', 'origin'], cwd=r.work,
                                                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                                                .returncode, 0, 'fixture: GitHub can still be read')
                            self.assertEqual(self._sent_refs(r), before, "a read of GitHub failed, and the block read it "
                                             "as \"no deploy branch\" and pushed: %r %r" % (st['stopped'], st['failed']))
                            t = st['trace'][st['trace'].index(('pick', 1)):]
                            self.assertIn('FETCH FAILED', [e[1] for e in t if e[0] == 'printed'], "a read of GitHub "
                                          "failed after step 2, and no block printed FETCH FAILED: %r" % t)

    def test_1b_a_branch_whose_name_only_ends_in_the_deploy_branchs_name_is_not_the_deploy_branch(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    with self.subTest(git=v, shell=shell):
                        r = self.fresh()
                        r.git('push', '-q', 'origin', 'HEAD~1:refs/heads/x/refs/heads/' + self.DEPLOY)
                        files = self._gen(r)
                        before = self._sent_refs(r)
                        st = self._flow(r, shell, files)
                        self.assertEqual(self._ref(r, self.DEPLOY), st['saved'], "GitHub's x/refs/heads/%s was read "
                                         "as the deploy branch, so %s was never set up" % (self.DEPLOY, self.DEPLOY))
                        self.assertFalse(st['stopped'] or st['failed'], '%r %r' % (st['stopped'], st['failed']))
                        self._sent_exactly_the_checked_commit(r, st, before, files)

    # --- 2. "as they are here" is one tree (call 2) -------------------------------------------------------------------
    def test_2_as_they_are_here_is_the_one_tree_step_2_prints_and_the_save_holds(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    for case in ('as they are here', 'one file changed here since, unsaved',
                                 'an older copy with the same names'):
                        with self.subTest(git=v, shell=shell, github_copy=case):
                            r = self.fresh()
                            files = self._gen(r)
                            if case.startswith('an older'):
                                copy = {f: '# older\n' + t for f, t in self.GENERATED.items()}
                            else:
                                copy = dict(self.GENERATED)
                            sha = self._object_commit(r, self._head(r), copy)
                            r.git('push', '-q', 'origin', sha + ':refs/heads/setup-copy')  # a copy from an earlier run
                            if case.startswith('one file'):
                                r.append('ONBOARDING-K8S.md', 'A note of my own.\n')
                            want = self._save_tree(r, files)
                            self.assertEqual(r.git('rev-parse', sha + '^{tree}').strip().decode() == want,
                                             case == 'as they are here', 'fixture')
                            st = self._flow(r, shell, files)
                            printed = re.findall(r'(?m)^tree ([0-9a-f]{40,64})$', self._before_the_ask(st))
                            self.assertEqual(printed, [want], "step 2 doesn't print the save's tree as `tree <id>`, so "
                                             "the ask has nothing to compare each GitHub line's tree with")
                            self.assertTrue(st['saved'], 'the flow never saved: %r %r' % (st['stopped'], st['failed']))
                            self.assertEqual(r.git('rev-parse', st['saved'] + '^{tree}').strip().decode(), want,
                                             "the save doesn't hold the tree step 2 printed")
        with self.subTest(what='text'):
            self._tree_decides(self._ask_text(self._phase()))

    # --- 3. a failed read at a re-run's start (call 3) ----------------------------------------------------------------
    def test_3_a_failed_read_at_a_reruns_start_with_argo_its_files_saved_here_is_told_truly(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    with self.subTest(git=v, shell=shell):
                        r = self.fresh()
                        files = self._gen(r)
                        self._refuse(r, 'refs/heads/main')
                        first = self._flow(r, shell, files)  # push 1 sets up the deploy branch; push 2 is refused
                        self.assertTrue(first['failed'] and self._ref(r, self.DEPLOY) == first['saved'],
                                        'fixture: %r %r' % (first['stopped'], first['failed']))
                        self.assertEqual(r.git('status', '--porcelain', '--', *files).decode(), '', "fixture: argo-it's "
                                         "files aren't saved here")
                        self.assertEqual(sorted(r.git('ls-files', '--', *files).decode().split()), files, 'fixture')
                        r.git('config', 'remote.origin.uploadpack', 'false')  # GitHub can't be read on the re-run
                        before = self._sent_refs(r)
                        st = self._flow(r, shell, files)
                        self.assertIsNone(st['ask'], 'GitHub could not be read, and the ask was shown')
                        self.assertEqual(self._sent_refs(r), before, 'GitHub changed')
                        self.assertTrue(st['failed'], 'no rule for a failed read at the start: %r' % st['stopped'])
                        self._read_fail_told(self._told(self._phase(), st['failed']))

    # --- 4. polarity: each new text check passes a plain reading and fails its plain opposite ----------------------------
    GOOD9 = '\n'.join((
        '**2. Check whether the deploy branch exists.**',
        '',
        '```bash',
        'git fetch --prune origin || { echo "FETCH FAILED"; exit 1; }',
        'git ls-remote --heads origin || { echo "FETCH FAILED"; exit 1; }',
        '```',
        '',
        "If the block prints `FETCH FAILED`, stop -- don't show the step-3 ask; nothing is sent. Tell the user:",
        '',
        "\"I couldn't tell what reached GitHub: I couldn't reach it just now. [if argo-it's files are already saved",
        'here (`git ls-files` lists them, unchanged): The setup files I made are saved on this computer, and nothing',
        "more was sent. / otherwise: I haven't saved or sent anything.] What to do next: run /argo-it again once",
        'GitHub can be reached -- it reads GitHub first."',
        '',
        '**3. Ask the user what they want to do:**',
        '',
        "\"I've generated your deployment pipeline -- the files are in your project folder, and nothing has been saved",
        'or sent yet [if a branch line step 2 printed has a commit whose tree',
        '(`git --no-replace-objects rev-parse -q --verify <line id>^{tree}`) equals the `tree <id>` step 2 printed,',
        "and argo-it's files aren't saved here, in place of that: a copy of them is already on GitHub from last time,",
        "but they aren't saved here yet]. Here's what's ready:",
        '',
        '**What would you like to do?**',
        '',
        '1. **Send it -- deploys to {hostname}**"',
        '',
        '**4. Execute based on user choice:**',
        ''))

    def test_4_control_new_text_checks_are_polarity_bound(self):  # control: passes today
        g = self.GOOD9
        cond = ('if a branch line step 2 printed has a commit whose tree\n(`git --no-replace-objects rev-parse -q --verify '
                '<line id>^{tree}`) equals the `tree <id>` step 2 printed,')
        alts = ("The setup files I made are saved on this computer, and nothing\nmore was sent. / otherwise: I haven't "
                "saved or sent anything.")
        checks = [
            ('_tree_decides', self._ask_text, [
                (cond, "if `git ls-remote --heads origin` shows any branch line whose commit holds argo-it's files as "
                       "they are here,"),
                (cond, "if a branch line step 2 printed has a commit whose files have the same names as argo-it's "
                       "(`git ls-tree --name-only <line id>`) and the `tree <id>` step 2 printed,"),
                (cond, "if a branch line step 2 printed has a commit for which `git diff --quiet <line id> -- "
                       "{generated_files}` finds no change from the `tree <id>` step 2 printed,"),
                (cond, cond[:-1] + " -- or, when its tree can't be read, whose file names (`git ls-tree --name-only "
                                   "<line id>`) are the same names,")]),
            ('_read_fail_told', lambda t: self._told(t, 'FETCH FAILED'), [
                ("I couldn't tell what reached GitHub: I couldn't reach it just now.", "I couldn't reach GitHub just now."),
                (alts, "I haven't saved or sent anything. / otherwise: The setup files I made are saved on this "
                       "computer, and nothing\nmore was sent."),
                ("[if argo-it's files are already saved\nhere (`git ls-files` lists them, unchanged): " + alts + ']',
                 "I haven't saved or sent anything."),
                ('The setup files I made are saved on this computer, and nothing\nmore was sent.',
                 'Nothing more was sent.'),
                ('run /argo-it again once\nGitHub can be reached -- it reads GitHub first.',
                 'push your setup again\nfrom VS Code.')]),
        ]
        for name, view, swaps in checks:
            fn = getattr(self, name)
            with self.subTest(check=name, text='plain reading'):
                fn(view(g))
            for old, opposite in swaps:
                self.assertIn(old, g)
                with self.subTest(check=name, opposite=opposite[:60]):
                    with self.assertRaises(AssertionError):
                        fn(view(g.replace(old, opposite)))


# ArgoItFirstSendFix7Cases' helpers (not its tests), for the owner's calls on adversarial round 3 below.
_FirstSendFix7 = type('_FirstSendFix7', (object,), {k: v for k, v in ArgoItFirstSendFix7Cases.__dict__.items()
                                                    if not k.startswith(('test', '__'))})


class ArgoItFirstSendAdv3Cases(_FirstSendFix7, _FirstSendAdv2, _FirstSendFix6, _FirstSendFix5, _FirstSendFix4,
                               _FirstSendFix3, _FirstSendFix2, _FirstSendAdv1, _FirstSendFix1, _FirstSend, Base):
    """Task 3 adversarial round 3 (on 72abf4f) and the owner's calls after it. Call A, "fetch all from GitHub": what is
    already on GitHub is read in full -- every branch and tag GitHub has, into argo-it's own ref names only, with exact
    reachability in a shallow clone -- so a branch the user already sent from a single-branch or `--depth 1` clone, and
    a commit GitHub has only through a tag, count as sent; the user's own branches, remote-tracking refs and tags are
    never touched; a failed fetch is FETCH FAILED with nothing saved or sent. Call B, "refuse a split origin": a push
    address that differs from the fetch address stops PHASE 5 before any read or ask, with nothing saved or sent on
    either repo and a plain message with a next step; a remote with no separate push address isn't refused. Every drive
    runs under bash and zsh, on each git this machine has; the text check is proven against its plain opposites in
    test_3. Values and secret-named lines are joined at run time (GitGuardian scans this file)."""

    SAME_PLACE = r"(?i)\bsame\s+(?:place|address)\b"
    # the owner's next step: ask whoever set up the fork, or remove the separate push (sending) address; "push address"
    # is the owner's own words for it, so it isn't read as a NEVER-say word or as a send there
    SPLIT_NEXT = (r"(?i)\bwhoever\s+set\s+(?:it\s+|this\s+|the\s+\w+\s+)?up\b|\bfork\b"
                  r"|\bremove\b[^.]{0,60}?\b(?:push|sending|send|second|separate|other)\s+address\b")
    ADDRESS_WORDS = r"(?i)\b(?:push|sending|send)\s+address(?:es)?\b"

    # --- fixtures --------------------------------------------------------------------------------------------------
    def _clone(self, r, *opts):
        """The work repo, cloned again from origin with `opts` (a `file://` URL, so `--depth` holds)."""
        shutil.rmtree(r.work)
        Repo._git(r.root, 'clone', '-q', *opts, 'file://' + os.path.join(r.root, 'origin'), 'work')

    def _mine(self, r):
        """The user's own refs here: branches, remote-tracking refs and tags, {ref: id}."""
        out = r.git('for-each-ref', '--format=%(objectname) %(refname)', 'refs/heads', 'refs/remotes', 'refs/tags')
        return dict(reversed(l.split(' ', 1)) for l in out.decode().splitlines())

    def _bare_state(self, git_dir):
        """A bare repo's refs and every object it holds."""
        def g(*a):
            return subprocess.run(['git', '--git-dir', git_dir] + list(a), stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE).stdout
        return g('for-each-ref'), g('cat-file', '--batch-all-objects', '--batch-check')

    def _read_log(self, r):
        """Every read of origin (its upload-pack: a fetch or an ls-remote) adds a line to the returned log."""
        log, script = os.path.join(r.root, 'reads.log'), os.path.join(r.root, 'upload-pack.sh')
        with open(script, 'w') as f:
            f.write("#!/bin/sh\necho read >> '%s'\nexec git upload-pack \"$@\"\n" % log)
        os.chmod(script, 0o755)
        r.git('config', 'remote.origin.uploadpack', script)
        return log

    def _saved_hits(self, res):
        return res.lines[res.lines.index(L_SAVED) + 1:] if L_SAVED in res.lines else ['(no saved label)']

    # --- the text check (proven against its plain opposites in test_3) ------------------------------------------------
    def _split_told(self, qs):
        """A split origin's stop tells the user, in plain words, that nothing was saved or sent and that argo-it only
        sends to the same place it reads from, with a next step that sends nothing: ask whoever set up the fork, or
        remove the separate push address (owner, call B)."""
        self.assertTrue(qs, 'the stop for a split origin tells the user nothing')
        good = [q for q in qs if re.search(self.SENT_NONE, q) and re.search(self.SAME_PLACE, q)
                and not re.search(self.NEVER_SAY, re.sub(self.ADDRESS_WORDS, 'second address', q))]
        self.assertTrue(good, "the stop for a split origin doesn't say, in plain words, that nothing was saved or sent "
                              "and that argo-it only sends to the same place it reads from: %r" % qs)
        self.assertTrue(any(self._next_step(q) and re.search(self.SPLIT_NEXT, self._next_step(q))
                            and not self._next_step_sends(re.sub(self.ADDRESS_WORDS, 'second address', q))
                            for q in good), "the stop for a split origin has no next step that sends nothing (ask "
                                            "whoever set up the fork, or remove the separate push address): %r" % good)

    # --- 1. call A: what GitHub has, read in full ---------------------------------------------------------------------
    def test_1a_in_a_single_branch_or_shallow_clone_a_branch_the_user_already_sent_counts_as_sent(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    for opts in (('--single-branch', '-b', 'main'), ('--depth', '1')):
                        with self.subTest(git=v, shell=shell, clone=' '.join(opts)):
                            k = fake('sentfeat' + shell + opts[0][2:6])
                            r = self.fresh()
                            self._clone(r, *opts)
                            r.git('checkout', '-q', '-b', 'feature')
                            r.write('settings.py', kv('API_' + 'KEY', k))
                            r.commit('my key, already sent')
                            r.write('notes.md', '# my notes\n')
                            r.commit('my notes, already sent')
                            r.git('push', '-q', '-u', 'origin', 'feature')
                            self.assertNotIn('refs/remotes/origin/feature', self._mine(r), 'fixture: not single-branch')
                            self.assertTrue(_b(k) in self._sent_objects(r), 'fixture: GitHub lacks the key commit')
                            files = self._gen(r)
                            before = self._sent_refs(r)
                            st = self._flow(r, shell, files)
                            self.assertEqual(self._listed(st, 0), [], "step 2 lists saves GitHub already has, so the "
                                             "ask says it will send them")
                            res = st['results'][0]
                            self.assertEqual(self._saved_hits(res), [], "2b reads a commit GitHub already has as "
                                             "\"saved, not sent\"")
                            self.no_leak(res, [k])
                            self.assertFalse(st['stopped'] or st['failed'], '%r %r' % (st['stopped'], st['failed']))
                            self._sent_exactly_the_checked_commit(r, st, before, files, refs=('feature',))

    def test_1b_a_commit_github_has_only_through_a_tag_counts_as_sent(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    with self.subTest(git=v, shell=shell):
                        k = fake('tagonly' + shell)
                        r = self.fresh()
                        r.write('k.py', kv('TO' + 'KEN', k))
                        r.commit('my token, sent with a tag')
                        r.git('tag', 'v1')
                        r.git('push', '-q', 'origin', 'v1')
                        r.write('notes.md', '# my notes\n')
                        r.commit('my notes, not sent')
                        top = self._head(r)
                        files = self._gen(r)
                        before = self._sent_refs(r)
                        st = self._flow(r, shell, files)
                        listed = self._listed(st, 0)
                        self.assertEqual(len(listed), 1, "step 2 doesn't list exactly the one save GitHub lacks: %r"
                                         % listed)
                        self.assertTrue(top.startswith(listed[0].split()[0]), 'step 2 lists %r' % listed)
                        res = st['results'][0]
                        self.assertEqual(self._saved_hits(res), [], "2b reads a commit GitHub has through a tag as "
                                         "\"saved, not sent\"")
                        self.no_leak(res, [k])
                        self.assertFalse(st['stopped'] or st['failed'], '%r %r' % (st['stopped'], st['failed']))
                        self._sent_exactly_the_checked_commit(r, st, before, files)

    def test_1c_argo_its_fetch_never_touches_the_users_branches_remote_tracking_refs_or_tags(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    with self.subTest(git=v, shell=shell):
                        r = self.fresh()
                        r.git('update-ref', 'refs/remotes/origin/gone', self._head(r))  # a branch GitHub dropped
                        r.git('branch', 'mine')
                        r.git('tag', 'v1')
                        none = os.path.join(r.root, 'no-hooks-other')
                        os.makedirs(none, exist_ok=True)
                        other = os.path.join(r.root, 'other')

                        def g(cwd, *a):
                            return Repo._git(cwd, '-c', 'core.hooksPath=' + none, *a)
                        g(r.root, 'clone', '-q', os.path.join(r.root, 'origin'), 'other')  # someone else sends a
                        with open(os.path.join(other, 'theirs.md'), 'w') as f:            # commit and a tag on it
                            f.write('# theirs\n')
                        g(other, 'add', '--', 'theirs.md')
                        g(other, 'commit', '-q', '-m', 'their change')
                        g(other, 'tag', 'v2')
                        g(other, 'push', '-q', 'origin', 'main', 'v2')
                        files = self._gen(r)
                        mine = self._mine(r)
                        st = self._flow(r, shell, files, picks=())
                        self.assertIsNotNone(st['ask'], 'fixture: %r %r' % (st['stopped'], st['failed']))
                        self.assertEqual(self._mine(r), mine, "argo-it's read of GitHub changed the user's own "
                                         "branches, remote-tracking refs or tags")

    def test_1d_a_failed_fetch_of_everything_github_has_prints_fetch_failed_with_nothing_saved_or_sent(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    with self.subTest(git=v, shell=shell):
                        r = self.fresh()
                        self._clone(r, '--single-branch', '-b', 'main')
                        with open(os.path.join(r.root, 'origin', 'refs', 'heads', 'broken'), 'w') as f:
                            f.write('0' * 39 + '1\n')  # a branch GitHub lists but can't send: a fetch of it fails
                        files = self._gen(r)
                        before, mine = self._sent_refs(r), self._mine(r)
                        st = self._flow(r, shell, files)
                        self.assertIsNone(st['ask'], "the fetch of everything GitHub has failed (or never ran), and "
                                          "the ask was shown")
                        self.assertIn(('printed', 'FETCH FAILED'), st['trace'], 'no block printed FETCH FAILED: %r'
                                      % st['trace'])
                        self.assertEqual(self._sent_refs(r), before, 'GitHub changed')
                        self.assertEqual(self._mine(r), mine, "the user's own refs changed")
                        status = r.git('status', '--porcelain', '-uall').decode().splitlines()
                        self.assertEqual(sorted(l[3:] for l in status if l.startswith('?? ')), files,
                                         "argo-it's files aren't left unsaved")

    def test_1e_in_a_shallow_clone_a_commit_is_read_against_its_real_parent_so_what_github_has_is_never_unsent(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    with self.subTest(git=v, shell=shell):
                        k = fake('shallowroot' + shell)
                        r = self.fresh()
                        r.write('b.py', kv('TO' + 'KEN', k))
                        r.commit('a token, sent and still on GitHub')
                        b = self._head(r)
                        r.write('c.md', '# c\n')
                        r.commit('a note GitHub later dropped')
                        c = self._head(r)
                        r.push()
                        self._clone(r, '--depth', '1')  # this copy starts at c, with no history before it
                        self._origin(r, 'update-ref', 'refs/heads/main', b)  # GitHub's main is rewound: c is gone
                        self.assertEqual(r.git('rev-parse', '--is-shallow-repository').decode().strip(), 'true',
                                         'fixture')
                        files = self._gen(r)
                        st = self._flow(r, shell, files, picks=())
                        self.assertIsNotNone(st['ask'], "a token GitHub still has (b.py, in the commit before c) was "
                                             "read as saved, not sent: past the shallow boundary c reads as adding every "
                                             "file: %r %r" % (st['stopped'], st['res'] and st['res'].lines))
                        res = st['results'][0]
                        self.assertEqual(self._saved_hits(res), [], "2b reads a file GitHub still has as \"saved, not "
                                         "sent\"")
                        self.no_leak(res, [k])
                        listed = self._listed(st, 0)
                        self.assertEqual(len(listed), 1, 'step 2 should list c alone, the one save GitHub lacks: %r'
                                         % listed)
                        self.assertTrue(c.startswith(listed[0].split()[0]), 'step 2 lists %r' % listed)

    # --- 2. call B: a split origin is refused --------------------------------------------------------------------------
    def test_2a_a_split_origin_is_refused_before_any_read_or_ask_with_nothing_saved_or_sent_on_either_repo(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    for how in ('a separate push address', 'two push addresses, one of them the fetch address'):
                        with self.subTest(git=v, shell=shell, origin=how):
                            r = self.fresh()
                            r.git('push', '-q', 'origin', 'main:refs/heads/' + self.DEPLOY)  # on the fetch repo only
                            fork = os.path.join(r.root, 'fork')
                            Repo._git(r.root, 'clone', '-q', '--bare', os.path.join(r.root, 'origin'), 'fork')
                            Repo._git(fork, 'update-ref', '-d', 'refs/heads/' + self.DEPLOY)
                            k = fake('splitorigin' + shell)
                            r.write('k.py', kv('API_' + 'KEY', k))
                            r.commit('my key, on the fetch repo only')
                            r.push()
                            url = r.git('remote', 'get-url', 'origin').decode().strip()
                            if how.startswith('a separate'):
                                r.git('remote', 'set-url', '--push', 'origin', fork)
                            else:
                                r.git('remote', 'set-url', '--add', '--push', 'origin', url)
                                r.git('remote', 'set-url', '--add', '--push', 'origin', fork)
                            log = self._read_log(r)
                            files = self._gen(r)
                            repos = (self._bare_state(os.path.join(r.root, 'origin')), self._bare_state(fork))
                            head, mine = self._head(r), self._mine(r)
                            st = self._flow(r, shell, files)
                            self.assertIsNone(st['ask'], 'a split origin was not refused before the ask')
                            self.assertEqual((self._bare_state(os.path.join(r.root, 'origin')), self._bare_state(fork)),
                                             repos, 'the fetch repo or the push repo changed')
                            self.assertFalse(os.path.exists(log), 'GitHub was read before the split origin was refused')
                            self.assertEqual((self._head(r), self._mine(r)), (head, mine), 'something was saved here')
                            self.assertTrue(st['failed'], 'no rule for a split origin: %r' % st['stopped'])
                            self._split_told(self._told(self._phase(), st['failed']))

    def test_2b_control_a_remote_with_no_separate_push_address_is_not_refused(self):  # control: passes today
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    for how in ('no push address', 'a push address equal to the fetch address'):
                        with self.subTest(git=v, shell=shell, origin=how):
                            r = self.fresh()
                            if how.startswith('a push'):
                                r.git('remote', 'set-url', '--push', 'origin',
                                      r.git('remote', 'get-url', 'origin').decode().strip())
                            files = self._gen(r)
                            before = self._sent_refs(r)
                            st = self._flow(r, shell, files)
                            self.assertFalse(st['stopped'] or st['failed'], '%r %r' % (st['stopped'], st['failed']))
                            self._sent_exactly_the_checked_commit(r, st, before, files)

    # --- 3. polarity: the new text check passes a plain reading and fails its plain opposites -------------------------
    GOOD10 = '\n'.join((
        '**2. Check whether the deploy branch exists.**',
        '',
        '```bash',
        '[ "$(git remote get-url --all origin)" = "$(git remote get-url --push --all origin)" ] || '
        '{ echo "SPLIT ORIGIN"; exit 1; }',
        '```',
        '',
        "If it prints `SPLIT ORIGIN`, stop -- don't show the step-3 ask; nothing is saved or sent. Tell the user:",
        '',
        "\"I haven't saved or sent anything: this project is set to send changes to a different place than it reads",
        'them from, and I only send to the same place I read from. What to do next: ask whoever set up the fork, or',
        'remove the separate sending address, then run /argo-it again."',
        ''))

    def test_3_control_the_split_origin_text_check_is_polarity_bound(self):  # control: passes today
        g = self.GOOD10

        def check(t):
            self._split_told(self._told(t, 'SPLIT ORIGIN'))
        with self.subTest(text='plain reading'):
            check(g)
        with self.subTest(text='"push address", the owner\'s words, in the next step'):
            check(g.replace('sending address', 'push address'))
        for old, opposite in (
                ("I haven't saved or sent anything: this", 'I sent your setup, but this'),
                ('and I only send to the same place I read from', 'and that is fine'),
                ('ask whoever set up the fork, or\nremove the separate sending address, then run /argo-it again',
                 'run /argo-it again'),
                ('ask whoever set up the fork, or\nremove the separate sending address, then',
                 'send your setup to the fork yourself, then'),
                ('this project is set to send changes', 'this project has a git remote with a pushurl that sends commits')):
            self.assertIn(old, g)
            with self.subTest(opposite=opposite[:60]):
                with self.assertRaises(AssertionError):
                    check(g.replace(old, opposite))


# ArgoItFirstSendAdv3Cases' helpers (not its tests), for call A on the redeploy's 3e below.
_FirstSendAdv3 = type('_FirstSendAdv3', (object,), {k: v for k, v in ArgoItFirstSendAdv3Cases.__dict__.items()
                                                    if not k.startswith(('test', '__'))})


class ArgoItRedeployCallACases(_FirstSendAdv3, _FirstSendFix7, _FirstSendAdv2, _FirstSendFix6, _FirstSendFix5,
                               _FirstSendFix4, _FirstSendFix3, _FirstSendFix2, _FirstSendAdv1, _FirstSendFix1, _FirstSend,
                               Base):
    """The owner's call A, applied to PHASE 5b's 3e by the coordinator (2026-10-24, after 35ded17's implementer concern
    1): the redeploy's secret check reads what GitHub has in full, the same way and with the same private refs as PHASE
    5. A commit GitHub already has -- on a branch a single-branch or `--depth 1` clone doesn't track, or only through a
    tag -- is never "saved, not sent"; the redeploy goes ahead; the user's own branches, remote-tracking refs and tags
    are untouched; a failed read of GitHub fails closed, with a true message. `_redeploy` follows PHASE 5b as written
    after the user's "Update {hostname}". Every drive runs under bash and zsh, on each git this machine has. Values and
    secret-named lines are joined at run time (GitGuardian scans this file)."""

    # --- PHASE 5b, followed as written ---------------------------------------------------------------------------
    def _phase5b(self):
        doc = ArgoItWiringCases._doc(self)
        i = doc.find('<step name="redeploy">')
        self.assertNotEqual(i, -1, 'argo-it.md: no <step name="redeploy">')
        return doc[i:doc.find('</step>', i)]

    def _redeploy(self, r, shell, branch):
        """PHASE 5b after the user picked "Update {hostname}": every ```bash block from step 1 through step 4's, in order,
        except 3a-3d (lint, settings and migration checks, which this fixture has nothing for). The block that runs
        secret-scan.py is 3e: its result is read by 3e's three bullets (anything but exit 0 or exit 1 with the three
        labels and hits is "couldn't check"), and any stop there ends the redeploy before step 4 (a comment naming
        the script, as step 4's does, isn't a call). Any other block that
        prints a line PHASE 5b names (`FETCH FAILED`) ends it too. Returns: res (3e's result), stopped (why, or None),
        mark, mine (the user's own refs right after 3e), sent (step 4's run, or None)."""
        need_shell(shell)
        p = self._phase5b()
        h1, h4 = re.search(r'^\*\*1\. ', p, re.M), re.search(r'^\*\*4\. ', p, re.M)
        self.assertTrue(h1 and h4, 'PHASE 5b: no "**1." or "**4." heading')
        heads = [(m.start(), m.group(1)) for m in re.finditer(r'^\*\*(\d[a-e]?)\. ', p, re.M)]
        fences = [f for f in self._fences(p) if f[0] > h1.start()]
        last = next(i for i, f in enumerate(fences) if f[0] > h4.start())
        st = {'res': None, 'stopped': None, 'mark': None, 'mine': None, 'sent': None}

        def sh(code):
            for k, v in (('{current_branch}', branch), ('{deploy_branch}', self.DEPLOY)):
                code = code.replace(k, v)
            self.assertNotRegex(code, r'(?<!\$)\{[A-Za-z_][\w-]*\}', 'an unknown placeholder in PHASE 5b: %r' % code)
            return subprocess.run([shell, '-c', code.replace(INSTALLED, SCRIPT)], cwd=r.work, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, timeout=180)
        for f in fences[:last + 1]:
            step = [h for at, h in heads if at < f[0]][-1]
            if step in ('3a', '3b', '3c', '3d'):
                continue
            cp = sh(f[2])
            if step == '3e':  # coordinator, 2026-11-21 (review finding 2): only 3e's block is 3e; step 4 checks its save too
                res = st['res'] = Result(cp, 0)
                st['mine'] = self._mine(r)
                labels = [L_UNSAVED, L_NEW, L_SAVED]
                ls, hits = res.lines, [x for x in res.lines if x not in labels]
                if (res.code not in (0, 1) or [x for x in ls if x in labels] != labels or bool(hits) != (res.code == 1)
                        or not all(re.match(r'.+:[0-9]+$', h) for h in hits)):
                    st['stopped'] = "couldn't check"
                elif ls[ls.index(L_SAVED) + 1:]:
                    st['stopped'] = 'a saved hit'
                elif hits:
                    st['stopped'] = 'hits to move'
                if st['stopped']:
                    return st
                continue
            marks = [m.group(1) for l in cp.stdout.decode().splitlines()
                     for m in [re.match(r'([A-Z][A-Z0-9]*(?: [A-Z0-9]+)+)(?::|$)', l)] if m]
            if f is fences[last]:
                st['sent'] = cp
            if marks:
                st['stopped'], st['mark'] = 'printed', marks[-1]
                return st
        return st

    def _keyed_redeploy(self, r, shell, where):
        """The user's own token commit, already on GitHub -- `where`: on another branch (`wip`), or only through a tag
        (`v1`) -- then a saved change and an unsaved one, the redeploy's own. Plus a remote-tracking ref of a branch
        GitHub dropped, and a tag only GitHub has: things a fetch could touch. Returns the token."""
        k = fake('redeploy' + shell + where[:4])
        base = self._head(r)
        r.write('k.py', kv('TO' + 'KEN', k))
        r.commit('my token, already on GitHub')
        if where.startswith('on another'):
            r.git('push', '-q', 'origin', 'HEAD:refs/heads/wip')
        else:
            r.git('tag', 'v1')
            r.git('push', '-q', 'origin', 'v1')
        r.write('notes.md', '# my notes\n')
        r.commit('my notes, not sent yet')
        r.append('app.py', 'x = 1\n')
        r.git('update-ref', 'refs/remotes/origin/gone', base)  # older than the token: it doesn't make it "sent"
        self._origin(r, 'tag', 'v9', 'main')
        self.assertTrue(_b(k) in self._sent_objects(r), 'fixture: GitHub lacks the token commit')
        self.assertNotIn('refs/remotes/origin/wip', self._mine(r), 'fixture: not single-branch')
        self._prep(r)
        return k

    # --- 1. a commit GitHub already has is never "saved, not sent"; the redeploy goes ahead; the user's refs untouched
    def test_1_a_redeploy_from_a_single_branch_or_shallow_clone_reads_what_github_has_in_full(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    for opts in (('--single-branch', '-b', 'main'), ('--depth', '1')):
                        for where in ('on another branch', 'only through a tag'):
                            with self.subTest(git=v, shell=shell, clone=' '.join(opts), token=where):
                                r = self.fresh()
                                self._clone(r, *opts)
                                k = self._keyed_redeploy(r, shell, where)
                                mine = self._mine(r)
                                st = self._redeploy(r, shell, 'main')
                                self.assertIsNotNone(st['res'], "PHASE 5b's 3e never ran: %r" % st)
                                self.assertEqual(self._saved_hits(st['res']), [], "3e reads a commit GitHub already has "
                                                 "(%s) as \"saved, not sent\"" % where)
                                self.no_leak(st['res'], [k])
                                self.assertIsNone(st['stopped'], 'the redeploy stopped: %r %r' % (st['stopped'],
                                                                                                  st['mark']))
                                self.assertEqual(st['mine'], mine, "the redeploy's read of GitHub changed the user's own "
                                                 "branches, remote-tracking refs or tags")
                                self.assertTrue(st['sent'] and st['sent'].returncode == 0, 'step 4 did not send: %r'
                                                % (st['sent'] and st['sent'].stderr[:300]))
                                self.assertEqual(self._ref(r, 'main'), self._head(r), "GitHub's main isn't the redeploy")

    # --- 2. a failed read of GitHub fails closed, with a true message ---------------------------------------------------
    def test_2_a_failed_read_of_github_stops_the_redeploy_before_anything_is_saved_or_sent(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    with self.subTest(git=v, shell=shell):
                        r = self.fresh()
                        self._clone(r, '--single-branch', '-b', 'main')
                        r.write('notes.md', '# my notes\n')
                        r.commit('my notes, not sent yet')
                        r.append('app.py', 'x = 1\n')
                        with open(os.path.join(r.root, 'origin', 'refs', 'heads', 'broken'), 'w') as f:
                            f.write('0' * 39 + '1\n')  # a branch GitHub lists but can't send: a fetch of it fails
                        self._prep(r)
                        before, head, mine = self._sent_refs(r), self._head(r), self._mine(r)
                        status = r.git('status', '--porcelain').decode()
                        st = self._redeploy(r, shell, 'main')
                        self.assertTrue(st['stopped'], "the read of everything GitHub has failed (or never ran), and "
                                        "the redeploy went ahead")
                        self.assertIsNone(st['sent'], 'step 4 ran')
                        self.assertEqual(self._sent_refs(r), before, 'GitHub changed')
                        self.assertEqual((self._head(r), self._mine(r)), (head, mine), 'something was saved here')
                        self.assertEqual(r.git('status', '--porcelain').decode(), status, "the user's changes moved")
                        if st['stopped'] == "couldn't check":  # 3e's own stop: "I couldn't check ... haven't saved or sent"
                            self.assertIn("I couldn't check your changes for secrets, so I haven't saved or sent "
                                          "anything", self._flat(ArgoItWiringCases('test_old_inline_scan_is_gone')
                                                                 ._section()))
                        else:
                            self.assertEqual(st['stopped'], 'printed', 'the redeploy stopped on %r' % st['stopped'])
                            qs = self._told(self._phase5b(), st['mark'])
                            self.assertTrue(any((re.search(self.SENT_NONE, q) or re.search(self.TELL, q))
                                                and not re.search(self.NEVER_SAY, q) for q in qs),
                                            "the stop on a failed read of GitHub doesn't say, in plain words, that "
                                            "nothing was saved or sent: %r" % qs)


    # --- 3. in a shallow clone, 3e reads a commit against its real parent ----------------------------------------------
    def test_3_in_a_shallow_clone_3e_reads_a_commit_against_its_real_parent_so_what_github_has_is_never_unsent(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    with self.subTest(git=v, shell=shell):
                        k = fake('redeployroot' + shell)
                        r = self.fresh()
                        r.write('b.py', kv('TO' + 'KEN', k))
                        r.commit('a token, sent and still on GitHub')
                        b = self._head(r)
                        r.write('c.md', '# c\n')
                        r.commit('a note GitHub later dropped')
                        r.push()
                        self._clone(r, '--depth', '1')  # this copy starts at c, with no history before it
                        self._origin(r, 'update-ref', 'refs/heads/main', b)  # GitHub's main is rewound: c is gone
                        r.git('fetch', '-q', 'origin')  # the user's own fetch: their origin/main is b now
                        r.append('app.py', 'x = 1\n')
                        self._prep(r)
                        st = self._redeploy(r, shell, 'main')
                        self.assertIsNotNone(st['res'], "PHASE 5b's 3e never ran: %r" % st)
                        self.assertEqual(self._saved_hits(st['res']), [], "3e reads a file GitHub still has (b.py, in "
                                         "the commit before c) as \"saved, not sent\": past the shallow boundary c "
                                         "reads as adding every file")
                        self.no_leak(st['res'], [k])
                        self.assertIsNone(st['stopped'], '%r %r' % (st['stopped'], st['mark']))
                        self.assertTrue(st['sent'] and st['sent'].returncode == 0, 'step 4 did not send')
                        self.assertEqual(self._ref(r, 'main'), self._head(r), "GitHub's main isn't the redeploy")



class ArgoItMoveIsAPickCases(Base):
    """main's rule (owner, 2026-11-17, approval-block.md "Every ask is a select"): 3e's move ask is a pick, never a
    typed answer -- one option per hit (a multi-select when there are several), a Stop here option, no "all of them"
    option, and a pick of a line together with Stop here is a stop."""

    def _section(self):
        return ArgoItWiringCases('test_old_inline_scan_is_gone')._section()

    def _ask(self):
        """From 'Which should I move' to 'Move only the ones': the ask's closing lines and its options."""
        sec = self._section()
        i = sec.index('Which should I move')
        return sec[i:sec.index('Move only the ones', i)]

    def _after(self):
        """The paragraph that reads the pick: from 'Move only the ones' to its end."""
        sec = self._section()
        i = sec.index('Move only the ones')
        j = sec.find('\n\n', i)
        return re.sub(r'\s+', ' ', sec[i:j if j != -1 else len(sec)])

    def _options(self):
        return re.findall(r'(?m)^- \*\*([^*]+)\*\*', self._ask())

    def test_1_each_hit_is_its_own_option(self):
        opts = self._options()
        self.assertIn('Move line [N] of [file]', opts, "3e's move ask has no option per hit: %r" % opts)
        self.assertRegex(re.sub(r'\s+', ' ', self._ask()), r'(?i)\bone (option|pick) per hit\b',
                         "3e's move ask doesn't say there is one option per hit")
        self.assertRegex(re.sub(r'\s+', ' ', self._ask()), r'(?i)multi-select',
                         "3e's move ask doesn't say several hits are a multi-select")

    def test_2_stop_here_is_an_option_and_nothing_else_is(self):
        opts = self._options()
        self.assertTrue(any(re.fullmatch(r'(?i)stop here', o.strip()) for o in opts), 'no Stop here option: %r' % opts)
        for o in opts:
            self.assertRegex(o.strip(), r'(?i)^(move line \[N\] of \[file\]|stop here)$', 'an option that is neither '
                             'one hit nor Stop here (an "all of them" option?): %r' % o)

    def test_3_no_typed_answer(self):
        ask = re.sub(r'\s+', ' ', self._ask())
        self.assertNotRegex(ask, r'(?i)which should I move --', '3e asks for a typed answer ("Which should I move -- ...")')
        self.assertNotRegex(ask, r'(?i)\b(each,? by (file and line|name)|type|tell me)\b', '3e asks the user to name hits')
        after = self._after()
        self.assertTrue(after.startswith('Move only the ones they picked'), 'the pick is read as names: %r' % after[:60])
        self.assertNotRegex(after, r"(?i)\bthey named\b|\bname none\b|\bdidn't name\b", 'the pick is read as names')

    def test_4_a_line_picked_with_stop_here_is_a_stop(self):
        self.assertRegex(self._after(), r'(?i)stop here\*?\*?[^.]{0,40}\b(with|along with|together with)\b[^.]{0,40}'
                                        r'\b(line|one)', 'a line picked together with Stop here is not read as a stop')

    def test_5_the_move_path_says_picked_not_named(self):
        flat = re.sub(r'\s+', ' ', self._section())
        for bad in ('open each named line', 'the named values', "one they didn't name", "a named hit's file",
                    'not just the named line'):
            self.assertNotIn(bad, flat, '3e still reads the move as named: %r' % bad)
        self.assertIn('open each picked line yourself', flat)

    def test_6_the_rules_line_says_picks(self):
        doc = ArgoItWiringCases('test_old_inline_scan_is_gone')._doc()
        i = doc.index('**Pre-push self-review rules')
        rules = doc[i:i + 3000]
        self.assertNotRegex(rules, r'the user names which', 'the pre-push rules still say the user names which')
        self.assertRegex(rules, r'3e gate \(`secret-scan\.py`[^)]*\) -- the user picks which')

    def test_7_control_the_same_checks_fail_on_the_old_typed_ask(self):  # control: passes today
        old = ('Which should I move -- **line [N] of [file]** [each, by file and line] -- or **stop here** so you\n'
               'can sort it out yourself?"\n\n')
        self.assertEqual(re.findall(r'(?m)^- \*\*([^*]+)\*\*', old), [])
        self.assertRegex(re.sub(r'\s+', ' ', old), r'(?i)which should I move --')



class ArgoItSealFilesCases(_FirstSendAdv3, _FirstSendFix7, _FirstSendAdv2, _FirstSendFix6, _FirstSendFix5,
                           _FirstSendFix4, _FirstSendFix3, _FirstSendFix2, _FirstSendAdv1, _FirstSendFix1, _FirstSend, Base):
    """Owner, 2026-11-21: the seal's files count as argo-it's files. main's `seal` step writes them before anything is
    saved or sent and says to save them with the change they describe; PHASE 5's first send saves only argo-it's files,
    by exact name. So the allowed list gains the seal's files by exact name -- `.make-it/manifest.json`,
    `.make-it/sealed-files.txt`, `MAKE-IT.md`, `backend/make-it-stamp.json` and each new ledger entry
    (`.make-it/ledger/NNNN-<12 hex>.json`, watermark.py's own naming) -- and one save holds both. A file that merely
    sits beside one, or a look-alike name, is still never saved or sent."""

    SEAL = {'.make-it/manifest.json': '{"schema": 1}\n', '.make-it/sealed-files.txt': 'f  app.py\n',
            'MAKE-IT.md': '# Built with make-it\n', 'backend/make-it-stamp.json': '{"schema": 1}\n',
            '.make-it/ledger/0002-0123456789ab.json': '{"n": 2}\n'}
    BESIDE = {'.make-it/notes.json': '{"beside": 1}\n', '.make-it/ledger/0003-draft.json': '{"beside": 2}\n',
              '.make-it/ledger/0002-0123456789ab.json.bak': '{"beside": 3}\n', '.make-it/ledger/README.md': 'beside 4\n',
              'MAKE-IT.md.orig': 'beside 5\n', 'backend/make-it-stamp.json.tmp': '{"beside": 6}\n',
              '.make-it/manifest.json~': '{"beside": 7}\n', 'backend/MAKE-IT.md': 'beside 8\n',
              '.make-it/ledger/0004-0123456789AB.json': '{"beside": 9}\n'}

    def _seal_list(self, p=None):
        """(start, end, code) of the one ```bash block in PHASE 5 that lists the seal's files."""
        blocks = [f for f in self._fences(p or self._phase()) if '.make-it/ledger' in f[2]]
        self.assertEqual(len(blocks), 1, "PHASE 5 has no one ```bash block that lists the seal's files (%d found)"
                         % len(blocks))
        return blocks[0]

    def _sealed(self, r):
        """A make-it project sealed once before (saved and sent), then sealed again by this run (unsaved), with
        look-alikes and files beside the seal's lying around."""
        r.write('.make-it/app-context.json', '{}\n')
        r.write('.make-it/ledger/0001-aaaaaaaaaaaa.json', '{"n": 1}\n')
        r.commit('a make-it project, sealed once')
        r.push()
        for rel, t in list(self.SEAL.items()) + list(self.BESIDE.items()):
            r.write(rel, t)

    def _listed(self, r, shell):
        cp = subprocess.run([shell, '-c', self._seal_list()[2]], cwd=r.work, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=60)
        self.assertEqual(cp.returncode, 0, 'the seal list failed: %r' % cp.stderr[:300])
        return [l for l in cp.stdout.decode().splitlines() if l]

    def test_1_the_seal_list_names_each_seal_file_exactly_and_nothing_beside_them(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                r = self.fresh()
                self._sealed(r)
                self.assertEqual(sorted(self._listed(r, shell)), sorted(self.SEAL))

    def test_2_no_seal_nothing_listed(self):  # not a make-it project: the seal step is skipped
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                self.assertEqual(self._listed(self.fresh(), shell), [])

    def test_3_the_seal_runs_and_is_listed_before_step_2(self):
        p = self._phase()
        at = self._seal_list(p)[0]
        self.assertLess(at, self._step_block(p, 2)[0], "the seal's files are listed after step 2's check reads the save")
        before = re.sub(r'\s+', ' ', p[p.index('**1. '):at])
        self.assertRegex(before, r'(?i)\bseal step\b', 'step 1 does not run the seal step before listing its files')
        self.assertRegex(before, r'(?i)\bbefore step 2\b', 'step 1 does not say the seal runs before step 2')

    def test_4_option_1s_files_hold_the_seal_list_and_no_folder_or_pattern(self):
        p = re.sub(r'\s+', ' ', self._phase())
        i = p.index('{generated_files}` = the path of every file')
        d = p[i:p.index('never a folder', i)]
        self.assertRegex(d, r"(?i)\bseal\b", "Option 1's files leave out the seal's files")
        self.assertNotRegex(d, r'`\.make-it/`|\*', "Option 1's files take in a folder or a pattern for the seal")

    def test_5_a_first_send_sends_the_seal_files_and_nothing_beside_them(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                r = self.fresh()
                self._sealed(r)
                # coordinator, 2026-11-21: the look-alikes are git-ignored here, so they aren't unsaved code (the owner's
                # decision 2); untracked ones stop the send: ArgoItUnsavedCodeCases test_2
                with open(os.path.join(r.work, '.git', 'info', 'exclude'), 'a') as f:
                    f.write(''.join('/%s\n' % n for n in self.BESIDE))
                files = sorted(self._generate(r) + self._listed(r, shell))
                st = self._flow(r, shell, files)
                self.assertIsNone(st['stopped'], 'a clean first send with the seal stopped: %r' % st['stopped'])
                self.assertEqual(self._ref(r, 'main'), st['saved'], "GitHub's main is not argo-it's save")
                self.assertEqual(r.git('diff', '--name-only', st['start'], st['saved']).decode().split(), files,
                                 "argo-it's save is not exactly its files and the seal's")
                sent = self._origin(r, 'ls-tree', '-r', '--name-only', 'refs/heads/main').decode().splitlines()
                for f in self.SEAL:
                    self.assertIn(f, sent, 'a seal file was not sent: %s' % f)
                for f in self.BESIDE:
                    self.assertNotIn(f, sent, 'a file beside the seal, or a look-alike, was sent: %s' % f)
                    self.assertTrue(os.path.isfile(r.path(f)), 'a file beside the seal was removed: %s' % f)



_SealFiles = type('_SealFiles', (object,), {k: v for k, v in ArgoItSealFilesCases.__dict__.items()
                                          if not k.startswith(('test', '__'))})
_RedeployCallA = type('_RedeployCallA', (object,), {k: v for k, v in ArgoItRedeployCallACases.__dict__.items()
                                                    if not k.startswith(('test', '__'))})


class ArgoItSealGitattributesCases(_SealFiles, _FirstSendAdv3, _FirstSendFix7, _FirstSendAdv2, _FirstSendFix6,
                                   _FirstSendFix5, _FirstSendFix4, _FirstSendFix3, _FirstSendFix2, _FirstSendAdv1,
                                   _FirstSendFix1, _FirstSend, Base):
    """Owner, 2026-11-21: `.gitattributes` goes in the first-deploy save only when the seal step just changed it. If it
    also held an unsaved change of the user's before the seal ran (changed, or new and not yet saved), the save doesn't
    guess: PHASE 5 stops before the ask, says so in one plain line, and sends nothing. The seal itself is prose (main's
    step); here it is played by `_seal`, between PHASE 5's before-the-seal block and its seal list, as the agent runs
    them."""

    ATTRS = '*.png binary\n'
    SEAL_LINES = '# make-it seal\n* -text\n'

    def _before_block(self, p=None):
        """(start, end, code) of the one ```bash block in PHASE 5 that notes how .gitattributes stands before the seal."""
        blocks = [f for f in self._fences(p or self._phase()) if '.gitattributes' in f[2] and '.make-it/ledger' not in f[2]
                  and f[0] < self._seal_list(p)[0]]
        self.assertEqual(len(blocks), 1, "PHASE 5 has no one ```bash block, before the seal list, that notes how "
                         ".gitattributes stands before the seal (%d found)" % len(blocks))
        return blocks[0]

    def _sh(self, r, code, shell):
        return subprocess.run([shell, '-c', code], cwd=r.work, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              timeout=60)

    def _project(self, r, attrs=True):
        r.write('.make-it/app-context.json', '{}\n')
        if attrs:
            r.write('.gitattributes', self.ATTRS)
        r.commit('a make-it project')
        r.push()

    def _seal(self, r, change_attrs):
        for rel, t in self.SEAL.items():
            r.write(rel, t)
        if change_attrs:
            have = open(r.path('.gitattributes')).read() if os.path.exists(r.path('.gitattributes')) else ''
            r.write('.gitattributes', have + self.SEAL_LINES)

    def _step1(self, r, shell, change_attrs, user_edit=None):
        """The user's own unsaved .gitattributes (`user_edit`: its text), then PHASE 5 step 1 as the agent runs it:
        the before-the-seal block, the seal, the seal list. Returns the list's run."""
        need_shell(shell)
        self._prep(r)
        if user_edit is not None:
            r.write('.gitattributes', user_edit)
        self.assertEqual(self._sh(r, self._before_block()[2], shell).returncode, 0, 'the before-the-seal block failed')
        self._seal(r, change_attrs)
        return self._sh(r, self._seal_list()[2], shell)

    def _sent_attrs(self, r):
        return self._origin(r, 'show', 'refs/heads/main:.gitattributes')

    def test_1_the_seal_changed_it_so_it_is_listed_and_sent(self):
        for shell in ('bash', 'zsh'):
            for attrs in (True, False):  # the seal adds lines to it, or writes it new
                with self.subTest(shell=shell, had_one=attrs):
                    r = self.fresh()
                    self._project(r, attrs)
                    cp = self._step1(r, shell, True)
                    out = cp.stdout.decode().split()
                    self.assertEqual(cp.returncode, 0, out)
                    self.assertEqual(sorted(out), sorted(list(self.SEAL) + ['.gitattributes']))
                    files = sorted(self._generate(r) + out)
                    st = self._flow(r, shell, files)
                    self.assertIsNone(st['stopped'], st['stopped'])
                    self.assertEqual(self._sent_attrs(r).decode(), (self.ATTRS if attrs else '') + self.SEAL_LINES,
                                     "GitHub's .gitattributes isn't the one the seal wrote")

    def test_2_the_seal_did_not_change_it_so_it_is_not_listed_or_sent(self):
        for shell in ('bash', 'zsh'):
            for edit in (None,):  # clean (the user's own unsaved change only is unsaved code now: finding 5)
                with self.subTest(shell=shell, user_edit=bool(edit)):
                    r = self.fresh()
                    self._project(r)
                    cp = self._step1(r, shell, False, edit)
                    out = cp.stdout.decode().split()
                    self.assertEqual(cp.returncode, 0, out)
                    self.assertEqual(sorted(out), sorted(self.SEAL))
                    st = self._flow(r, shell, sorted(self._generate(r) + out))
                    self.assertIsNone(st['stopped'], st['stopped'])
                    self.assertEqual(self._sent_attrs(r).decode(), self.ATTRS, '.gitattributes was sent')

    def test_3_the_users_own_unsaved_change_and_the_seals_stop_before_the_ask(self):
        for shell in ('bash', 'zsh'):
            for tracked in (True, False):  # a change to a saved file, or a new file not saved yet
                with self.subTest(shell=shell, tracked=tracked):
                    r = self.fresh()
                    self._project(r, tracked)
                    before = self._sent_refs(r)
                    # the seal's lines from an earlier run, then the user's own line (finding 5: a user line with no
                    # seal line beside it is unsaved code, and stops before the seal)
                    cp = self._step1(r, shell, True, (self.ATTRS if tracked else '') + self.SEAL_LINES + '*.jpg binary\n')
                    lines = cp.stdout.decode().splitlines()
                    marks = [l for l in lines if re.fullmatch(self.MARK_LINE, l)]
                    self.assertNotEqual(cp.returncode, 0, 'the seal list went on: %r' % lines)
                    self.assertEqual(len(marks), 1, 'no one stop line printed: %r' % lines)
                    self.assertNotIn('.gitattributes', lines, '.gitattributes listed to be saved')
                    self.assertEqual(self._sent_refs(r), before, 'GitHub changed')
                    qs = self._told(self._phase(), marks[0])
                    self.assertTrue(any(re.search(self.SENT_NONE, q) and '.gitattributes' in q
                                        and not re.search(self.NEVER_SAY, q) for q in qs),
                                    "the stop doesn't say, in plain words, that nothing was sent and why: %r" % qs)
                    rule = re.sub(r'\s+', ' ', self._phase())
                    i = rule.index('`%s`' % marks[0])
                    self.assertRegex(rule[i:i + 300], self.NOT_SHOWN, "the stop doesn't say the ask isn't shown")


class ArgoItRedeployReadsGitHubFirstCases(_RedeployCallA, _FirstSendAdv3, _FirstSendFix7, _FirstSendAdv2,
                                          _FirstSendFix6, _FirstSendFix5, _FirstSendFix4, _FirstSendFix3,
                                          _FirstSendFix2, _FirstSendAdv1, _FirstSendFix1, _FirstSend, Base):
    """The coordinator's extension of the owner's calls A and B (2026-11-21) to the redeploy (PHASE 5b): a split origin
    stops it before the ask, in PHASE 5's words; step 1 reads GitHub (the same lines as PHASE 5 step 2) before it
    counts "saved changes not sent yet", so the number in the ask counts what GitHub has, and a failed read is a stop
    before the ask, never a guessed number. The copied lines stay identical; outside a repo the message says so."""

    SHALLOW = '[ "$(git rev-parse --is-shallow-repository)" != true ]'
    FETCH = "git fetch --prune --no-tags --refmap= origin"
    SPLIT = '[ "$(git remote get-url --all origin)" ='

    def _step1_5b(self):
        p = self._phase5b()
        a, b = re.search(r'^\*\*1\. ', p, re.M).start(), re.search(r'^\*\*2\. ', p, re.M).start()
        fs = [f for f in self._fences(p) if a < f[0] < b]
        self.assertTrue(fs, 'PHASE 5b step 1 has no ```bash block')
        return [f[2] for f in fs]

    def _run_step1(self, cwd, shell):
        out, code = b'', 0
        for c in self._step1_5b():
            cp = subprocess.run([shell, '-c', c], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
            out += cp.stdout
            code = cp.returncode
            if code:
                break
        return out.decode(), code

    def test_1_a_split_origin_stops_the_redeploy_before_the_ask_in_phase_5s_words(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                r = self.fresh()
                Repo._git(r.root, 'init', '-q', '--bare', 'fork')
                r.git('remote', 'set-url', '--push', 'origin', os.path.join(r.root, 'fork'))
                r.append('app.py', 'x = 1\n')
                self._prep(r)
                before = self._sent_refs(r)
                out, code = self._run_step1(r.work, shell)
                self.assertIn('SPLIT ORIGIN', out.splitlines(), 'step 1 lets a split origin through to the ask')
                st = self._redeploy(r, shell, 'main')
                self.assertEqual((st['stopped'], st['mark']), ('printed', 'SPLIT ORIGIN'))
                self.assertIsNone(st['res'], '3e ran')
                self.assertIsNone(st['sent'], 'step 4 ran')
                self.assertEqual(self._sent_refs(r), before, 'GitHub changed')
                self._split_told(self._told(self._phase5b(), 'SPLIT ORIGIN'))
                self.assertEqual(self._told(self._phase5b(), 'SPLIT ORIGIN'), self._told(self._phase(), 'SPLIT ORIGIN'),
                                 "the redeploy's split-origin stop isn't PHASE 5's, word for word")

    def test_2_the_count_in_the_ask_is_what_github_lacks(self):
        for v, env in self._gits():
            with self._using(env):
                for shell in ('bash', 'zsh'):
                    for opts in (('--single-branch', '-b', 'main'), ('--depth', '1')):
                        for where in ('on another branch', 'only through a tag'):
                            with self.subTest(git=v, shell=shell, clone=' '.join(opts), token=where):
                                r = self.fresh()
                                self._clone(r, *opts)
                                self._keyed_redeploy(r, shell, where)
                                mine = self._mine(r)
                                out, code = self._run_step1(r.work, shell)
                                self.assertEqual(code, 0, out)
                                nums = [l for l in out.splitlines() if re.fullmatch(r'\d+', l)]
                                self.assertEqual(nums[-1:], ['1'], 'step 1 counts what GitHub already has (%s) as '
                                                 'not sent: %r' % (where, out))
                                self.assertNotIn('my token, already on GitHub', out)
                                self.assertIn('my notes, not sent yet', out)
                                self.assertEqual(self._mine(r), mine, "step 1 changed the user's own refs")

    def test_3_a_failed_read_stops_before_the_ask_with_no_number(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                r = self.fresh()
                self._clone(r, '--single-branch', '-b', 'main')
                r.write('notes.md', '# my notes\n')
                r.commit('my notes, not sent yet')
                with open(os.path.join(r.root, 'origin', 'refs', 'heads', 'broken'), 'w') as f:
                    f.write('0' * 39 + '1\n')
                self._prep(r)
                out, code = self._run_step1(r.work, shell)
                self.assertNotEqual(code, 0)
                self.assertIn('FETCH FAILED', out.splitlines())
                self.assertFalse([l for l in out.splitlines() if re.fullmatch(r'\d+', l)], 'a count was made: %r' % out)
                qs = self._told(self._phase5b(), 'FETCH FAILED')
                self.assertTrue(any(re.search(self.SENT_NONE, q) and not re.search(self.NEVER_SAY, q) for q in qs), qs)
                rule = re.sub(r'\s+', ' ', re.sub(self.FENCE, '', self._phase5b(), flags=re.M | re.S))
                i = rule.index('`FETCH FAILED`')
                self.assertRegex(rule[i:i + 300], self.NOT_SHOWN, "the stop doesn't say the ask isn't shown")

    def test_4_the_copied_lines_are_identical(self):
        p5, p5b = self._phase(), self._phase5b()
        w = ArgoItWiringCases('test_old_inline_scan_is_gone')
        copies = {'PHASE 5 step 2': self._step_block(p5, 2)[2], 'PHASE 5b step 1': '\n'.join(self._step1_5b()),
                  'PHASE 5b 3e': w._block()}
        for start in (self.SHALLOW, self.FETCH, self.SPLIT):
            got = {k: [l for l in c.splitlines() if l.startswith(start)] for k, c in copies.items()}
            if start == self.SPLIT:
                got.pop('PHASE 5b 3e')
            for k, ls in got.items():
                self.assertEqual(len(ls), 1, '%s: %d lines start %r' % (k, len(ls), start))
            self.assertEqual(len({ls[0] for ls in got.values()}), 1, 'the copies differ: %r' % got)

    def test_5_outside_a_repo_the_message_says_so(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                with tempfile.TemporaryDirectory() as td:
                    w = ArgoItWiringCases('test_old_inline_scan_is_gone')
                    res = w._run(os.path.realpath(td))
                    self.assertEqual(res.code, 2)
                    self.assertNotIn('FETCH FAILED', res.lines, '3e says GitHub failed outside a repo')
                    self.assertIn('NOT A REPO', res.lines)
                    out, code = self._run_step1(os.path.realpath(td), shell)
                    self.assertNotEqual(code, 0)
                    self.assertNotIn('FETCH FAILED', out.splitlines())
                    self.assertIn('NOT A REPO', out.splitlines())
        qs = self._told(self._phase5b(), 'NOT A REPO')
        self.assertTrue(any(re.search(self.SENT_NONE, q) and not re.search(self.NEVER_SAY, q)
                            and not re.search(r'(?i)github', q) for q in qs), qs)
        sec = re.sub(r'\s+', ' ', w._section())
        self.assertRegex(sec, r'`NOT A REPO`', "3e's reasons don't cover NOT A REPO")



class ArgoItUnsavedCodeCases(_SealFiles, _FirstSendAdv3, _FirstSendFix7, _FirstSendAdv2, _FirstSendFix6, _FirstSendFix5,
                             _FirstSendFix4, _FirstSendFix3, _FirstSendFix2, _FirstSendAdv1, _FirstSendFix1, _FirstSend,
                             Base):
    """Owner, 2026-11-21 (decision 2): in a make-it project the first deploy stops BEFORE the seal when the user has
    unsaved code -- each path git status lists in the project folder that the seal fingerprints (watermark.py
    sealed_path: not Markdown, not under .make-it/, not backend/make-it-stamp.json), except .gitattributes and
    argo-it's own generated files. Ignored files never count. The redeploy doesn't get this stop."""

    def _unsaved_block(self, p=None):
        p = p or self._phase()
        blocks = [f for f in self._fences(p) if '--untracked-files=all' in f[2]]
        self.assertEqual(len(blocks), 1, 'PHASE 5 has no one ```bash block that checks for unsaved code (%d)' % len(blocks))
        return blocks[0]

    def _project(self, r, sub=''):
        r.write(sub + '.make-it/app-context.json', '{}\n')
        r.write(sub + 'lib/util.py', 'x = 1\n')
        r.write(sub + 'README.md', '# app\n')
        r.write(sub + '.gitattributes', '*.png binary\n')
        r.commit('a make-it project')
        r.push()

    def _check(self, r, shell, files=(), sub=''):
        need_shell(shell)
        self._prep(r)
        code = self._files_filled(self._unsaved_block()[2], list(files) or ['ONBOARDING-K8S.md'])
        cp = subprocess.run([shell, '-c', code], cwd=os.path.join(r.work, sub) if sub else r.work,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
        return cp.returncode, cp.stdout.decode().splitlines()

    def test_1_unsaved_code_stops_before_the_seal_naming_how_many_and_the_first_two(self):
        cases = {'a change to a saved file': lambda r: r.append('lib/util.py', 'y = 2\n'),
                 'a staged change': lambda r: (r.append('lib/util.py', 'y = 2\n'), r.git('add', 'lib/util.py')),
                 'a deleted file': lambda r: os.remove(r.path('lib/util.py')),
                 'a new file': lambda r: r.write('lib/new.py', 'z = 3\n')}
        for shell in ('bash', 'zsh'):
            for what, do in cases.items():
                with self.subTest(shell=shell, what=what):
                    r = self.fresh()
                    self._project(r)
                    do(r)
                    code, out = self._check(r, shell)
                    self.assertNotEqual(code, 0, what)
                    self.assertEqual(out[:2], ['UNSAVED CODE', '1'], out)
                    self.assertIn(out[2], ('lib/util.py', 'lib/new.py'), out)
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell, what='three files, in a project below the repo top'):
                r = self.fresh()
                self._project(r, 'web/')
                for n in ('a.py', 'b.py', 'c.py'):
                    r.write('web/' + n, 'v = 1\n')
                code, out = self._check(r, shell, sub='web/')
                self.assertEqual(out[:2], ['UNSAVED CODE', '3'], out)
                self.assertEqual(out[2:], ['a.py', 'b.py'], 'not the first two, by path from the project folder')

    def test_2_untracked_look_alikes_are_unsaved_code_and_stop_the_send(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                r = self.fresh()
                self._sealed(r)
                before = self._sent_refs(r)
                files = sorted(self._generate(r) + self._listed(r, shell))
                st = self._flow(r, shell, files)
                self.assertTrue(st['stopped'] or st['failed'], 'untracked look-alikes went through')
                self.assertIsNone(st['ask'], 'the ask was shown')
                self.assertEqual(self._sent_refs(r), before, 'GitHub changed')
                code, out = self._check(r, shell, files)
                self.assertEqual(out[:2], ['UNSAVED CODE', '2'], out)  # MAKE-IT.md.orig, backend/make-it-stamp.json.tmp
                self.assertEqual(sorted(out[2:]), ['MAKE-IT.md.orig', 'backend/make-it-stamp.json.tmp'])

    def test_3_what_is_not_unsaved_code_goes_on(self):
        cases = {"argo-it's own files": lambda r: [r.write(f, t) for f, t in self.GENERATED.items()],
                 'an ignored file': lambda r: (r.write('.gitignore', 'build/\n'), r.commit('ignore build'), r.push(),
                                               r.write('build/out.js', 'x\n')),
                 'a Markdown file': lambda r: r.append('README.md', 'more\n'),
                 "the seal's own files": lambda r: [r.write(f, t) for f, t in self.SEAL.items()]}
        for shell in ('bash', 'zsh'):
            for what, do in cases.items():
                with self.subTest(shell=shell, what=what):
                    r = self.fresh()
                    self._project(r)
                    do(r)
                    code, out = self._check(r, shell, sorted(self.GENERATED))
                    self.assertEqual((code, out), (0, []), what)

    def test_4_not_a_make_it_project_no_check(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                r.append('app.py', 'x = 1\n')
                self.assertEqual(self._check(r, shell), (0, []))

    def test_5_the_check_comes_before_the_seal_and_its_stop_is_one_true_line(self):
        p = self._phase()
        at = self._unsaved_block(p)[0]
        flat = re.sub(r'\s+', ' ', p)
        self.assertLess(p.index('`.make-it/app-context.json`'), at)
        self.assertLess(at, p.index('run the seal step now'), 'the unsaved-code check is not before the seal')
        qs = self._told(p, 'UNSAVED CODE')
        good = [q for q in qs if re.search(self.SENT_NONE, q) and not re.search(self.NEVER_SAY, q)
                and '/wrap-it' in q and re.search(r'\[N\]', q) and re.search(r'\[(?:the )?first path\]', q)]
        self.assertTrue(good, qs)
        i = flat.index('`UNSAVED CODE`')
        self.assertRegex(flat[i:i + 400], r"(?i)don't run the seal", "the stop doesn't say the seal isn't run")
        self.assertRegex(flat[i:i + 400], self.NOT_SHOWN)
        self.assertRegex(flat, r'(?i)redeploy[^.]{0,120}\b(?:doesn.t|does not)\b[^.]{0,40}\bstop',
                         "the text doesn't say the redeploy doesn't get this stop")


class ArgoItGitattributesContentCases(_SealFiles, _FirstSendAdv3, _FirstSendFix7, _FirstSendAdv2, _FirstSendFix6,
                                      _FirstSendFix5, _FirstSendFix4, _FirstSendFix3, _FirstSendFix2, _FirstSendAdv1,
                                      _FirstSendFix1, _FirstSend, Base):
    """Coordinator, 2026-11-21 (concern 1): .gitattributes is listed when its unsaved difference from the saved version
    is ONLY the seal's own lines (watermark.py ATTRS and its '# make-it seal' header), added in this run or an earlier
    one; seal lines with anything else -> GITATTRIBUTES MIXED; no seal line in the difference -> not listed."""

    ATTRS = '*.png binary\n'
    SEAL_LINES = ('# make-it seal\n* -text\nMAKE-IT.md merge=union\n.make-it/sealed-files.txt merge=union\n'
                  'backend/make-it-stamp.json merge=union\n')

    def _project(self, r):
        r.write('.make-it/app-context.json', '{}\n')
        r.write('.gitattributes', self.ATTRS)
        r.commit('a make-it project')
        r.push()

    def _list(self, r, shell):
        need_shell(shell)
        self._prep(r)
        for rel, t in self.SEAL.items():
            r.write(rel, t)
        cp = subprocess.run([shell, '-c', self._seal_list()[2]], cwd=r.work, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=60)
        return cp.returncode, cp.stdout.decode().splitlines()

    def test_1_seal_lines_left_from_an_earlier_run_are_listed_and_sent(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                self._project(r)
                r.append('.gitattributes', self.SEAL_LINES)  # an earlier run's seal; then "Not now"
                code, out = self._list(r, shell)
                self.assertEqual(code, 0, out)
                self.assertIn('.gitattributes', out)
                st = self._flow(r, shell, sorted(self._generate(r) + out))
                self.assertIsNone(st['stopped'], st['stopped'])
                self.assertEqual(self._origin(r, 'show', 'refs/heads/main:.gitattributes').decode(),
                                 self.ATTRS + self.SEAL_LINES)

    def test_2_seal_lines_and_a_user_line_stop(self):
        for shell in ('bash', 'zsh'):
            for order in ('user first', 'seal first'):
                with self.subTest(shell=shell, order=order):
                    r = self.fresh()
                    self._project(r)
                    parts = ['*.jpg binary\n', self.SEAL_LINES]
                    r.append('.gitattributes', ''.join(parts if order == 'user first' else parts[::-1]))
                    code, out = self._list(r, shell)
                    self.assertNotEqual(code, 0)
                    self.assertIn('GITATTRIBUTES MIXED', out)
                    self.assertNotIn('.gitattributes', out)

    def test_3_a_user_line_only_is_not_listed(self):
        for shell in ('bash', 'zsh'):
            for edit in ('add', 'remove'):
                with self.subTest(shell=shell, edit=edit):
                    r = self.fresh()
                    self._project(r)
                    if edit == 'add':
                        r.append('.gitattributes', '*.jpg binary\n')
                    else:
                        r.write('.gitattributes', '')
                    code, out = self._list(r, shell)
                    self.assertEqual(code, 0, out)
                    self.assertNotIn('.gitattributes', out)
                    self.assertNotIn('GITATTRIBUTES MIXED', out)

    def test_4_no_difference_is_not_listed(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                self._project(r)
                r.append('.gitattributes', self.SEAL_LINES)
                r.commit('saved with the seal lines')
                code, out = self._list(r, shell)
                self.assertEqual((code, '.gitattributes' in out), (0, False), out)

    def test_5_the_seal_lines_are_watermark_pys(self):
        with open(os.path.join(ROOT, '.claude', 'make-it', 'scripts', 'watermark.py'), encoding='utf-8') as f:
            src = f.read()
        attrs = re.search(r'^ATTRS = \[(.*)\]$', src, re.M).group(1)
        block = self._seal_list()[2]
        for line in re.findall(r'"([^"]+)"', attrs) + ['# make-it seal']:
            self.assertIn(line, src if line.startswith('#') else attrs)
            self.assertIn(line, block, 'the seal list does not know the seal line %r' % line)



class ArgoItTroubleshootSendsThroughRedeployCases(Base):
    """Plan Task 4: 5c troubleshooting never pushes around the gate. Every 5c row that ends in a send goes through PHASE
    5b from its step 1 (its checks, its read of GitHub, its "Update {hostname}" pick, 3a-3e, then step 4's save and
    send); no line in 5c runs or tells the agent to run a push or a commit itself. `kubectl rollout restart` is Task 5:
    this test leaves it alone."""

    OLD = ('Let me push from the right one...', 'Fix locally, push (same as pre-push self-review)',
           'Read logs, fix code if clear, push again')
    TOLD = (r'(?i)\bgit\s+(?:-c\s+\S+\s+)*(?:push|commit)\b|\blet me push\b|\bfix[^|.\n]{0,40}\bpush\b'
            r"|(?<!never )(?<!don't )(?<!not )\bpush(?:es|ing)?\s+(?:again|from|it|them|the fix|your|now)\b"
            r'|\bcommit and push\b|,\s*push\b')

    def _doc(self):
        return ArgoItWiringCases('test_old_inline_scan_is_gone')._doc()

    def _section(self, doc=None):
        doc = doc or self._doc()
        i = doc.index('<step name="post-deploy-troubleshoot">')
        return doc[i:doc.index('</step>', i)]

    def _pushes(self, sec):
        return [l for l in sec.splitlines() if re.search(self.TOLD, l)]

    def _row(self, sec, first):
        rows = [l for l in sec.splitlines() if l.startswith('| ' + first)]
        self.assertTrue(rows, 'no 5c row starts %r' % first)
        return rows

    def test_1_no_line_in_5c_pushes_or_commits(self):
        self.assertEqual(self._pushes(self._section()), [], '5c tells the agent to push or commit itself')

    def test_2_each_row_that_sends_names_the_redeploy_path(self):
        sec = self._section()
        for first in ('Run exists but wrong branch', 'CI failed (lint/build)', 'Pod crash-looping'):
            for row in self._row(sec, first):
                self.assertRegex(row, r'PHASE 5b[^|]{0,40}step 1', '%r does not go through PHASE 5b from its step 1' % first)
                self.assertRegex(row, r'Update \{hostname\}', "%r doesn't say the send waits for the pick" % first)
        for first in ('CI failed (lint/build)', 'Pod crash-looping'):
            row = self._row(sec, first)[0]
            self.assertRegex(row, r'(?i)\bunsaved\b', "%r doesn't leave the fix unsaved for step 4" % first)
            self.assertRegex(row, r'"I [^"]*\bnothing is sent\b[^"]*"', "%r doesn't tell the user nothing is sent yet" % first)

    def test_3_the_rules_line_agrees(self):
        doc = self._doc()
        rules = doc[doc.index('**Pre-push self-review rules'):]
        rules = rules[:rules.index('</guardrails>')]
        self.assertRegex(re.sub(r'\s+', ' ', rules), r'(?i)troubleshoot[^.\n]{0,80}never (?:commits?|pushes|sends)'
                         r'[^\n]{0,200}PHASE 5b[^\n]{0,40}step 1', "the rules don't say 5c sends only through PHASE 5b")

    def test_4_controls_each_old_push_fails_and_a_restart_row_does_not(self):
        sec = self._section()
        rows = ['| Run exists but wrong branch | CI ran on a different branch. | "Your build ran on a different branch. '
                'Let me push from the right one..." |',
                '| CI failed (lint/build) | Yes | Fix locally, push (same as pre-push self-review) |',
                '| Pod crash-looping | Maybe | Read logs, fix code if clear, push again |',
                'Then `git push origin {current_branch}`.',
                '```bash\ngit commit -m "fix" && git push\n```']
        for old in rows:
            with self.subTest(old=old[:40]):
                self.assertTrue(self._pushes(sec + '\n' + old), 'the check misses %r' % old)
        self.assertEqual(self._pushes('| Pod running old image | Yes (if kubectl) | '
                                      '`kubectl rollout restart deployment/{service} -n {namespace}` |'), [])
        self.assertEqual(self._pushes('| No recent run | CI never triggered. Push may not have reached GitHub. | '
                                      '"x" Then go to PHASE 5b (redeploy) from its step 1 -- never push from here '
                                      'without them. |'), [])


class ArgoItSmallConcernsCases(ArgoItUnsavedCodeCases):
    """The last step's two small concerns: a path git would quote is shown as it is, and a blank line beside the seal's
    lines in .gitattributes is a change of its own."""

    def test_1_a_path_git_would_quote_is_shown_as_it_is(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                self._project(r)
                name = 'lib/my "q" file.py'
                r.write(name, 'x = 1\n')
                code, out = self._check(r, shell)
                self.assertEqual(out, ['UNSAVED CODE', '1', name], out)

    def test_2_a_blank_line_beside_the_seal_lines_is_a_change(self):
        g = ArgoItGitattributesContentCases('test_1_seal_lines_left_from_an_earlier_run_are_listed_and_sent')
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = g.fresh()
                r.write('.make-it/app-context.json', '{}\n')
                r.write('.gitattributes', g.ATTRS + '\n')  # the saved file already has a blank line
                r.commit('a make-it project')
                r.push()
                r.append('.gitattributes', '\n' + g.SEAL_LINES)
                code, out = g._list(r, shell)
                self.assertIn('GITATTRIBUTES MIXED', out, 'a second blank line next to the seal lines went unseen')

    # the class it borrows from runs its own tests once already
    test_1_unsaved_code_stops_before_the_seal_naming_how_many_and_the_first_two = None
    test_2_untracked_look_alikes_are_unsaved_code_and_stop_the_send = None
    test_3_what_is_not_unsaved_code_goes_on = None
    test_4_not_a_make_it_project_no_check = None
    test_5_the_check_comes_before_the_seal_and_its_stop_is_one_true_line = None



class ReviewScannerCases(Base):
    """Review of ab54f84, scanner findings: 1 (UTF-16 files are text), 3 (Python string prefixes; Kubernetes / Compose
    `- name: X` / `value: ...` on adjacent lines), 9 (an unreadable file is "couldn't check"; --commit reads the whole
    range). Values are joined at run time."""

    def test_f1_utf16_files_with_a_byte_order_mark_are_scanned(self):
        for enc, bom in (('utf-16-le', b'\xff\xfe'), ('utf-16-be', b'\xfe\xff')):
            for where in ('new', 'saved'):
                with self.subTest(enc=enc, where=where):
                    v = fake('ps1' + enc[-2:] + where)
                    r = self.fresh()
                    r.branch()
                    r.write('deploy.ps1', bom + ('# deploy\r\n$env:DB_' + 'PASSWORD = "%s"\r\n' % v).encode(enc))
                    if where == 'saved':
                        r.commit('deploy script')
                        self.check(r.scan(), saved=['deploy.ps1:2'], secrets=[v])
                    else:
                        self.check(r.scan(), new=['deploy.ps1:2'], secrets=[v])

    def test_f1_control_a_utf16_file_without_a_secret_is_clean(self):  # control
        r = self.fresh()
        r.write('notes.ps1', b'\xff\xfe' + '# just notes\r\nWrite-Host "hello"\r\n'.encode('utf-16-le'))
        self.check(r.scan())

    def test_f3_python_string_prefixes_are_literals(self):
        for pre in ('r', 'b', 'u', 'f', 'rb', 'Br', 'F'):
            with self.subTest(prefix=pre):
                v = fake('prefix' + pre)
                r = self.fresh()
                r.write('settings.py', 'SECRET_' + 'KEY = %s"%s"\n' % (pre, v))
                self.check(r.scan(), new=['settings.py:1'], secrets=[v])
        v = fake('fstring')
        r = self.fresh()
        r.write('db.py', 'connect(pass' + 'word=f"%s")\n' % v)
        self.check(r.scan(), new=['db.py:1'], secrets=[v])

    def test_f3_a_name_and_its_value_on_adjacent_lines(self):
        for q in ('', '"', "'"):
            with self.subTest(quote=q):
                v = fake('k8sadj' + str(len(q)))
                r = self.fresh()
                r.write('env/dev/backend.yaml', 'env:\n  - name: LOG_LEVEL\n    value: info\n  - name: DB_' + 'PASSWORD\n'
                        '    value: %s%s%s\n' % (q, v, q))
                self.check(r.scan(), new=['env/dev/backend.yaml:5'], secrets=[v])

    def test_f3_controls_adjacent_lines_that_are_not_a_secret(self):  # controls
        r = self.fresh()
        r.write('a.yaml', 'env:\n  - name: LOG_' + 'LEVEL\n    value: verbose-debugging\n  - name: DB_' + 'PASSWORD\n'
                '    valueFrom:\n      secretKeyRef:\n        name: app-db\n        key: password\n'
                '  - name: API_' + 'TOKEN\n    value: ${API_TOKEN}\n')
        self.check(r.scan())

    def test_f9_an_unreadable_new_file_is_couldnt_check(self):
        if hasattr(os, 'geteuid') and os.geteuid() == 0:
            self.skipTest('root reads a mode-000 file')
        v = fake('unreadable')
        r = self.fresh()
        r.write('locked.py', kv('API_' + 'KEY', v))
        os.chmod(r.path('locked.py'), 0)
        self.addCleanup(os.chmod, r.path('locked.py'), 0o644)
        res = r.scan()
        self.assertEqual(res.code, 2, 'an unreadable file read as clean: %r' % res.lines)
        self.no_leak(res, [v])

    def test_f9_commit_reads_every_unsent_commit_it_reaches(self):
        v = fake('rangeparent')
        r = self.fresh()
        r.branch()
        r.write('a.py', kv('API_' + 'KEY', v))
        r.commit('the key, two commits back')
        r.write('b.md', '# notes\n')
        r.commit('a clean commit on top')
        head = r.git('rev-parse', 'HEAD').strip().decode()
        self.check(r.scan(args=['--repo', r.work, '--commit', head]), saved=['a.py:1'], secrets=[v])


class ReviewUnsavedCodeCases(ArgoItUnsavedCodeCases):
    """Review of ab54f84, findings 4 and 8 on the unsaved-code check and the .gitattributes block: names with a space or
    a non-ASCII letter; keep-out files are never advised to be saved; the .gitattributes block only in a make-it
    project."""

    test_1_unsaved_code_stops_before_the_seal_naming_how_many_and_the_first_two = None
    test_2_untracked_look_alikes_are_unsaved_code_and_stop_the_send = None
    test_3_what_is_not_unsaved_code_goes_on = None
    test_4_not_a_make_it_project_no_check = None
    test_5_the_check_comes_before_the_seal_and_its_stop_is_one_true_line = None

    def test_f4_markdown_names_with_a_space_or_accent_are_not_unsaved_code(self):
        for shell in ('bash', 'zsh'):
            for sub in ('', 'web/'):
                with self.subTest(shell=shell, sub=sub):
                    r = self.fresh()
                    self._project(r, sub)
                    r.write(sub + 'my notes.md', 'a\n')
                    r.write(sub + 'café.MD', 'b\n')
                    self.assertEqual(self._check(r, shell, sub=sub), (0, []))

    def test_f4_code_names_with_a_space_or_accent_are_shown_as_they_are(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                self._project(r)
                r.write('my code.py', 'a = 1\n')
                r.write('café.py', 'b = 2\n')
                code, out = self._check(r, shell)
                self.assertEqual(out[:2], ['UNSAVED CODE', '2'], out)
                self.assertEqual(sorted(out[2:]), sorted(['my code.py', 'café.py']))

    def test_f8_a_keep_out_file_is_never_advised_to_be_saved(self):
        for shell in ('bash', 'zsh'):
            for name in ('server.pem', 'data/app.db', '.env.production'):
                with self.subTest(shell=shell, name=name):
                    r = self.fresh()
                    self._project(r)
                    r.write(name, 'x\n')
                    code, out = self._check(r, shell)
                    self.assertEqual(out[:3], ['UNSAVED CODE', '1', name], out)
                    self.assertIn('keep-out: ' + name, out)
        flat = re.sub(r'\s+', ' ', self._phase())
        i = flat.index('`UNSAVED CODE`')
        rule = flat[i:flat.index('**2. Check whether the deploy branch', i)]
        self.assertRegex(rule, r'keep-out:', "the stop has no rule for a keep-out file")
        self.assertRegex(rule, r'(?i)should never be saved with (?:your|the) code',
                         "the stop doesn't say a keep-out file should never be saved")

    def test_f8_the_keep_out_list_is_the_scanners(self):
        mod = RegistryFilesCases._scanner()
        code = self._unsaved_block()[2]
        self.assertIn('keep-out', code, 'the unsaved-code check has no keep-out list')
        for p in [x.decode() for x in mod.KEEP_OUT]:
            self.assertIn(p.split('/')[-1], code, 'the keep-out check misses %s' % p)
        self.assertIn('.aws/credentials', code)

    def test_f8_the_gitattributes_block_runs_only_in_a_make_it_project(self):
        g = ArgoItGitattributesContentCases('test_1_seal_lines_left_from_an_earlier_run_are_listed_and_sent')
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                r = self.fresh()
                r.write('.gitattributes', '*.png binary\n')
                r.commit('not a make-it project')
                r.append('.gitattributes', '*.jpg binary\n' + g.SEAL_LINES)
                self._prep(r)
                cp = subprocess.run([shell, '-c', self._seal_list()[2]], cwd=r.work, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, timeout=60)
                self.assertEqual((cp.returncode, cp.stdout.decode().split()), (0, []))

    def test_f9_the_check_runs_before_the_seal_by_running_the_blocks(self):
        """PHASE 5 step 1's blocks, run in order in a project with unsaved code: the run stops at the unsaved-code
        check, and the seal list (which reads what the seal wrote) never runs."""
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                r = self.fresh()
                self._project(r)
                r.write('lib/new.py', 'z = 3\n')
                for rel, t in self.SEAL.items():
                    r.write(rel, t)
                self._prep(r)
                p = self._phase()
                a, b = re.search(r'^\*\*1\. ', p, re.M).start(), re.search(r'^\*\*2\. ', p, re.M).start()
                ran = []
                for f in [f for f in self._fences(p) if a < f[0] < b]:
                    code = self._files_filled(f[2], sorted(self.GENERATED))
                    cp = subprocess.run([shell, '-c', code], cwd=r.work, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        timeout=60)
                    ran.append((f[2], cp.stdout.decode()))
                    if cp.returncode:
                        break
                self.assertTrue(ran and 'UNSAVED CODE' in ran[-1][1].splitlines(), ran)
                self.assertFalse([c for c, _ in ran if '.make-it/ledger' in c], 'the seal list ran before the stop')


class ReviewOriginCases(_RedeployCallA, _FirstSendAdv3, _FirstSendFix7, _FirstSendAdv2, _FirstSendFix6, _FirstSendFix5,
                        _FirstSendFix4, _FirstSendFix3, _FirstSendFix2, _FirstSendAdv1, _FirstSendFix1, _FirstSend,
                        Base):
    """Review of ab54f84, findings 6 and 8: the split-origin check compares host and owner/repository (git's own
    insteadOf rewriting applied), so HTTPS reads with SSH sends, or a `.git`-only difference, go ahead; no origin and
    no git each get their own true line; new messages don't say "GitHub" for any host; the first deploy's failed read
    doesn't open with what reached GitHub when nothing was sent."""

    def _split_lines(self):
        out = []
        for c in (self._step_block(self._phase(), 2)[2], '\n'.join(
                ArgoItRedeployReadsGitHubFirstCases._step1_5b(self))):
            ls = [l for l in c.splitlines() if 'SPLIT ORIGIN' in l]
            self.assertEqual(len(ls), 1)
            out.append(ls[0])
        return out

    def _split(self, setup):
        res = []
        for line in self._split_lines():
            r = self.fresh()
            r.git('remote', 'set-url', 'origin', 'https://github.com/acme/app.git')
            for args in setup:
                r.git(*args)
            cp = subprocess.run(['bash', '-c', line], cwd=r.work, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            res.append('SPLIT ORIGIN' in cp.stdout.decode())
        return res

    def test_f6_the_same_repository_by_another_address_is_not_split(self):
        cases = {'pushInsteadOf ssh': [('config', 'url.git@github.com:.pushInsteadOf', 'https://github.com/')],
                 '.git only': [('remote', 'set-url', '--push', 'origin', 'https://github.com/acme/app')],
                 'a trailing slash': [('remote', 'set-url', '--push', 'origin', 'https://github.com/acme/app/')],
                 'ssh:// with a user': [('remote', 'set-url', '--push', 'origin', 'ssh://git@github.com/acme/app.git')]}
        for what, setup in cases.items():
            with self.subTest(what=what):
                self.assertEqual(self._split(setup), [False, False], what)

    def test_f6_another_repository_or_host_is_still_split(self):
        cases = {'another repository': [('remote', 'set-url', '--push', 'origin', 'git@github.com:acme/fork.git')],
                 'another owner': [('remote', 'set-url', '--push', 'origin', 'https://github.com/someone/app.git')],
                 'another host': [('remote', 'set-url', '--push', 'origin', 'https://gitlab.com/acme/app.git')]}
        for what, setup in cases.items():
            with self.subTest(what=what):
                self.assertEqual(self._split(setup), [True, True], what)

    def test_f8_no_origin_has_its_own_line_on_both_paths(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                r = self.fresh(remote=False)
                self._prep(r)
                for name, code in (('PHASE 5 step 2', self._fill(self._step_block(self._phase(), 2)[2], ['x'])),
                                   ('PHASE 5b step 1', '\n'.join(ArgoItRedeployReadsGitHubFirstCases._step1_5b(self)))):
                    cp = subprocess.run([shell, '-c', code], cwd=r.work, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    out = cp.stdout.decode().splitlines()
                    self.assertIn('NO ORIGIN', out, name)
                    self.assertNotIn('FETCH FAILED', out, name)
        for sec in (self._phase(), self._phase5b()):
            qs = self._told(sec, 'NO ORIGIN')
            self.assertTrue(any(re.search(self.SENT_NONE, q) and not re.search(r'GitHub|fork', q) for q in qs), qs)

    def test_f8_no_git_has_its_own_line(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                exe = shutil.which(shell)
                with tempfile.TemporaryDirectory() as td:
                    for code in ('\n'.join(ArgoItRedeployReadsGitHubFirstCases._step1_5b(self)),
                                 ArgoItWiringCases('test_old_inline_scan_is_gone')._block()):
                        cp = subprocess.run([exe, '-c', code], cwd=td, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                            env={'PATH': os.path.join(td, 'none'), 'HOME': td})
                        self.assertIn('NO GIT', cp.stdout.decode().splitlines())
        qs = self._told(self._phase5b(), 'NO GIT')
        self.assertTrue(any(re.search(self.SENT_NONE, q) and re.search(r'(?i)\bgit\b', q) for q in qs), qs)
        self.assertRegex(re.sub(r'\s+', ' ', ArgoItWiringCases('test_old_inline_scan_is_gone')._section()), r'`NO GIT`')

    def test_f8_new_messages_name_no_host(self):
        for q in self._told(self._phase5b(), 'FETCH FAILED') + self._told(self._phase5b(), 'NOT A REPO'):
            self.assertNotIn('GitHub', q.split('e.g.')[0], 'a redeploy message says GitHub for any host: %r' % q)
        sec = re.sub(r'\s+', ' ', ArgoItWiringCases('test_old_inline_scan_is_gone')._section())
        i = sec.index('The block printed `FETCH FAILED`')
        self.assertNotIn('GitHub', sec[i:i + 120].split('e.g.')[0])

    def test_f8_the_first_deploys_failed_read_starts_with_what_happened(self):
        for q in self._told(self._phase(), 'FETCH FAILED'):
            self.assertTrue(q.startswith("I couldn't reach "), q[:80])


class ReviewRedeployCases(_RedeployCallA, _FirstSendAdv3, _FirstSendFix7, _FirstSendAdv2, _FirstSendFix6,
                          _FirstSendFix5, _FirstSendFix4, _FirstSendFix3, _FirstSendFix2, _FirstSendAdv1,
                          _FirstSendFix1, _FirstSend, Base):
    """Review of ab54f84, findings 2, 7 and 8 on the redeploy: step 4 checks the exact commit it made (a pre-commit
    hook runs after 3e) and pushes that id; it sends only what the ask named; argo-it's pushes never send submodule
    commits; commit messages aren't scanned, and the rules say so; the first deploy's re-asks restart at the seal."""

    def _run5b(self, r, shell, after_step1=None):
        p = self._phase5b()
        heads = [(m.start(), m.group(1)) for m in re.finditer(r'^\*\*(\d[a-e]?)\. ', p, re.M)]
        h1, h4 = [a for a, h in heads if h == '1'][0], [a for a, h in heads if h == '4'][0]
        fences = [f for f in self._fences(p) if f[0] > h1]
        last = next(i for i, f in enumerate(fences) if f[0] > h4)
        out, done = [], False
        for f in fences[:last + 1]:
            step = [h for at, h in heads if at < f[0]][-1]
            if step in ('3a', '3b', '3c', '3d'):
                continue
            if step != '1' and not done:
                done = True
                if after_step1:
                    after_step1()
            code = f[2].replace('{current_branch}', 'main').replace('{deploy_branch}', self.DEPLOY)
            cp = subprocess.run([shell, '-c', code.replace(INSTALLED, SCRIPT)], cwd=r.work, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=180)
            out.append((step, cp))
            marks = [l for l in cp.stdout.decode().splitlines() if re.fullmatch(self.MARK_LINE, l)]
            if marks or (cp.returncode and step != '3e'):
                return out, (marks[-1] if marks else None)
            if step == '3e' and cp.returncode:
                return out, '3e'
        return out, None

    def test_f2_a_hook_that_adds_a_secret_at_the_save_never_sends_it(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                v = fake('hookadded' + shell)
                r = self.fresh()
                hooks = os.path.join(r.root, 'hooks')
                os.makedirs(hooks)
                with open(os.path.join(hooks, 'pre-commit'), 'w') as f:
                    f.write("#!/bin/sh\nprintf 'API_%s = \"%s\"\\n' > gen.py\ngit add gen.py\n" % ('KEY', v))
                os.chmod(os.path.join(hooks, 'pre-commit'), 0o755)
                r.append('app.py', 'x = 1\n')
                self._prep(r, hooks)
                before = self._sent_refs(r)
                out, mark = self._run5b(r, shell)
                self.assertFalse(_b(v) in self._sent_objects(r), 'the key a hook added at the save reached GitHub')
                self.assertEqual(self._sent_refs(r), before, 'GitHub changed')
                self.assertTrue(mark, 'step 4 went on: %r' % [(s, c.stdout[-200:]) for s, c in out])
                self.assertIn('gen.py:1', out[-1][1].stdout.decode().splitlines())
                qs = self._told(self._phase5b(), mark)
                self.assertTrue(any(re.search(r"(?i)\bsaved\b[^.]{0,40}\bon this computer\b", q)
                                    and re.search(r"(?i)\b(?:didn't|did not|haven't|not) sen[dt]\b", q)
                                    and not re.search(r"(?i)haven't saved", q) for q in qs),
                                "the stop doesn't say, truly, that the save is here and nothing was sent: %r" % qs)

    def test_f2_control_a_clean_redeploy_sends_the_checked_commit(self):  # control
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                r = self.fresh()
                r.append('app.py', 'x = 1\n')
                self._prep(r)
                out, mark = self._run5b(r, shell)
                self.assertIsNone(mark, [(s, c.stdout[-300:]) for s, c in out])
                self.assertEqual(self._ref(r, 'main'), self._head(r))

    def test_f7_a_commit_made_after_the_ask_is_not_sent(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                r = self.fresh()
                r.append('app.py', 'x = 1\n')
                self._prep(r)
                before = self._sent_refs(r)

                def late():
                    r.write('late.py', 'late = 1\n')
                    r.git('add', 'late.py')
                    r.git('commit', '-q', '-m', 'made after the ask')
                out, mark = self._run5b(r, shell, late)
                self.assertEqual(self._sent_refs(r), before, 'a commit the ask never named was sent')
                self.assertEqual(mark, 'CHANGED SINCE THE ASK')
                self.assertEqual(r.git('log', '-1', '--format=%s').decode().strip(), 'made after the ask',
                                 'step 4 saved on top of a change the ask never named')
                qs = self._told(self._phase5b(), 'CHANGED SINCE THE ASK')
                self.assertTrue(any(re.search(self.SENT_NONE, q) and '/argo-it' in q for q in qs), qs)

    def test_f7_the_first_deploys_re_asks_restart_at_the_seal(self):
        flat = re.sub(r'\s+', ' ', self._phase())
        for mark in ('CHANGED SINCE THE ASK', 'SAVED SINCE THE CHECK'):
            i = flat.index('If it prints `%s`' % mark)
            rule = flat[i:i + 600]
            self.assertRegex(rule, r'(?i)back to step 1\b', '%s: the re-ask does not start again at step 1' % mark)
            self.assertRegex(rule, r'(?i)\bseal\b', '%s: the re-ask does not take the seal again' % mark)

    def test_f8_argo_its_pushes_never_send_submodule_commits(self):
        for sec in (self._phase(), self._phase5b()):
            for f in self._fences(sec):
                for l in f[2].splitlines():
                    if re.search(r'^\s*[^#]*\bgit\s+push\b', l):
                        self.assertIn('--recurse-submodules=no', l, l)

    def test_f8_the_rules_say_commit_messages_are_not_checked(self):
        doc = ArgoItWiringCases('test_old_inline_scan_is_gone')._doc()
        rules = doc[doc.index('**Pre-push self-review rules'):]
        rules = re.sub(r'\s+', ' ', rules[:rules.index('</guardrails>')])
        self.assertRegex(rules, r'(?i)(?:save|commit) messages? (?:is|are) never checked')


class ReviewTextCases(ArgoItWiringCases):
    """Review of ab54f84, findings 8 (a real backslash in a shown path is escaped) and 10 (the crash-looping row asks
    before a change beyond 3a's safe fixes)."""

    def test_f8_a_real_backslash_in_a_name_is_escaped(self):
        v = fake('backslash')
        r = self.fresh()
        r.write('a\\x41.py', kv('API_' + 'KEY', v))
        self.check(r.scan(), new=['a\\x5cx41.py:1'], secrets=[v])

    def test_f10_crash_looping_asks_before_a_change_beyond_the_safe_fixes(self):
        doc = self._doc()
        i = doc.index('<step name="post-deploy-troubleshoot">')
        sec = doc[i:doc.index('</step>', i)]
        row = [l for l in sec.splitlines() if l.startswith('| Pod crash-looping')][0]
        self.assertRegex(row, r"(?i)3a's safe fixes", 'the row does not limit what it changes on its own')
        self.assertRegex(row, r'(?i)ask first|asks? before', 'the row does not ask before another change')
        j = sec.index('**Crash-looping fix')
        ask = sec[j:sec.index('\n\n**', j + 5) if '\n\n**' in sec[j + 5:] else len(sec)]
        opts = re.findall(r'(?m)^- \*\*([^*]+)\*\*', ask)
        self.assertEqual(len(opts), 2, opts)
        self.assertRegex(opts[0], r'^Change \[file\]$')
        self.assertRegex(opts[1], r'^Leave it$')
        flat = re.sub(r'\s+', ' ', ask)
        for what, rx in (('the evidence', r'(?i)logs show'), ('what changes', r'(?i)I.d change \[file\]'),
                         ('the undo', r'(?i)put the file back'), ('the one thing to check', r'(?i)the one thing to check'),
                         ('a select', r'(?i)plain yes isn.t an answer'), ('nothing sent', r'(?i)not saved or sent')):
            self.assertRegex(flat, rx, 'the crash-looping ask lacks %s' % what)



class ReviewRound2Cases(ArgoItUnsavedCodeCases):
    """The coordinator's calls on the review's blocked parts (2026-11-21): finding 5 (a user's own .gitattributes edit
    with no seal line is unsaved code), finding 1 (git's binary rule kept, and written down), and the SSH-port form."""

    test_1_unsaved_code_stops_before_the_seal_naming_how_many_and_the_first_two = None
    test_2_untracked_look_alikes_are_unsaved_code_and_stop_the_send = None
    test_3_what_is_not_unsaved_code_goes_on = None
    test_4_not_a_make_it_project_no_check = None
    test_5_the_check_comes_before_the_seal_and_its_stop_is_one_true_line = None
    SEAL_LINES = '# make-it seal\n* -text\n'

    def test_f5_a_users_own_gitattributes_edit_is_unsaved_code(self):
        for shell in ('bash', 'zsh'):
            for how in ('a line added', 'a line removed', 'a new file'):
                with self.subTest(shell=shell, how=how):
                    r = self.fresh()
                    self._project(r)
                    if how == 'a line added':
                        r.append('.gitattributes', '*.jpg binary\n')
                    elif how == 'a line removed':
                        r.write('.gitattributes', '')
                    else:
                        r.git('rm', '-q', '--cached', '.gitattributes')
                        r.git('commit', '-q', '-m', 'unsave it')
                        r.write('.gitattributes', '*.jpg binary\n')
                    code, out = self._check(r, shell)
                    self.assertNotEqual(code, 0, how)
                    self.assertEqual(out[:3], ['UNSAVED CODE', '1', '.gitattributes'], out)

    def test_f5_seal_lines_or_seal_lines_mixed_pass_the_check(self):
        for shell in ('bash', 'zsh'):
            for extra in ('', '*.jpg binary\n'):  # seal lines only: sent later; mixed: GITATTRIBUTES MIXED later
                with self.subTest(shell=shell, mixed=bool(extra)):
                    r = self.fresh()
                    self._project(r)
                    r.append('.gitattributes', self.SEAL_LINES + extra)
                    self.assertEqual(self._check(r, shell), (0, []))

    def test_f5_one_classifier_for_both_blocks(self):
        def awk(code):
            m = re.search(r"awk -v f=\"\$o\" '(.*?)' \"\$o\" \.gitattributes", code, re.S)
            self.assertTrue(m, 'no .gitattributes classifier in %r' % code[:200])
            return m.group(1)
        self.assertEqual(awk(self._unsaved_block()[2]), awk(self._seal_list()[2]),
                         'the unsaved-code check and the seal list classify .gitattributes differently')

    def test_f1_the_rules_say_a_file_with_a_zero_byte_is_not_checked(self):
        doc = ArgoItWiringCases('test_old_inline_scan_is_gone')._doc()
        rules = doc[doc.index('**Pre-push self-review rules'):]
        rules = re.sub(r'\s+', ' ', rules[:rules.index('</guardrails>')])
        self.assertRegex(rules, r'(?i)zero byte in its first 8,000 bytes[^.]{0,200}never checked')

    def test_ssh_port_is_not_a_split_another_host_still_is(self):
        o = ReviewOriginCases('test_f6_the_same_repository_by_another_address_is_not_split')
        self.assertEqual(o._split([('remote', 'set-url', '--push', 'origin', 'ssh://git@github.com:22/acme/app.git')]),
                         [False, False])
        self.assertEqual(o._split([('remote', 'set-url', '--push', 'origin', 'ssh://git@gitlab.com:22/acme/app.git')]),
                         [True, True])



# Task 5: the troubleshooting blocks and asks, pinned whole
T5_CTX = r'''c=$(python3 -I -c 'import json; d=json.load(open(".make-it/app-context.json")).get("deployment") or {}; print(d.get("k8s_context") or "")' 2>/dev/null)
v=$(python3 -I -c 'import json; d=json.load(open(".make-it/app-context.json")).get("deployment") or {}; print(d.get("k8s_server") or "")' 2>/dev/null)
# A server address, compared without a trailing / and with its scheme and host in small letters
low() { awk '{ sub(/\/+$/, ""); i = index($0, "://"); if (!i) { print; next }; r = substr($0, i + 3); j = index(r, "/"); h = j ? substr(r, 1, j - 1) : r; print tolower(substr($0, 1, i + 2) h) (j ? substr(r, j) : "") }'; }'''

T5_NAMES = r'''# The app's namespace and name, as plain Kubernetes names only: never anything a shell would run
ns='{namespace}'; svc='{service}'
printf '%s\n' "$ns" "$svc" | grep -vqxE '[a-z0-9]([-a-z0-9]*[a-z0-9])?' && { echo "BAD NAME"; exit 1; }'''

T5_SAME = r'''[ "$(kubectl config current-context 2>/dev/null)" = "$c" ] && [ "$(kubectl config view --minify --context "$c" -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null | low)" = "$(printf '%s\n' "$v" | low)" ]'''

T5_READ = '''# The app's own cluster, as setup recorded it (deployment.k8s_context, and its server address deployment.k8s_server)
''' + T5_NAMES + '''
''' + T5_CTX + '''
[ -n "$c" ] && [ -n "$v" ] || { echo "NO CLUSTER RECORD"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "NO KUBECTL"; exit 1; }
# Read only, and only while this computer points at that cluster, by its name and its server address
''' + T5_SAME + ''' || { echo "NOT ITS CLUSTER"; exit 1; }
kubectl --context "$c" get pods -n "$ns" -o jsonpath='{.items[*].spec.containers[*].image}' || { echo "READ FAILED"; exit 1; }
grep 'image:' "env/dev/$svc.yaml"
'''

T5_CHECK = '''# Before the ask: a restart may only reach the app's own cluster, so this computer must point at it, by name and address
''' + T5_CTX + '''
[ -n "$c" ] && [ -n "$v" ] || { echo "CLUSTER UNKNOWN"; exit 1; }
''' + T5_SAME + ''' || { echo "OTHER CLUSTER"; exit 1; }
'''

T5_RESTART = '''# Only after the user picked "Restart {hostname}": on the app's own cluster, checked again right before
''' + T5_NAMES + '''
''' + T5_CTX + '''
[ -n "$c" ] && [ -n "$v" ] && ''' + T5_SAME + ''' || { echo "OTHER CLUSTER"; exit 1; }
kubectl --context "$c" rollout restart "deployment/$svc" -n "$ns"
'''

T5_RERUN = '''# Only after the user picked "Rebuild {hostname}": the last build of this project, run again
gh run rerun {run_id}
'''

T5_LOGS = '''# Read only, on the app's own cluster by name and address: what the running version printed last
''' + T5_NAMES + '''
''' + T5_CTX + '''
[ -n "$c" ] && [ -n "$v" ] || { echo "NO CLUSTER RECORD"; exit 1; }
''' + T5_SAME + ''' || { echo "NOT ITS CLUSTER"; exit 1; }
kubectl --context "$c" logs -n "$ns" "deploy/$svc" --tail=100 || { echo "READ FAILED"; exit 1; }
'''

T5_RESTART_ASK = '''"Your app at {hostname} is still running an older version than the last one built and sent: [the
evidence, in plain words -- e.g. 'the running version came from Tuesday's build; the latest is from
today']. I can restart it on [the app's cluster name] -- the group of servers it runs on -- so it
picks up the latest version. Anyone using {hostname} right now is interrupted for about 30 seconds
while it restarts. There's nothing to undo: a restart only starts your app again on the version
already sent, and your code and data don't change. The one thing to check: is anyone in the middle
of something on {hostname} right now?

- **Restart {hostname}** -- restart it now on [the app's cluster name]
- **Not now** -- I change nothing"'''

T5_REBUILD_ASK = '''"The last build of your app didn't finish handing the latest version to the deployment system:
[the evidence, in plain words]. I can run that build again: it builds the last version you sent and
hands it over, and [the app's cluster name / the servers your app runs on] picks it up within a few
minutes. Anyone using {hostname} may be interrupted for about 30 seconds when the new version
starts. There's nothing to undo: it sends the same version again, and your code and data don't
change. The one thing to check: is anyone in the middle of something on {hostname} right now?

- **Rebuild {hostname}** -- run the last build again now
- **Not now** -- I change nothing"'''


class ArgoItRestartAsksCases(Base):
    """Plan Task 5 (owner's go, 2026-11-21): troubleshooting never restarts the running app or re-runs its build on its
    own. Diagnosing only reads, on the app's own cluster by name (`--context`, from `deployment.k8s_context`, which
    setup records). One select before a restart or a rebuild; never on another cluster or an unknown one, where the
    Argo CD click steps are given instead. The blocks and the two asks are pinned whole; then they are run under bash
    and zsh with a fake kubectl and gh on PATH."""

    CTX = T5_CTX
    READ = T5_READ
    CHECK = T5_CHECK
    RESTART = T5_RESTART
    RERUN = T5_RERUN
    LOGS = T5_LOGS
    RESTART_ASK = T5_RESTART_ASK
    REBUILD_ASK = T5_REBUILD_ASK

    def _doc(self):
        return ArgoItWiringCases('test_old_inline_scan_is_gone')._doc()

    def _section(self, doc=None):
        doc = doc or self._doc()
        i = doc.index('<step name="post-deploy-troubleshoot">')
        return doc[i:doc.index('</step>', i)]

    def _fences(self, sec):
        return re.findall(r'(?ms)^```bash\n(.*?)^```', sec)

    # --- pinned whole ----------------------------------------------------------------------------------------------
    def test_1_the_blocks_are_pinned_whole(self):
        fs = self._fences(self._section())
        for name in ('READ', 'CHECK', 'RESTART', 'RERUN', 'LOGS'):
            self.assertIn(getattr(self, name), fs, '5c has no block exactly as %s' % name)

    def test_2_the_asks_are_pinned_whole(self):
        sec = self._section()
        for name in ('RESTART_ASK', 'REBUILD_ASK'):
            self.assertIn(getattr(self, name), sec, '5c has no %s exactly as pinned' % name)
            ask = getattr(self, name)
            self.assertNotRegex(ask, r'(?i)\b(pod|container|image|rollout|kubectl)\b', 'a NEVER-say word in %s' % name)

    def test_3_no_restart_or_rerun_outside_its_block(self):
        sec = self._section()
        for f in self._fences(sec):
            if f not in (self.RESTART, self.RERUN):
                self.assertNotRegex(f, r'rollout\s+restart|run\s+rerun', 'a restart or rerun outside its block: %r' % f)
        flat = re.sub(r'\s+', ' ', re.sub(r'(?ms)^```bash\n.*?^```', '', sec))
        self.assertNotRegex(flat, r'`kubectl[^`]*rollout restart[^`]*`|`gh run rerun[^`]*`(?![^|]{0,40}only)',
                            'a restart or rerun named as an action outside its pick')

    def test_4_every_kubectl_names_the_cluster(self):
        for f in self._fences(self._section()):
            for l in f.splitlines():
                if re.search(r'^\s*[^#]*\bkubectl\s', l) and 'config current-context' not in l and 'command -v' not in l:
                    self.assertIn('--context', l, l)

    def test_5_the_rows_and_the_rules_ask_first(self):
        sec = self._section()
        rows = [l for l in sec.splitlines() if l.startswith(('| Pod running old image', '| Deploy branch not updated'))]
        self.assertEqual(len(rows), 3, rows)
        for row in rows:
            auto = row.split('|')[2].strip()
            self.assertNotRegex(auto, r'^(?:Yes|Maybe)\b', 'a restart or rebuild row still auto-fixes: %r' % row)
        doc = self._doc()
        self.assertNotIn("don't ask the user to click around Argo", doc)
        rules = doc[doc.index('**Post-deploy troubleshooting rules (PHASE 5c):**'):]
        rules = re.sub(r'\s+', ' ', rules[:rules.index('\n\n')])
        self.assertRegex(rules, r'(?i)only after the user picks Restart \{hostname\} or Rebuild \{hostname\}')
        self.assertRegex(rules, r"(?i)another cluster[^.]{0,120}Argo CD")

    def test_6_setup_records_the_apps_cluster(self):
        doc = self._doc()
        i = doc.index('<step name="setup">')
        setup = re.sub(r'\s+', ' ', doc[i:doc.index('</step>', i)])
        self.assertRegex(setup, r'deployment\.k8s_context', "setup doesn't record the app's cluster")
        self.assertRegex(setup, r'(?i)\*\*None of these / not sure\*\*', "the cluster pick has no way out")
        self.assertRegex(setup, r'(?i)local', "setup offers local clusters as the app's")

    def test_7_the_stops_and_not_now_are_true_lines(self):
        sec = self._section()
        flat = re.sub(r'\s+', ' ', sec)
        for mark, rx in (('CLUSTER UNKNOWN', r"I won't restart your app from here: I have no record of which cluster"),
                         ('OTHER CLUSTER', r"I won't restart your app from here: this computer is set to work with")):
            i = flat.index('`%s`' % mark)
            self.assertRegex(flat[i:i + 700], rx, mark)
            self.assertRegex(flat[i:i + 700], r'(?i)Argo CD', '%s gives no Argo CD steps' % mark)
        self.assertRegex(flat, r"(?i)Not now., a dismissed ask, or any other answer changes nothing")
        self.assertIn("I haven't changed anything. When it suits you, run /argo-it again and pick Restart {hostname}.",
                      flat)

    # --- run under bash and zsh, with a fake kubectl and gh --------------------------------------------------------
    def _env(self, td, ctx, server='https://k8s.acme.example:6443'):
        bin_ = os.path.join(td, 'bin')
        os.makedirs(bin_, exist_ok=True)
        log = os.path.join(td, 'calls.log')
        for tool in ('kubectl', 'gh'):
            with open(os.path.join(bin_, tool), 'w') as f:
                f.write('#!/bin/sh\necho "%s $*" >> "%s"\ncase "$*" in\n  *"config current-context"*) printf '
                        "'%%s\\n' \"$FAKE_CTX\";;\n  *\"config view\"*) printf '%%s\\n' \"$FAKE_SERVER\";;\n"
                        "  *\"get pods\"*) echo reg/app:old;;\nesac\n" % (tool, log))
            os.chmod(os.path.join(bin_, tool), 0o755)
        return log, dict(os.environ, PATH=bin_ + os.pathsep + os.environ['PATH'], FAKE_CTX=ctx, FAKE_SERVER=server)

    def _run(self, code, cwd, env, shell):
        code = (code.replace('{namespace}', 'acme').replace('{service}', 'backend').replace('{hostname}', 'acme.example')
                .replace('{run_id}', '42').replace('{deploy_branch}', 'deploy-nonprod').replace('{current_branch}', 'main'))
        return subprocess.run([shutil.which(shell), '-c', code], cwd=cwd, env=env, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=60)

    def _project(self, td, recorded):
        os.makedirs(os.path.join(td, '.make-it'))
        with open(os.path.join(td, '.make-it', 'app-context.json'), 'w') as f:
            f.write('{"deployment": {"k8s_context": "acme-prod-eu", "k8s_server": "https://k8s.acme.example:6443"}}\n'
                    if recorded else '{"deployment": {}}\n')
        os.makedirs(os.path.join(td, 'env', 'dev'))
        with open(os.path.join(td, 'env', 'dev', 'backend.yaml'), 'w') as f:
            f.write('image: reg/app:new\n')

    def _calls(self, log):
        return open(log).read().splitlines() if os.path.exists(log) else []

    def test_8_nothing_restarts_or_reruns_before_the_pick(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                with tempfile.TemporaryDirectory() as td:
                    self._project(td, True)
                    log, env = self._env(td, 'acme-prod-eu')
                    for f in self._fences(self._section()):
                        if f not in (self.RESTART, self.RERUN):
                            self._run(f, td, env, shell)
                    calls = self._calls(log)
                    self.assertFalse([c for c in calls if 'rollout restart' in c or 'run rerun' in c], calls)
                    reads = [c for c in calls if c.startswith('kubectl ') and 'config current-context' not in c]
                    self.assertTrue(reads, 'no read of the cluster ran: %r' % calls)
                    for c in reads:
                        self.assertIn('--context acme-prod-eu', c, c)

    def test_9_the_pick_restarts_on_the_apps_cluster_only(self):
        for shell in ('bash', 'zsh'):
            for now, recorded, ok in (('acme-prod-eu', True, True), ('someone-elses', True, False),
                                      ('', True, False), ('acme-prod-eu', False, False)):
                with self.subTest(shell=shell, now=now, recorded=recorded):
                    need_shell(shell)
                    with tempfile.TemporaryDirectory() as td:
                        self._project(td, recorded)
                        log, env = self._env(td, now)
                        check = self._run(self.CHECK, td, env, shell)
                        self.assertEqual(check.returncode == 0, ok, check.stdout)
                        cp = self._run(self.RESTART, td, env, shell)
                        restarts = [c for c in self._calls(log) if 'rollout restart' in c]
                        if ok:
                            self.assertEqual(restarts, ['kubectl --context acme-prod-eu rollout restart '
                                                        'deployment/backend -n acme'])
                        else:
                            self.assertEqual(restarts, [], 'a restart on %r' % now)
                            self.assertIn(b'CLUSTER UNKNOWN' if not recorded else b'OTHER CLUSTER',
                                          check.stdout)

    def test_10_controls_each_old_form_fails_these_checks(self):  # controls
        old_line = 'kubectl rollout restart deployment/{service} -n {namespace} 2>/dev/null'
        self.assertNotIn('--context', old_line)
        self.assertRegex(old_line, r'rollout\s+restart')
        old_row = '| Pod running old image | Yes (if kubectl) | `kubectl rollout restart deployment/{service} -n {namespace}` |'
        self.assertRegex(old_row.split('|')[2].strip(), r'^(?:Yes|Maybe)\b')
        old_rule = "- If kubectl is available, use `kubectl rollout restart` -- don't ask the user to click around Argo"
        self.assertIn("don't ask the user to click around Argo", old_rule)
        sec = self._section()
        for cut in ("[the app's cluster name] -- the group of servers it runs on -- ", 'interrupted for about 30 seconds'):
            self.assertIn(cut, self.RESTART_ASK)
            self.assertNotIn(self.RESTART_ASK.replace(cut, ''), sec, 'the ask without %r passes' % cut)
        self.assertNotIn(self.RESTART.replace('--context "$c" ', ''), self._fences(sec))



class ReReviewRedeployCases(ReviewRedeployCases):
    """Re-review of 03aef71, finding 1: the redeploy's pin also covers new files (step 1 keeps the path list; a path
    3a, 3b, 3c or a 3e move changed is written to argo-it-touched), runs before anything is staged, catches a change to
    the online copy's branches, and the push sends the checked save by id even if HEAD moves during the check.
    Finding 3: SAVE NOT SENT only when a save was made in step 4."""

    test_f2_a_hook_that_adds_a_secret_at_the_save_never_sends_it = None
    test_f2_control_a_clean_redeploy_sends_the_checked_commit = None
    test_f7_a_commit_made_after_the_ask_is_not_sent = None
    test_f7_the_first_deploys_re_asks_restart_at_the_seal = None
    test_f8_argo_its_pushes_never_send_submodule_commits = None
    test_f8_the_rules_say_commit_messages_are_not_checked = None

    def _run5b2(self, r, shell, after_step1=None, scanner=None):
        p = self._phase5b()
        heads = [(m.start(), m.group(1)) for m in re.finditer(r'^\*\*(\d[a-e]?)\. ', p, re.M)]
        h1, h4 = [a for a, h in heads if h == '1'][0], [a for a, h in heads if h == '4'][0]
        fences = [f for f in self._fences(p) if f[0] > h1]
        last = next(i for i, f in enumerate(fences) if f[0] > h4)
        out, done = [], False
        for f in fences[:last + 1]:
            step = [h for at, h in heads if at < f[0]][-1]
            if step in ('3a', '3b', '3c', '3d'):
                continue
            if step != '1' and not done:
                done = True
                if after_step1:
                    after_step1()
            code = f[2].replace('{current_branch}', 'main').replace('{deploy_branch}', self.DEPLOY)
            if scanner and step == '4':
                code = code.replace('python3 ' + INSTALLED, scanner)
            code = code.replace(INSTALLED, SCRIPT)
            cp = subprocess.run([shell, '-c', code], cwd=r.work, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=180)
            out.append((step, cp))
            marks = [l for l in cp.stdout.decode().splitlines() if re.fullmatch(self.MARK_LINE, l)]
            if marks or (cp.returncode and step != '3e'):
                return out, (marks[-1] if marks else None)
            if step == '3e' and cp.returncode:
                return out, '3e'
        return out, None

    def _ready(self, shell):
        need_shell(shell)
        r = self.fresh()
        r.append('app.py', 'x = 1\n')
        self._prep(r)
        return r

    def test_1_a_new_file_after_the_ask_is_not_sent_and_nothing_is_staged(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self._ready(shell)
                before = self._sent_refs(r)
                gi = open(r.path('.gitignore')).read() if os.path.exists(r.path('.gitignore')) else None
                out, mark = self._run5b2(r, shell, lambda: r.write('late.py', 'late = 1\n'))
                self.assertEqual(mark, 'CHANGED SINCE THE ASK')
                self.assertEqual(self._sent_refs(r), before)
                self.assertEqual(r.git('diff', '--cached', '--name-only').decode(), '', 'the index was left staged')
                self.assertEqual(open(r.path('.gitignore')).read() if os.path.exists(r.path('.gitignore')) else None,
                                 gi, '.gitignore was changed before the stop')

    def test_2_a_listed_file_changed_again_or_a_touched_file_still_goes(self):
        for shell in ('bash', 'zsh'):
            for how in ('a listed file, changed again', 'a file 3b changed, recorded'):
                with self.subTest(shell=shell, how=how):
                    r = self._ready(shell)

                    def between():
                        if how.startswith('a listed'):
                            r.append('app.py', 'y = 2\n')
                        else:
                            r.write('env/dev/backend.yaml', 'kind: Deployment\n')
                            with open(os.path.join(r.work, '.git', 'argo-it-touched'), 'a') as f:
                                f.write('env/dev/backend.yaml\n')
                    out, mark = self._run5b2(r, shell, between)
                    self.assertIsNone(mark, [(s_, c.stdout[-200:]) for s_, c in out])
                    self.assertEqual(self._ref(r, 'main'), self._head(r))

    def test_3_a_change_to_the_online_copys_branches_stops_the_send(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self._ready(shell)
                r.write('b.py', 'b = 1\n')
                r.commit('a save not sent yet')
                before = None

                def elsewhere():  # someone sends that save from another copy before step 4
                    r.git('push', '-q', 'origin', 'HEAD:refs/heads/elsewhere')
                out, mark = self._run5b2(r, shell, elsewhere)
                self.assertEqual(mark, 'CHANGED SINCE THE ASK')

    def test_4_the_push_sends_the_checked_save_even_if_head_moves_during_the_check(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self._ready(shell)
                wrap = os.path.join(r.root, 'scan-then-commit.sh')
                with open(wrap, 'w') as f:
                    f.write('#!/bin/sh\n"%s" "%s" "$@"; rc=$?\ngit -c user.name=t -c user.email=t@t commit -q '
                            '--allow-empty -m "made during the check"\nexit $rc\n' % (sys.executable, SCRIPT))
                os.chmod(wrap, 0o755)
                out, mark = self._run5b2(r, shell, scanner=wrap)
                self.assertIsNone(mark, [(s_, c.stdout[-200:]) for s_, c in out])
                sent = self._ref(r, 'main')
                self.assertEqual(r.git('log', '-1', '--format=%s', sent).decode().strip(),
                                 'Deploy: [brief description of changes]', 'a commit the check never read was sent')

    def test_5_save_not_sent_only_when_a_save_was_made(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                r = self.fresh()
                r.write('b.py', 'b = 1\n')
                # step 4 adds its keep-out lines to .gitignore when they're missing: here they're saved already
                pats = ['.env*', '!.env.example'] + [x.decode() for x in RegistryFilesCases._scanner().KEEP_OUT
                                                     if x != b'.env*'] + ['.aws/credentials']
                r.write('.gitignore', ''.join(x + '\n' for x in pats))
                r.commit('saved, nothing unsaved')
                self._prep(r)
                fail = os.path.join(r.root, 'scan-fails.sh')
                with open(fail, 'w') as f:
                    f.write('#!/bin/sh\nexit 2\n')
                os.chmod(fail, 0o755)
                out, mark = self._run5b2(r, shell, scanner=fail)
                self.assertEqual(mark, 'NOT SENT')
                qs = self._told(self._phase5b(), 'NOT SENT')
                self.assertTrue(qs and not [q for q in qs if re.search(r'(?i)\bI saved\b', q)], qs)
                self.assertTrue(any(re.search(self.SENT_NONE, q) or re.search(r"(?i)didn't send", q) for q in qs), qs)

    def test_6_the_text_says_which_paths_may_change(self):
        flat = re.sub(r'\s+', ' ', self._phase5b())
        self.assertRegex(flat, r'(?i)argo-it-touched')
        self.assertRegex(flat, r'(?i)3a, 3b, 3c or a 3e move')


class ReReviewMiscCases(ArgoItRestartAsksCases):
    """Re-review of 03aef71, findings 2, 4, 5, 6, 7, 8, 10."""

    for _t in [k for k in list(vars(ArgoItRestartAsksCases)) if k.startswith('test')]:
        locals()[_t] = None
    del _t

    def test_f2_same_name_other_server_no_restart_no_ask(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                with tempfile.TemporaryDirectory() as td:
                    self._project(td, True)
                    log, env = self._env(td, 'acme-prod-eu', 'https://somewhere-else:6443')
                    self.assertIn(b'OTHER CLUSTER', self._run(self.CHECK, td, env, shell).stdout)
                    self.assertIn(b'NOT ITS CLUSTER', self._run(self.READ, td, env, shell).stdout)
                    self._run(self.RESTART, td, env, shell)
                    self.assertFalse([c for c in self._calls(log) if 'rollout restart' in c or ' get pods' in c])

    def test_f2_setup_saves_the_server_address(self):
        doc = self._doc()
        i = doc.index('<step name="setup">')
        setup = re.sub(r'\s+', ' ', doc[i:doc.index('</step>', i)])
        self.assertRegex(setup, r'deployment\.k8s_server')
        self.assertIn("kubectl config view --minify --context", setup)

    def test_f7_read_step_stops_have_their_own_lines_with_no_restart_talk(self):
        flat = re.sub(r'\s+', ' ', self._section())
        for mark in ('NO CLUSTER RECORD', 'NOT ITS CLUSTER', 'READ FAILED'):
            i = flat.index('If it prints `%s`' % mark)
            line = re.search(r'"(I[^"]{20,})"', flat[i:i + 900]).group(1)
            self.assertNotRegex(line, r'(?i)restart', '%s talks about a restart: %r' % (mark, line))
            self.assertRegex(flat[i:i + 900], r'(?i)Argo CD', mark)

    def test_f8_names_in_5c_commands_are_quoted(self):
        for f in self._fences(self._section()):
            for l in f.splitlines():
                if l.lstrip().startswith('#'):
                    continue
                spans = [(m.start(), m.end()) for m in re.finditer(r"'[^']*'", l)]  # single quotes: nothing runs
                for m in re.finditer(r'\{(?:namespace|service)\}', l):
                    self.assertTrue(any(a < m.start() < b for a, b in spans), 'unquoted in %r' % l)

    def test_f10_no_record_says_how_to_turn_restarts_on(self):
        flat = re.sub(r'\s+', ' ', self._section())
        for mark in ('NO CLUSTER RECORD', 'CLUSTER UNKNOWN'):
            i = flat.index('If it prints `%s`' % mark)
            self.assertRegex(flat[i:i + 900], r'ask me to record its cluster', mark)
        self.assertRegex(flat, r"(?i)If the user asks to record the app's cluster")


class ReReviewOriginCases(ReviewOriginCases):
    """Re-review of 03aef71, findings 4, 5 and 6."""

    for _t in [k for k in list(vars(ReviewOriginCases)) if k.startswith('test')]:
        locals()[_t] = None
    del _t

    def test_f4_an_scp_path_starting_with_digits_is_a_path_not_a_port(self):
        self.assertEqual(self._split([('remote', 'set-url', '--push', 'origin', 'git@github.com:22/acme/app.git')]),
                         [True, True])
        self.assertEqual(self._split([('remote', 'set-url', '--push', 'origin', 'ssh://git@github.com:22/acme/app.git')]),
                         [False, False])

    def test_f4_the_case_limit_is_written_down(self):
        flat = re.sub(r'\s+', ' ', self._phase())
        self.assertRegex(flat, r'(?i)capital letters alone still count')

    def test_f6_the_redeploy_text_names_no_host(self):
        p = self._phase5b()
        lines = [l for l in p.splitlines() if 'GitHub' in l]
        self.assertEqual(lines, [l for l in lines if 'GitHub Actions workflow mirrors' in l], lines)


class ReReviewKeepOutCases(ArgoItUnsavedCodeCases):
    """Re-review of 03aef71, finding 5: every keep-out file is named."""

    test_1_unsaved_code_stops_before_the_seal_naming_how_many_and_the_first_two = None
    test_2_untracked_look_alikes_are_unsaved_code_and_stop_the_send = None
    test_3_what_is_not_unsaved_code_goes_on = None
    test_4_not_a_make_it_project_no_check = None
    test_5_the_check_comes_before_the_seal_and_its_stop_is_one_true_line = None

    def test_f5_every_keep_out_file_is_named(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                r = self.fresh()
                self._project(r)
                for n in ('a.pem', 'b.key', 'c.db'):
                    r.write(n, 'x\n')
                code, out = self._check(r, shell)
                self.assertEqual(sorted(l for l in out if l.startswith('keep-out: ')),
                                 ['keep-out: a.pem', 'keep-out: b.key', 'keep-out: c.db'], out)
        flat = re.sub(r'\s+', ' ', self._phase())
        i = flat.index('`UNSAVED CODE`')
        self.assertRegex(flat[i:i + 1600], r'(?i)each path after a `keep-out:` line')



class ConfirmRedeployCases(ReReviewRedeployCases):
    """PR #134 confirmation pass, items 1 and 5: a commit a post-commit hook adds after argo-it's save is never sent;
    argo-it's own files and .gitignore count as touched by name, so the pin needn't list them."""

    for _t in [k for k in list(vars(ReReviewRedeployCases)) if k.startswith('test')]:
        locals()[_t] = None
    del _t

    def test_1_a_post_commit_hooks_own_save_is_never_sent(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                r = self.fresh()
                hooks = os.path.join(r.root, 'hooks')
                os.makedirs(hooks)
                with open(os.path.join(hooks, 'post-commit'), 'w') as f:
                    f.write('#!/bin/sh\n[ -n "$IN_HOOK" ] && exit 0\necho "hk = 1" > hk.py\ngit add hk.py\n'
                            'IN_HOOK=1 git commit -q -m "added by a hook"\n')
                os.chmod(os.path.join(hooks, 'post-commit'), 0o755)
                r.append('app.py', 'x = 1\n')
                self._prep(r, hooks)
                before = self._sent_refs(r)
                out, mark = self._run5b2(r, shell)
                self.assertEqual(self._sent_refs(r), before, "the hook's save reached the online copy")
                self.assertFalse(b'hk = 1' in self._sent_objects(r))
                self.assertEqual(mark, 'SAVE ADDED MORE')
                qs = self._told(self._phase5b(), 'SAVE ADDED MORE')
                self.assertTrue(any(re.search(r'(?i)\bsaved\b[^.]{0,40}\bon this computer\b', q)
                                    and re.search(r"(?i)didn't send", q) and re.search(r'(?i)only send what I named', q)
                                    for q in qs), qs)

    def test_5_argo_its_own_files_and_gitignore_count_as_touched(self):
        for shell in ('bash', 'zsh'):
            with self.subTest(shell=shell):
                need_shell(shell)
                r = self.fresh()
                r.write('env/dev/kustomization.yaml', 'resources:\n  - backend.yaml\n')
                r.write('env/dev/backend.yaml', 'kind: Deployment\n')
                r.write('.gitignore', 'node_modules/\n')
                r.commit('argo-it set up')
                r.push()
                r.append('app.py', 'x = 1\n')
                self._prep(r)

                def between():  # 3b adds a setting to a manifest, and a 3e move edits .gitignore: neither recorded
                    r.append('env/dev/backend.yaml', 'metadata: {}\n')
                    r.append('.gitignore', '.env*\n')
                out, mark = self._run5b2(r, shell, between)
                self.assertIsNone(mark, [(s_, c.stdout[-200:]) for s_, c in out])
                self.assertEqual(self._ref(r, 'main'), self._head(r))
                r.write('late.py', 'late = 1\n')  # control: someone else's new file still stops a second send
                r.append('app.py', 'y = 2\n')
                out, mark = self._run5b2(r, shell, lambda: r.write('later.py', 'z = 1\n'))
                self.assertEqual(mark, 'CHANGED SINCE THE ASK')


class ConfirmClusterCases(ArgoItRestartAsksCases):
    """PR #134 confirmation pass, items 2, 3 and 4."""

    for _t in [k for k in list(vars(ArgoItRestartAsksCases)) if k.startswith('test')]:
        locals()[_t] = None
    del _t

    def test_2_a_name_that_would_run_something_is_refused(self):
        for shell in ('bash', 'zsh'):
            for bad in ('$(touch pwned)', '`touch pwned`', 'Acme_App', ''):
                with self.subTest(shell=shell, bad=bad):
                    need_shell(shell)
                    with tempfile.TemporaryDirectory() as td:
                        self._project(td, True)
                        log, env = self._env(td, 'acme-prod-eu')
                        for block in (self.READ, self.RESTART, self.LOGS):
                            cp = self._run(block.replace('{namespace}', bad), td, env, shell)
                            self.assertIn(b'BAD NAME', cp.stdout)
                        self.assertFalse(os.path.exists(os.path.join(td, 'pwned')), 'a name ran a command')
                        self.assertFalse([c for c in self._calls(log) if ' get pods' in c or 'rollout restart' in c
                                          or ' logs ' in c])
        flat = re.sub(r'\s+', ' ', self._section())
        i = flat.index('If it prints `BAD NAME`')
        self.assertRegex(flat[i:i + 600], r'"I[^"]{20,}"')

    def test_3_a_trailing_slash_or_capitals_in_scheme_and_host_is_the_same_server(self):
        for shell in ('bash', 'zsh'):
            for now, ok in (('HTTPS://K8S.Acme.example:6443/', True), ('https://k8s.acme.example:6443///', True),
                            ('https://k8s.acme.example:6443/Other', False), ('https://other.example:6443', False)):
                with self.subTest(shell=shell, now=now):
                    need_shell(shell)
                    with tempfile.TemporaryDirectory() as td:
                        self._project(td, True)
                        log, env = self._env(td, 'acme-prod-eu', now)
                        self.assertEqual(self._run(self.CHECK, td, env, shell).returncode == 0, ok)

    def test_4_no_record_is_true_when_only_local_clusters_are_known(self):
        flat = re.sub(r'\s+', ' ', self._section())
        for mark in ('NO CLUSTER RECORD', 'CLUSTER UNKNOWN'):
            i = flat.index('If it prints `%s`' % mark)
            self.assertRegex(flat[i:i + 1200], r"(?i)only knows local clusters, so there's none to record yet", mark)
        self.assertRegex(flat, r"(?i)If the user asks to record the app's cluster[^.]{0,200}only local clusters")


if __name__ == '__main__':
    unittest.main()
