#!/usr/bin/env bash
# E12-S6 review (2026-11-24): two facts the live checks rest on, checked in the scaffolds themselves.
#   - R04's write-route rule holds in each scaffold: every POST, PUT, PATCH and DELETE route carries the permission
#     check (FastAPI: `require_permission(` in the handler's signature or its `dependencies=`; Next.js: `requirePermission`
#     in the exported handler), except R04's public list, read from R04's own row. A guard removed must fail here.
#   - The scaffold's browser tests ship the browser tool, pinned: `e2e/package.json` names `@playwright/test` at one exact
#     version, and `e2e/package-lock.json` locks that same version, so make-it step 22b's `npm ci` installs exactly it
#     and writes no new file. An `e2e/package.json` without the tool must fail here.
# Usage: test-scaffold-e2e-and-guards.sh [ROOT]. With no ROOT it checks this repo, then proves the checks fail on opposites.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; SELF="$root/scripts/$(basename "$0")"
R="${1:-$root}"; cd "$R"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
ERRF="$(mktemp)"; TMPD="$(mktemp -d)"; exec 4>&2 2>"$ERRF"; trap 'cat "$ERRF" >&4; rm -rf "$ERRF" "$TMPD"' EXIT

BS=.claude/make-it/references/build-standards.md; SC=.claude/make-it/scaffolds
FILES="$BS $SC/fastapi-nextjs/backend/app/routers $SC/nextjs-fullstack/src/app/api $SC/fastapi-nextjs/e2e"

python3 -I - "$BS" "$SC" <<'PY' || fail=1
import glob, json, os, re, sys
bs_path, sc = sys.argv[1:3]
failed = False
def check(name, cond, why=""):
    global failed
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        failed = True
        if why: print("  " + why)

r04 = next((l for l in open(bs_path, encoding="utf-8") if l.startswith("**R04** ")), "")
m = re.search(r"unless it is on the public list: (.*?) \(", r04)
public = set(re.findall(r"`((?:POST|PUT|PATCH|DELETE) /[^`]+)`", m.group(1))) if m else set()
check("R04 names its public list", public == {"POST /api/auth/logout"}, f"read: {sorted(public)}")

# FastAPI scaffold: each write decorator, its full path, and whether the handler carries require_permission(
routes, unguarded = [], []
for f in sorted(glob.glob(f"{sc}/fastapi-nextjs/backend/app/routers/*.py")):
    src = open(f, encoding="utf-8").read()
    pm = re.search(r'APIRouter\([^)]*prefix="([^"]*)"', src)
    prefix = pm.group(1) if pm else ""
    for d in re.finditer(r'^@router\.(post|put|patch|delete)\("([^"]*)"(.*?)\n(async )?def \w+\((.*?)\)\s*(->[^:]*)?:', src, re.M | re.S):
        method, path, deco, sig = d.group(1).upper(), d.group(2), d.group(3), d.group(5)
        route = f"{method} {prefix}{path}".rstrip("/") if path not in ("", "/") else f"{method} {prefix}"
        routes.append(route)
        if "require_permission(" not in deco + sig and route not in public:
            unguarded.append(f"{route} ({os.path.basename(f)})")
check("the FastAPI scaffold's write routes were found", len(routes) >= 20, f"found {len(routes)}")
check("every FastAPI scaffold write route carries require_permission, but R04's public list", not unguarded,
      "no require_permission: " + ", ".join(unguarded))

# Next.js full-stack scaffold: each exported write handler carries requirePermission
nx_routes, nx_unguarded = [], []
for f in sorted(glob.glob(f"{sc}/nextjs-fullstack/src/app/api/**/route.ts", recursive=True)):
    src = open(f, encoding="utf-8").read()
    path = "/" + os.path.relpath(os.path.dirname(f), f"{sc}/nextjs-fullstack/src/app").replace(os.sep, "/")
    path = re.sub(r"\[(\w+)\]", r"{\1}", path)
    heads = list(re.finditer(r"^export async function (POST|PUT|PATCH|DELETE)\b", src, re.M))
    for k, h in enumerate(heads):
        body = src[h.end(): heads[k + 1].start() if k + 1 < len(heads) else len(src)]
        nxt = re.search(r"^export ", body, re.M)
        body = body[: nxt.start()] if nxt else body
        route = f"{h.group(1)} {path}"
        nx_routes.append(route)
        if "requirePermission" not in body and route not in public:
            nx_unguarded.append(route)
check("the Next.js scaffold's write routes were found", len(nx_routes) >= 8, f"found {len(nx_routes)}")
check("every Next.js scaffold write route carries requirePermission, but R04's public list", not nx_unguarded,
      "no requirePermission: " + ", ".join(nx_unguarded))

# e2e: the browser tool, pinned and locked
for e2e in sorted(glob.glob(f"{sc}/*/e2e")):
    name = e2e.split("/")[-2]
    try:
        pj = json.load(open(f"{e2e}/package.json", encoding="utf-8"))
    except (OSError, ValueError):
        pj = {}
    ver = {**pj.get("dependencies", {}), **pj.get("devDependencies", {})}.get("@playwright/test", "")
    check(f"{name}/e2e/package.json names the browser tool, @playwright/test, at one exact version",
          bool(re.fullmatch(r"\d+\.\d+\.\d+", ver)), f"@playwright/test: {ver or '(missing)'}")
    try:
        lock = json.load(open(f"{e2e}/package-lock.json", encoding="utf-8"))
    except (OSError, ValueError):
        lock = {}
    lv = lock.get("packages", {}).get("node_modules/@playwright/test", {}).get("version", "")
    root_dev = lock.get("packages", {}).get("", {}).get("devDependencies", {}).get("@playwright/test", "")
    check(f"{name}/e2e/package-lock.json locks that same version", bool(ver) and lv == ver and root_dev == ver,
          f"package.json {ver or '-'}, lock {lv or '-'} (root {root_dev or '-'})")
check("a scaffold ships e2e/ (fastapi-nextjs)", os.path.isdir(f"{sc}/fastapi-nextjs/e2e"))
sys.exit(1 if failed else 0)
PY

if [ -z "${1:-}" ]; then
  opp() {
    local d="$TMPD/m"; rm -rf "$d"; mkdir -p "$d"
    tar -cf - $FILES | tar -xf - -C "$d"
    perl -0pi -e "$2" "$d/$1"; ! cmp -s "$1" "$d/$1" || return 1
    local out; out="$(bash "$SELF" "$d" 2>&1)" && return 1
    printf "%s\n" "$out" | grep -F "FAIL $3" >/dev/null
  }
  check "(control) an unchanged copy passes" 'd="$TMPD/c"; mkdir -p "$d"; tar -cf - $FILES | tar -xf - -C "$d"; bash "$SELF" "$d" >/dev/null 2>&1'
  check "(control) a FastAPI write route with its permission check removed (create_role)" \
    'opp "$SC/fastapi-nextjs/backend/app/routers/roles.py" "s/(async def create_role\(.*?)Depends\(require_permission\(\"admin\.roles\", \"create\"\)\)/\$1Depends(get_current_user)/s" "every FastAPI scaffold write route carries"'
  check "(control) a Next.js write route with its permission check removed (POST /api/users)" \
    'opp "$SC/nextjs-fullstack/src/app/api/users/route.ts" "s/(export async function POST\b.*?)requirePermission\([^)]*\)/\$1null/s" "every Next.js scaffold write route carries"'
  check "(control) an e2e/package.json without the browser tool" \
    'opp "$SC/fastapi-nextjs/e2e/package.json" "s/\"\@playwright\/test\": \"[^\"]*\"/\"left-pad\": \"1.3.0\"/" "fastapi-nextjs/e2e/package.json names the browser tool"'
  check "(control) the browser tool back to a range" \
    'opp "$SC/fastapi-nextjs/e2e/package.json" "s/\"\@playwright\/test\": \"/\"\@playwright\/test\": \"^/" "fastapi-nextjs/e2e/package.json names the browser tool"'
fi

check "the whole run wrote nothing to stderr" '[ ! -s "$ERRF" ] || { sed "s/^/  stderr: /" "$ERRF"; false; }'
[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
