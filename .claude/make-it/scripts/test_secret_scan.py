#!/usr/bin/env python3
"""Tests for secret-scan.py, driven only through its command line.

Run standalone:  python3 .claude/make-it/scripts/test_secret_scan.py -v
(`secret-scan.py --self-test` runs this file.)

Every test builds a throwaway repo (bare origin + work clone), plants secret
values, runs the scanner, and asserts (1) the exact stdout, (2) the exit code,
(3) that no planted value -- not even an 8-byte slice of it -- appears in
stdout or stderr.  Python 3.9 compatible, stdlib only.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
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


def kv(name, value, sep=' = ', q='"'):
    return '%s%s%s%s%s\n' % (name, sep, q, value, q)


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

    SHAPES = ('API_KEY = "sk-1234567890abcdef"\nPASSWORD = \'hunter2hunter2\'\n')
    SHAPE_VALUES = ['sk-1234567890abcdef', 'hunter2hunter2']

    def test_j_value_shapes_unsaved(self):
        r = self.fresh()
        r.append('app.py', self.SHAPES + 'SECRET_KEY = "abcdefghijk"\n')
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
                + 'token = self.token_value\nTOKEN = abcdefghijkl\n')
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
        v1, v2 = 'crlf-secret-value-1234', 'crlf-unquoted-1234'
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
        v = 'hunter2hunter2'
        hit = ['config.ini', 'a.cfg', 'a.conf', 'a.properties', 'a.toml', 'a.yaml', 'a.yml', 'Dockerfile',
               'Dockerfile.dev', 'docker-compose.dev', 'docker-compose.override.yml', '.env.example',
               'prod.env', 'sub/x.env.sample']
        miss = ['run.sh', 'notes.txt', 'app.js', 'a.py', 'README.md', 'config.json']
        for n in hit + miss:
            r.write(n, 'PASSWORD=%s\n' % v)
        self.check(r.scan(), new=['%s:1' % n for n in sorted(hit)], secrets=[v])

    def test_unquoted_value_shapes_in_a_compose_file(self):
        r = self.fresh()
        vs = ['supersecret1', 'hunter2hunter2', 'abc12345#frag']
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
        v1, v2 = 'supersecret1', 'hunter2hunter2'
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
        v = 'hunter2hunter2'
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
        r.write('docker-compose.yml', '      - DATABASE_URL=postgres://app:MyPassword=2024xyzQ@db/app\n')
        res = r.scan()
        self.check(res, secrets=['MyPassword=2024xyzQ'])
        self.assertNotIn(b'MyPassword', res.out + res.err)

    def test_value_is_not_reread_as_a_name_in_py(self):
        r = self.fresh()
        r.write('u.py', 'url = "postgres://app:MyPassword=2024xyzQ@db/app"\n')
        res = r.scan()
        self.check(res, secrets=['MyPassword=2024xyzQ'])
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
        v = 'sk-live-realkey-123456'
        self._ignore_env(r)
        r.write('.env.example', 'API_KEY=%s\n' % v)
        self.check(r.scan(), new=['.env.example:1'], secrets=[v])

    def test_ignored_nested_env_example_is_still_scanned(self):
        r = self.fresh()
        v = 'sk-live-realkey-123456'
        self._ignore_env(r)
        r.write('config/.env.example', 'API_KEY=%s\n' % v)
        self.check(r.scan(), new=['config/.env.example:1'], secrets=[v])

    def test_ignored_env_local_stays_no_hit(self):
        r = self.fresh()
        v = 'sk-live-realkey-123456'
        self._ignore_env(r)
        r.write('.env.local', 'API_KEY=%s\n' % v)
        self.check(r.scan(), secrets=[v])

    def test_env_example_in_ignored_folder_is_not_scanned(self):
        r = self.fresh()
        v = 'sk_test_realisticvalue123'
        r.write('.gitignore', 'node_modules/\n')
        r.commit('ignore')
        r.write('node_modules/pkg/.env.example', 'API_KEY=%s\n' % v)
        self.check(r.scan(), secrets=[v], code=0)

    def test_root_env_example_hidden_by_excludes_file_is_still_a_hit(self):
        r = self.fresh()
        v = 'sk_test_rootvalue12345'
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
        v1, v2 = 'abcdefghijkl', 'hunter2hunter2'
        r.write('old.cfg', ('NAME=demo\nTOKEN=%s\n' % v1).encode('utf-16-le'))
        r.write('new.cfg', ('PASSWORD=%s\n' % v2).encode('utf-16-le'))
        self.check(r.scan(), unsaved=['old.cfg:2'], new=['new.cfg:1'], secrets=[v1, v2])

    def test_unknown_working_tree_encoding_is_could_not_check(self):
        r = self.fresh()
        r.write('.gitattributes', '*.cfg text working-tree-encoding=X-NOT-A-CODEC\n')
        r.commit('attr')
        r.write('a.cfg', 'PASSWORD=hunter2hunter2\n')
        res = r.scan()
        self.assertEqual(res.code, 2)
        self.assertEqual(res.out, b'')
        self.no_leak(res, ['hunter2hunter2'])

    def test_inline_map_and_list_values_in_compose_are_hits(self):
        r = self.fresh()
        v1, v2 = 'supersecret1', 'supersecret12'
        r.write('docker-compose.yml', '    environment: {POSTGRES_PASSWORD: "%s"}\n'
                '    env: ["PASSWORD=%s"]\n' % (v1, v2))
        self.check(r.scan(), new=['docker-compose.yml:1',
                                  'docker-compose.yml:2'], secrets=[v1, v2])

    def test_value_inside_inline_map_is_not_reread_as_a_name(self):
        r = self.fresh()
        r.write('docker-compose.yml', 'X: {postgres://app:MyPassword=2024xyzQ@db}\n')
        res = r.scan()
        self.check(res, secrets=['MyPassword=2024xyzQ'])
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
        v = 'sk_test_projectignore123'
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
        v = 'zq9FAKEsecretA1xyz'
        r.write('app.py', BASE + kv('API_KEY', v))
        r.git('add', 'app.py')
        r.git('update-index', flag, 'app.py')
        r.write('app.py', b'\0\0binary junk\n')
        self.check(r.scan(), unsaved=['app.py:2'], secrets=[v])

    def test_1_name_started_inside_a_string_literal_leaks_nothing(self):
        r = self.fresh()
        v = 'Zk9/c2VjcmV0QPwd='
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
        v = 'zq9FAKEsecretM1xyz'
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
        v = 'zq9FAKEsecretC1xyz'
        os.symlink('API_KEY="%s"' % v, r.path('link.py'))
        self.check(r.scan(), new=['link.py:1'], secrets=[v])

    def test_5a_new_file_with_clean_filter_is_scanned_as_stored(self):
        r = self.fresh()
        v = 'zq9FAKEsecretD1xyz'
        r.git('config', 'filter.r13.clean', "tr 'A-Za-z' 'N-ZA-Mn-za-m'")
        r.write('.gitattributes', 'settings.py filter=r13\n')
        r.write('settings.py', 'NCV_XRL = "md9SNXRfrpergQ1klm"\n')
        self.check(r.scan(), new=['settings.py:1'], secrets=[v])

    def test_5b_unsaved_with_nul_stripping_clean_filter(self):
        r = self.fresh()
        v = 'zq9FAKEsecretD2xyz'
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
        v1, v2, v3 = 'zq9FAKEsecretG1aa', 'zq9FAKEsecretG1bb', 'zq9FAKEsecretG1cc'
        r.write('db.py', 'conn = psycopg2.connect("dbname=" + name, password="%s")\n' % v1)
        r.write('api.js', 'fetch(base + "?user=" + u, { apiKey: "%s" });\n' % v2)
        r.write('pr.py', 'print("user=", user); API_KEY = "%s"\n' % v3)
        self.check(r.scan(), new=['api.js:1', 'db.py:1', 'pr.py:1'],
                   secrets=[v1, v2, v3])

    def test_8_triple_quoted_value_is_not_an_empty_literal(self):
        r = self.fresh()
        v = 'zq9FAKEsecretF1aaa'
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
        r.write('app.js', 'const pw = prod ? "AcmeProdPassword" : "localdevpass1";\n')
        r.write('cfg.js', 'const c = { password: isProd ? "AdminPassword" : "devdevdevdev" };\n')
        r.write('App.java', 'String t = prod ? "ghp_MySecretToken" : "devtokenvalue";\n')
        r.write('sq.js', "const pw = prod ? 'AcmeProdPassword' : 'localdevpass1';\n")
        res = r.scan()
        blob = res.out + b'\n' + res.err
        for v in ('AcmeProdPassword', 'AdminPassword', 'ghp_MySecretToken'):
            self._no_slice(res, v)
            self.assertNotIn(_b(v), blob)
        self.check(res)

    def _one(self, rel, text, hit, secret):
        r = self.fresh()
        r.write(rel, text)
        self.check(r.scan(), new=[hit], secrets=[secret])

    def test_2a_json_loads_literal_body_is_scanned(self):
        self._one('a.py', 'data = json.loads(\'{"password": "hunter2hunter2"}\')\n',
                  'a.py:1', 'hunter2hunter2')

    def test_2b_json_parse_literal_body_is_scanned(self):
        self._one('b.js', 'const c = JSON.parse(\'{"apiKey":"sk-live-abcdef123456"}\');\n',
                  'b.js:1', 'sk-live-abcdef123456')

    def test_2c_curl_json_body_in_shell_is_scanned(self):
        self._one('seed.sh', 'curl -d \'{"username":"admin","password":"zq9FAKEsecretSH1"}\' http://localhost/api\n',
                  'seed.sh:1', 'zq9FAKEsecretSH1')

    def test_2d_compose_command_export_is_scanned(self):
        self._one('docker-compose.yml', '    command: sh -c "export X=1; PASSWORD=zq9FAKEcompose1"\n',
                  'docker-compose.yml:1', 'zq9FAKEcompose1')

    def test_2e_compose_command_and_chain_is_scanned(self):
        self._one('c2/docker-compose.yml',
                  '    command: bash -c "pip install x && SECRET_KEY=zq9FAKEcompose2 python app.py"\n',
                  'c2/docker-compose.yml:1', 'zq9FAKEcompose2')

    def test_3_lexer_misread_never_leaks_a_base64_slice(self):
        r = self.fresh()
        v = 'Zk9/c2VjcmV0QPwd='
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
        v = 'sk-live-lfs-secret-12345'
        r.write('settings.json', '{"apiKey": "%s"}\n' % v)
        self.check(r.scan(), new=['settings.json:1'], secrets=[v])

    @unittest.skipUnless(shutil.which('git-lfs'), 'git-lfs not installed')
    def test_4b_missing_lfs_object_fails_closed(self):
        r = self._lfs_repo()
        v = 'sk-live-lfs-secret-12345'
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
             "  --from-literal=JWT_SECRET='zq9FAKEjwtA1xyz9' \\\n"
             "  --from-literal=POSTGRES_PASSWORD='zq9FAKEpgB1xyz9'\n")

    def _from_literal(self, rel):
        r = self.fresh()
        r.write(rel, self.SETUP)
        self.check(r.scan(), new=[rel + ':2', rel + ':3'],
                   secrets=['zq9FAKEjwtA1xyz9', 'zq9FAKEpgB1xyz9'])

    def test_1a_from_literal_in_shell_script_hits(self):
        self._from_literal('setup.sh')

    def test_1b_from_literal_in_onboarding_doc_hits(self):
        self._from_literal('ONBOARDING-K8S.md')

    def test_1c_terraform_var_equals_hits(self):
        self._one('infra.sh', 'terraform apply -var=db_password="zq9FAKEtfC1xyz9"\n',
                  'infra.sh:1', 'zq9FAKEtfC1xyz9')

    def test_1d_helm_set_equals_hits(self):
        self._one('deploy.sh', 'helm install x --set=auth.password="zq9FAKEhelmD1x9"\n',
                  'deploy.sh:1', 'zq9FAKEhelmD1x9')

    def test_1e_yaml_item_from_literal_hits(self):
        self._one('job.yml', '        - --from-literal=password=zq9FAKEyamlE1x9\n',
                  'job.yml:1', 'zq9FAKEyamlE1x9')

    def _clean(self, files, secret):
        r = self.fresh()
        for rel, text in files.items():
            r.write(rel, text)
        res = r.scan()
        self.check(res, secrets=[secret])
        self._no_slice(res, secret)
        self.assertNotIn(_b(secret), res.out + res.err)

    def test_2_multiline_ternary_never_prints_the_value(self):
        self._clean({'ml.js': 'const pw = isProd ?\n  "AcmeProdPassword" : "localdevpass1";\n',
                     'ml.php': "$pw = $isProd ?\n  'AcmeProdPassword' : 'localdevpass1';\n"},
                    'AcmeProdPassword')

    def test_3_shell_test_never_prints_the_value(self):
        self._clean({'yoda.sh': 'if [ "AcmeProdPassword" = "$(cat /run/pw)" ]; then echo ok; fi\n',
                     'yoda2.sh': 'if [[ "AcmeProdPassword" = "$(cat /run/pw)" ]]; then echo ok; fi\n'},
                    'AcmeProdPassword')

    @unittest.skipUnless(shutil.which('git-lfs'), 'git-lfs not installed')
    def test_5a_lfs_unsaved_edit_hits(self):
        r = ReReview3Cases._lfs_repo(self)
        r.write('s.json', '{"name": "demo"}\n')
        r.commit('s')
        r.push()
        v = 'sk-live-lfs-unsaved-1234'
        r.append('s.json', '"apiKey": "%s"\n' % v)
        self.check(r.scan(), unsaved=['s.json:2'], secrets=[v])

    @unittest.skipUnless(shutil.which('git-lfs'), 'git-lfs not installed')
    def test_5b_lfs_saved_commit_hits(self):
        r = ReReview3Cases._lfs_repo(self)
        r.branch('feat')
        v = 'sk-live-lfs-saved-5678'
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
                  'CONFIG = {\n    "debug": False,  # needed in prod?\n    "password": "zq9FAKEdictP1xyz",\n',
                  'settings.py:3', 'zq9FAKEdictP1xyz')

    def test_1b_comment_question_mark_keeps_js_key(self):
        self._one('cfg.js',
                  'module.exports = {\n  retries: 3, // enough?\n  "apiKey": "zq9FAKEjsP2xyz12",\n',
                  'cfg.js:3', 'zq9FAKEjsP2xyz12')

    def test_1c_comment_question_mark_after_open_brace(self):
        self._one('s.py', 'DB = {  # which db?\n    "password": "zq9FAKEbraceP7xy",\n',
                  's.py:2', 'zq9FAKEbraceP7xy')

    def test_1d_comment_question_mark_after_yaml_parent(self):
        self._one('c.yml', 'env:  # needed?\n  "PASSWORD": "zq9FAKEyamlP6xyz"\n',
                  'c.yml:2', 'zq9FAKEyamlP6xyz')

    def test_2a_comment_only_line_ending_in_question_mark_keeps_key(self):
        self._one('g.py', 'CONFIG = {\n    # rotate?\n    "password": "zq9FAKEguardG1xyz",\n',
                  'g.py:3', 'zq9FAKEguardG1xyz')

    def test_2b_yaml_parent_without_question_mark_keeps_key(self):
        self._one('g.yml', 'env:\n  "PASSWORD": "zq9FAKEguardG2xyz"\n',
                  'g.yml:2', 'zq9FAKEguardG2xyz')

    def test_3_ternary_with_trailing_comment_never_prints_the_value(self):
        self._clean('t1.js',
                    'const pw = isProd ? // production\n  "AcmeProdPassword" : "localdevpass1";\n',
                    'AcmeProdPassword')

    def test_4_blank_line_after_question_mark_never_prints_the_value(self):
        self._clean('t2.js',
                    'const pw = isProd ?\n\n  "AcmeProdPassword" : "localdevpass1";\n',
                    'AcmeProdPassword')


class QuotedKeyCases(Base):
    """Owner amendments: nothing from file contents is printed. A hit is `file:line` or no hit."""

    PLANT = 'AcmeProdPassword'
    VAL = 'localdevpass1'

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
        r.write('t.js', 'const pw = isProd ?\n\n  "localdevpass1";\n')
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
        r.write('w.py', 'KEYS = {"sk_live_AcmeSecretKey": "acme-corporation"}\n')
        res = r.scan()
        self.check(res, new=['w.py:1'], secrets=['sk_live_AcmeSecretKey', 'acme-corporation'])
        self._leak_free(res, ['sk_live_AcmeSecretKey', 'acme-corporation'])

    def test_5_json_key_that_is_the_value_looking_string_hits_and_is_not_printed(self):
        r = self.fresh()
        r.write('x.json', '{"AcmeProdPassword": "zq9FAKEjsonX1xyz"}\n')
        res = r.scan()
        self.check(res, new=['x.json:1'], secrets=['zq9FAKEjsonX1xyz'])
        self.assertNotIn(b'AcmeProdPassword', res.out + res.err)


class OutputOrderCases(Base):
    """Hits sort by (file, line) and de-duplicate per line; blank lines must not slow the scan."""

    def test_a_two_quoted_keys_on_one_line_print_once(self):
        r = self.fresh()
        r.write('t.js', 'const c = { "password": "zq9FAKEdupA1xyz9", "apiKey": "zq9FAKEdupB1xyz9" };\n')
        self.check(r.scan(), new=['t.js:1'], secrets=['zq9FAKEdupA1xyz9', 'zq9FAKEdupB1xyz9'])

    def test_b_order_is_file_then_line(self):
        r = self.fresh()
        r.write('a.json', '{"password": "zq9FAKEsortC1xy9"}\n')
        r.write('a.py', 'API_KEY = "zq9FAKEsortD1xy9"\n')
        self.check(r.scan(), new=['a.json:1', 'a.py:1'],
                   secrets=['zq9FAKEsortC1xy9', 'zq9FAKEsortD1xy9'])

    def test_c_long_line_then_many_blank_lines_is_fast(self):
        r = self.fresh()
        r.write('big.py', 'x = "' + 'a' * 2000000 + '"\n' + '\n' * 10000 + 'API_KEY = "zq9FAKEspeedE1x9"\n')
        t = time.time()
        cp = subprocess.run([sys.executable, SCRIPT, '--repo', r.work],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        res = Result(cp, time.time() - t)
        self.check(res, new=['big.py:10002'], secrets=['zq9FAKEspeedE1x9'])


class ValueStringCases(Base):
    """A string that is itself a VALUE is scanned inside too (amendment, last bullet)."""

    def _one(self, rel, text, v):
        r = self.fresh()
        r.write(rel, text)
        res = r.scan()
        self.check(res, new=[rel + ':1'], secrets=[v])
        self.assertEqual(res.code, 1)

    def test_a_python_assignment_of_a_command_string(self):
        self._one('a.py', 'cmd = \'API_KEY="zq9FAKEsecretV1xyz" ./deploy.sh\'\n', 'zq9FAKEsecretV1xyz')

    def test_b_python_keyword_argument_command_string(self):
        self._one('b.py', 'subprocess.run(args=\'API_KEY="zq9FAKEsecretV2xyz" ./deploy.sh\', shell=True)\n',
                  'zq9FAKEsecretV2xyz')

    def test_c_js_object_property_command_string(self):
        self._one('c.js', 'const job = { cmd: \'export API_KEY="zq9FAKEsecretV3xyz"\' };\n', 'zq9FAKEsecretV3xyz')

    def test_d_compose_command_string(self):
        self._one('docker-compose.yml', '    command: "sh -c \'export PASSWORD=zq9FAKEsecretV4xyz; ./run\'"\n',
                  'zq9FAKEsecretV4xyz')

    def test_e_guard_url_with_password_equals_stays_clean(self):
        r = self.fresh()
        r.write('d.py', 'url = "postgres://app:MyPassword=2024xyzQ@db/app"\n')
        res = r.scan()
        self.check(res, secrets=['MyPassword=2024xyzQ'])
        self.assertEqual(res.code, 0)


class AdversarialRound2Cases(Base):
    """Counterexamples from task-1-adv2.md, each on its exact input."""

    def test_1_password_value_with_equals_is_never_printed(self):
        r = self.fresh()
        r.write('docker-compose.yml',
                'services:\n  a:\n'
                '    command: ["./wait-for", "postgresql+asyncpg://app:MyPassword=2024xyzQ@db/app"]\n'
                '    x: 1\n'
                '      - postgresql+asyncpg://app:MyPassword=2024xyzA@db/app\n')
        r.write('Dockerfile', 'FROM x\nENV DATABASE_URL postgresql+asyncpg://app:MyPassword=2024xyzB@db/app\n')
        r.write('settings.toml', 'urls = ["postgresql+psycopg2://app:MyPassword=2024xyzC@db/app"]\n')
        r.write('braces.yml', 'X: {postgresql+asyncpg://app:MyPassword=2024xyzQ@db}\n')
        r.write('k8s.yaml', 'args:\n          - -Dspring.datasource.password=MyPassword=2024xyzQ\n')
        r.write('fr.yml', 'cl\u00e9: MyPassword=2024xyzQ\n')
        res = r.scan()
        self.assertEqual(res.code, 1, 'stderr=%r' % res.err[:300])
        self.assertEqual(res.lines, [L_UNSAVED, L_NEW, 'Dockerfile:2', 'braces.yml:1',
                                     'docker-compose.yml:3', 'docker-compose.yml:5', 'fr.yml:1',
                                     'k8s.yaml:2', 'settings.toml:1', L_SAVED])
        for v in ('MyPassword', '2024xyz'):
            self.assertNotIn(_b(v), res.out + res.err)
        self.no_leak(res, ['MyPassword=2024xyzQ'])

    def test_2_quoted_assignments_inside_literals_in_non_config_files(self):
        r = self.fresh()
        r.write('deploy.sh', "#!/bin/sh\nssh app@prod.example.net 'export DB_PASSWORD=\"zq9FAKEsecretS1xyz\"; ./migrate'\n")
        r.write('run.py', "import subprocess\nsubprocess.run('API_KEY=\"zq9FAKEsecretP1xyz\" ./deploy.sh', shell=True)\n")
        r.write('job.js', "const { execSync } = require('child_process');\n"
                          "execSync(`SECRET_KEY='zq9FAKEsecretJ1xyz' node worker.js`);\n")
        r.write('README.md', '# App\nBefore starting, run `export API_KEY="zq9FAKEsecretM1xyz"` in your shell.\n')
        vs = ['zq9FAKEsecretS1xyz', 'zq9FAKEsecretP1xyz', 'zq9FAKEsecretJ1xyz', 'zq9FAKEsecretM1xyz']
        self.check(r.scan(), new=['README.md:2', 'deploy.sh:2', 'job.js:2', 'run.py:2'], secrets=vs)

    def test_3_yaml_value_ending_in_question_mark_does_not_hide_next_key(self):
        r = self.fresh()
        v = 'zq9FAKEsecretY2xyz'
        r.write('queries.yml', 'find_user: SELECT * FROM users WHERE id = ?\n"db_password": "%s"\n' % v)
        r.write('ctl.yml', 'find_user: SELECT * FROM users WHERE id = 1\n"db_password": "%s"\n' % v)
        self.check(r.scan(), new=['ctl.yml:2', 'queries.yml:2'], secrets=[v])


# ------------------------------------------------- adversarial round 3 (last)
class AdversarialRound3Cases(Base):
    PLACEHOLDER_TXT = b'name = "demo"\nAPI_KEY = "xxxxxxxxxxxxxxxxxxxx"\n'
    FILLED = b'name = "demo"\nAPI_KEY = "zq9FAKEsecretF1xyzwq"\n'
    SECRET = 'zq9FAKEsecretF1xyzwq'

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
        v = ['zq9FAKEsecretD%dxyzw' % i for i in range(1, 6)]
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
        v = ['zq9FAKEsecretE%dxyzw' % i for i in range(1, 4)]
        r.write('a.ts', 'class A {}\nthis.config!.apiKey = "%s";\n' % v[0])
        r.write('b.js', 'const Client = 1;\nnew Client().token = "%s";\n' % v[1])
        r.write('c.py', 'clients = {}\nclients["prod"].secret = "%s"\n' % v[2])
        r.commit('glued names 2')
        self.check(r.scan(), saved=['a.ts:2', 'b.js:2', 'c.py:2'], secrets=v)

    def test_3c_control_name_like_word_after_plus_in_base64_run_is_no_hit(self):
        # Like ReReview3Cases.test_3 (which covers `/`): the lookbehind's reason to exist, for `+`.
        r = self.fresh()
        r.write('app.yml', 'description: use key Zk9+c2VjcmV0QPwd=abcdefgh1\nnote: Zk9/c2VjcmV0QPwd=abcdefgh1\n')
        self.check(r.scan(), secrets=['Zk9+c2VjcmV0QPwd=abcdefgh1'])


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
        r.write('app.yml', 'name: demo\nurl: "/token=abcdefgh12345"\n')
        self.check(r.scan(), secrets=['abcdefgh12345'])

    def test_3b_quoted_url_path_starting_with_name_source_is_no_hit(self):
        r = self.fresh()
        r.write('call.js', "const x = 1;\nfetch(\"/token='abcdefgh12345'\")\n")
        self.check(r.scan(), secrets=['abcdefgh12345'])

    def test_4_base64_run_starting_with_slash_is_no_hit(self):
        r = self.fresh()
        r.write('app.yml', 'description: use key /c2VjcmV0QPwd=abcdefgh1\n')
        self.check(r.scan(), secrets=['c2VjcmV0QPwd=abcdefgh1'])

    def test_5_protocol_relative_url_password_is_still_a_hit(self):
        r = self.fresh()
        r.write('proxy.yml', 'upstream: "//app:MyPassword=2024xyzQ@db/app"\n')
        self.check(r.scan(), new=['proxy.yml:1'], secrets=['MyPassword=2024xyzQ', '2024xyzQ'])


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
        r.append('app.py', kv('API_KEY', 'zq9FAKEcommitted1234'))
        r.commit('key')
        r.append('app.py', kv('PASSWORD', 'zq9FAKEunsaved5678'))
        res = self._run(r.work)
        self.check(res, unsaved=['app.py:3'], saved=['app.py:2'],
                   secrets=['zq9FAKEcommitted1234', 'zq9FAKEunsaved5678'])

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


if __name__ == '__main__':
    unittest.main()
