# Counting adoption across your repositories (the adoption scan)

For administrators. One read-only script sorts every repository in a GitHub organisation into one
class: built with make-it, using Claude Code without make-it, or neither. It also counts the make-it
steps recorded in each project's seal history. It sends nothing anywhere but GitHub's own API, and
it only reads.

Script: `.claude/make-it/scripts/adoption-scan.py` (installed at
`~/.claude/make-it/scripts/adoption-scan.py`). Python standard library and the `gh` CLI, nothing else.

## Running it

Sign in to `gh` as someone who can read the organisation's repositories, then run it from a folder
that is not inside a git project:

```bash
python3 -I "$HOME/.claude/make-it/scripts/adoption-scan.py" --org <your-org>
```

| Option | What it does |
|---|---|
| `--org <name>` | The organisation to scan. |
| `--user <name>` | A personal account instead of an organisation (its own repositories). If you pass `--org` with a personal account's name, the scan says so and tells you to use `--user`. |
| `--limit <n>` | Scan only the first n repositories, in name order. Good for a first try. |
| `--page-size <n>` | Repositories per query, 1 to 100 (default 20). If GitHub times out, the scan halves the page on its own, down to one. |
| `--trailers` | Also search commits for a `Co-Authored-By: Claude` trailer (MA7). |
| `--ci-pattern <text>` | The text a workflow's `uses:` line holds when it calls your organisation's reusable CI, for example `your-org/shared-ci/.github/workflows/build.yml`. The scan records the ref after `@` (MA4). |
| `--out <folder>` | Where to write the results. Default: a new folder named for the date and time, in the current folder. |

**Exit codes.** 0: every repository was scanned. 3: it finished, but some repositories could not be
scanned or a search failed (the summary says which part). 2: it could not scan at all (gh missing or
signed out, no such organisation, an output folder it refused, a bad option).

**How long.** A run over a few thousand repositories takes about a quarter of an hour at the default
page size. A run over 30 repositories with `--trailers` took about a minute and a half, most of it
the commit search's pages, which are paced to GitHub's search limit.

## What it looks for (signals)

Default branches only. Each repository is read with GitHub's GraphQL API by path
(`HEAD:<path>`), many repositories to a query. Nothing is cloned.

| Signal | What it is | Where it looks |
|---|---|---|
| **MA0** decision file | make-it's record of the app's decisions. Every make-it version writes it, so it finds apps built before the build record existed. | `.make-it/app-context.json`, `app-context.json` at the root, `.make-it-state.md`, and one code search for `app-context.json` anywhere in the organisation |
| **MA1** build record | Written by make-it's seal. The scan reads its make-it version, project type and scaffold. | `.make-it/manifest.json` |
| **MA2** seal history | One entry per make-it run that changed code. Counted per skill, with the latest date and the make-it versions seen. An entry it cannot read (damaged, oddly named, too big) is counted but not broken down. | `.make-it/ledger/` |
| **MA3** readable seal | Whether the file exists. Not whether it is right. | `MAKE-IT.md` |
| **MA4** reusable CI | Workflows whose text holds your `--ci-pattern`, and the ref they call it at. | `.github/workflows/*.yml`, `*.yaml` |
| **MA5** /ship-it requests | Pull requests labelled `ship-it-managed`: how many, and the newest. | Pull requests |
| **MA6** Claude Code files | Claude Code's project files. | `CLAUDE.md`, `.claude/` |
| **MA7** Claude commits | Commits with a `Co-Authored-By: Claude` trailer (`--trailers` only). | One commit search |

## The classes

Each repository gets exactly one:

| Class | Means |
|---|---|
| **make-it** | It has a build record (MA1). |
| **make-it, no build record** | It has the decision file, a seal history or `MAKE-IT.md`, but no build record. Usually an app built with an older make-it. |
| **Claude Code, no make-it** | Claude Code's files or Claude commit trailers, and nothing from make-it. |
| **no signal** | None of the above was found. |
| **not scanned** | GitHub would not answer for it, even on its own. It is never counted as "no signal": run the scan again later. |

**Why the decision file matters.** A scan that looks only for the build record finds nothing in an
organisation whose apps predate it: the build record is recent, and older apps carry only the
decision file. MA0 is what finds them, and the summary says how many were found that way.

Archived repositories are scanned and listed apart. They are left out of every count.

## What you get

A summary on screen, in plain words: the count in each class; how many repositories carry a build
record, a seal history and `MAKE-IT.md`; make-it steps from the seal histories per skill; CI callers
by ref; /ship-it repositories and requests; trailer counts; how many could not be scanned; how long
it took. And two files in the output folder, one row per repository: `adoption-scan.json` and
`adoption-scan.csv`.

**Keep the files internal.** They list the organisation's repository names. The scan writes them
only into the folder you choose (or its new dated folder), readable only by you, never over an
existing file, and it refuses a folder inside a git project unless git ignores it, so a commit can't
publish them by accident. In the CSV, a cell that starts with `=`, `+`, `-` or `@` gets a leading `'`,
so a spreadsheet never runs it as a formula.

## What it cannot tell you

- **Whether a seal is intact.** Presence is not validity. The scan never checks a seal and never says
  one is intact: `watermark.py verify` does that, in each repository's merge gate
  (`watermark.md` section 3).
- **Anything off the default branch.** Work on other branches is not seen; nor is GitHub's code
  search, which also skips files of 384 KB or more.
- **Every Claude commit.** GitHub's search returns at most 1,000 results, so the trailer count is a
  lower bound, and the summary says so. A trailer can also be typed by hand or removed.
- **Who ran make-it, or when, beyond the seal history's dates.** For people and activity, see
  Claude Code's own usage reporting (the usage-monitoring guide).
- **A `ship-it-managed` label that was never added.** MA5 counts labels, so a team that doesn't label
  its requests shows none.

## Read-only, and how that is enforced

- It uses the `gh` sign-in you already have. It never takes a token as an option, never reads one,
  and never prints what `gh` itself says (only GitHub's answers, as data).
- Every GraphQL request is a query. The script refuses to send anything containing `mutation`, before
  `gh` runs. Every other request is a `GET` to GitHub's two search endpoints, and the script refuses
  any other path.
- Values are passed to `gh` as plain strings (`-f`), never as `@file`, and never through a shell.
- Everything a repository holds is untrusted: names are checked before they are used, file sizes are
  capped, damaged JSON is counted and skipped, and nothing is run.
- `scripts/test-adoption-scan.py` pins all of this against a stub `gh` and synthetic answers. Its
  workflow is `.github/workflows/adoption-scan.yml`.

## Sign-in and scopes

Check your sign-in with `gh auth status`; its "Token scopes" line lists what `gh` can do.

- **`repo`** is needed to read private repositories. GitHub's scope list describes it as "full access
  to public and private repositories including read and write access to code": there is no read-only
  scope for private code. The scan only reads, but the sign-in itself could write, so run it as an
  account you trust with that.
- **`read:org`** gives read-only access to organisation membership. `gh` asks for it by default
  (the `gh auth login` manual lists `repo`, `read:org` and `gist` as the minimum for a token).
- A public-only scan works with less, but private repositories then go uncounted.
- Not checked: whether an organisation that enforces SAML single sign-on needs the `gh` sign-in
  authorised for it first, and whether a fine-grained, read-only token used through `gh` covers every
  query. Try `--limit 5` first.

Sources (checked 2026-11-22):
https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps,
https://cli.github.com/manual/gh_auth_login.

## Rate limits (what the scan respects)

Checked on 2026-11-22 against GitHub's documentation:

- **Search:** code search allows 10 requests a minute; other searches 30. Each search returns at most
  1,000 results; code search covers the default branch only and files under 384 KB. The scan spaces
  its code-search pages 6.5 seconds apart and its commit-search pages 2.1 seconds apart.
  https://docs.github.com/en/rest/search/search
- **Secondary limits:** a limited answer is a 403 or 429. The scan waits for `retry-after` if given,
  or until `x-ratelimit-reset` if nothing is left, or else at least a minute, then longer, and gives
  up after four tries (that part is then reported, never read as empty).
  https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
- **GraphQL:** 5,000 points an hour for a user; a request that takes more than 10 seconds is stopped
  (a 502 or 504), and a query over its resource limits returns partial results with an error. The
  scan then halves the page and tries again, down to one repository; one that still fails is "not
  scanned". When fewer than 50 points are left it waits for the reset.
  https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api

## Not proven

Tested against synthetic answers and one real run over 30 repositories of a personal account. Not
run against a large organisation, and not against GitHub Enterprise Server (`gh` reaches one through its
`GH_HOST` setting; not tried).
