#!/usr/bin/env python3
"""Behaviour test for security-pass.py (build-verify Part D's scanners). Run: python3 -I scripts/test-security-pass.py

Needs no Docker and no network: it runs the script's discovery, refusal, report-folder and decision parts against
small fixture trees and saved report folders. The healthy reports in scripts/security-pass-fixtures/healthy/ come
from a real run on a copy of the throwaway app nemo-proof (2026-11-21), cut down to the fields the script reads.
"""
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, ".claude", "make-it", "scripts", "security-pass.py")
HEALTHY = os.path.join(ROOT, "scripts", "security-pass-fixtures", "healthy")
spec = importlib.util.spec_from_file_location("security_pass", SCRIPT)
sp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sp)

HEALTHY_LINES = [
    "semgrep: ran -- 16 findings, 216 files, 9 file warnings",
    "bandit: ran -- 27 findings, 99 files, 10108 lines",
    "npm-audit: ran -- .make-it/ui-review/package-lock.json: 0 vulnerabilities; frontend/package-lock.json: 0 vulnerabilities",
    "pip-audit: ran -- backend/requirements-dev.txt: 62 packages, 0 vulnerable; backend/requirements.txt: 66 packages, "
    "0 vulnerable; mock-services/mock-oidc/requirements.txt: 18 packages, 0 vulnerable",
    "trivy: ran -- 4 files, 0 vulnerabilities",
]
SEMGREP_404 = {"errors": [
    {"code": 2, "level": "error", "message": "Failed to download configuration from https://semgrep.dev/p/no-such-ruleset-xyz HTTP 404.", "type": "SemgrepError"},
    {"code": 7, "level": "error", "message": "invalid configuration file found (1 configs were invalid)", "type": "SemgrepError"}],
    "paths": {"scanned": []}, "results": [], "skipped_rules": [], "version": "1.85.0"}
BANDIT_MIXED = {"errors": [{"filename": "./backend/app/broken.py", "reason": "syntax error while parsing AST from file"}],
                "metrics": {"./backend/app/broken.py": {"loc": 2}, "./backend/app/main.py": {"loc": 2}, "_totals": {"loc": 4}},
                "results": [{"filename": "./backend/app/main.py", "test_id": "B602", "line_number": 2, "issue_severity": "HIGH"}]}


class Folder:
    """A copy of the healthy report folder to change for one case."""

    def __init__(self, case):
        self.dir = tempfile.mkdtemp()
        shutil.copytree(HEALTHY, self.dir, dirs_exist_ok=True)
        case.addCleanup(shutil.rmtree, self.dir, True)

    def put(self, name, text=None, obj=None, err="", code=0):
        if obj is not None:
            text = json.dumps(obj)
        for ext, body in ((".json", text), (".err", err), (".exit", f"{code}\n")):
            path = os.path.join(self.dir, name + ext)
            if body is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "w") as f:
                    f.write(body)

    def drop(self, prefix):
        for f in os.listdir(self.dir):
            if f.startswith(prefix):
                os.remove(os.path.join(self.dir, f))

    def write(self, name, text):
        with open(os.path.join(self.dir, name), "w") as f:
            f.write(text)

    def lines(self):
        res = sp.collect(self.dir)
        return [sp.line(n, res[n]) for n in sp.ORDER], res


class Decide(unittest.TestCase):
    def test_healthy_real_run(self):
        lines, res = Folder(self).lines()
        self.assertEqual(lines, HEALTHY_LINES)
        self.assertTrue(all(res[n]["state"] == "ran" for n in sp.ORDER))
        self.assertEqual(res["semgrep"]["image"], sp.IMAGES["semgrep"])

    def test_bandit_one_unparsable_file_still_ran(self):
        f = Folder(self); f.put("bandit", obj=BANDIT_MIXED, code=1)
        lines, res = f.lines()
        self.assertEqual(lines[1], "bandit: ran -- 1 findings, 2 files, 4 lines, 1 file not parsed (first: backend/app/broken.py)")
        self.assertEqual(res["bandit"]["warnings"], 1)

    def test_bandit_nothing_parsed_is_not_run_with_the_json_reason(self):
        bad = {"errors": BANDIT_MIXED["errors"], "metrics": {"./backend/app/broken.py": {"loc": 2}, "_totals": {"loc": 2}}, "results": []}
        f = Folder(self); f.put("bandit", obj=bad, err="")
        self.assertEqual(f.lines()[0][1], "bandit: NOT RUN -- could not parse any file (first: backend/app/broken.py: syntax error while parsing AST from file)")

    def test_bandit_nothing_read_is_not_run(self):
        f = Folder(self); f.put("bandit", obj={"errors": [], "metrics": {"_totals": {"loc": 0}}, "results": []})
        self.assertEqual(f.lines()[0][1], "bandit: NOT RUN -- read no lines of code")

    def test_semgrep_rule_download_failure_is_not_run_with_the_json_reason(self):
        f = Folder(self); f.put("semgrep", obj=SEMGREP_404, err="", code=7)
        self.assertEqual(f.lines()[0][0], "semgrep: NOT RUN -- Failed to download configuration from https://semgrep.dev/p/no-such-ruleset-xyz HTTP 404.")

    def test_semgrep_per_file_warnings_still_ran(self):
        rep = json.load(open(os.path.join(HEALTHY, "semgrep.json")))
        rep["errors"].append({"code": 3, "level": "warn", "message": "Timeout", "path": "frontend/app/page.tsx", "type": "Timeout"})
        f = Folder(self); f.put("semgrep", obj=rep)
        self.assertEqual(f.lines()[0][0], "semgrep: ran -- 16 findings, 216 files, 10 file warnings")

    def test_semgrep_skipped_rules_are_counted(self):
        rep = json.load(open(os.path.join(HEALTHY, "semgrep.json")))
        rep["skipped_rules"] = [{"rule_id": "x.y"}]
        f = Folder(self); f.put("semgrep", obj=rep)
        self.assertEqual(f.lines()[0][0], "semgrep: ran -- 16 findings, 216 files, 9 file warnings, 1 rules skipped")

    def test_semgrep_every_file_failed_is_not_run(self):
        rep = {"errors": [{"code": 3, "level": "warn", "message": "Timeout", "path": p, "type": t}
                          for p, t in (("a.js", "Timeout"), ("b.py", "Syntax error"), ("b.py", "Timeout"))],
               "paths": {"scanned": ["a.js", "b.py"]}, "results": [], "skipped_rules": [], "version": "1.85.0"}
        f = Folder(self); f.put("semgrep", obj=rep)
        self.assertEqual(f.lines()[0][0], "semgrep: NOT RUN -- every scanned file failed to parse or timed out (2 of 2 files)")

    def test_semgrep_no_network_reason_comes_from_stderr(self):
        f = Folder(self); f.put("semgrep", text="", err="Traceback...\nrequests.exceptions.ConnectionError: Failed to resolve 'semgrep.dev'\n", code=2)
        self.assertEqual(f.lines()[0][0], "semgrep: NOT RUN -- requests.exceptions.ConnectionError: Failed to resolve 'semgrep.dev'")

    def test_npm_error_only_json_is_not_run_with_its_message(self):
        f = Folder(self)
        f.put("npm-audit--frontend%2Fpackage-lock.json", err="npm error A complete log of this run can be found in: x.log\n", code=1,
              obj={"message": "request to https://registry.npmjs.org/-/npm/v1/security/audits/quick failed, reason: getaddrinfo EAI_AGAIN registry.npmjs.org",
                   "error": {"summary": "", "detail": ""}})
        self.assertEqual(f.lines()[0][2], "npm-audit: NOT RUN for 1 of 2 -- .make-it/ui-review/package-lock.json: 0 vulnerabilities; "
                         "frontend/package-lock.json: request to https://registry.npmjs.org/-/npm/v1/security/audits/quick failed, "
                         "reason: getaddrinfo EAI_AGAIN registry.npmjs.org")

    def test_pip_empty_report_reason_from_stderr(self):
        f = Folder(self)
        f.put("pip-audit--backend%2Frequirements.txt", text="", code=1,
              err="[notice] A new release of pip is available\nERROR: No matching distribution found for pip-audit==2.9.0\n")
        self.assertIn("backend/requirements.txt: ERROR: No matching distribution found for pip-audit==2.9.0", f.lines()[0][3])
        self.assertTrue(f.lines()[0][3].startswith("pip-audit: NOT RUN for 1 of 3 -- "))

    def test_pip_absent_report_and_empty_stderr_never_points_at_an_empty_file(self):
        f = Folder(self); f.put("pip-audit--backend%2Frequirements.txt", text=None, err="", code=125)
        self.assertIn("backend/requirements.txt: no report and no error output (exit 125)", f.lines()[0][3])

    def test_trivy_wrong_target_is_not_run(self):
        f = Folder(self); f.put("trivy", obj={"SchemaVersion": 2, "ArtifactName": ".", "Results": []})
        self.assertEqual(f.lines()[0][4], "trivy: NOT RUN -- the report is not for the project folder (target .)")

    def test_refused_requirements_file_is_a_not_run_part(self):
        f = Folder(self); f.write("pip-audit--backend%2Frequirements-base.txt.refused", "includes another file (-r), so pip-audit was not run on it\n")
        self.assertEqual(f.lines()[0][3], "pip-audit: NOT RUN for 1 of 4 -- backend/requirements-base.txt: includes another file (-r), so pip-audit was not "
                         "run on it; backend/requirements-dev.txt: 62 packages, 0 vulnerable; backend/requirements.txt: 66 packages, 0 vulnerable; "
                         "mock-services/mock-oidc/requirements.txt: 18 packages, 0 vulnerable")

    def test_nothing_to_audit_lines(self):
        f = Folder(self); f.drop("npm-audit"); f.drop("bandit"); f.drop("pip-audit")
        f.write("npm-audit.none", "no package-lock.json found\n")
        f.write("bandit.none", "no Python code found\n")
        f.write("pip-audit.none", "no requirements file found (requirements*.txt)\n")
        lines, res = f.lines()
        self.assertEqual(lines[1:4], ["bandit: nothing to audit -- no Python code found", "npm-audit: nothing to audit -- no package-lock.json found",
                                      "pip-audit: nothing to audit -- no requirements file found (requirements*.txt)"])
        self.assertEqual(res["bandit"]["state"], "nothing to audit")

    def test_a_scanner_with_no_report_at_all_is_not_run(self):
        f = Folder(self); f.drop("trivy")
        self.assertEqual(f.lines()[0][4], "trivy: NOT RUN -- no report: its step did not run")

    def test_a_marker_beside_a_report_fails_loudly(self):
        f = Folder(self); f.write("pip-audit.none", "no requirements file found\n")
        with self.assertRaises(sp.PassError):
            sp.collect(f.dir)


class Refuse(unittest.TestCase):
    def test_each_refused_form(self):
        cases = {"-r base.txt\nflask==3.0\n": "includes another file (-r)", "--requirement=base.txt\n": "includes another file (--requirement)",
                 "-c constraints.txt\n": "includes another file (-c)", "-e ./evil\n": "names a local or editable package (-e)",
                 "./pkg\n": "names a local or editable package (./pkg)", "--index-url https://example.invalid/simple\nflask\n": "names a package index or host (--index-url)",
                 "flask\n--extra-index-url=https://x.invalid\n": "names a package index or host (--extra-index-url)",
                 "-i https://x.invalid\n": "names a package index or host (-i)", "--find-links /wheels\n": "names a package index or host (--find-links)",
                 "--trusted-host x.invalid\n": "names a package index or host (--trusted-host)",
                 "pkg @ https://x.invalid/pkg.whl\n": "names a package by URL (https://)", "git+https://x.invalid/r.git\n": "names a package by URL (git+)"}
        for text, why in cases.items():
            self.assertEqual(sp.refused(text), why + ", so pip-audit was not run on it", text)

    def test_plain_files_pass(self):
        self.assertIsNone(sp.refused("# -r not this\nfastapi==0.141.1  # web\nuvicorn[standard]>=0.30 ; python_version>'3.8'\n\nrequests==2.31.0 \\\n  --hash=sha256:abc\n"))


class Discover(unittest.TestCase):
    def tree(self, files, links=()):
        d = tempfile.mkdtemp(); self.addCleanup(shutil.rmtree, d, True)
        for rel in files:
            p = os.path.join(d, rel); os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "w").write("x = 1\n")
        for rel, target in links:
            os.symlink(target, os.path.join(d, rel))
        return d

    def test_prunes_installed_and_built_folders_and_never_follows_links(self):
        out = tempfile.mkdtemp(); self.addCleanup(shutil.rmtree, out, True)
        open(os.path.join(out, "outside.py"), "w").write("x = 1\n")
        d = self.tree(["app/main.py", "backend/requirements.txt", "backend/requirements-dev.txt", "frontend/package-lock.json",
                       "frontend/node_modules/x/package-lock.json", "backend/env/pyvenv.cfg", "backend/env/lib/python3.12/site-packages/pip/x.py",
                       "backend/env/requirements.txt", ".git/hooks/x.py", ".tox/py/lib/x.py", "lib/site-packages/y.py", "frontend/.next/a/package-lock.json",
                       "dist/x.py", "build/y.py", "__pycache__/z.py", "backend/tests/test_a.py"],
                      links=[("link.py", "/etc/hosts"), ("linked", out)])
        found = sp.discover(d)
        self.assertEqual(found["py"], ["app/main.py"])
        self.assertEqual(found["locks"], ["frontend/package-lock.json"])
        self.assertEqual(found["reqs"], ["backend/requirements-dev.txt", "backend/requirements.txt"])
        self.assertEqual(found["venvs"], ["backend/env"])

    def test_no_python_and_no_lockfile(self):
        found = sp.discover(self.tree(["frontend/app/page.tsx"]))
        self.assertEqual((found["py"], found["locks"], found["reqs"]), ([], [], []))


class Commands(unittest.TestCase):
    def setUp(self):
        self.found = {"py": ["app/main.py"], "locks": ["frontend/package-lock.json"], "reqs": ["backend/requirements.txt"], "venvs": ["backend/env"]}
        self.cmds = sp.commands("/p", self.found)

    def test_every_container_is_read_only_pinned_and_gets_no_socket_or_environment(self):
        for name, argv in self.cmds:
            joined = " ".join(argv)
            self.assertEqual(argv[:3], ["docker", "run", "--rm"], name)
            self.assertTrue(any(a in sp.IMAGES.values() for a in argv), name)
            self.assertNotIn("docker.sock", joined); self.assertNotIn("--privileged", argv)
            self.assertFalse({"-e", "--env", "--env-file"} & set(argv), name)
            for i, a in enumerate(argv):
                if a == "-v":
                    self.assertTrue(argv[i + 1].endswith(":ro") or argv[i + 1].startswith("make-it-trivy-cache:"), argv[i + 1])
        for digest in sp.IMAGES.values():
            self.assertRegex(digest, r"@sha256:[0-9a-f]{64}$")

    def test_pip_audit_sees_only_its_file_and_trivy_not_the_project_config(self):
        pip = [a for n, a in self.cmds if n.startswith("pip-audit")][0]
        self.assertIn("/p/backend/requirements.txt:/req/requirements.txt:ro", pip)
        self.assertNotIn("/p:/src:ro", pip)
        trivy = [a for n, a in self.cmds if n == "trivy"][0]
        self.assertEqual(trivy[trivy.index("-w") + 1], "/"); self.assertEqual(trivy[-1], "/src"); self.assertNotIn("--config", trivy)

    def test_bandit_gets_the_file_list_and_semgrep_skips_the_virtualenv(self):
        bandit = [a for n, a in self.cmds if n == "bandit"][0]
        self.assertEqual(bandit[-1], "app/main.py"); self.assertNotIn("-r", bandit)
        semgrep = [a for n, a in self.cmds if n == "semgrep"][0]
        self.assertIn("--exclude=backend/env", semgrep)

    def test_audit_check_runs_the_vendored_checker_from_the_node_pin(self):
        argv = sp.audit_cmd("coverage-ledger", "/run/x/coverage-ledger.json", "/audit")
        self.assertEqual(argv, ["docker", "run", "--rm", "--network", "none", "-v", "/audit:/audit:ro", "-v", "/run/x:/audit-run:ro",
                                sp.IMAGES["node"], "node", "/audit/validate-coverage-ledger.cjs", "/audit-run/coverage-ledger.json"])
        with self.assertRaises(sp.PassError):
            sp.audit_cmd("anything-else", "/run/x/f.json", "/audit")


class ReportFolder(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp(); self.addCleanup(shutil.rmtree, self.home, True)
        self.base = os.path.join(self.home, "cache", "make-it-security")

    def test_created_private_and_each_run_is_its_own_folder(self):
        a = sp.new_run("/some/project", self.base); b = sp.new_run("/some/project", self.base)
        self.assertNotEqual(a, b)
        for p in (self.base, os.path.dirname(a), a):
            self.assertEqual(stat.S_IMODE(os.lstat(p).st_mode), 0o700, p)
        self.assertEqual(os.listdir(a), [])

    def test_a_shared_or_planted_folder_is_refused(self):
        os.makedirs(self.base); os.chmod(self.base, 0o755)
        with self.assertRaises(sp.PassError):
            sp.new_run("/some/project", self.base)

    def test_a_symlinked_folder_is_refused(self):
        real = os.path.join(self.home, "real"); os.makedirs(real, mode=0o700)
        os.makedirs(os.path.dirname(self.base)); os.symlink(real, self.base)
        with self.assertRaises(sp.PassError):
            sp.new_run("/some/project", self.base)

    def test_a_folder_someone_else_owns_is_refused(self):
        os.makedirs(self.base, mode=0o700)
        with self.assertRaises(sp.PassError):
            sp.private_dir(self.base, uid=os.getuid() + 1)


class Cli(unittest.TestCase):
    def test_a_missing_project_is_a_failure_to_run_not_a_result(self):
        r = subprocess.run([sys.executable, "-I", SCRIPT, "scan", "/no/such/project"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)

    def test_usage(self):
        r = subprocess.run([sys.executable, "-I", SCRIPT], capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
