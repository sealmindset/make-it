#!/usr/bin/env python3
"""secret-scan.py -- find hardcoded secrets in what argo-it is about to send.

Usage:  secret-scan.py [--repo PATH]     (default: the current directory)
        secret-scan.py --self-test       (runs test_secret_scan.py next to this file)

Prints three labels -- unsaved edits, new files, saved-not-sent -- with each hit under its
label as `file:line: NAME`. Never a value: the gate must not leak what it is guarding.
Exit 0 = no hits, 1 = hits, 2 = couldn't check (an unreadable scope must never look clean).
Python 3.9+, stdlib only.
"""
import argparse
import fnmatch
import os
import re
import stat
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LABELS = (b'== unsaved edits ==', b'== new files ==', b'== saved, not sent ==')

# Pin every setting that changes what git prints, so a user's config can't hide or garble a line.
# (cwd is always the repo top, so diff.relative is a no-op.) --no-replace-objects: `git replace`
# can't swap in a clean stand-in, since push sends the real objects.
GIT = ['git', '--no-replace-objects', '-c', 'color.ui=never', '-c', 'core.quotePath=false',
       '-c', 'diff.noprefix=false', '-c', 'diff.mnemonicPrefix=false', '-c', 'diff.suppressBlankEmpty=false',
       '-c', 'log.showRoot=true']
# --text + our own NUL check: a .gitattributes `binary` / `-diff` can't hide a text file.
DIFF = ['--no-color', '--no-ext-diff', '--no-textconv', '--text', '--no-renames', '--full-index',
        '--submodule=short', '--src-prefix=a/', '--dst-prefix=b/']
# Every unsent commit, merges included (-c: a line new to every parent is the merge's own).
LOG = ['log', '--no-show-signature', '--format=', '-c', '--no-renames']
UNSENT = ['HEAD', '--not', '--remotes', '--']

# Keep-out list: it mirrors argo-it PHASE 5b step 4, which never stages these (at any depth).
KEEP_OUT = (b'.env*', b'*.pem', b'*.key', b'id_rsa*', b'id_ed25519*', b'id_ecdsa*', b'id_dsa*', b'*.keychain*',
            b'.netrc', b'*credentials*.json', b'*service-account*.json', b'*.sqlite*', b'*.db', b'*.p12', b'*.pfx')
CONFIG_EXTS = (b'.ini', b'.cfg', b'.conf', b'.properties', b'.toml', b'.yaml', b'.yml')

ASSIGN = re.compile(r'(?<![A-Za-z0-9_.-])([A-Za-z_][A-Za-z0-9_.-]*)["\'`]?[ \t]*(?::=|=|:)[ \t]*')
WORDS = re.compile(r'[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+')
LAST = {'password', 'passwd', 'pwd', 'secret', 'token', 'credentials', 'apikey'}
KEY_KINDS = {'api', 'private', 'access', 'secret', 'signing', 'encryption', 'client', 'master', 'ssh'}
UNQUOTED = re.compile(r'[^ \t\r\n]*')
# [^}] inside {{ }}: a lazy .*? here backtracks exponentially on a crafted value.
REFERENCE = re.compile(r'(?:\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*|\{\{[^}]*\}\})+')
PLACEHOLDER = re.compile(r'example|todo|placeholder|changeme|change-me|mock|your-.*-here|your_.*_here|<.*>|xxxx'
                         r'|\*\*\*\*', re.I)


class Fail(Exception):
    """Couldn't check: exit 2. Messages are our own words, never file content."""


def git_out(cwd, *args, input=None):
    p = subprocess.run(GIT + list(args), cwd=cwd, input=input, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode:
        raise Fail('git %s failed' % args[0])
    return p.stdout


def git_lines(cwd, *args):
    """Stream git's output line by line (all history can be bigger than memory)."""
    with subprocess.Popen(GIT + list(args), cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as p:
        for line in p.stdout:
            yield line.rstrip(b'\n')
    if p.returncode:
        raise Fail('git %s failed' % args[0])


ESC = {7: b'a', 8: b'b', 9: b't', 10: b'n', 11: b'v', 12: b'f', 13: b'r', 34: b'"', 92: b'\\'}


def cq(s):
    """git's quote_c_style with core.quotePath=false (pinned above)."""
    if not any(c < 32 or c in (34, 92, 127) for c in s):
        return s
    return b'"' + b''.join(b'\\' + ESC[c] if c in ESC else b'\\%03o' % c if c < 32 or c == 127 else bytes([c])
                           for c in s) + b'"'


def headers(names):
    """Each file's diff header exactly as git prints it -> its exact name from a -z listing.
    So no quoted name is ever parsed, and a header we can't place is a failure, not a guess."""
    m = {}
    for n in names.split(b'\0'):
        if n:
            m[b'diff --git ' + cq(b'a/' + n) + b' ' + cq(b'b/' + n)] = n
            m[b'diff --combined ' + cq(n)] = n
    return m


def added_lines(lines, names):
    """(path, line number in the new version, text, new blob id) for each line the patch adds.
    In a combined (merge) hunk only lines new to every parent count. Inside a hunk every line starts
    with a column character, so file content can't pose as a header."""
    path = sha = n = None
    width = 1
    for line in lines:
        if n is not None and line[:1] in (b' ', b'+', b'-', b'\\'):
            cols = line[:width]
            if line[:1] == b'\\' or b'-' in cols:
                continue
            if cols == b'+' * width:
                yield path, n, line[width:], sha
            n += 1
            continue
        n = None
        if line.startswith(b'diff '):
            path, sha = names.get(line), None
            if path is None:
                raise Fail('git printed a diff for a file it did not list')
        elif line.startswith(b'index '):
            sha = line.split(b' ')[1].split(b'..')[1]
        elif line.startswith(b'@@'):
            width = len(line) - len(line.lstrip(b'@')) - 1
            plus = line.split(b' ')[width + 1]
            if path is None or not plus.startswith(b'+'):
                raise Fail('unreadable hunk header')
            n = int(plus[1:].split(b',')[0])


def secret_named(name):
    w = [x.lower() for x in WORDS.findall(name)]
    return bool(w) and (w[-1] in LAST or (w[-1] == 'key' and len(w) > 1 and w[-2] in KEY_KINDS))


def hit_names(text, config):
    """Secret-named NAMEs assigned a literal value on this line. Source code needs quotes.
    The search resumes after every NAME's value, never inside it, so part of a value
    (`URL=postgres://app:MyPassword=...`) is never read -- or printed -- as a NAME."""
    s = text.decode('utf-8', 'surrogateescape')  # any byte is fine; lengths count characters
    m = ASSIGN.search(s)
    while m:
        name, i = m.group(1), m.end()
        resume, v, named = i, None, secret_named(name)
        q = s[i:i + 1]
        j = s.find(q, i + 1) if q in ('"', "'", '`') else -1
        if j >= 0:
            v, resume = s[i + 1:j], j + 1
        elif config and q in ('{', '[') and not named:
            resume = i + 1  # a YAML/TOML/JSON flow opener (`env: {PASSWORD: "..."}`) holds NAMEs of its own
        elif config:  # (an unclosed quote is no literal: source code resumes right after the sep)
            v = UNQUOTED.match(s, i).group()
            resume = i + len(v)
        if named and v is not None and len(v) >= 8 and not REFERENCE.fullmatch(v) and not PLACEHOLDER.search(v):
            yield name
        m = ASSIGN.search(s, resume)


def is_config(path):
    base = path.rsplit(b'/', 1)[-1]
    return b'.env' in base or base.endswith(CONFIG_EXTS) or base.startswith((b'Dockerfile', b'docker-compose'))


def kept_out(path):
    base = path.rsplit(b'/', 1)[-1]
    if base == b'.env.example':
        return False
    return (b'/' + path).endswith(b'/.aws/credentials') or any(fnmatch.fnmatchcase(base, p) for p in KEEP_OUT)


def shown(path):
    """A control byte in a name could split a hit or forge a label line: print it as \\xNN.
    Unicode line breaks (C1 incl. NEL, U+2028, U+2029) split lines too: print them as \\uXXXX."""
    s = path.decode('utf-8', 'surrogateescape')
    s = re.sub(r'[\x00-\x1f\x7f]', lambda m: '\\x%02x' % ord(m.group()), s)
    s = re.sub(r'[\x80-\x9f\u2028\u2029]', lambda m: '\\u%04x' % ord(m.group()), s)
    return s.encode('utf-8', 'surrogateescape')


def collect(rows, is_binary):
    """Hits from (path, line, text, blob) rows; a file's binary check runs only once it has a hit."""
    hits, binary = set(), {}
    for path, n, text, sha in rows:
        found = list(hit_names(text, is_config(path)))
        if found:
            if (path, sha) not in binary:
                binary[path, sha] = is_binary(path, sha)
            if not binary[path, sha]:
                hits.update((path, n, name) for name in found)
    return hits


def nul_in_head(data):
    return b'\0' in data[:8000]  # git's binary rule


def encodings(top, paths):
    """path -> the working-tree-encoding git converts it from to UTF-8 when staged (None: stored as-is)."""
    out = git_out(top, 'check-attr', '--stdin', '-z', 'working-tree-encoding',
                  input=b''.join(p + b'\0' for p in paths)).split(b'\0')
    m = {}
    for i in range(0, len(out) - 1, 3):
        v = out[i + 2]  # like git: no value, or UTF-8 itself, means no conversion
        m[out[i]] = None if v in (b'', b'unspecified') or re.fullmatch(rb'(?i)utf-?8', v) else v
    if len(out) != 3 * len(paths) + 1 or set(m) != set(paths):
        raise Fail('git check-attr did not answer for every file')
    return m


def stored(full, enc):
    """The file as git stores and sends it, or None if that is binary. A working-tree-encoding file
    is judged after decoding: its raw bytes (UTF-16's NULs) are not what git sends."""
    with open(full, 'rb') as f:
        data = f.read(8000)
        if enc is None and nul_in_head(data):
            return None  # never read the rest of a plain binary file
        data += f.read()
    if enc is not None:
        try:
            data = data.decode(enc.decode()).encode('utf-8')
        except (LookupError, UnicodeError):  # our own words: the codec's message can quote the file's bytes
            raise Fail("can't decode a file from its working-tree-encoding")
    return None if nul_in_head(data) else data


def scan(repo):
    top = git_out(repo, 'rev-parse', '--show-toplevel')[:-1]
    changed = git_out(top, 'diff', '--name-only', '-z', '--no-renames', 'HEAD', '--')
    # argo-it's save step adds `!.env.example` to .gitignore, so list untracked files exactly as it then stages them.
    untracked = set(git_out(top, 'ls-files', '--others', '--exclude-standard', '--exclude=!.env.example',
                            '-z').split(b'\0')) - {b''}
    enc = encodings(top, (set(changed.split(b'\0')) - {b''}) | untracked)

    def on_disk(path, sha):
        full = os.path.join(top, path)
        if not stat.S_ISREG(os.lstat(full).st_mode):
            return False  # a symlink's text is its target
        return stored(full, enc[path]) is None

    unsaved = collect(
        (r for r in added_lines(git_lines(top, 'diff', *DIFF, 'HEAD', '--'), headers(changed))
         if not kept_out(r[0])), on_disk)

    rows = []
    for path in untracked:
        full = os.path.join(top, path)
        if kept_out(path) or not stat.S_ISREG(os.lstat(full).st_mode):
            continue  # a nested repo shows as a directory
        data = stored(full, enc[path])
        if data is not None:
            rows.extend((path, n, text, None) for n, text in enumerate(data.split(b'\n'), 1))
    new = collect(rows, lambda path, sha: False)

    saved = collect(
        added_lines(git_lines(top, *LOG, '-p', *DIFF, *UNSENT),
                    headers(git_out(top, *LOG, '-z', '--name-only', *UNSENT))),
        lambda path, sha: nul_in_head(git_out(top, 'cat-file', 'blob', sha.decode())))
    return unsaved, new, saved


def main():
    ap = argparse.ArgumentParser(description='Find hardcoded secrets in what argo-it is about to send.')
    ap.add_argument('--repo', default='.', help='repo to scan (default: the current directory)')
    ap.add_argument('--self-test', action='store_true', help='run test_secret_scan.py')
    a = ap.parse_args()
    if a.self_test:
        return subprocess.call([sys.executable, os.path.join(HERE, 'test_secret_scan.py')])
    try:
        scopes = scan(a.repo)
    except Exception as e:  # anything unexpected is "couldn't check" -- never a traceback that could quote data
        sys.stderr.write("secret-scan: couldn't check: %s\n" % (e if isinstance(e, Fail) else type(e).__name__))
        return 2
    out = sys.stdout.buffer
    for label, hits in zip(LABELS, scopes):
        out.write(label + b'\n')
        for path, n, name in sorted(hits):
            out.write(b'%s:%d: %s\n' % (shown(path), n, name.encode()))
    return 1 if any(scopes) else 0


if __name__ == '__main__':
    sys.exit(main())
