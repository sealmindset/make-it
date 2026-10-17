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
        self.check(r.scan(), unsaved=['app.py:2: PASSWORD'], secrets=[v1, v2])

    def test_b_untracked_file(self):
        r = self.fresh()
        v = 'untracked-secret-value-9012'
        r.write('a.py', kv('TOKEN', v))
        self.check(r.scan(), new=['a.py:1: TOKEN'], secrets=[v])

    def test_c_never_pushed_branch(self):
        r = self.fresh()
        v = 'committed-secret-value-1234'
        r.branch()
        r.append('app.py', kv('API_KEY', v))
        r.commit('key')
        self.check(r.scan(), saved=['app.py:2: API_KEY'], secrets=[v])

    def test_d_added_then_removed_in_unsent_commits_still_a_hit(self):
        # QUESTION FOR THE OWNER: the brief says "added then removed (no hit)", but its scope rule
        # (every commit in HEAD --not --remotes, added lines only) and the old harness both report
        # it: pushing the branch sends the secret in history.  This test follows the scope rule.
        r = self.fresh()
        v = 'added-then-removed-value-777'
        r.branch()
        r.append('app.py', kv('API_KEY', v))
        r.commit('add')
        r.write('app.py', BASE)
        r.commit('rm')
        self.check(r.scan(), saved=['app.py:2: API_KEY'], secrets=[v])

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
        self.check(r.scan(), saved=['app.py:2: API_KEY'], secrets=[v])

    SHAPES = ('API_KEY = "sk-1234567890abcdef"\nPASSWORD = \'hunter2hunter2\'\n')
    SHAPE_VALUES = ['sk-1234567890abcdef', 'hunter2hunter2']

    def test_j_value_shapes_unsaved(self):
        r = self.fresh()
        r.append('app.py', self.SHAPES + 'SECRET_KEY = "abcdefghijk"\n')
        self.check(r.scan(), unsaved=['app.py:2: API_KEY', 'app.py:3: PASSWORD', 'app.py:4: SECRET_KEY'],
                   secrets=self.SHAPE_VALUES + ['abcdefghijk'])

    def test_k_value_shapes_untracked(self):
        r = self.fresh()
        r.write('k.py', self.SHAPES)
        self.check(r.scan(), new=['k.py:1: API_KEY', 'k.py:2: PASSWORD'], secrets=self.SHAPE_VALUES)

    def test_l_value_shapes_unsent_commit(self):
        r = self.fresh()
        r.branch()
        r.append('app.py', self.SHAPES)
        r.commit('k')
        self.check(r.scan(), saved=['app.py:2: API_KEY', 'app.py:3: PASSWORD'], secrets=self.SHAPE_VALUES)

    V_COMMITTED, V_UNSTAGED = 'committed-secret-value-1234', 'unstaged-secret-value-5678'

    def _committed_plus_unsaved(self, r):
        r.branch()
        r.append('app.py', kv('API_KEY', self.V_COMMITTED))
        r.commit('key')
        r.append('app.py', kv('PASSWORD', self.V_UNSTAGED))

    def _check_m(self, r, via_cwd=False):
        self.check(r.scan(via_cwd=via_cwd), unsaved=['app.py:3: PASSWORD'], saved=['app.py:2: API_KEY'],
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
        self.check(r.scan(), unsaved=['app.py:2: PASSWORD'], secrets=[self.V_UNSTAGED])

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
        self.check(r.scan(), unsaved=['my file.py:2: PASSWORD'],
                   saved=['my file.py:1: TOKEN', 'naïve.py:1: API_KEY'], secrets=[v1, v2, v3])

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
        self.check(r.scan(), unsaved=['lib/placeholder_image.py:1: TOKEN'],
                   saved=['lib/placeholder_image.py:1: API_KEY'], secrets=[v1, v2])

    def test_t_untracked_placeholder_path_and_other(self):
        r = self.fresh()
        v1, v2 = 'real-secret-value-5678', 'real-secret-value-9999'
        r.write('lib/placeholder_image.py', kv('TOKEN', v1))
        r.write('lib/other.py', kv('TOKEN', v2))
        r.write('a/b/c/deep.py', kv('TOKEN', v2))
        self.check(r.scan(), new=['a/b/c/deep.py:1: TOKEN', 'lib/other.py:1: TOKEN',
                                  'lib/placeholder_image.py:1: TOKEN'], secrets=[v1, v2])

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
        self.check(r.scan(), new=['TODO.py:1: TOKEN'], secrets=[v])


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
        self.check(r.scan(), unsaved=['app.py:2: PASSWORD'], secrets=[v])

    def test_w2_unsent_commit_latin1_first_then_secret(self):
        r = self.fresh()
        v = 'committed-secret-value-1234'
        r.branch()
        r.write('a_seed.csv', b'id,name\n1,caf\xe9\n')
        r.append('app.py', kv('API_KEY', v))
        r.commit('both')
        self.check(r.scan(), saved=['app.py:2: API_KEY'], secrets=[v])

    def test_w3_unsent_commit_secret_first_latin1_after(self):
        r = self.fresh()
        v = 'committed-secret-value-1234'
        r.branch()
        r.write('z_seed.csv', b'id,name\n1,caf\xe9\n')
        r.append('app.py', kv('API_KEY', v))
        r.commit('both')
        self.check(r.scan(), saved=['app.py:2: API_KEY'], secrets=[v])

    def test_w4_untracked_latin1_file_holding_secret(self):
        r = self.fresh()
        v = 'untracked-secret-value-9012'
        r.write('l1.py', b'caf\xe9\n' + _b(kv('TOKEN', v)))
        self.check(r.scan(), new=['l1.py:2: TOKEN'], secrets=[v])

    def test_w5_latin1_byte_on_the_secret_line(self):
        r = self.fresh()
        v1, v2 = b'caf\xe9-committed-secret-1234', b'caf\xe9-unsaved-secret-5678'
        r.branch()
        r.append('app.py', b'API_KEY = "' + v1 + b'"\n')
        r.commit('k')
        r.append('app.py', b'PASSWORD = "' + v2 + b'"\n')
        self.check(r.scan(), unsaved=['app.py:3: PASSWORD'], saved=['app.py:2: API_KEY'], secrets=[v1, v2])

    def test_w6_untracked_latin1_byte_on_the_secret_line(self):
        r = self.fresh()
        v = b'caf\xe9-untracked-secret-9012'
        r.write('l2.py', b'TOKEN = "' + v + b'"\n')
        self.check(r.scan(), new=['l2.py:1: TOKEN'], secrets=[v])

    def _bundle(self):
        # ~2 MB on one line, no newline
        return (b'QUJD' * 520000)

    def test_x1_two_mb_single_line_untracked_and_staged(self):
        r = self.fresh()
        v = 'unstaged-secret-value-5678'
        r.write('a_bundle.js', self._bundle())
        r.append('app.py', kv('PASSWORD', v))
        res = r.scan()
        self.check(res, unsaved=['app.py:2: PASSWORD'], secrets=[v])
        self.assertLess(res.secs, 20)
        r.git('add', 'a_bundle.js')  # now it is an added line in `git diff HEAD`
        res = r.scan()
        self.check(res, unsaved=['app.py:2: PASSWORD'], secrets=[v])
        self.assertLess(res.secs, 20)

    def test_x1b_two_mb_single_line_with_secret_at_the_end(self):
        r = self.fresh()
        v = 'bundle-secret-value-0001'
        r.write('big.py', self._bundle() + b'\n' + _b(kv('TOKEN', v)))
        res = r.scan()
        self.check(res, new=['big.py:2: TOKEN'], secrets=[v])
        self.assertLess(res.secs, 20)

    def test_x2_nul_after_9000_bytes_is_text(self):
        r = self.fresh()
        v1, v2 = 'committed-secret-value-1234', 'after-nul-secret-value-77'
        r.branch()
        r.write('a_big.txt', b'a' * 9000 + b'\nx\x00y\n' + _b(kv('TOKEN', v2)))
        r.append('app.py', kv('API_KEY', v1))
        r.commit('k')
        self.check(r.scan(), saved=['a_big.txt:3: TOKEN', 'app.py:2: API_KEY'], secrets=[v1, v2])

    def test_x3_double_quote_in_committed_file_name(self):
        r = self.fresh()
        v = 'committed-secret-value-1234'
        r.branch()
        r.write('q"x.py', kv('API_KEY', v))
        r.commit('k')
        self.check(r.scan(), saved=['q"x.py:1: API_KEY'], secrets=[v])


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
        self.check(r.scan(), unsaved=['app.py:2: TOKEN'], secrets=vs)

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
        self.check(r.scan(), unsaved=['app.py:2: PASSWORD', 'app.py:3: TOKEN'], secrets=[v1, v2])

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
        self.check(r.scan(), unsaved=['app.py:27: TOKEN'], secrets=[v])

    def test_saved_line_number_is_from_the_commit_that_added_it(self):
        r = self.fresh()
        v = 'added-early-secret-1234'
        r.branch()
        r.append('app.py', kv('API_KEY', v))
        r.commit('add')
        r.write('app.py', '# header\n' + BASE + kv('API_KEY', v))
        r.commit('shift')
        self.check(r.scan(), saved=['app.py:2: API_KEY'], secrets=[v])

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
        self.check(r.scan(), saved=['app.py:2: API_KEY'], secrets=[v])

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
        self.check(r.scan(), saved=['app.py:2: API_KEY'], secrets=[v])

    def test_no_remote_all_history_counts(self):
        r = self.fresh(remote=False)
        v1, v2 = 'noremote-secret-value-1', 'noremote-secret-value-2'
        r.append('app.py', kv('API_KEY', v1))
        r.commit('one')
        r.write('b.py', kv('TOKEN', v2))
        r.commit('two')
        self.check(r.scan(), saved=['app.py:2: API_KEY', 'b.py:1: TOKEN'], secrets=[v1, v2])

    def test_no_remote_clean_repo_has_no_hits(self):
        self.check(self.fresh(remote=False).scan())

    def test_ignored_untracked_files_are_not_scanned(self):
        r = self.fresh()
        v1, v2 = 'ignored-secret-value-1234', 'visible-secret-value-5678'
        r.write('.gitignore', 'ignored.py\nbuild/\n')
        r.write('ignored.py', kv('TOKEN', v1))
        r.write('build/out.py', kv('TOKEN', v1))
        r.write('seen.py', kv('TOKEN', v2))
        self.check(r.scan(), new=['seen.py:1: TOKEN'], secrets=[v1, v2])

    def test_output_is_sorted_numerically_by_line_and_deduped(self):
        r = self.fresh()
        v1, v2, v3 = 'sorted-secret-value-aaaa', 'sorted-secret-value-bbbb', 'sorted-secret-value-cccc'
        a = '# 1\n' + kv('PASSWORD', v1) + '# x\n' * 7 + kv('TOKEN', v2)  # PASSWORD line 2, TOKEN line 10
        r.write('b.py', kv('TOKEN', v3))
        r.write('a.py', a)
        exp = ['a.py:2: PASSWORD', 'a.py:10: TOKEN', 'b.py:1: TOKEN']
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
            exp.append('names.py:%d: %s' % (i + 1, name))
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
        self.check(r.scan(), unsaved=['app.py:4: SECRET_KEY'], saved=['app.py:2: AWS_SECRET_ACCESS_KEY'],
                   secrets=[v1, v2, v3])


# ---------------------------------------------------------------- value rule
class ValueRuleCases(Base):
    def test_quoted_length_boundary_and_quote_kinds(self):
        r = self.fresh()
        short, ok = 'abcdefg', 'abcdefgh'
        r.write('v.py', kv('PASSWORD', short) + kv('PASSWORD', ok) + kv('TOKEN', 'q7chars', q="'")
                + kv('TOKEN', 'bt-eight-chars', q='`') + 'PASSWORD = ""\n')
        self.check(r.scan(), new=['v.py:2: PASSWORD', 'v.py:4: TOKEN'], secrets=[ok, 'bt-eight-chars'])

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
        self.check(r.scan(), new=['ph.py:%d: PASSWORD' % (n + 1), 'ph.py:%d: PASSWORD' % (n + 2)],
                   secrets=near)

    def test_crlf_line_endings_do_not_leak_cr_or_break_hits(self):
        r = self.fresh()
        v1, v2 = 'crlf-secret-value-1234', 'crlf-unquoted-1234'
        r.write('crlf.py', 'x = 1\r\n' + kv('TOKEN', v1).replace('\n', '\r\n'))
        r.write('crlf.yml', 'password: %s\r\n' % v2)
        self.check(r.scan(), new=['crlf.py:2: TOKEN', 'crlf.yml:1: password'], secrets=[v1, v2])

    def test_unusual_line_separators_do_not_shift_line_numbers(self):
        r = self.fresh()
        v = 'separator-secret-1234'
        junk = 'a\x0bb\x0cc\x1cd\x1de\x1ef\rg \u0085     end\n'
        r.write('sep.py', junk + kv('TOKEN', v))
        self.check(r.scan(), new=['sep.py:2: TOKEN'], secrets=[v])

    def test_diff_lookalike_content_cannot_misdirect_the_scan(self):
        r = self.fresh()
        v = 'lookalike-secret-1234'
        r.append('app.py', '++ b/fake.py\n@@ -1 +100 @@\ndiff --git a/x b/x\n' + kv('PASSWORD', v))
        self.check(r.scan(), unsaved=['app.py:5: PASSWORD'], secrets=[v])

    def test_file_without_trailing_newline(self):
        r = self.fresh()
        v1, v2 = 'nonewline-secret-1111', 'nonewline-secret-2222'
        r.branch()
        r.write('nonl.py', 'TOKEN = "%s"' % v1)
        r.commit('nonl')
        r.write('nonl2.py', 'TOKEN = "%s"' % v2)
        self.check(r.scan(), new=['nonl2.py:1: TOKEN'], saved=['nonl.py:1: TOKEN'], secrets=[v1, v2])


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
        self.check(r.scan(), new=['%s:1: PASSWORD' % n for n in sorted(hit)], secrets=[v])

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
        self.check(r.scan(), new=['docker-compose.yml:4: POSTGRES_PASSWORD', 'docker-compose.yml:5: password',
                                  'docker-compose.yml:6: TOKEN'], secrets=vs)

    def test_committed_compose_and_dotenv_in_unsent_commits(self):
        r = self.fresh()
        v1, v2 = 'supersecret1', 'hunter2hunter2'
        r.branch()
        r.write('docker-compose.yml',
                'services:\n  db:\n    environment:\n      - POSTGRES_PASSWORD=%s\n' % v1)
        r.commit('compose')
        r.write('.env', 'PASSWORD=%s\n' % v2)
        r.commit('env')
        self.check(r.scan(), saved=['.env:1: PASSWORD', 'docker-compose.yml:4: POSTGRES_PASSWORD'],
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
        self.check(r.scan(), saved=['db.sqlite3:1: TOKEN', 'id_rsa:1: PASSWORD'], secrets=[v])

    def test_dotenv_example_and_lookalikes_are_scanned(self):
        r = self.fresh()
        v = 'looks-real-secret-value-9'
        r.write('.env.example', 'API_KEY=%s\n' % v)
        r.write('credentials.py', kv('API_KEY', v))
        r.write('service-account.yaml', kv('API_KEY', v))
        r.write('a.pem.txt', kv('API_KEY', v))
        r.write('envfile.py', kv('API_KEY', v))
        self.check(r.scan(), new=['.env.example:1: API_KEY', 'a.pem.txt:1: API_KEY', 'credentials.py:1: API_KEY',
                                  'envfile.py:1: API_KEY', 'service-account.yaml:1: API_KEY'], secrets=[v])


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
        self.assertNotIn(b'x.py:', res.out)
        self.no_leak(res, [v])

    def test_plain_directory_via_cwd(self):
        td = tempfile.TemporaryDirectory()
        self.addCleanup(td.cleanup)
        cp = subprocess.run([sys.executable, SCRIPT], cwd=td.name, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=60)
        self.assertEqual(cp.returncode, 2)

    def test_missing_path(self):
        td = tempfile.TemporaryDirectory()
        self.addCleanup(td.cleanup)
        cp = subprocess.run([sys.executable, SCRIPT, '--repo', os.path.join(td.name, 'nope')],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
        self.assertEqual(cp.returncode, 2)


if __name__ == '__main__':
    unittest.main()
