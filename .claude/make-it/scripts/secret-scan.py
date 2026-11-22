#!/usr/bin/env python3
"""secret-scan.py -- find hardcoded secrets in what argo-it is about to send.

Usage:  secret-scan.py [--repo PATH]     (default: the current directory)
        secret-scan.py --commit ID       (one commit by its full id: it and every commit it reaches that
                                          origin doesn't have, all under saved-not-sent)
        secret-scan.py --also PATH...    (also these new files, even when .gitignore hides them: argo-it's
                                          own files, which its save takes in by name)
        secret-scan.py --sent GLOB       (repeatable: what these refs reach counts as sent, in place of
                                          origin's remote-tracking branches -- argo-it's own copy of every
                                          branch and tag GitHub has)

Prints three labels -- unsaved edits, new files, saved-not-sent -- with each hit under its
label as `file:line`. Only what origin has counts as sent (no other remote): that is where argo-it sends. Nothing from a file's contents is ever printed: the gate must not leak what it is guarding.
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
import unicodedata

LABELS = (b'== unsaved edits ==', b'== new files ==', b'== saved, not sent ==')

# Pin every setting that changes what git prints, so a user's config can't hide or garble a line.
# (cwd is always the repo top, so diff.relative is a no-op.) --no-replace-objects: `git replace`
# can't swap in a clean stand-in, since push sends the real objects.
GIT = ['git', '--no-replace-objects', '-c', 'color.ui=never', '-c', 'core.quotePath=false',
       '-c', 'diff.noprefix=false', '-c', 'diff.mnemonicPrefix=false', '-c', 'diff.suppressBlankEmpty=false',
       '-c', 'log.showRoot=true']
# --text + our own NUL check: a .gitattributes `binary` / `-diff` can't hide a text file.
# -U1: a user's diff.context=0 can't drop the line before an added one (see hit).
DIFF = ['--no-color', '--no-ext-diff', '--no-textconv', '--text', '--no-renames', '--full-index', '-U1',
        '--submodule=short', '--src-prefix=a/', '--dst-prefix=b/']
# Every unsent commit, merges included (-c: a line new to every parent is the merge's own).
LOG = ['log', '--no-show-signature', '--format=', '-c', '--no-renames']

# Keep-out list: it mirrors argo-it PHASE 5b step 4, which never stages these (at any depth).
KEEP_OUT = (b'.env*', b'*.pem', b'*.key', b'id_rsa*', b'id_ed25519*', b'id_ecdsa*', b'id_dsa*', b'*.keychain*',
            b'.netrc', b'.git-credentials', b'*credentials*.json', b'*service-account*.json', b'*.sqlite*', b'*.db',
            b'*.db-*', b'*.p12', b'*.pfx')
# ...and step 4's `git reset` of them, run as-is on the scan's copy of the index.
RESET = ([':(top,glob)**/' + p.decode() for p in KEEP_OUT + (b'.aws/credentials',)]
         + [':(top,glob,exclude)**/.env.example'])
CONFIG_EXTS = (b'.ini', b'.cfg', b'.conf', b'.properties', b'.toml', b'.yaml', b'.yml')
# Registry config by name: its `_authToken=` / `password =` values are unquoted.
CONFIG_NAMES = (b'.npmrc', b'.pypirc')
# npm, twine, yarn and dotenv read these as text whatever bytes they hold: a NUL in a comment can't skip them.
TEXT_NAMES = (b'.npmrc', b'.pypirc', b'.yarnrc.yml', b'.env*')
# dotenvx's and dotenv-vault's key files: secret-only by design, so in an unsent commit they hit by name.
ENV_KEY_FILES = (b'.env.keys', b'.env.me')
# Owner's call: in a .env* file, a secret word anywhere in a setting's name makes it secret-named.
ENV_WORDS = re.compile(r'PASSWORD|SECRET|TOKEN|PRIVATE_KEY', re.I)
# Owner's call: in a YAML file, a `secretKey:` whose WHOLE value, less YAML's quotes, is a setting name names a
# setting, not its value (an ExternalSecret's `- secretKey: DATABASE_PASSWORD`). Capitals, digits and underscores
# with a letter (the first letter is a capital, so this can't backtrack). SK_LINE: the line holds only that key and
# value (a list dash, matching quotes and a ` #` comment allowed), so a second word, a tab, a flow map or a `''`
# escape is checked as before; hit() also needs the value not to go on to the next line. Accepted cost: a real
# all-capitals password in that exact spot passes.
SETTING_NAME = re.compile(r'[0-9_]*[A-Z][A-Z0-9_]*')
SK_LINE = re.compile(r'([ \t]*(?:-[ \t]+)?)(["\']?)secretKey\2[ \t]*:[ \t]+(["\']?)%s\3(?:[ \t]+#.*|[ \t]*)\r?'
                     % SETTING_NAME.pattern)

NAME, SEP = r'[A-Za-z_][A-Za-z0-9_.-]*', r'[ \t]*(?::=|=|:)[ \t]*'
IDENT, SEP_AT = re.compile(NAME), re.compile(SEP)
QUOTES = (('"', 3), ("'", 3), ('"', 1), ("'", 1), ('`', 1))
QUOTE = '|'.join(q * n for q, n in QUOTES)  # longest first
OPENER = re.compile(QUOTE)
# A literal opener or a trailing comment (` #` needs the space: `x#y`, `$#`, `this.#f` aren't comments).
COMMENT = re.compile(r'%s|(?<=[ \t])#|//' % QUOTE)
# The next literal opener or NAME sep, so a NAME only ever starts outside a literal. A NAME starts only:
# - at the start, or after anything but a word char or one of `.+/-`. So never inside a base64 / base64url / hex
#   run (a misread literal end can't turn `Zk9/c2VjcmV0QPwd=` into a NAME), a path (`./db_password:`,
#   `~/.git-credentials:`), a regex (`/token="(...)"/`) or a URL (`://user:` would swallow `MyPassword=...` as
#   its value). `=` is fine: base64 pads only at the end, and a NAME follows one in `--from-literal=JWT_SECRET=`.
#   `-` isn't (`--password=` stays a known limit);
# - after member access on a closer: `).` `].` `!.` `?.` or a quote then `.` (`f().key`, `a[0].key`, `x!.key`;
#   `obj.key` is one dotted NAME);
# - LINE_TOKEN only (a whole line, not a literal's body, which values() scans as its own string, so there
#   `"//app:MyPassword=..."` stays a URL): after `//` at the start or after a space or tab (a `//key` comment),
#   or after `+` at the start (a patch's `+KEY` line).
AFTER = r'(?<![A-Za-z0-9_.+/-])|(?<=[)\]!?"\'`]\.)'
TOKEN = re.compile(r'%s|(?:%s)(%s)%s' % (QUOTE, AFTER, NAME, SEP))
LINE = r'%s|(?:%s|(?<=^//)|(?<=[ \t]//)|(?<=^\+))(%s)%s'
LINE_TOKEN = re.compile(LINE % (QUOTE, AFTER, NAME, SEP))
# npm reads .npmrc keys up to the first `=` (`@acme-token:registry=`, `//localhost:4873/:_authToken=`), so `:` is
# never a sep there: a scope or a registry's host:port never starts a NAME that would swallow the real key.
NPMRC_TOKEN = re.compile(LINE % (QUOTE, AFTER, NAME, r'[ \t]*=[ \t]*'))
# One literal (backslash escapes; a triple quote may hold single quotes), unrolled so it can't backtrack.
LITERAL = {q * n: re.compile(r'{e}[^{q}\\]*(?:(?:\\.{t})[^{q}\\]*)*{e}'.format(
    e=q * n, q=q, t='' if n == 1 else '|%s(?!%s)' % (q, q * 2))) for q, n in QUOTES}
WORDS = re.compile(r'[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+')
LAST = {'password', 'passwd', 'pwd', 'secret', 'token', 'credentials', 'apikey'}
KEY_KINDS = {'api', 'private', 'access', 'secret', 'signing', 'encryption', 'client', 'master', 'ssh'}
UNQUOTED = re.compile(r'[^ \t\r\n]*')
# A Python string prefix right before a value's opening quote (`r'...'`, `b"..."`, `f"..."`, `rb'...'`)
PREFIX = re.compile(r'(?:[rR][bBfF]?|[bBfF][rR]?|[uU])(?=["\'])')
# Kubernetes / Compose env lists: `- name: X` with its `value: ...` on the next line (argo-it's own manifest shape)
ENV_NAME = re.compile(r'[ \t]*(?:-[ \t]+)?name[ \t]*:[ \t]*(["\']?)(%s)\1[ \t]*\r?' % NAME)
ENV_VALUE = re.compile(r'([ \t]*)value[ \t]*:(?=[ \t]|$)')
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


def secret_named(name, config):
    if config == 'env' and ENV_WORDS.search(name):  # `DB_PASSWORD_PROD`, `DOTENV_PRIVATE_KEY_PRODUCTION`
        return True
    if name == '_auth':  # .npmrc's base64 user:password -- exact, so `auth`, `oauth_url`, `AUTH_MODE` stay clean;
        return config  # config files only: in code (`_auth = "required-login"`) it's an ordinary name
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


def values(s, config, start=True, token=TOKEN):
    """(NAME, VALUE) on a line. A NAME only starts outside a string literal, and the search resumes after its
    VALUE, never inside it as a NAME -- so a matched NAME's VALUE is skipped as a VALUE (the `c2VjcmV0QPwd` in
    `encode(p, "Zk9/c2VjcmV0QPwd=", alg="HS256")`, the `MyPassword` in `URL=postgres://app:MyPassword=...`),
    and scanned inside only for further `NAME sep VALUE` assignments (`cmd = 'API_KEY="..." ./deploy.sh'`).
    A literal in key position followed by sep is a quoted key (`"password": ...`); `x ? "AcmePwd" : ...` isn't.
    Any other literal that isn't a VALUE is scanned inside by the same rules (`json.loads('{...}')`,
    `ssh host 'export PASSWORD="..."'`, compose's `- "PASSWORD=..."`).
    `start`: line start is a key position (not when the line goes on a ternary from the line before).
    `token`: LINE_TOKEN for a whole line, TOKEN (the default) for a literal's body."""
    i, dead = 0, set()
    while True:
        m = token.search(s, i)
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
                yield from values(body, config)
                continue
            name, i = body, sep.end()
        else:
            name = m.group(1)
        pre = PREFIX.match(s, i)
        if pre and literal_at(s, pre.end()):
            i = pre.end()
        lit = literal_at(s, i)
        if lit:
            v, i = lit
            yield from values(v, config)  # a stored command (`cmd = 'API_KEY="..." ./run'`) hides an assignment
        elif not config:
            continue  # source code needs quotes
        elif s[i:i + 1] in ('{', '[') and not secret_named(name, config):
            continue  # a YAML/TOML/JSON flow opener (`env: {PASSWORD: "..."}`) holds NAMEs of its own
        else:
            v = UNQUOTED.match(s, i).group()  # (an unclosed quote is no literal)
            if config == 'env' and v == '#' and s[i - 1:i] in (' ', '\t'):
                v = ''  # `SMTP_PASSWORD= # note`: an empty value and a comment. `KEY= #x` is a value (python-dotenv
                # and Docker Compose read `#x`), and the `#x` is in the file that is sent
            i += len(v)
        yield name, v


def goes_on(lines, n, col):
    """Does YAML read line n's plain value on past its line? It does when the next line that isn't blank is
    indented past the key's column `col` and isn't a comment (`lines`: the file's new version)."""
    for line in lines[n:]:
        if line.strip():
            return len(line) - len(line.lstrip(b' \t')) > col and not line.lstrip().startswith(b'#')
    return False


def hit(text, path, prev=None, more=None):
    """Does this line of `path` assign a literal value to a secret-named NAME? Source code needs quotes.
    `prev` is the last non-blank line before it in the new version: in source code, if that, less a trailing
    comment, ends inside a ternary (`const pw = isProd ?`, `isProd ? // prod`, or `c1 ? c2 ? a :`), this line's
    start is no key position, so `  "AcmeProdPassword" : "dev"` isn't a quoted key. A YAML parent `env:` (no `?`)
    or a comment's `?` (`# rotate?`, `"debug": False,  # in prod?`) isn't one: the `"password": ...` under it
    stays a key. Config files have no ternary: a value ending in `?` (`WHERE id = ?`) can't hide the next key.
    `more(col)`: does this line's YAML value go on to the next line (see goes_on)? None = can't tell, so a
    `secretKey:` setting name is checked as any other value."""
    if not text.strip():
        return False  # a blank row holds no hit; skip decoding its (possibly huge) context line
    s = text.decode('utf-8', 'surrogateescape')  # any byte is fine; lengths count characters
    config, start, base = is_config(path), True, path.rsplit(b'/', 1)[-1]
    passes = [(s, config, LINE_TOKEN)]  # (line, config rules or not, token)
    if base == b'.npmrc':
        # Before this task .npmrc was read as source code, where a quoted value after `NAME:` is a value
        # (`_authToken: "..."`, `; old token: "..."`): keep that reading as well, so nothing it caught is missed.
        passes = [(s, config, NPMRC_TOKEN), (s, False, LINE_TOKEN)]
        # npm's key is all before the first `=`, trimmed: a quoted key loses one pair of matching outer quotes
        # (`"..._authToken"=`), any other is cut at its first `;` or `#`; then less a trailing `[]` (an array): so
        # `_authToken;ci=`, `_authToken#ci=` and `_authToken[]=` set `_authToken`. Then npm env-replaces it, and an
        # unset `${X?}` is '' (`_authTok${X?}en=`): so that key less every `${...}` too, whatever the environment.
        # Scan those lines too.
        k, eq, rest = s.partition('=')
        key = k.strip()
        if len(key) > 1 and key[0] == key[-1] and key[0] in '"\'':
            key = key[1:-1]
        else:
            key = re.split('[;#]', key, maxsplit=1)[0].rstrip()
        key = key[:-2] if key.endswith('[]') else key
        passes += [(x + eq + rest, config, NPMRC_TOKEN) for x in {key, re.sub(r'\$\{[^}]*\}', '', key)}
                   if eq and x != k]
    elif base == b'.pypirc':
        # .pypirc too was read as source code before this task (`# old: password = "..."`): keep that reading.
        passes.append((s, False, LINE_TOKEN))
    if not config:
        p = (prev or b'').strip()
        c = uncommented(p.decode('utf-8', 'surrogateescape')).rstrip()
        ternary = c.endswith('?') or (c.endswith(':') and '?' in c)
        start = not ternary or p.startswith((b'#', b'//', b'/*', b'*'))
    # In a .env* file a secret word in the name counts at any length: `PASSWORD_MIN_LENGTH=8` stops a send (the
    # owner's accepted cost). Not in .env.example (owner's call): the 8-character floor stays there, so make-it's
    # own template lines (`ENFORCE_SECRETS=false`) pass; the wide name rule still applies to it.
    short = config == 'env' and base != b'.env.example'
    # In a .env* file a quote that doesn't close on its line opens a value that runs on (python-dotenv and Compose
    # read `KEY="`, the next lines and the closing quote as one value; Node dotenv does so for a backtick too), so
    # its length isn't on this line: no floor.
    # configparser lowercases .pypirc option names, so twine reads `PassWord =` as `password`.
    fold = base == b'.pypirc'
    if config and prev is not None and ENV_VALUE.match(s):
        named = ENV_NAME.fullmatch(prev.decode('utf-8', 'surrogateescape'))
        if named:  # `- name: DB_PASSWORD` then `  value: ...`: read as `DB_PASSWORD: ...`
            passes.append((named.group(2) + ':' + s[ENV_VALUE.match(s).end():], config, LINE_TOKEN))
    sk = base.endswith((b'.yaml', b'.yml')) and SK_LINE.fullmatch(s)
    sk = sk and more is not None and not more(len(sk.group(1)))
    return any((len(v) >= 8 or v and short and ENV_WORDS.search(name)
                or config == 'env' and v[:1] in ('"', "'", '`') and not literal_at(v, 0))
               and (secret_named(name, config) or fold and secret_named(name.lower(), config))
               and not REFERENCE.fullmatch(v) and not placeholder(v)
               and not (sk and name == 'secretKey' and SETTING_NAME.fullmatch(v))
               for line, rules, token in passes for name, v in values(line, rules, start, token))


def is_config(path):
    """'env' for a .env* file (a config file with a wider name rule: see secret_named), else True or False."""
    base = path.rsplit(b'/', 1)[-1]
    if fnmatch.fnmatchcase(base, b'.env*'):
        return 'env'
    return (b'.env' in base or base.endswith(CONFIG_EXTS) or base in CONFIG_NAMES
            or base.startswith((b'Dockerfile', b'docker-compose')))


def kept_out(path):
    base = path.rsplit(b'/', 1)[-1]
    if base == b'.env.example':
        return False
    return (b'/' + path).endswith(b'/.aws/credentials') or any(fnmatch.fnmatchcase(base, p) for p in KEEP_OUT)


def by_line(path):
    """A .env* file in an unsent commit is checked line by line (owner's call), unless it is a key file
    (ENV_KEY_FILES) or its name is also a key, certificate or database name (`.env.pem`, `.env.db`): fail closed."""
    base = path.rsplit(b'/', 1)[-1]
    return (fnmatch.fnmatchcase(base, b'.env*') and base not in ENV_KEY_FILES
            and not any(fnmatch.fnmatchcase(base, p) for p in KEEP_OUT if p != b'.env*'))


def shown(path):
    """A control byte in a name could split a hit or forge a label line: print it as \\xNN.
    The agent must be able to type what it reads, or a name could open a different file or none. So every other
    character str.isprintable() rejects prints as \\uXXXX (more digits past U+FFFF), and 3e's escaped-name stop
    fires: Unicode line breaks (C1 incl. NEL, U+2028, U+2029), spaces other than ASCII's (Zs: U+00A0 comes back
    as a space), invisible and format characters (Cf: U+200B, U+FEFF), private use (Co: U+F8FF, macOS SMB's
    U+F001-U+F029) and code points this Python's Unicode data doesn't know (Cn), so newer ones escape on 3.9."""
    s = path.decode('utf-8', 'surrogateescape')
    # A real backslash is escaped too (\x5c), so a shown `\xNN` or `\uXXXX` is always the scanner's escape
    s = re.sub(r'[\x00-\x1f\x7f\\]', lambda m: '\\x%02x' % ord(m.group()), s)
    # A byte that isn't UTF-8 decodes to a lone surrogate (U+DC80-U+DCFF). Print the byte itself as \xNN: raw, no
    # one can type it, and \xNN names the byte that is actually in the name (\u-and-4-hex would name a code point
    # that isn't).
    # A name not in NFC form (e + U+0301, U+212A KELVIN SIGN) comes back NFC when the agent types it, which on a
    # byte-exact disk opens a different file: print every non-ASCII character of such a name escaped.
    nfc = unicodedata.is_normalized('NFC', s)
    s = ''.join(c if c.isprintable() and (nfc or c < '\x80') else
                '\\x%02x' % (ord(c) - 0xdc00) if 0xdc80 <= ord(c) <= 0xdcff else '\\u%04x' % ord(c) for c in s)
    return s.encode('utf-8', 'surrogateescape')


def continued(rows):
    """The rows, plus each .pypirc option joined with its continuation lines as one more row, at the option's
    line: configparser (twine's parser) reads the indented lines after an option, and blank lines between, into
    its value (`password =`, then `    pypi-...`). A continuation whose option line isn't a row (an edit under a
    pushed `password =`) is joined to the line before it, at its own line."""
    run = None  # [path, blob, the run's line, its last line, its parts (joined once, so linear), joined any]
    for row in rows:
        path, n, text, sha, prev = row
        more = text[:1] in (b' ', b'\t') and bool(text.strip())
        if run and run[:2] == [path, sha] and n == run[3] + 1 and (more or not text.strip()):
            run[3], run[5] = n, run[5] or more
            run[4].append(text.strip())
        else:
            if run and run[5]:
                yield run[0], run[2], b''.join(run[4]), run[1], None
            run = None
            if path.rsplit(b'/', 1)[-1] == b'.pypirc':
                run = [path, sha, n, n, [prev, text.strip()] if more and prev else [text], more and bool(prev)]
        yield row
    if run and run[5]:
        yield run[0], run[2], b''.join(run[4]), run[1], None


def collect(rows, blob, lfs):
    """Hits from (path, line, text, blob, line before) rows; a file's binary check runs only once it has a hit.
    An LFS pointer is scanned as the whole object it names (what the push uploads); a missing object can't
    be checked."""
    hits, binary, pointers, split = set(), {}, {}, {}

    def lines(sha):  # a file's new version, read (and split) only for a `secretKey:` setting-name line
        if sha not in split:
            split[sha] = blob(sha).split(b'\n')
        return split[sha]
    utf16 = {}
    for path, n, text, sha, prev in continued(rows):
        if b'\0' in text and (path, sha) not in utf16:  # a UTF-16 file: its diff lines are full of zero bytes
            data = blob(sha)
            utf16[path, sha] = data[:2] in (b'\xff\xfe', b'\xfe\xff')
            if utf16[path, sha]:  # every line of it counts, as for an LFS object (it isn't diffed as text)
                hits |= {(path, k) for k in utf16_hits(data, path)}
        if utf16.get((path, sha)):
            continue
        oid = LFS_OID.fullmatch(text)
        if oid:
            pointers[path, sha] = oid.group(1)
        if hit(text, path, prev, lambda col: goes_on(lines(sha), n, col)):
            if (path, sha) not in binary:
                binary[path, sha] = nul_in_head(blob(sha), path)
            if not binary[path, sha]:
                hits.add((path, n))
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
            if nul_in_head(f.read(8000), path):
                continue
            f.seek(0)
            # ponytail: an LFS-stored .pypirc isn't joined (see continued), and an LFS-stored YAML `secretKey:` setting
            # name gets no exemption (no `more`, so it is checked as any value); add both here if one turns up
            prev = None
            for n, line in enumerate(f, 1):
                line = line.rstrip(b'\n')
                if hit(line, path, prev):
                    hits.add((path, n))
                if line.strip():
                    prev = line
    return hits


def utf16_hits(data, path):
    """Line numbers of a UTF-16 file (it opens with a byte-order mark) holding a hit: PowerShell 5.1 writes these."""
    prev = None
    for n, line in enumerate(data.decode('utf-16', 'replace').split('\n'), 1):
        b = line.rstrip('\r').encode('utf-8', 'surrogateescape')
        if hit(b, path, prev):
            yield n
        if b.strip():
            prev = b


def nul_in_head(data, path):
    """git's binary rule, except for TEXT_NAMES: their tools read them as text."""
    base = path.rsplit(b'/', 1)[-1]
    return b'\0' in data[:8000] and not any(fnmatch.fnmatchcase(base, p) for p in TEXT_NAMES)


def staged(top, untracked, base):
    """Added lines of what argo-it step 4 commits, and the paths new to the repo. Step 4's `git add -A` and
    keep-out `git reset` run on a copy of the index, so git itself applies clean filters, working-tree-encoding,
    symlinks and assume-unchanged / skip-worktree exactly as step 4 will. The real index, the working tree and
    .gitignore are never touched; like step 4, the add writes blobs to the object store."""
    real = os.path.join(top, git_out(top, 'rev-parse', '--git-path', 'index')[:-1])
    with tempfile.TemporaryDirectory() as tmp:
        env = dict(os.environ, GIT_INDEX_FILE=os.path.join(tmp, 'index'))
        try:
            # copy2, not copyfile: git re-reads ("racily clean") an entry whose mtime isn't older than the index
            # file's own. A fresh mtime would make the copy trust stat where step 4's add (real index) re-reads.
            shutil.copy2(real, env['GIT_INDEX_FILE'])
        except FileNotFoundError:
            pass  # no index yet: git starts an empty one, as it would for step 4
        git_out(top, 'add', '-u', env=env)  # = the tracked half of `git add -A`
        if untracked:  # ...and the untracked half (forced: the listing already applied step 4's ignore rules)
            git_out(top, 'add', '-f', '--pathspec-from-file=-', '--pathspec-file-nul', env=env,
                    input=b''.join(b':(literal)' + p + b'\0' for p in untracked))
        git_out(top, 'reset', '-q', '--', *RESET, env=env)
        st = git_out(top, 'diff', '--cached', '--name-status', '-z', '--no-renames', *base, '--', env=env)
        st = st.split(b'\0')[:-1]
        names = dict(zip(st[1::2], st[::2]))  # path -> status letter
        rows = list(added_lines(git_lines(top, 'diff', '--cached', *DIFF, *base, '--', env=env),
                                headers(b'\0'.join(names))))
    return rows, {p for p in untracked if names.get(p) == b'A'}


def scan(repo, commit=None, also=(), sent=()):
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
    # --remotes=origin: origin's branches only (refs/remotes/origin/*), so a commit only another remote has is unsent.
    # --sent GLOB replaces it: the refs argo-it fetched every branch and tag GitHub has into.
    known = ['--glob=' + g for g in sent] or ['--remotes=origin']
    unsent = ['HEAD'] + [h.decode() for h in heads] + ['--not'] + known + ['--']
    # No commits yet (an unborn HEAD): nothing is saved, so nothing saved is unsent; staged() diffs against no commit.
    born = subprocess.run(GIT + ['rev-parse', '-q', '--verify', 'HEAD'], cwd=top, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0
    if commit is not None:  # one commit by its id (argo-it's save, on no branch): what a push of that id sends
        if not re.fullmatch(r'[0-9a-f]{40,64}', commit) or subprocess.run(
                GIT + ['rev-parse', '-q', '--verify', commit + '^{commit}'], cwd=top, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL).returncode:
            raise Fail('not a commit id')
        unsent, born = [commit, '--not'] + known + ['--'], True
    st = [t for t in git_out(top, *LOG, '-z', '--name-status', *unsent).split(b'\0') if t] if born else []
    changed = list(zip(st[1::2], st[::2]))  # (path, status), per commit; a merge's status has one letter per parent
    # A keep-out file an unsent commit adds or changes is a hit by its name alone, at line 1: the push sends it.
    # Its lines are never scanned. A deletion (D from every parent) sends nothing. A .env* file is the exception
    # (owner's call, see by_line): its lines are checked as before, so a public setting (NEXT_PUBLIC_*) doesn't
    # stop a send.
    keep = {p for p, _ in changed if kept_out(p) and not by_line(p)}
    rows = added_lines(git_lines(top, *LOG, '-p', *DIFF, *unsent),
                       headers(b'\0'.join(p for p, _ in changed))) if born else []
    saved = collect((r for r in rows if r[0] not in keep), blob, lfs)
    saved |= {(p, 1) for p, s in changed if p in keep and s.strip(b'D')}
    if commit is not None:  # the working tree and the index aren't in that commit
        return set(), set(), saved

    # argo-it's save step adds `!.env.example` to .gitignore, so list untracked files exactly as it then stages them.
    # Its other .gitignore lines make the keep-out files ignored: never hash those.
    untracked = [p for p in git_out(top, 'ls-files', '--others', '--exclude-standard', '--exclude=!.env.example',
                                    '-z').split(b'\0') if p and not kept_out(p)]
    # argo-it's save takes its own files in by name, whatever .gitignore says, so `--also` lists them unignored too
    # (named from where the scan runs, as argo-it names them).
    if also:
        untracked += [p for p in git_out(repo, 'ls-files', '--others', '--full-name', '-z', '--',
                                         *(':(literal)' + a for a in also)).split(b'\0')
                      if p and not kept_out(p) and p not in untracked]
    rows, added = staged(top, untracked, ['HEAD'] if born else [])
    unsaved = collect((r for r in rows if r[0] not in added), blob, lfs)
    new = collect((r for r in rows if r[0] in added), blob, lfs)
    return unsaved, new, saved


def main():
    ap = argparse.ArgumentParser(description='Find hardcoded secrets in what argo-it is about to send.')
    ap.add_argument('--repo', default='.', help='repo to scan (default: the current directory)')
    ap.add_argument('--commit', metavar='ID', help="check only this commit, by its full id (it and every commit it "
                                                    "reaches that origin doesn't have)")
    ap.add_argument('--also', nargs='+', default=[], metavar='PATH', help="also check these new files, even when "
                                                                       ".gitignore hides them")
    ap.add_argument('--sent', action='append', default=[], metavar='GLOB', help="count what these refs reach as "
                                                                                "sent (repeatable)")
    a = ap.parse_args()
    try:
        scopes = scan(a.repo, a.commit, a.also, a.sent)
    except Exception as e:  # anything unexpected is "couldn't check" -- never a traceback that could quote data
        sys.stderr.write("secret-scan: couldn't check: %s\n" % (e if isinstance(e, Fail) else type(e).__name__))
        return 2
    out = sys.stdout.buffer
    for label, hits in zip(LABELS, scopes):
        out.write(label + b'\n')
        for path, n in sorted(hits):
            out.write(b'%s:%d\n' % (shown(path), n))
    return 1 if any(scopes) else 0


if __name__ == '__main__':
    sys.exit(main())
