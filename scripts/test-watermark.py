#!/usr/bin/env python3
"""Contract test for watermark.py. Run: python3 -I scripts/test-watermark.py

The build record (.make-it/manifest.json) is a claim; `verify` is the proof. Every test builds a
throwaway app from the real scaffold, so the real protected list and the real CONTENT_MANIFEST are
what is checked. Exit codes: 0 pass, 1 fail, 3 a security file changed and needs review.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FW = os.path.join(ROOT, ".claude", "make-it")
SCRIPT = os.path.join(FW, "scripts", "watermark.py")
SCAFFOLD = os.path.join(FW, "scaffolds", "fastapi-nextjs")
PERMS = "backend/app/middleware/permissions.py"


def run(*args, cwd=None):
    return subprocess.run([sys.executable, "-I", SCRIPT, *args], capture_output=True, text=True, cwd=cwd)


def git(app, *args):
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
    return subprocess.run(["git", "-C", app, *args], capture_output=True, text=True, env=env, check=True)


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="wm-")
        self.app = os.path.join(self.tmp, "app")
        shutil.copytree(SCAFFOLD, self.app, ignore=shutil.ignore_patterns("__pycache__", "node_modules"))
        os.makedirs(os.path.join(self.app, ".make-it"))
        self.ctx({"project_type": "web-app", "active_tiers": [0, 1], "scaffold": "fastapi-nextjs"})
        git(self.app, "init", "-q", "-b", "main")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def ctx(self, d):
        with open(os.path.join(self.app, ".make-it", "app-context.json"), "w") as f:
            json.dump(d, f)

    def p(self, rel):
        return os.path.join(self.app, rel)

    def record(self):
        with open(self.p(".make-it/manifest.json")) as f:
            return json.load(f)

    def write(self, *extra):
        r = run("write", "--app", self.app, *extra)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return r

    def verify(self, *extra):
        return run("verify", "--app", self.app, *extra)

    def edit(self, rel, text="\n# changed by hand\n"):
        with open(self.p(rel), "a") as f:
            f.write(text)


class Write(Base):
    def test_clean_build_writes_a_record_and_passes(self):
        self.write()
        rec = self.record()
        self.assertEqual(rec["schema"], 1)
        with open(os.path.join(ROOT, "VERSION")) as f:
            self.assertEqual(rec["framework"]["version"], f.read().strip())
        self.assertRegex(rec["framework"]["content_manifest_sha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(rec["project"]["scaffold"], "fastapi-nextjs")
        files = rec["security_files"]
        self.assertGreaterEqual(len(files), 10)
        self.assertTrue(all(e["state"] == "match" for e in files), files)
        r = self.verify()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_record_is_the_same_bytes_when_nothing_changed(self):
        # a hook rewrites it after every session: it must not churn git
        self.write()
        a = open(self.p(".make-it/manifest.json"), "rb").read()
        self.write()
        self.assertEqual(a, open(self.p(".make-it/manifest.json"), "rb").read())
        self.assertNotIn(b"time", a.lower())

    def test_record_holds_no_secret_and_no_file_content(self):
        with open(self.p(".env"), "w") as f:
            f.write("JWT_SECRET=supersecretvalue123\n")
        self.write()
        raw = open(self.p(".make-it/manifest.json")).read()
        self.assertNotIn("supersecretvalue123", raw)
        self.assertNotIn("require_permission", raw)

    def test_results_and_notes_are_kept(self):
        res = os.path.join(self.tmp, "results.json")
        with open(res, "w") as f:
            json.dump({"deep_audit": "ran", "fixed": 1, "open": 0}, f)
        self.write("--results", res)
        self.assertEqual(self.record()["security_results"]["deep_audit"], "ran")
        self.edit(PERMS)
        r = run("note", "--app", self.app, PERMS, "AUDIT-002 missing check on export, commit abc1234")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.write()  # a later rewrite keeps both
        rec = self.record()
        self.assertEqual(rec["security_results"]["deep_audit"], "ran")
        e = [x for x in rec["security_files"] if x["path"] == PERMS][0]
        self.assertEqual(e["state"], "changed")
        self.assertIn("AUDIT-002", e["note"])

    def test_note_refuses_a_path_that_is_not_a_security_file(self):
        self.write()
        r = run("note", "--app", self.app, "README.md", "x")
        self.assertNotEqual(r.returncode, 0)

    def test_other_project_types_get_a_record_without_file_hashes(self):
        for d in ("backend", "frontend", "mock-services"):  # a CLI tool has none of the scaffold
            shutil.rmtree(self.p(d))
        self.ctx({"project_type": "cli", "active_tiers": [0, 3], "scaffold": None})
        self.write()
        rec = self.record()
        self.assertEqual(rec["security_files"], [])
        r = self.verify()  # nothing could be checked: that is never a silent pass
        self.assertEqual(r.returncode, 3, r.stdout + r.stderr)
        self.assertIn("could not be checked", r.stdout)
        self.assertEqual(self.verify("--allow-unlisted").returncode, 0)


class Hook(Base):
    def hook(self, cwd):
        return subprocess.run([sys.executable, "-I", SCRIPT, "hook"], input=json.dumps({"cwd": cwd}),
                              capture_output=True, text=True)

    def test_hook_writes_the_record_silently_from_a_subfolder(self):
        r = self.hook(self.p("backend/app"))
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))
        self.assertEqual(self.record()["schema"], 1)

    def test_hook_does_nothing_outside_a_make_it_project(self):
        other = os.path.join(self.tmp, "other")
        os.makedirs(other)
        r = self.hook(other)
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))
        self.assertFalse(os.path.exists(os.path.join(other, ".make-it")))

    def test_hook_never_fails_on_bad_input(self):
        r = subprocess.run([sys.executable, "-I", SCRIPT, "hook"], input="not json", capture_output=True, text=True)
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))

    def test_hook_leaves_an_unchanged_record_untouched(self):
        self.write()
        path = self.p(".make-it/manifest.json")
        os.utime(path, (1, 1))
        self.hook(self.app)
        self.assertEqual(os.path.getmtime(path), 1)


class Verify(Base):
    def test_no_record_fails_with_a_plain_next_step(self):
        r = self.verify()
        self.assertEqual(r.returncode, 1)
        self.assertIn("/resume-it", r.stdout)

    def test_unreadable_record_fails(self):
        with open(self.p(".make-it/manifest.json"), "w") as f:
            f.write("{not json")
        self.assertEqual(self.verify().returncode, 1)

    def test_hand_edit_needs_review_and_names_the_file(self):
        self.write()
        self.edit(PERMS)
        r = self.verify()
        self.assertEqual(r.returncode, 3, r.stdout + r.stderr)
        self.assertIn(PERMS, r.stdout)

    def test_an_honest_rewrite_after_an_edit_still_needs_review(self):
        self.write()
        self.edit(PERMS)
        self.write()
        self.assertEqual(self.verify().returncode, 3)

    def test_a_forged_record_is_not_believed(self):
        # the record says everything matches; the code says otherwise
        self.write()
        forged = open(self.p(".make-it/manifest.json")).read()
        self.edit(PERMS)
        with open(self.p(".make-it/manifest.json"), "w") as f:
            f.write(forged)
        r = self.verify()
        self.assertEqual(r.returncode, 3)
        self.assertIn(PERMS, r.stdout)

    def test_a_deleted_security_file_fails(self):
        self.write()
        os.remove(self.p(PERMS))
        r = self.verify()
        self.assertEqual(r.returncode, 1)
        self.assertIn(PERMS, r.stdout)

    def test_a_symlinked_security_file_fails(self):
        self.write()
        os.remove(self.p(PERMS))
        os.symlink(os.path.join(SCAFFOLD, PERMS), self.p(PERMS))  # same bytes, but not a real file
        self.assertEqual(self.verify().returncode, 1)

    def test_a_record_from_another_release_fails(self):
        self.write()
        rec = self.record()
        rec["framework"]["content_manifest_sha256"] = "0" * 64
        with open(self.p(".make-it/manifest.json"), "w") as f:
            json.dump(rec, f)
        r = self.verify()
        self.assertEqual(r.returncode, 1)
        self.assertIn("release", r.stdout.lower())

    def test_a_record_that_names_another_scaffold_does_not_skip_the_hashes(self):
        # claiming "no scaffold" in the record must not switch the file check off
        self.write()
        rec = self.record()
        rec["project"]["scaffold"] = None
        rec["security_files"] = []
        with open(self.p(".make-it/manifest.json"), "w") as f:
            json.dump(rec, f)
        self.edit(PERMS)
        self.assertEqual(self.verify().returncode, 3)

    def test_a_change_already_on_the_base_branch_is_accepted(self):
        self.write()
        self.edit(PERMS)
        git(self.app, "add", "-A")
        git(self.app, "commit", "-q", "-m", "reviewed change")
        base = git(self.app, "rev-parse", "HEAD").stdout.strip()
        r = self.verify("--base-ref", base)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("accepted", r.stdout.lower())
        self.edit(PERMS, "\n# a second, new change\n")
        self.assertEqual(self.verify("--base-ref", base).returncode, 3)

    def test_a_route_file_with_no_permission_check_fails(self):
        self.write()
        with open(self.p("backend/app/routers/exports.py"), "w") as f:
            f.write('from fastapi import APIRouter\nrouter = APIRouter()\n\n@router.get("/api/exports")\ndef all_rows():\n    return []\n')
        r = self.verify()
        self.assertEqual(r.returncode, 1)
        self.assertIn("backend/app/routers/exports.py", r.stdout)

    def test_a_missing_rbac_table_fails(self):
        self.write()
        mig = self.p("backend/alembic/versions/001_rbac_schema.py")
        src = open(mig).read()
        self.assertIn('"role_permissions"', src)
        with open(mig, "w") as f:
            f.write(src.replace('"role_permissions"', '"role_perms"'))
        r = self.verify()
        self.assertEqual(r.returncode, 1)
        self.assertIn("role_permissions", r.stdout)

    def test_json_output(self):
        self.write()
        self.edit(PERMS)
        out = json.loads(self.verify("--json").stdout)
        self.assertEqual(out["result"], "review")
        self.assertEqual([c["path"] for c in out["changed"]], [PERMS])

    def test_it_never_runs_the_app(self):
        self.write()
        marker = os.path.join(self.tmp, "ran")
        with open(self.p(PERMS), "a") as f:
            f.write(f"\nopen({marker!r}, 'w').write('x')\n")
        self.verify()
        self.write()
        self.assertFalse(os.path.exists(marker))


GOOD_IMPORT = "from fastapi import APIRouter, Depends\nfrom app.middleware.permissions import require_permission\nrouter = APIRouter()\n"
GUARDED = GOOD_IMPORT + '@router.get("/ok")\ndef ok(u=Depends(require_permission("x", "read"))):\n    return []\n'

# every one of these was a working bypass in the first version; each must fail (exit 1)
ROUTE_BYPASSES = {
    "guard only in a comment": 'from fastapi import APIRouter\nrouter = APIRouter()\n# require_permission(\n@router.get("/w")\ndef w():\n    return []\n',
    "guard only in a string": GOOD_IMPORT + 'X = "require_permission("\n@router.get("/w")\ndef w():\n    return []\n',
    "router under another name": 'from fastapi import APIRouter\nr = APIRouter()\n@r.get("/w")\ndef w():\n    return []\n',
    "add_api_route": 'from fastapi import APIRouter\nrouter = APIRouter()\ndef w():\n    return []\nrouter.add_api_route("/w", w)\n',
    "decorator kept in a variable": 'from fastapi import APIRouter\nrouter = APIRouter()\nf = router.get("/w")\n@f\ndef w():\n    return []\n',
    "decorator called directly": 'from fastapi import APIRouter\nrouter = APIRouter()\nrouter.get("/w")(lambda: [])\n',
    "one guarded route hiding an unguarded one": GUARDED + '@router.get("/w")\ndef w():\n    return []\n',
    "its own no-op require_permission": 'from fastapi import APIRouter, Depends\nrouter = APIRouter()\ndef require_permission(*a):\n    return lambda: None\n@router.get("/w")\ndef w(u=Depends(require_permission("x", "read"))):\n    return []\n',
    "require_permission from another module": 'from fastapi import APIRouter, Depends\nfrom app.authz import require_permission\nrouter = APIRouter()\n@router.get("/w")\ndef w(u=Depends(require_permission("x", "read"))):\n    return []\n',
    "an encoding line that hides the decorator": '# -*- coding: utf-7 -*-\nfrom fastapi import APIRouter\nrouter = APIRouter()\n+AEA-router.get("/w")\ndef w():\n    return []\n',
    "not Python at all": "def (:\n",
}


class Adversarial(Base):
    """The findings of the independent review, 2026-11-16. Nothing under the app is trusted."""

    def put(self, rel, text):
        os.makedirs(os.path.dirname(self.p(rel)), exist_ok=True)
        with open(self.p(rel), "w") as f:
            f.write(text)

    def test_a_properly_guarded_new_route_passes(self):
        self.write()
        self.put("backend/app/routers/widgets.py", GUARDED)
        r = self.verify()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_route_bypasses_fail(self):
        self.write()
        for name, src in ROUTE_BYPASSES.items():
            for rel in ("backend/app/routers/w.py", "backend/app/routers/v2/w.py", "backend/app/api/w.py", "backend/other/w.py"):
                with self.subTest(name=name, rel=rel):
                    self.put(rel, src)
                    r = self.verify()
                    self.assertEqual(r.returncode, 1, f"{name} at {rel}: {r.stdout}")
                    self.assertIn(rel, r.stdout)
                    os.remove(self.p(rel))

    def test_switching_sign_in_off_from_other_files_fails(self):
        self.write()
        for rel, src in {
            "backend/app/patch.py": "import app.middleware.permissions as p\np.require_permission = lambda *a, **k: (lambda: None)\n",
            "backend/app/overrides.py": "def off(app, dep):\n    app.dependency_overrides[dep] = lambda: None\n",
            "backend/app/extra.py": 'from fastapi import FastAPI\na = FastAPI()\n@a.get("/api/dump")\ndef dump():\n    return []\n',
        }.items():
            with self.subTest(rel=rel):
                self.put(rel, src)
                self.assertEqual(self.verify().returncode, 1, rel)
                os.remove(self.p(rel))

    def test_renaming_the_folders_does_not_switch_the_check_off(self):
        self.write()
        for a, b in (("backend", "api"), ("frontend", "web"), ("mock-services", "mocks")):
            os.rename(self.p(a), self.p(b))
        rec = self.record()
        rec["project"]["scaffold"], rec["security_files"] = None, []
        with open(self.p(".make-it/manifest.json"), "w") as f:
            json.dump(rec, f)
        r = self.verify()
        self.assertEqual(r.returncode, 3, r.stdout)
        self.assertNotIn("check: pass", r.stdout)

    def test_migrations_are_parsed_not_matched(self):
        self.write()
        mig = self.p("backend/alembic/versions/001_rbac_schema.py")
        keep = open(mig).read()
        with open(mig, "w") as f:
            f.write('# op.create_table("roles") op.create_table("permissions") op.create_table("role_permissions")\n')
        self.assertEqual(self.verify().returncode, 1)
        with open(mig, "w") as f:
            f.write(keep)
        self.assertEqual(self.verify().returncode, 0)
        self.put("backend/alembic/versions/999_drop.py", 'from alembic import op\ndef upgrade():\n    op.drop_table("role_permissions")\n')
        r = self.verify()
        self.assertEqual(r.returncode, 1)
        self.assertIn("drops", r.stdout)

    def test_base_ref_must_be_a_commit_id_not_a_name_the_pr_can_own(self):
        self.write()
        git(self.app, "add", "-A")
        git(self.app, "commit", "-q", "-m", "clean base")
        base = git(self.app, "rev-parse", "HEAD").stdout.strip()
        self.edit(PERMS)
        git(self.app, "commit", "-q", "-am", "backdoor")
        git(self.app, "tag", "main-base")  # a name pointing at the PR's own commit
        for ref in ("HEAD", "main", "main-base"):
            self.assertEqual(self.verify("--base-ref", ref).returncode, 3, ref)
        self.assertEqual(self.verify("--base-ref", base).returncode, 3)
        # swapping the base's file for the backdoored one with a replace ref must not be believed
        good = git(self.app, "rev-parse", f"{base}:{PERMS}").stdout.strip()
        evil = git(self.app, "rev-parse", f"HEAD:{PERMS}").stdout.strip()
        git(self.app, "replace", good, evil)
        self.assertEqual(self.verify("--base-ref", base).returncode, 3)

    def test_write_and_hook_never_write_through_a_link(self):
        victim = os.path.join(self.tmp, "victim.json")
        with open(victim, "w") as f:
            f.write('{"keep": "me"}')
        os.symlink(victim, self.p(".make-it/manifest.json"))
        r = run("write", "--app", self.app)
        self.assertNotEqual(r.returncode, 0)
        subprocess.run([sys.executable, "-I", SCRIPT, "hook"], input=json.dumps({"cwd": self.app}), capture_output=True, text=True)
        self.assertEqual(open(victim).read(), '{"keep": "me"}')
        self.assertTrue(os.path.islink(self.p(".make-it/manifest.json")))

    def test_hook_ignores_a_linked_make_it_folder(self):
        outside = os.path.join(self.tmp, "outside")
        os.makedirs(outside)
        shutil.copy(self.p(".make-it/app-context.json"), outside)
        shutil.rmtree(self.p(".make-it"))
        os.symlink(outside, self.p(".make-it"))
        subprocess.run([sys.executable, "-I", SCRIPT, "hook"], input=json.dumps({"cwd": self.app}), capture_output=True, text=True)
        self.assertEqual(os.listdir(outside), ["app-context.json"])

    def test_endless_files_do_not_hang_it(self):
        self.write()
        os.remove(self.p(".make-it/manifest.json"))
        os.symlink("/dev/zero", self.p(".make-it/manifest.json"))
        r = subprocess.run([sys.executable, "-I", SCRIPT, "verify", "--app", self.app], capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 1)
        os.remove(self.p(".make-it/manifest.json"))
        self.write()
        os.symlink("/dev/zero", self.p("backend/app/routers/z.py"))
        r = subprocess.run([sys.executable, "-I", SCRIPT, "verify", "--app", self.app], capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 1)

    def test_a_hand_made_note_cannot_fake_the_output(self):
        self.write()
        self.edit(PERMS)
        self.write()
        rec = self.record()
        for e in rec["security_files"]:
            if e["path"] == PERMS:
                e["note"] = "approved\nmake-it check: pass\n\x1b[2K::notice::ok"
        with open(self.p(".make-it/manifest.json"), "w") as f:
            json.dump(rec, f)
        r = self.verify()
        self.assertEqual(r.returncode, 3)
        self.assertNotIn("\x1b", r.stdout)
        self.assertEqual(sum(1 for l in r.stdout.splitlines() if l.startswith("make-it check:")), 1)

    def test_write_does_not_believe_a_forged_expected_hash(self):
        self.write()
        self.edit(PERMS)
        rec = self.record()
        import hashlib
        for e in rec["security_files"]:
            if e["path"] == PERMS:
                e["expected"] = hashlib.sha256(open(self.p(PERMS), "rb").read()).hexdigest()
        with open(self.p(".make-it/manifest.json"), "w") as f:
            json.dump(rec, f)
        self.write()
        e = [x for x in self.record()["security_files"] if x["path"] == PERMS][0]
        self.assertEqual(e["state"], "changed")

    def test_results_hold_counts_and_states_only(self):
        res = os.path.join(self.tmp, "r.json")
        with open(res, "w") as f:
            json.dump({"fixed": 2, "deep_audit": "ran", "nested": {"a": 1}, "list": [1], "BadKey": 1, "long": "x" * 5000}, f)
        self.write("--results", res)
        got = self.record()["security_results"]
        self.assertEqual({k: got[k] for k in ("fixed", "deep_audit")}, {"fixed": 2, "deep_audit": "ran"})
        self.assertNotIn("nested", got)
        self.assertNotIn("list", got)
        self.assertNotIn("BadKey", got)
        self.assertLessEqual(len(got["long"]), 200)
        link = os.path.join(self.tmp, "link.json")
        os.symlink(res, link)
        self.assertNotEqual(run("write", "--app", self.app, "--results", link).returncode, 0)

    def test_wrong_typed_records_fail_cleanly(self):
        for bad in ('{"framework": "x"}', '{"project": [1]}', '{"security_files": 5}',
                    '{"security_files": [{"path": [1]}]}', "[" * 100000):
            with self.subTest(bad=bad[:30]):
                with open(self.p(".make-it/manifest.json"), "w") as f:
                    f.write(bad)
                r = self.verify("--json")
                self.assertEqual(r.returncode, 1, r.stderr[-300:])
                self.assertEqual(json.loads(r.stdout)["result"], "fail")

    def test_a_fake_git_repo_in_the_project_is_never_used(self):
        # round 2: with no real .git, files named HEAD/objects/config made git treat the project as a repo
        self.write()
        shutil.rmtree(self.p(".git"))
        marker = os.path.join(self.tmp, "ran")
        os.makedirs(self.p("objects"))
        os.makedirs(self.p("refs/heads"))
        with open(self.p("HEAD"), "w") as f:
            f.write("ref: refs/heads/keep\n")
        with open(self.p("config"), "w") as f:
            f.write(f'[core]\n\tbare = true\n[extensions]\n\tpartialClone = origin\n[remote "origin"]\n\turl = ext::sh -c touch% {marker}\n\tpromisor = true\n[protocol "ext"]\n\tallow = always\n')
        self.edit(PERMS)
        r = self.verify("--base-ref", "a" * 40)
        self.assertEqual(r.returncode, 3, r.stdout)
        self.assertFalse(os.path.exists(marker))

    def test_code_in_skipped_looking_folders_is_still_checked(self):
        self.write()
        bad = 'from fastapi import APIRouter\nrouter = APIRouter()\n@router.get("/x")\nasync def x():\n    return 1\n'
        for rel in ("backend/app/node_modules/x.py", "backend/app/venv/x.py", "backend/app/__pycache__/x.py"):
            with self.subTest(rel=rel):
                self.put(rel, bad)
                self.assertEqual(self.verify().returncode, 1, rel)
                shutil.rmtree(os.path.dirname(self.p(rel)))
        os.makedirs(os.path.join(self.tmp, "real"))
        os.symlink(os.path.join(self.tmp, "real"), self.p("backend/app/extra"))
        self.assertEqual(self.verify().returncode, 1)
        os.remove(self.p("backend/app/extra"))
        self.put("backend/app/routers/y.pyc", "x")
        self.assertEqual(self.verify().returncode, 1)

    def test_an_open_route_cannot_hide_behind_the_health_routes_name(self):
        self.write()
        with open(self.p("backend/app/main.py"), "a") as f:
            f.write('\n\n@app.get("/api/dump-users")\nasync def health():\n    return "all users"\n')
        r = self.verify()
        self.assertEqual(r.returncode, 1, r.stdout)

    def test_round_two_shapes_never_pass_on_their_own(self):
        # each got exit 0 in the second review. Now a fail (1) or security review (3), never a pass.
        self.write()
        H = GOOD_IMPORT
        N = "from fastapi import APIRouter, Depends\nrouter = APIRouter()\n"
        shapes = {
            "guard wrapped in str()": H + "@router.get('/x', description=str(require_permission('a','b')))\nasync def x():\n    return 1\n",
            "guard inside a lambda": H + "@router.get('/x')\nasync def x(_=Depends(lambda: require_permission('a','b'))):\n    return 1\n",
            "rebound by a for loop": H + "for require_permission in (lambda r, a: (lambda: None),):\n    pass\n@router.get('/x')\nasync def x(_=Depends(require_permission('a','b'))):\n    return 1\n",
            "rebound as a parameter": H + "def build(require_permission):\n    @router.get('/x')\n    async def x(_=Depends(require_permission('a','b'))):\n        return 1\nbuild(lambda r, a: (lambda: None))\n",
            "import under if False": "from fastapi import APIRouter, Depends\nrouter = APIRouter()\nif False:\n    from app.middleware.permissions import require_permission\nglobals()['require_permission'] = lambda r, a: (lambda: None)\n@router.get('/x')\nasync def x(_=Depends(require_permission('a','b'))):\n    return 1\n",
            "star import": H + "from app.lib.h import *\n@router.get('/x')\nasync def x(_=Depends(require_permission('a','b'))):\n    return 1\n",
            "decorator factory kept": N + "g = router.get\n@g('/x')\nasync def x():\n    return 1\n",
            "direct call with keyword path": N + "async def x():\n    return 1\nrouter.get(path='/x')(x)\n",
            "map over the decorator": N + "async def x():\n    return 1\nlist(map(router.get('/x'), [x]))\n",
            "getattr on the router": N + "async def x():\n    return 1\ngetattr(router, 'add_api_' + 'route')('/x', x)\n",
            "routes= list": "from fastapi import APIRouter\nfrom fastapi.routing import APIRoute\nasync def x():\n    return 1\nrouter = APIRouter(routes=[APIRoute('/x', x)])\n",
            "exec": N + "exec(\"@router.get('/x')\\nasync def x(): return 1\")\n",
            "middleware answering itself": "from app.main import app\n@app.middleware('http')\nasync def m(request, call_next):\n    return await call_next(request)\n",
            "routes.append": "from app.main import app\napp.router.routes.append(None)\n",
            "vars() on the permission module": "import app.middleware.permissions as _p\nvars(_p)['require_permission'] = lambda *a: (lambda: None)\n",
            "setattr on the permission module": "import app.middleware.permissions as _p\nsetattr(_p, 'require_permission', lambda *a: (lambda: None))\n",
            "sys.modules swap": "import sys, types\nsys.modules['app.middleware.permissions'] = types.SimpleNamespace()\n",
            "replace get_current_user": "import app.middleware.auth as _a\n_a.get_current_user = lambda: None\n",
            "tests imported into the app": "import importlib\nimportlib.import_module('tests.prod_overrides')\n",
            "tests imported plainly": "import tests.prod_overrides\n",
        }
        for name, src in shapes.items():
            with self.subTest(name=name):
                self.put("backend/app/zz.py", src)
                r = self.verify()
                self.assertIn(r.returncode, (1, 3), f"{name}: {r.stdout}")
                self.assertIn("backend/app/zz.py", r.stdout)
                os.remove(self.p("backend/app/zz.py"))
        self.assertEqual(self.verify().returncode, 0)

    def test_ordinary_generated_code_passes_without_review(self):
        # the review rule must not flood the reviewers: plain CRUD code is not "unusual"
        self.write()
        self.put("backend/app/routers/widgets.py", GOOD_IMPORT + (
            'import httpx, os\n'
            '@router.put("/widgets/{i}", dependencies=[Depends(require_permission("widgets", "update"))])\n'
            'async def update(i: int, body: dict):\n'
            '    obj = {}\n'
            '    for k, v in body.items():\n'
            '        setattr(obj, k, v)\n'
            '    port = int(os.environ.get("PORT", "8000"))\n'
            '    async with httpx.AsyncClient() as client:\n'
            '        r = await client.get("/upstream")\n'
            '    return {"name": getattr(obj, "name", None), "port": port, "up": body.get("x")}\n'))
        r = self.verify()
        self.assertEqual(r.returncode, 0, r.stdout)

    def test_migration_drops_in_other_forms_fail(self):
        self.write()
        for src in ("from alembic import op\ndef upgrade():\n    op.drop_table(table_name='role_permissions')\n",
                    "from alembic import op\ndef upgrade():\n    op.execute('DROP TABLE role_permissions CASCADE')\n",
                    "from alembic import op\ndef downgrade():\n    op.drop_table('roles')\ndef upgrade():\n    downgrade()\n"):
            with self.subTest(src=src[30:70]):
                self.put("backend/alembic/versions/999_x.py", src)
                self.assertEqual(self.verify().returncode, 1)
                os.remove(self.p("backend/alembic/versions/999_x.py"))

    def test_entry_point_files_are_on_the_security_list(self):
        self.write()
        paths = [e["path"] for e in self.record()["security_files"]]
        self.assertIn("backend/Dockerfile", paths)
        self.assertIn("backend/entrypoint.sh", paths)


class Wiring(unittest.TestCase):
    """Each build skill writes the record; the checks and the spec exist."""

    def read(self, rel):
        with open(os.path.join(ROOT, rel)) as f:
            return f.read()

    def test_protected_list_is_real_and_placeholder_free(self):
        lst = [l.strip() for l in self.read(".claude/make-it/watermark/protected-fastapi-nextjs.txt").splitlines()
               if l.strip() and not l.startswith("#")]
        self.assertGreaterEqual(len(lst), 10)
        manifest = self.read("CONTENT_MANIFEST")
        import re
        for rel in lst:
            path = os.path.join(SCAFFOLD, rel)
            self.assertTrue(os.path.isfile(path), rel)
            self.assertIn(f"  make-it/scaffolds/fastapi-nextjs/{rel}\n", manifest, rel)
            self.assertIsNone(re.search(r"\[[A-Z][A-Z0-9_]+\]", open(path).read()), f"{rel} has a placeholder")
        for must in ("backend/app/middleware/auth.py", PERMS, "backend/app/routers/auth.py"):
            self.assertIn(must, lst)

    def test_checks_are_defined_once(self):
        bs = self.read(".claude/make-it/references/build-standards.md")
        for i in range(1, 5):
            self.assertEqual(bs.count(f"**WM0{i}** "), 1, f"WM0{i}")
        self.assertNotIn("**WM05**", bs)

    def test_every_build_skill_writes_the_record(self):
        for cmd in ("make-it", "resume-it", "retrofit-it", "fix-it"):
            text = self.read(f".claude/commands/{cmd}.md")
            self.assertIn("watermark.py", text, cmd)
            self.assertIn("watermark.md", text, cmd)
        for cmd in ("make-it", "resume-it", "retrofit-it"):
            self.assertIn("WM01-WM04", self.read(f".claude/commands/{cmd}.md"), cmd)

    def test_spec_says_the_record_is_a_claim_and_is_written_silently(self):
        spec = " ".join(self.read(".claude/make-it/references/watermark.md").split())
        self.assertRegex(spec, r"(?i)a claim, not proof")
        self.assertRegex(spec, r"(?i)asked nothing")
        self.assertRegex(spec, r"(?i)never (edit|write).{0,60}by hand")
        self.assertRegex(spec, r"(?i)security review")

    def test_a_fix_in_a_security_file_is_noted(self):
        for rel in (".claude/make-it/references/build-verify-security.md", ".claude/make-it/references/fix-strategies.md"):
            self.assertIn("watermark.py", self.read(rel), rel)


if __name__ == "__main__":
    unittest.main(verbosity=1)
