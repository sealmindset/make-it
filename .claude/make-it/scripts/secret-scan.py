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
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LABELS = (b'== unsaved edits ==', b'== new files ==', b'== saved, not sent ==')

# Pin every setting that changes what git prints, so a user's config can't hide or garble a line.
# (cwd is always the repo top, so diff.relative is a no-op.) --no-replace-objects: `git replace`
# can't swap in a clean stand-in, since push sends the real objects.
GIT = ['git', '--no-replace-objects', '-c', 'color.ui=never', '-c', 'core.quotePath=false',
       '-c', 'diff.noprefix=false', '-c', 'diff.mnemonicPrefix=false', '-c', 'diff.suppressBlankEmpty=false',
       '-c', 'log.showRoot=true']
# --text + our own NUL check: a .gitattributes `binary` / `-diff` can't hide a text file.
# -U1: a user's diff.context=0 can't drop the line before an added one (see hit_names).
DIFF = ['--no-color', '--no-ext-diff', '--no-textconv', '--text', '--no-renames', '--full-index', '-U1',
        '--submodule=short', '--src-prefix=a/', '--dst-prefix=b/']
# Every unsent commit, merges included (-c: a line new to every parent is the merge's own).
LOG = ['log', '--no-show-signature', '--format=', '-c', '--no-renames']

# Keep-out list: it mirrors argo-it PHASE 5b step 4, which never stages these (at any depth).
KEEP_OUT = (b'.env*', b'*.pem', b'*.key', b'id_rsa*', b'id_ed25519*', b'id_ecdsa*', b'id_dsa*', b'*.keychain*',
            b'.netrc', b'*credentials*.json', b'*service-account*.json', b'*.sqlite*', b'*.db', b'*.p12', b'*.pfx')
# ...and step 4's `git reset` of them, run as-is on the scan's copy of the index.
RESET = ([':(top,glob)**/' + p.decode() for p in KEEP_OUT + (b'.aws/credentials',)]
         + [':(top,glob,exclude)**/.env.example'])
CONFIG_EXTS = (b'.ini', b'.cfg', b'.conf', b'.properties', b'.toml', b'.yaml', b'.yml')

NAME, SEP = r'[A-Za-z_][A-Za-z0-9_.-]*', r'[ \t]*(?::=|=|:)[ \t]*'
IDENT, SEP_AT = re.compile(NAME), re.compile(SEP)
QUOTES = (('"', 3), ("'", 3), ('"', 1), ("'", 1), ('`', 1))
QUOTE = '|'.join(q * n for q, n in QUOTES)  # longest first
OPENER = re.compile(QUOTE)
# A literal opener or a trailing comment (` #` needs the space: `x#y`, `$#`, `this.#f` aren't comments).
COMMENT = re.compile(r'%s|(?<=[ \t])#|//' % QUOTE)
# The next literal opener or NAME sep, so a NAME only ever starts outside a literal -- and never inside a
# base64 / base64url / hex run, so a misread literal end can't turn `Zk9/c2VjcmV0QPwd=` into a NAME.
# Not `=`: base64 pads only at the end, and a NAME follows one in `--from-literal=JWT_SECRET='...'`.
TOKEN = re.compile(r'%s|(?<![A-Za-z0-9_.+/-])(%s)%s' % (QUOTE, NAME, SEP))
# One literal (backslash escapes; a triple quote may hold single quotes), unrolled so it can't backtrack.
LITERAL = {q * n: re.compile(r'{e}[^{q}\\]*(?:(?:\\.{t})[^{q}\\]*)*{e}'.format(
    e=q * n, q=q, t='' if n == 1 else '|%s(?!%s)' % (q, q * 2))) for q, n in QUOTES}
WORDS = re.compile(r'[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+')
LAST = {'password', 'passwd', 'pwd', 'secret', 'token', 'credentials', 'apikey'}
KEY_KINDS = {'api', 'private', 'access', 'secret', 'signing', 'encryption', 'client', 'master', 'ssh'}
UNQUOTED = re.compile(r'[^ \t\r\n]*')
# [^}] inside {{ }}: a lazy .*? here backtracks exponentially on a crafted value.
REFERENCE = re.compile(r'(?:\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*|\{\{[^}]*\}\})+')
PLACEHOLDER = re.compile(r'example|todo|placeholder|changeme|change-me|mock|xxxx|\*\*\*\*')
# `your-…-here`, `your_…_here`, `<…>` by find, not `.*`: that regex backtracks quadratically on a long value.
AROUND = (('your-', '-here'), ('your_', '_here'), ('<', '>'))
# A Git LFS pointer's oid line: the push uploads the object it names, not the pointer.
LFS_OID = re.compile(rb'oid sha256:([0-9a-f]{64})')


class Fail(Exception):
    """Couldn't check: exit 2. Messages are our own words, never file content."""


def git_out(cwd, *args, input=None, env=None):
    p = subprocess.run(GIT + list(args), cwd=cwd, input=input, env=env, stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL)
    if p.returncode:
        raise Fail('git %s failed' % args[0])
    return p.stdout


def git_lines(cwd, *args, env=None):
    """Stream git's output line by line (all history can be bigger than memory)."""
    with subprocess.Popen(GIT + list(args), cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as p:
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
    """(path, line number in the new version, text, new blob id, the last non-blank line before it in the new
    version or None) for each line the patch adds. In a combined (merge) hunk only lines new to every parent
    count. Inside a hunk every line starts with a column character, so file content can't pose as a header."""
    path = sha = n = prev = None
    width = 1
    for line in lines:
        if n is not None and line[:1] in (b' ', b'+', b'-', b'\\'):
            cols = line[:width]
            if line[:1] == b'\\' or b'-' in cols:
                continue
            if cols == b'+' * width:
                yield path, n, line[width:], sha, prev
            if line[width:].strip():  # a blank line between `?` and its branch can't hide the `?`
                prev = line[width:]
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
            n, prev = int(plus[1:].split(b',')[0]), None  # with -U1 the line before an added one is in its hunk


def secret_named(name):
    w = [x.lower() for x in WORDS.findall(name)]
    return bool(w) and (w[-1] in LAST or (w[-1] == 'key' and len(w) > 1 and w[-2] in KEY_KINDS))


def placeholder(v):
    v = v.lower()
    if PLACEHOLDER.search(v):
        return True
    for a, b in AROUND:
        i = v.find(a)
        if i >= 0 and v.find(b, i + len(a)) >= 0:
            return True
    return False


def literal_at(s, i):
    """(content, end) of the string literal opening at s[i]; None if none opens there or it doesn't close."""
    q = OPENER.match(s, i)
    m = q and LITERAL[q.group()].match(s, i)
    if m:
        n = len(q.group())
        return s[i + n:m.end() - n], m.end()


def key_position(s, i, start):
    """A quoted key opens at line start (when `start`) or after `{`, `[`, `,` or a YAML `- ` -- never after a
    ternary's `?`. After `[` only directly: a shell test's `[ "AcmePwd" = ...` always takes a space."""
    j = i
    while j and s[j - 1] in ' \t':
        j -= 1
    if j < i and j and s[j - 1] == '-':
        j -= 1
        while j and s[j - 1] in ' \t':
            j -= 1
        return j == 0 and start
    if j == 0:
        return start
    return s[j - 1] in '{,' or (s[j - 1] == '[' and j == i)


def uncommented(s):
    """s less a trailing ` #` or `//` comment. Literals are walked as values() walks them, so a `#` or `//` in
    one (`"http://x"`, `"#fff"`) never cuts."""
    i, dead = 0, set()
    while True:
        m = COMMENT.search(s, i)
        if not m:
            return s
        i = m.end()
        if m.group() in ('#', '//'):
            return s[:m.start()]
        lit = None if m.group() in dead else literal_at(s, m.start())
        if lit:
            i = lit[1]
        elif m.group() in ('"', "'"):
            dead.add(m.group())  # an apostrophe (see values()): every later one is unclosed too
        else:
            return s  # a ` or triple-quoted literal runs on past this line


def values(s, config, start=True):
    """(NAME, VALUE) pairs on a line. A NAME only starts outside a string literal, and the search resumes after
    its VALUE, never inside it -- so no part of a value (the `c2VjcmV0QPwd` in `encode(p, "Zk9/c2VjcmV0QPwd=",
    alg="HS256")`, the `MyPassword` in `URL=postgres://app:MyPassword=...`) is ever read or printed as a NAME.
    A literal in key position followed by sep is a quoted key (`"password": ...`); `x ? "AcmePwd" : ...` isn't.
    Any other literal that isn't a VALUE is scanned by the same rules when it holds JSON (`json.loads('{...}')`),
    and always in a config file (compose's `- "PASSWORD=..."`, `command: sh -c "... PASSWORD=..."`).
    `start`: line start is a key position (not when the line goes on a ternary from the line before)."""
    i, dead = 0, set()
    while True:
        m = TOKEN.search(s, i)
        if not m:
            return
        i = m.end()
        if m.group(1) is None:  # a literal opens here
            lit = None if m.group() in dead else literal_at(s, m.start())
            if lit is None:
                if m.group() in ('"', "'"):  # these can't span lines: an apostrophe, not a literal. Every later
                    dead.add(m.group())  # one is unclosed too, so skip them unscanned (else a 2 MB line is slow)
                    continue
                return  # a ` or triple-quoted literal runs on past this line
            body, i = lit
            sep = SEP_AT.match(s, i)
            if not (sep and IDENT.fullmatch(body) and key_position(s, m.start(), start)):
                if config or body[:1] in ('{', '['):
                    yield from values(body, config)
                continue
            name, i = body, sep.end()
        else:
            name = m.group(1)
        lit = literal_at(s, i)
        if lit:
            v, i = lit
        elif not config:
            continue  # source code needs quotes
        elif s[i:i + 1] in ('{', '[') and not secret_named(name):
            continue  # a YAML/TOML/JSON flow opener (`env: {PASSWORD: "..."}`) holds NAMEs of its own
        else:
            v = UNQUOTED.match(s, i).group()  # (an unclosed quote is no literal)
            i += len(v)
        yield name, v


def hit_names(text, config, prev=None):
    """Secret-named NAMEs assigned a literal value on this line. Source code needs quotes.
    `prev` is the last non-blank line before it in the new version: if that, less a trailing comment, ends inside
    a ternary (`const pw = isProd ?`, `isProd ? // prod`, or `c1 ? c2 ? a :`), this line's start is no key
    position, so `  "AcmeProdPassword" : "dev"` isn't a quoted key. A YAML parent `env:` (no `?`) or a comment's
    `?` (`# rotate?`, `"debug": False,  # in prod?`) isn't one: the `"password": ...` under it stays a key."""
    s = text.decode('utf-8', 'surrogateescape')  # any byte is fine; lengths count characters
    p = (prev or b'').strip()
    c = uncommented(p.decode('utf-8', 'surrogateescape')).rstrip()
    ternary = c.endswith('?') or (c.endswith(':') and '?' in c)
    start = not ternary or p.startswith((b'#', b'//', b'/*', b'*'))
    for name, v in values(s, config, start):
        if len(v) >= 8 and secret_named(name) and not REFERENCE.fullmatch(v) and not placeholder(v):
            yield name


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


def collect(rows, blob, lfs):
    """Hits from (path, line, text, blob, line before) rows; a file's binary check runs only once it has a hit.
    An LFS pointer is scanned as the whole object it names (what the push uploads); a missing object can't
    be checked."""
    hits, binary, pointers = set(), {}, {}
    for path, n, text, sha, prev in rows:
        oid = LFS_OID.fullmatch(text)
        if oid:
            pointers[path, sha] = oid.group(1)
        found = list(hit_names(text, is_config(path), prev))
        if found:
            if (path, sha) not in binary:
                binary[path, sha] = nul_in_head(blob(sha))
            if not binary[path, sha]:
                hits.update((path, n, name) for name in found)
    for (path, sha), oid in pointers.items():
        data = blob(sha)
        if len(data) >= 1024 or not data.startswith(b'version https://'):
            continue  # git-lfs reads only a small blob that opens with its version line as a pointer
        # ponytail: default storage dir only -- a custom lfs.storage reads as missing (exit 2); ask `git lfs env`
        # if that bites. Every line counts (the old object isn't diffed), so already-pushed lines can stop the send.
        try:
            f = open(os.path.join(lfs, oid[:2], oid[2:4], oid), 'rb')
        except FileNotFoundError:
            raise Fail('an LFS object in scope is not on disk')
        with f:
            if nul_in_head(f.read(8000)):
                continue
            f.seek(0)
            prev = None
            for n, line in enumerate(f, 1):
                line = line.rstrip(b'\n')
                hits.update((path, n, name) for name in hit_names(line, is_config(path), prev))
                if line.strip():
                    prev = line
    return hits


def nul_in_head(data):
    return b'\0' in data[:8000]  # git's binary rule


def staged(top, untracked):
    """Added lines of what argo-it step 4 commits, and the paths new to the repo. Step 4's `git add -A` and
    keep-out `git reset` run on a copy of the index, so git itself applies clean filters, working-tree-encoding,
    symlinks and assume-unchanged / skip-worktree exactly as step 4 will. The real index, the working tree and
    .gitignore are never touched; like step 4, the add writes blobs to the object store."""
    real = os.path.join(top, git_out(top, 'rev-parse', '--git-path', 'index')[:-1])
    with tempfile.TemporaryDirectory() as tmp:
        env = dict(os.environ, GIT_INDEX_FILE=os.path.join(tmp, 'index'))
        try:
            shutil.copyfile(real, env['GIT_INDEX_FILE'])
        except FileNotFoundError:
            pass  # no index yet: git starts an empty one, as it would for step 4
        git_out(top, 'add', '-u', env=env)  # = the tracked half of `git add -A`
        if untracked:  # ...and the untracked half (forced: the listing already applied step 4's ignore rules)
            git_out(top, 'add', '-f', '--pathspec-from-file=-', '--pathspec-file-nul', env=env,
                    input=b''.join(b':(literal)' + p + b'\0' for p in untracked))
        git_out(top, 'reset', '-q', '--', *RESET, env=env)
        st = git_out(top, 'diff', '--cached', '--name-status', '-z', '--no-renames', 'HEAD', '--', env=env)
        st = st.split(b'\0')[:-1]
        names = dict(zip(st[1::2], st[::2]))  # path -> status letter
        rows = list(added_lines(git_lines(top, 'diff', '--cached', *DIFF, 'HEAD', '--', env=env),
                                headers(b'\0'.join(names))))
    return rows, {p for p in untracked if names.get(p) == b'A'}


def scan(repo):
    top = git_out(repo, 'rev-parse', '--show-toplevel')[:-1]

    def blob(sha):
        return git_out(top, 'cat-file', 'blob', sha.decode())

    # git-lfs keeps objects under the common git dir (shared by linked worktrees), not --git-path.
    lfs = os.path.join(top, git_out(top, 'rev-parse', '--git-common-dir')[:-1], b'lfs', b'objects')

    # Saved, not sent runs before staged(): its `git add` can re-run the LFS clean filter on a racily clean file
    # and re-create a missing object, so a commit's LFS objects are checked as the user left them.
    # Step 4's commit during a merge (MERGE_HEAD) has those heads as parents too, so the push sends them.
    try:
        with open(os.path.join(top, git_out(top, 'rev-parse', '--git-path', 'MERGE_HEAD')[:-1]), 'rb') as f:
            heads = f.read().split()
    except FileNotFoundError:
        heads = []
    if not all(re.fullmatch(rb'[0-9a-f]{40,64}', h) for h in heads):
        raise Fail('unreadable MERGE_HEAD')
    unsent = ['HEAD'] + [h.decode() for h in heads] + ['--not', '--remotes', '--']
    saved = collect(
        added_lines(git_lines(top, *LOG, '-p', *DIFF, *unsent),
                    headers(git_out(top, *LOG, '-z', '--name-only', *unsent))), blob, lfs)

    # argo-it's save step adds `!.env.example` to .gitignore, so list untracked files exactly as it then stages them.
    # Its other .gitignore lines make the keep-out files ignored: never hash those.
    untracked = [p for p in git_out(top, 'ls-files', '--others', '--exclude-standard', '--exclude=!.env.example',
                                    '-z').split(b'\0') if p and not kept_out(p)]
    rows, added = staged(top, untracked)
    unsaved = collect((r for r in rows if r[0] not in added), blob, lfs)
    new = collect((r for r in rows if r[0] in added), blob, lfs)
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
