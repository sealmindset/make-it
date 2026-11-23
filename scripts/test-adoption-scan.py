#!/usr/bin/env python3
"""Contract test for adoption-scan.py. Run: python3 -I scripts/test-adoption-scan.py

The scan reads an organisation's repositories through `gh` and sorts each into one class. Here a stub
`gh` on PATH serves hand-written answers shaped like GitHub's (scripts/adoption-scan-fixtures/, no
real organisation's data) and records every call, so the test can prove what the scan asked for as
well as what it concluded. The scan runs in-process so its waits are recorded, not slept.
"""
import contextlib
import csv
import importlib.util
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, ".claude", "make-it", "scripts", "adoption-scan.py")
FIXTURE = os.path.join(ROOT, "scripts", "adoption-scan-fixtures", "example-org.json")
TOKEN = "ghp_" + "Q7x" * 12  # token-shaped, fake: the stub prints it on stderr to tempt a leak
TOKEN_SHAPE = re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}")

STUB = r'''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ["STUB_GH_LOG"], "a") as f:
    f.write(json.dumps(args) + "\n")
sys.stderr.write("gh: something went wrong for %s\n" % os.environ.get("STUB_TOKEN", ""))
fx = json.load(open(os.environ["STUB_GH_FIXTURE"]))
state_path = os.environ["STUB_GH_STATE"]
state = json.load(open(state_path)) if os.path.exists(state_path) else {}

def save():
    json.dump(state, open(state_path, "w"))

def reply(status, body, headers=None, code=0):
    head = {"Content-Type": "application/json", "X-Ratelimit-Remaining": "4000", "X-Ratelimit-Reset": "0"}
    head.update(headers or {})
    sys.stdout.write("HTTP/2.0 %d X\n" % status + "".join("%s: %s\n" % kv for kv in head.items()) + "\n")
    sys.stdout.write(body if isinstance(body, str) else json.dumps(body))
    sys.exit(code if status < 400 else 1)

def fields(a):
    out = {}
    for i, x in enumerate(a):
        if x in ("-f", "-F") and i + 1 < len(a):
            k, _, v = a[i + 1].partition("=")
            out[k] = v
    return out

def queued(kind):
    q = fx.get("failures", {}).get(kind, [])
    n = state.get(kind, 0)
    state[kind] = n + 1
    save()
    return q[n] if n < len(q) else None

if args[:1] != ["api"]:
    sys.exit(9)
if os.environ.get("STUB_EXIT"):  # gh failing before GitHub answers: 4 is gh's "not signed in"
    sys.exit(int(os.environ["STUB_EXIT"]))
f = fields(args)
if "graphql" in args:
    q = f["query"]
    if "repositoryOwner" in q:
        fail = queued("listing")
        if fail:
            reply(fail["status"], fail.get("body", "{}"), fail.get("headers"))
        own = fx["owner"]
        if f["login"].lower() != own["login"].lower():
            reply(200, {"data": {"repositoryOwner": None}})
        import re
        page = min(int(os.environ.get("STUB_LIST_PAGE", "100")), int(re.search(r"first: (\d+)", q).group(1)))
        start = int(f.get("after") or 0)
        lf = fx.get("listing_fail", {}).get(str(start))
        if lf:
            n = state.get("lf" + str(start), 0)
            state["lf" + str(start)] = n + 1
            save()
        if lf and n < lf.get("times", 999):
            err = {"type": "FORBIDDEN", "path": ["repositoryOwner", "repositories"],
                   "message": "Resource protected by organization SAML enforcement. You must grant your OAuth token access to this organization."} \
                if lf["kind"] == "sso" else {"path": ["repositoryOwner", "repositories"],
                                             "message": "Something went wrong while executing your query. This may be the result of a timeout"}
            if lf["kind"] == "error_with_list":
                chunk = fx["repos"][start:start + page]
                nodes = [{"name": r["name"], "nameWithOwner": own["login"] + "/" + r["name"], "isArchived": r["isArchived"],
                          "isFork": r["isFork"]} for r in chunk]
                reply(200, {"data": {"repositoryOwner": {"__typename": own["type"], "login": own["login"], "repositories": {
                    "pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": nodes}}},
                    "errors": [{"path": ["repositoryOwner", "repositories"], "message": "Something went wrong"}]}, code=1)
            reply(200, {"data": {"repositoryOwner": {"__typename": own["type"], "login": own["login"], "repositories": None}},
                        "errors": [err]}, {"X-GitHub-SSO": "required; url=https://github.com/orgs/example-org/sso?authorization_request=x"}
                  if lf["kind"] == "sso" else None, code=1)
        chunk = fx["repos"][start:start + page]
        nodes = [{"name": r["name"], "nameWithOwner": own["login"] + "/" + r["name"], "isArchived": r["isArchived"],
                  "isFork": r["isFork"]} for r in chunk]
        more = start + page < len(fx["repos"])
        reply(200, {"data": {"repositoryOwner": {"__typename": own["type"], "login": own["login"], "repositories": {
            "pageInfo": {"hasNextPage": more, "endCursor": str(start + page)}, "nodes": nodes}}}})
    fail = queued("content")
    if fail:
        reply(fail["status"], fail.get("body", "{}"), fail.get("headers"))
    names = {k: v for k, v in f.items() if k.startswith("n") and k[1:].isdigit()}
    by = {r["name"]: r for r in fx["repos"]}
    behaviours = [by.get(v, {}).get("behaviour") for v in names.values()]
    if "timeout" in behaviours or ("timeout_in_batch" in behaviours and len(names) > 1):
        reply(502, '{"message":"We couldn\'t respond to your request in time"}')
    if os.environ.get("STUB_BIG"):
        reply(200, '{"data": {"pad": "' + "x" * int(os.environ["STUB_BIG"]) + '"}}')
    if "pathless_in_batch" in behaviours and len(names) > 1:
        reply(200, {"data": None, "errors": [{"message": "Something went wrong while executing your query. "
                                                         "This may be the result of a timeout"}]}, code=1)
    data, errors = {}, []
    for k, v in names.items():
        alias, r = "r" + k[1:], by.get(v)
        if r is None or r.get("behaviour") == "error":
            data[alias] = None
            errors.append({"type": "SOMETHING", "path": [alias], "message": "Something went wrong"})
            continue
        c = {}
        for key in ("ctx", "rootctx", "state", "manifest", "ledger", "readable", "claudemd", "claudedir", "workflows"):
            if (key + ":") in q:
                c[key] = r["content"].get(key)
        c["shipit"] = r["content"].get("shipit", {"totalCount": 0, "nodes": []})
        data[alias] = c
    body = {"data": data}
    if errors:
        body["errors"] = errors
    reply(200, body, code=1 if errors else 0)
path = next(a for a in args if a.startswith("search/"))
kind = path.split("/")[1]
fail = queued(kind)
if fail:
    reply(fail["status"], fail.get("body", '{"message":"You have exceeded a secondary rate limit"}'), fail.get("headers"))
items = fx["code_search" if kind == "code" else "commit_search"]
per, page = int(f.get("per_page", 100)), int(f.get("page", 1))
per = int(os.environ.get("STUB_SEARCH_PAGE", per))
total = fx.get("commit_total", len(items)) if kind == "commits" else fx.get("code_total", len(items))
reply(200, {"total_count": total, "incomplete_results": False, "items": items[(page - 1) * per: page * per]})
'''


def load_module():
    spec = importlib.util.spec_from_file_location("adoption_scan", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="adoption-")
        self.bin = os.path.join(self.tmp, "bin")
        os.mkdir(self.bin)
        with open(os.path.join(self.bin, "gh"), "w") as f:
            f.write("#!" + sys.executable + "\n" + STUB)
        os.chmod(os.path.join(self.bin, "gh"), 0o755)
        self.log = os.path.join(self.tmp, "gh-log.jsonl")
        with open(FIXTURE) as f:
            self.fx = json.load(f)
        self.fixture_path = os.path.join(self.tmp, "fixture.json")
        self.env = {"PATH": self.bin + os.pathsep + os.environ.get("PATH", ""), "STUB_GH_LOG": self.log,
                    "STUB_GH_FIXTURE": self.fixture_path, "STUB_GH_STATE": os.path.join(self.tmp, "state.json"),
                    "STUB_TOKEN": TOKEN, "GH_TOKEN": TOKEN}
        self.out_n = 0
        self.mod = load_module()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def scan(self, *args, out=None):
        """Run the scan in-process: (exit code, stdout+stderr, written json or None, sleeps)."""
        with open(self.fixture_path, "w") as f:
            json.dump(self.fx, f)
        if os.path.exists(self.env["STUB_GH_STATE"]):
            os.remove(self.env["STUB_GH_STATE"])  # queued failures count from each run's start
        if out is None:
            self.out_n += 1
            out = os.path.join(self.tmp, f"out{self.out_n}")
        argv = list(args) if "--org" in args or "--user" in args else ["--org", "example-org", *args]
        buf, sleeps = io.StringIO(), []
        with mock.patch.dict(os.environ, self.env), mock.patch.object(self.mod, "SLEEP", sleeps.append), \
                contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            try:
                code = self.mod.main([*argv, "--out", out])
            except SystemExit as e:
                code = e.code
        data = None
        if os.path.exists(os.path.join(out, "adoption-scan.json")):
            with open(os.path.join(out, "adoption-scan.json")) as f:
                data = json.load(f)
        self.last_out = out
        return code, buf.getvalue(), data, sleeps

    def calls(self):
        if not os.path.exists(self.log):
            return []
        with open(self.log) as f:
            return [json.loads(l) for l in f]

    def content_calls(self):
        return [c for c in self.calls() if "graphql" in c and "repositoryOwner" not in self.query(c)]

    @staticmethod
    def query(call):
        i = call.index("-f")
        return call[i + 1]

    @staticmethod
    def by_repo(data):
        return {r["repository"].split("/", 1)[1]: r for r in data["repositories"]}


class Classes(Base):
    def test_each_class(self):
        code, out, data, _ = self.scan("--trailers")
        got = {k: v["class"] for k, v in self.by_repo(data).items()}
        self.assertEqual(got["app-one"], "make-it")
        self.assertEqual(got["app-two"], "make-it, no build record")
        self.assertEqual(got["app-three"], "make-it, no build record")
        self.assertEqual(got["app-four"], "Claude Code, no make-it")
        self.assertEqual(got["app-five"], "Claude Code, no make-it")  # its trailer commits only
        self.assertEqual(got["app-six"], "no signal")
        self.assertEqual(got["app-eight"], "not scanned")
        self.assertEqual(got["app-nine"], "make-it, no build record")  # root app-context.json
        self.assertEqual(got["app-ten"], "make-it")
        self.assertEqual(got['bad"name){x}'], "not scanned")
        self.assertEqual(code, 3, out)  # finished, with repositories it could not scan

    def test_without_trailers_a_trailer_only_repository_is_no_signal_and_no_commit_search_runs(self):
        _, _, data, _ = self.scan()
        self.assertEqual(self.by_repo(data)["app-five"]["class"], "no signal")
        self.assertFalse([c for c in self.calls() if "search/commits" in c])
        self.assertIsNone(self.by_repo(data)["app-five"]["ma7_trailer_commits"])

    def test_the_lesson_the_decision_file_alone_finds_older_make_it_apps(self):
        """A scan that looks only for the build record finds none of these: MA0 is what finds them."""
        code, out, data, _ = self.scan()
        repos = self.by_repo(data)
        for name in ("app-two", "app-three", "app-nine"):
            self.assertFalse(repos[name]["ma1_build_record"], name)
            self.assertTrue(repos[name]["ma0_decision_file"], name)
            self.assertEqual(repos[name]["class"], "make-it, no build record", name)
        self.assertIn("app-context.json elsewhere (code search)", repos["app-three"]["ma0_where"])
        self.assertIn(".make-it/app-context.json", repos["app-two"]["ma0_where"])
        self.assertIn(".make-it-state.md", repos["app-two"]["ma0_where"])
        self.assertIn("app-context.json", repos["app-nine"]["ma0_where"])
        self.assertRegex(out, r"3 were found by make-it's decision file")
        # an organisation whose apps all predate the build record still counts them
        for r in self.fx["repos"]:
            for k in ("manifest", "ledger", "readable"):
                r["content"].pop(k, None)
        _, _, data, _ = self.scan()
        self.assertEqual(data["counts"]["make-it, no build record"], 4)  # app-one now too; archived app-seven not counted
        self.assertEqual(data["counts"]["make-it"], 0)

    def test_a_search_hit_outside_the_listed_repositories_is_ignored(self):
        _, _, data, _ = self.scan()
        self.assertNotIn("not-listed", self.by_repo(data))


class Signals(Base):
    def test_build_record_ledger_seal_and_ship_it(self):
        _, out, data, _ = self.scan("--ci-pattern", "example-org/shared-ci/.github/workflows/build.yml")
        one = self.by_repo(data)["app-one"]
        self.assertEqual((one["ma1_version"], one["ma1_type"], one["ma1_scaffold"]), ("1.71.16", "web-app", "fastapi-nextjs"))
        self.assertTrue(one["ma1_readable"])
        self.assertTrue(one["ma3_make_it_md"])
        self.assertTrue(one["ma6_claude_files"])
        self.assertEqual((one["ma5_ship_it_prs"], one["ma5_latest"]), (3, "2026-10-01"))
        self.assertEqual(one["ma4_ci_refs"], ["v2"])  # README.md is not a workflow
        self.assertEqual(self.by_repo(data)["app-two"]["ma4_ci_refs"], ["main"])
        self.assertIn("v2 (1)", out)
        self.assertIn("main (1)", out)

    def test_a_malformed_ledger_entry_is_counted_but_not_parsed(self):
        _, out, data, _ = self.scan()
        one = self.by_repo(data)["app-one"]
        # 0001 and 0002 parse; 0003 is not JSON; notes.json is not an entry's name; .DS_Store is not history
        self.assertEqual(one["ma2_ledger_entries"], 4)
        self.assertEqual(one["ma2_unreadable"], 2)
        self.assertEqual(one["ma2_skills"], {"make-it": 1, "resume-it": 1})
        self.assertEqual(one["ma2_latest"], "2026-10-02")
        self.assertEqual(one["ma2_versions"], ["1.70.0", "1.71.16"])
        ten = self.by_repo(data)["app-ten"]
        self.assertEqual((ten["ma2_ledger_entries"], ten["ma2_unreadable"], ten["ma2_too_large"]), (3, 1, 1))  # a bad skill name; truncated
        self.assertEqual(ten["ma2_skills"], {"fix-it": 1})
        self.assertRegex(out, r"could not be read")

    def test_hostile_files_are_parsed_defensively(self):
        deep = "[" * 100000 + "]" * 100000
        self.fx["repos"][5]["content"] = {
            "manifest": {"__typename": "Blob", "byteSize": len(deep), "isTruncated": False, "text": deep},
            "ledger": {"__typename": "Tree", "entries": [
                {"name": "0001-0123456789ab.json", "type": "blob",
                 "object": {"__typename": "Blob", "byteSize": len(deep), "isTruncated": False, "text": deep}},
                {"name": "0002-0123456789ab.json", "type": "blob",
                 "object": {"__typename": "Blob", "byteSize": 30, "isTruncated": False, "text": "1" * 5000}},
                {"name": "0003-0123456789ab.json", "type": "blob", "object": None}]}}
        code, out, data, _ = self.scan()
        six = self.by_repo(data)["app-six"]
        self.assertTrue(six["ma1_build_record"])
        self.assertFalse(six["ma1_readable"])
        self.assertEqual((six["ma2_ledger_entries"], six["ma2_unreadable"], six["ma2_too_large"]), (3, 2, 1))
        self.assertEqual(six["class"], "make-it")

    def test_the_commit_search_note_says_it_is_a_lower_bound(self):
        _, out, data, _ = self.scan("--trailers")
        self.assertEqual(self.by_repo(data)["app-five"]["ma7_trailer_commits"], 2)
        self.assertIn("at most 1,000", out)
        self.assertTrue(any("1,000" in n for n in data["notes"]))
        q = [c for c in self.calls() if "search/commits" in c]
        self.assertTrue(q)
        self.assertIn('q=org:example-org "Co-Authored-By: Claude"', q[0])


class Failures(Base):
    def test_a_partial_error_marks_only_that_repository_not_scanned(self):
        _, out, data, _ = self.scan()
        repos = self.by_repo(data)
        self.assertEqual(repos["app-eight"]["class"], "not scanned")
        self.assertIsNone(repos["app-eight"]["ma0_decision_file"])  # never read as "no signal"
        self.assertEqual(repos["app-seven"]["class"], "make-it")
        self.assertEqual(repos["app-one"]["class"], "make-it")
        alone = [c for c in self.content_calls() if sum(1 for a in c if a.startswith("n") and a[1:2].isdigit()) == 1]
        self.assertTrue(any("n0=app-eight" in c for c in alone), "the failing repository is tried once more on its own")
        self.assertRegex(out, r"not scanned\s+2")
        self.assertIn('NOT counted as "no signal"', out)

    def test_a_timeout_shrinks_the_page_down_to_one(self):
        _, _, data, _ = self.scan("--page-size", "8")
        sizes = [sum(1 for a in c if re.fullmatch(r"n\d+=.*", a)) for c in self.content_calls()]
        self.assertEqual(sizes[0], 8)
        self.assertIn(1, sizes)
        self.assertEqual(self.by_repo(data)["app-nine"]["class"], "make-it, no build record")

    def test_a_repository_that_always_times_out_is_not_scanned_and_the_rest_are(self):
        self.fx["repos"][8]["behaviour"] = "timeout"
        code, _, data, _ = self.scan()
        repos = self.by_repo(data)
        self.assertEqual(repos["app-nine"]["class"], "not scanned")
        self.assertEqual(repos["app-one"]["class"], "make-it")
        self.assertEqual(code, 3)

    def test_an_error_naming_no_repository_shrinks_the_page_too(self):
        self.fx["repos"][3]["behaviour"] = "pathless_in_batch"
        code, _, data, _ = self.scan("--page-size", "4")
        repos = self.by_repo(data)
        self.assertEqual(repos["app-four"]["class"], "Claude Code, no make-it")
        self.assertEqual(repos["app-one"]["class"], "make-it")
        sizes = [sum(1 for a in c if re.fullmatch(r"n\d+=.*", a)) for c in self.content_calls()]
        self.assertEqual(sizes[:3], [4, 2, 2])

    def test_graphql_rate_limited_waits_then_goes_on(self):
        self.fx["failures"] = {"content": [{"status": 200, "body": json.dumps(
            {"errors": [{"type": "RATE_LIMITED", "message": "API rate limit exceeded"}]})}]}
        _, _, data, sleeps = self.scan()
        self.assertIn(60, sleeps)
        self.assertEqual(self.by_repo(data)["app-one"]["class"], "make-it")

    def test_an_invalid_repository_name_is_never_sent(self):
        self.scan()
        self.assertFalse([c for c in self.calls() if any("bad" in a for a in c)])

    def test_a_rate_limited_search_waits_as_github_says(self):
        self.fx["failures"] = {"code": [{"status": 403, "headers": {"Retry-After": "7"}}, {"status": 429}]}
        code, _, data, sleeps = self.scan()
        self.assertIn(7, [round(s) for s in sleeps])
        self.assertTrue(any(s >= 60 for s in sleeps), sleeps)  # no header: at least a minute
        self.assertEqual(self.by_repo(data)["app-three"]["class"], "make-it, no build record")

    def test_code_search_pages_are_spaced_to_its_limit(self):
        self.env["STUB_SEARCH_PAGE"] = "1"
        _, _, data, sleeps = self.scan()
        self.assertEqual(len([c for c in self.calls() if "search/code" in c]), 3)  # three hits, one a page
        self.assertGreaterEqual(min(sleeps), 6, sleeps)  # 10 a minute

    def test_a_search_that_keeps_failing_is_reported_never_read_as_no_hits(self):
        self.fx["failures"] = {"code": [{"status": 403}] * 10}
        code, out, data, _ = self.scan()
        self.assertEqual(code, 3)
        self.assertIn("code search failed", out)

    def test_a_personal_account_is_named_plainly(self):
        self.fx["owner"]["type"] = "User"
        code, out, data, _ = self.scan()
        self.assertEqual(code, 2)
        self.assertIn("personal account", out)
        self.assertIn("--user example-org", out)
        self.assertIsNone(data)

    def test_user_scans_a_personal_account(self):
        self.fx["owner"]["type"] = "User"
        code, out, data, _ = self.scan("--user", "example-org", "--trailers")
        self.assertEqual(self.by_repo(data)["app-one"]["class"], "make-it")
        searches = [c for c in self.calls() if any(a.startswith("search/") for a in c)]
        self.assertTrue(searches)
        self.assertTrue(all(any(a.startswith("q=user:example-org ") for a in c) for c in searches))
        self.fx["owner"]["type"] = "Organization"
        code, out, _, _ = self.scan("--user", "example-org")
        self.assertEqual(code, 2)
        self.assertIn("--org example-org", out)

    def test_an_unknown_owner_or_failed_listing_exits_2(self):
        code, out, data, _ = self.scan("--org", "nobody-here")
        self.assertEqual(code, 2)
        self.assertIn("No organisation", out)
        self.fx["failures"] = {"listing": [{"status": 401}]}
        code, out, _, _ = self.scan()
        self.assertEqual(code, 2)
        self.assertIn("gh auth login", out)


class Arguments(Base):
    def test_limit_and_page_size(self):
        self.env["STUB_LIST_PAGE"] = "2"
        code, _, data, _ = self.scan("--limit", "3", "--page-size", "2")
        self.assertEqual([r["repository"] for r in data["repositories"]],
                         ["example-org/app-one", "example-org/app-two", "example-org/app-three"])
        self.assertTrue(all(sum(1 for a in c if re.fullmatch(r"n\d+=.*", a)) <= 2 for c in self.content_calls()))
        self.assertEqual(code, 0)
        for bad in (["--page-size", "0"], ["--page-size", "101"], ["--limit", "0"], ["--org", "a b"],
                    ["--ci-pattern", ""]):
            self.assertEqual(self.scan(*bad)[0], 2, bad)

    def test_no_ci_pattern_means_no_workflow_reading(self):
        _, out, data, _ = self.scan()
        self.assertFalse(any("HEAD:.github/workflows" in self.query(c) for c in self.content_calls()))
        self.assertIsNone(self.by_repo(data)["app-one"]["ma4_ci_refs"])

    def test_help_documents_exit_codes(self):
        p = subprocess.run([sys.executable, "-I", SCRIPT, "--help"], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0)
        for must in ("0 ", "2 ", "3 ", "4 ", "INCOMPLETE", "read-only", "--user"):
            self.assertIn(must, p.stdout)


class ReadOnly(Base):
    def test_every_call_is_a_read(self):
        self.scan("--trailers", "--ci-pattern", "example-org/shared-ci")
        calls = self.calls()
        self.assertGreater(len(calls), 5)
        for c in calls:
            self.assertEqual(c[:2], ["api", "-i"], c)
            if "graphql" in c:
                body = " ".join(c)
                self.assertNotRegex(body.lower(), r"mutation", c)
                self.assertTrue(self.query(c).startswith("query=query"), c)
            else:
                self.assertEqual(c[2:4], ["-X", "GET"], c)
                self.assertIn(c[4], ("search/code", "search/commits"))
            self.assertFalse([a for a in c if a in ("-F", "--field", "--input")], c)  # no @file reading

    def test_a_mutation_is_refused_before_gh_runs(self):
        with mock.patch.dict(os.environ, self.env):
            for q in ("mutation { addStar(input: {}) { clientMutationId } }", "query { a } MUTATION { b }",
                      "{ viewer { login } }"):
                with self.assertRaises(RuntimeError):
                    self.mod.gh_graphql(q, {})
            with self.assertRaises(RuntimeError):
                self.mod.gh_get("repos/example-org/app-one/issues", {})
        self.assertEqual(self.calls(), [])

    def test_no_token_shaped_string_is_ever_printed_or_written(self):
        self.fx["repos"][5]["content"] = {"manifest": {"__typename": "Blob", "byteSize": 80, "isTruncated": False,
                                                       "text": json.dumps({"project": {"type": TOKEN}})}}
        for args in ([], ["--trailers"], ["--org", "nobody-here"]):
            _, out, _, _ = self.scan(*args)
            self.assertNotRegex(out, TOKEN_SHAPE)
            for root, _, files in os.walk(self.last_out):
                for n in files:
                    with open(os.path.join(root, n)) as f:
                        self.assertNotRegex(f.read(), TOKEN_SHAPE, n)
        self.assertFalse(any("token" in a.lower() for c in self.calls() for a in c))


class Output(Base):
    def test_csv_cells_cannot_become_formulas(self):
        self.scan()
        with open(os.path.join(self.last_out, "adoption-scan.csv"), newline="") as f:
            rows = list(csv.reader(f))
        for row in rows:
            for cell in row:
                self.assertNotIn(cell[:1], ("=", "+", "-", "@", "\t", "\r"), row)
        ten = next(r for r in rows if r[0] == "example-org/app-ten")
        self.assertIn("'=cmd|' /C calc'!A0", ten)
        self.assertIn("'+SUM(1,1)", ten)
        self.assertIn("'@evil", ten)
        with open(os.path.join(self.last_out, "adoption-scan.csv")) as f:
            self.assertTrue(f.readline().startswith('"repository"'))  # every field quoted

    def test_archived_are_listed_and_left_out_of_the_counts(self):
        _, out, data, _ = self.scan()
        self.assertTrue(self.by_repo(data)["app-seven"]["archived"])
        self.assertRegex(out, r"11 repositories looked at: 10 active, 1 archived")
        self.assertRegex(out, r"(?m)^\s+make-it\s+2$")  # app-one, app-ten; not archived app-seven
        self.assertIn("Archived (not counted): 1", out)
        self.assertNotIn("app-seven", out)  # names stay in the files
        self.assertEqual(data["counts"]["make-it"], 2)

    def test_no_repository_name_is_printed_by_default(self):
        for args in ([], ["--trailers", "--ci-pattern", "example-org/shared-ci"]):
            _, out, data, _ = self.scan(*args)
            self.assertNotIn("app-", out)
            self.assertNotIn("bad", out)
            self.assertIn("example-org/app-seven", [r["repository"] for r in data["repositories"]])

    def test_the_closing_line_fits_the_mode(self):
        _, out, _, _ = self.scan()
        self.assertIn("the organisation's repository names", out)
        self.fx["owner"]["type"] = "User"
        _, out, _, _ = self.scan("--user", "example-org")
        self.assertIn("the account's repository names", out)
        self.assertNotIn("organisation's repository names", out)

    def test_output_files_are_created_exclusively(self):
        target = os.path.join(self.tmp, "exists.json")
        with open(target, "w") as f:
            f.write("{}")
        with self.assertRaises(FileExistsError):
            self.mod.write_file(target, "x")
        os.symlink(os.path.join(self.tmp, "elsewhere.json"), os.path.join(self.tmp, "link.json"))
        with self.assertRaises(OSError):
            self.mod.write_file(os.path.join(self.tmp, "link.json"), "x")
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "elsewhere.json")))

    def test_the_summary_never_says_a_seal_is_intact(self):
        _, out, _, _ = self.scan()
        self.assertIn("does not check", out)
        self.assertNotRegex(out.lower(), r"seals? (is|are) (intact|valid)|verified seal")
        self.assertRegex(out, r"Took \d")

    def test_refuses_to_write_inside_a_git_project_unless_ignored(self):
        repo = os.path.join(self.tmp, "repo")
        os.mkdir(repo)
        subprocess.run(["git", "init", "-q", repo], check=True)
        code, out, data, _ = self.scan(out=os.path.join(repo, "scan"))
        self.assertEqual(code, 2)
        self.assertIn("repository names", out)
        self.assertFalse(os.path.exists(os.path.join(repo, "scan")))
        self.assertEqual(self.calls(), [], "refused before asking GitHub anything")
        os.mkdir(os.path.join(repo, "sub"))
        os.symlink(os.path.join(repo, "sub"), os.path.join(self.tmp, "looks-outside"))
        self.assertEqual(self.scan(out=os.path.join(self.tmp, "looks-outside", "scan"))[0], 2)  # a link can't hide it
        with open(os.path.join(repo, ".gitignore"), "w") as f:
            f.write("scan/\n")
        code, _, data, _ = self.scan(out=os.path.join(repo, "scan"))
        self.assertIsNotNone(data)
        self.assertEqual(oct(os.stat(os.path.join(repo, "scan", "adoption-scan.json")).st_mode & 0o777), "0o600")

    def test_never_overwrites_and_never_follows_a_link(self):
        out = os.path.join(self.tmp, "o")
        self.scan(out=out)
        self.assertEqual(self.scan(out=out)[0], 2)
        os.symlink(self.tmp, os.path.join(self.tmp, "link"))
        self.assertEqual(self.scan(out=os.path.join(self.tmp, "link"))[0], 2)

    def test_default_folder_is_new_and_dated(self):
        cwd = os.getcwd()
        os.chdir(self.tmp)
        try:
            with open(self.fixture_path, "w") as f:
                json.dump(self.fx, f)
            buf = io.StringIO()
            with mock.patch.dict(os.environ, self.env), mock.patch.object(self.mod, "SLEEP", lambda s: None), \
                    contextlib.redirect_stdout(buf):
                self.mod.main(["--org", "example-org", "--limit", "1"])
                self.mod.main(["--org", "example-org", "--limit", "1"])
        finally:
            os.chdir(cwd)
        made = sorted(n for n in os.listdir(self.tmp) if n.startswith("adoption-scan-"))
        self.assertEqual(len(made), 2, made)
        self.assertRegex(made[0], r"^adoption-scan-\d{4}-\d{2}-\d{2}")


class Listing(Base):
    """Fix round 1: a listing that fails part-way never reads as a complete count."""

    def listing_calls(self):
        return [c for c in self.calls() if "graphql" in c and "repositoryOwner" in self.query(c)]

    def test_an_error_on_a_later_page_marks_the_run_incomplete(self):
        self.env["STUB_LIST_PAGE"] = "2"
        self.fx["listing_fail"] = {"2": {"kind": "timeout"}}
        code, out, data, sleeps = self.scan()
        self.assertEqual(code, 4, out)
        self.assertIn("INCOMPLETE", out)
        self.assertIn("listing stopped after 2 repositories", out)
        self.assertTrue(data["incomplete"].startswith("listing stopped after 2 repositories"), data["incomplete"])
        self.assertEqual(len(data["repositories"]), 2)
        with open(os.path.join(self.last_out, "adoption-scan.csv"), newline="") as f:
            rows = list(csv.DictReader(f))
        self.assertTrue(rows and all(r["scan_status"].startswith("INCOMPLETE: listing stopped after 2") for r in rows))
        firsts = [int(re.search(r"first: (\d+)", self.query(c)).group(1)) for c in self.listing_calls()]
        self.assertIn(1, firsts)  # the listing's page shrinks too
        self.assertTrue(sleeps)   # and it waits between tries

    def test_a_listing_error_that_clears_on_retry_completes(self):
        self.env["STUB_LIST_PAGE"] = "2"
        self.fx["listing_fail"] = {"2": {"kind": "timeout", "times": 1}}
        code, out, data, _ = self.scan()
        self.assertIsNone(data["incomplete"])
        self.assertEqual(len(data["repositories"]), 11)
        self.assertEqual(code, 3)  # app-eight and the bad name, as ever
        self.assertNotIn("INCOMPLETE", out)

    def test_single_sign_on_is_named_with_what_to_do(self):
        self.fx["listing_fail"] = {"0": {"kind": "sso"}}
        code, out, data, _ = self.scan()
        self.assertEqual(code, 4)
        self.assertIn("single sign-on", out)
        self.assertIn("gh auth", out)
        self.assertEqual(len(self.listing_calls()), 1)  # retrying cannot help
        self.assertEqual(data["repositories"], [])
        self.assertIn("single sign-on", data["incomplete"])

    def test_a_failure_on_the_first_page_is_incomplete_not_zero(self):
        self.fx["listing_fail"] = {"0": {"kind": "timeout"}}
        code, out, data, _ = self.scan()
        self.assertEqual(code, 4)
        self.assertIn("listing stopped after 0 repositories", out)
        self.assertNotRegex(out, r"(?m)^\s+no signal\s+0$")  # no class table that reads as a clean count


class FixRound(Base):
    def test_a_capped_code_search_is_said(self):
        self.fx["code_total"] = 5000
        code, out, data, _ = self.scan()
        self.assertEqual(code, 3)
        self.assertIn("code search was capped", out)
        self.assertTrue(any("code search was capped" in n for n in data["notes"]))

    def test_decision_file_and_seal_only_are_counted_apart(self):
        entry = {"name": "0001-0123456789ab.json", "type": "blob", "object": {
            "__typename": "Blob", "byteSize": 99, "isTruncated": False,
            "text": json.dumps({"schema": 1, "skill": "make-it", "date": "2026-01-01", "make_it": {"version": "1.0"}})}}
        self.fx["repos"][5]["content"] = {"ledger": {"__typename": "Tree", "entries": [entry]}}  # app-six
        self.fx["repos"][3]["content"] = {"readable": {"__typename": "Blob"}}                     # app-four
        _, out, _, _ = self.scan()
        self.assertIn("3 were found by make-it's decision file", out)
        self.assertIn("2 by a seal history or MAKE-IT.md alone", out)

    def test_a_too_large_answer_is_refused_without_reading_it_all(self):
        self.mod.RESPONSE_CAP = 20000
        self.env["STUB_BIG"] = "200000"
        code, out, data, _ = self.scan()
        self.assertEqual(code, 3)
        reasons = {r["not_scanned_reason"] for r in data["repositories"] if r["class"] == "not scanned"}
        self.assertTrue(any("too large" in (x or "") for x in reasons), reasons)

    def test_a_rate_limit_given_up_on_stops_the_scan_and_marks_it_incomplete(self):
        self.fx["failures"] = {"content": [{"status": 403, "headers": {"Retry-After": "999999"}}] * 20}
        code, out, data, sleeps = self.scan("--page-size", "3")
        self.assertEqual(code, 4)
        self.assertTrue(sleeps and max(sleeps) <= 3600, sleeps)
        self.assertEqual(len(self.content_calls()), 4)  # one batch's tries, then no more
        self.assertGreaterEqual(out.count("Waiting"), 4)
        self.assertIn("INCOMPLETE", out)
        scanned = [r for r in data["repositories"] if r["class"] != "not scanned"]
        self.assertEqual(scanned, [])
        self.assertTrue(all("rate limit" in r["not_scanned_reason"] for r in data["repositories"]
                            if r["repository"] != 'example-org/bad"name){x}'))

    def test_a_reset_a_day_away_is_capped_and_said(self):
        import time as _t
        self.fx["failures"] = {"code": [{"status": 403, "headers": {"X-Ratelimit-Remaining": "0",
                                                                    "X-Ratelimit-Reset": str(int(_t.time()) + 86400)}}]}
        _, out, _, sleeps = self.scan()
        self.assertIn(3600, sleeps)
        self.assertIn("Waiting 3600 s", out)

    def test_graphql_waits_are_said(self):
        self.fx["failures"] = {"content": [{"status": 200, "body": json.dumps(
            {"errors": [{"type": "RATE_LIMITED", "message": "API rate limit exceeded"}]})}]}
        _, out, _, _ = self.scan()
        self.assertIn("Waiting 60 s", out)

    def test_each_failure_says_why(self):
        with tempfile.TemporaryDirectory() as empty:
            self.env["PATH"] = empty
            self.assertIn("not installed", self.scan()[1])
        self.setUp()
        self.env["STUB_EXIT"] = "4"
        code, out, _, _ = self.scan()
        self.assertEqual(code, 2)
        self.assertIn("not signed in", out)
        self.env["STUB_EXIT"] = "1"
        self.assertIn("network", self.scan()[1])
        del self.env["STUB_EXIT"]
        self.fx["failures"] = {"listing": [{"status": 403, "body": '{"message": "Resource not accessible by integration"}',
                                            "headers": {"X-Accepted-Oauth-Scopes": "repo", "X-Oauth-Scopes": "gist"}}]}
        out = self.scan()[1]
        self.assertIn("repo", out)
        self.assertIn("gh auth refresh -s repo", out)

    def test_a_signal_needs_the_right_kind_of_object(self):
        self.fx["repos"][5]["content"] = {"manifest": {"__typename": "Tree"}, "ctx": {"__typename": "Tree"},
                                          "claudemd": {"__typename": "Tree"}, "readable": {"__typename": "Tree"},
                                          "claudedir": {"__typename": "Blob"}}
        _, _, data, _ = self.scan()
        self.assertEqual(self.by_repo(data)["app-six"]["class"], "no signal")

    def test_a_ci_pattern_in_a_comment_is_not_a_call(self):
        self.fx["repos"][5]["content"] = {"workflows": {"__typename": "Tree", "entries": [
            {"name": "old.yml", "type": "blob", "object": {"__typename": "Blob", "byteSize": 80, "isTruncated": False,
             "text": "  # uses: example-org/shared-ci/.github/workflows/build.yml@old\n"}}]}}
        _, _, data, _ = self.scan("--ci-pattern", "example-org/shared-ci")
        self.assertEqual(self.by_repo(data)["app-six"]["ma4_ci_refs"], [])

    def test_a_truncated_file_is_too_large_not_parsed_even_when_its_text_is_valid(self):
        good = json.dumps({"schema": 1, "skill": "make-it", "date": "2026-01-01", "make_it": {"version": "1.0"}})
        rec = json.dumps({"framework": {"version": "1.0"}, "project": {"type": "web-app"}})
        self.fx["repos"][5]["content"] = {
            "manifest": {"__typename": "Blob", "byteSize": 99, "isTruncated": True, "text": rec},
            "ledger": {"__typename": "Tree", "entries": [{"name": "0001-0123456789ab.json", "type": "blob", "object": {
                "__typename": "Blob", "byteSize": 99, "isTruncated": True, "text": good}}]}}
        _, out, data, _ = self.scan()
        six = self.by_repo(data)["app-six"]
        self.assertEqual((six["ma1_readable"], six["ma1_version"], six["ma1_note"]), (False, None, "too large to read here"))
        self.assertEqual((six["ma2_ledger_entries"], six["ma2_too_large"], six["ma2_unreadable"], six["ma2_skills"]), (1, 1, 0, {}))
        self.assertIn("too large to read here", out)


class Partial(Base):
    """Second re-check: a search that failed or was capped marks every row partial, never "complete"."""

    def rows(self):
        with open(os.path.join(self.last_out, "adoption-scan.csv"), newline="") as f:
            return list(csv.DictReader(f))

    def test_a_capped_search_marks_every_row_partial(self):
        self.fx["code_total"] = 5000
        code, out, data, _ = self.scan("--limit", "3")  # three repositories that all scan cleanly
        self.assertEqual(code, 3)
        self.assertIn("code search was capped", out)
        self.assertTrue(data["partial"] and any("code search was capped" in n for n in data["partial"]))
        self.assertIsNone(data["incomplete"])
        self.assertTrue(all(r["scan_status"].startswith("partial: code search capped") for r in self.rows()))
        self.assertIn("may be missing some", out)

    def test_a_failed_search_marks_every_row_partial(self):
        self.fx["failures"] = {"commits": [{"status": 403}] * 10}
        code, _, data, _ = self.scan("--limit", "3", "--trailers")
        self.assertEqual(code, 3)
        self.assertTrue(all(r["scan_status"].startswith("partial: commit search failed") for r in self.rows()))
        self.assertTrue(data["partial"])

    def test_a_clean_run_is_complete(self):
        code, out, data, _ = self.scan("--limit", "3")
        self.assertEqual(code, 0)
        self.assertIsNone(data["partial"])
        self.assertTrue(all(r["scan_status"] == "complete" for r in self.rows()))
        self.assertNotIn("may be missing some", out)


class ListingRecovers(Base):
    def listing_firsts(self):
        return [int(re.search(r"first: (\d+)", self.query(c)).group(1)) for c in self.calls()
                if "graphql" in c and "repositoryOwner" in self.query(c)]

    def test_failures_spread_through_a_long_listing_do_not_add_up(self):
        self.env["STUB_LIST_PAGE"] = "2"
        self.fx["listing_fail"] = {str(i): {"kind": "timeout", "times": 1} for i in (2, 4, 6, 8)}
        code, out, data, _ = self.scan()
        self.assertIsNone(data["incomplete"], out)
        self.assertEqual(len(data["repositories"]), 11)
        firsts = self.listing_firsts()
        self.assertEqual(firsts[-1], 100)  # the page size grows back after successful pages
        self.assertIn(25, firsts)

    def test_an_answer_with_errors_and_a_list_is_an_error(self):
        self.fx["listing_fail"] = {"0": {"kind": "error_with_list"}}
        code, out, data, _ = self.scan()
        self.assertEqual(code, 4)
        self.assertEqual(data["repositories"], [])  # the list beside the error is not trusted
        self.assertGreater(len(self.listing_firsts()), 1)

    def test_a_reason_never_ends_in_two_full_stops(self):
        self.env["STUB_EXIT"] = "1"
        code, out, _, _ = self.scan()
        self.assertEqual(code, 4)
        self.assertIn("network", out)
        self.assertNotIn("..", out)


if __name__ == "__main__":
    unittest.main(verbosity=1)
