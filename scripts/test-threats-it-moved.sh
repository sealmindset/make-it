#!/usr/bin/env bash
# E05-S35: /threats-it moved to its own repository (https://github.com/sealmindset/threats-it). When make-it's
# installer updates a machine that has make-it's old copy (~/.claude/commands/threats-it.md and
# ~/.claude/make-it/threats-it/), it removes only the files that are still exactly what make-it installed (the
# CONTENT_MANIFEST of that install), keeps and names a changed one, leaves the separate install's command alone,
# never touches ~/.claude/threats-it/ (the organisation profile), and says in one line that it moved and how to
# install it.
#   Part 1  install.sh itself, run against a throwaway HOME holding an old install
#   Part 2  install.ps1's Plan-ThreatsItRetirement against the same fixtures (pwsh; SKIPPED loudly without it,
#           and a failure in CI, where pwsh is present on the runner)
#   Part 3  make-it no longer ships, tests or describes /threats-it, apart from the pointer
# Never touches the real ~/.claude.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
fail=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
if command -v pwsh >/dev/null 2>&1; then pwsh() { LC_ALL=C LANG=C command pwsh "$@"; }; fi
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi; }
MOVED='/threats-it has moved to its own repository'

# old_install HOME: what make-it installed before /threats-it moved, with its manifest, and a profile
old_install() {
  local C="$1/.claude"
  mkdir -p "$C/commands" "$C/make-it/threats-it/scripts/__pycache__" "$C/make-it/threats-it/references" "$C/threats-it"
  printf 'old /threats-it command\n' > "$C/commands/threats-it.md"
  printf 'print("hunt")\n' > "$C/make-it/threats-it/scripts/hunt.py"
  printf '# VEX\n' > "$C/make-it/threats-it/references/vex.md"
  printf 'bytecode' > "$C/make-it/threats-it/scripts/__pycache__/_common.cpython-312.pyc"
  printf '1.0.0\n' > "$C/make-it/VERSION"
  { printf '%s  commands/threats-it.md\n' "$(sha "$C/commands/threats-it.md")"
    printf '%s  make-it/threats-it/references/vex.md\n' "$(sha "$C/make-it/threats-it/references/vex.md")"
    printf '%s  make-it/threats-it/scripts/hunt.py\n' "$(sha "$C/make-it/threats-it/scripts/hunt.py")"; } > "$C/make-it/CONTENT_MANIFEST"
  printf 'Organisation name: Example Org\nTenant 00000000-0000-0000-0000-000000000000\n' > "$C/threats-it/environment.md"
}
profile_same() { [ "$(sha "$1/.claude/threats-it/environment.md")" = "$2" ] && [ "$(ls -A "$1/.claude/threats-it")" = "environment.md" ]; }
inst() { HOME="$1" bash "$root/install.sh" 2>&1; }

# --- Part 1: install.sh ----------------------------------------------------------------------------
H="$T/unchanged"; old_install "$H"; P="$(sha "$H/.claude/threats-it/environment.md")"
out="$(inst "$H")"; rc=$?
[ $rc -eq 0 ] && ok "an update over the old copy succeeds" || bad "update failed (exit $rc): $(printf '%s' "$out" | tail -5)"
[ ! -e "$H/.claude/commands/threats-it.md" ] && [ ! -e "$H/.claude/make-it/threats-it" ] \
  && ok "the unchanged old command and support folder are removed" || bad "old copy left: $(ls "$H/.claude/commands" "$H/.claude/make-it" 2>&1 | grep threats)"
[ "$(printf '%s\n' "$out" | grep -cF "$MOVED")" -eq 1 ] && printf '%s' "$out" | grep -qF "sealmindset/threats-it/main/install.sh" \
  && ok "it says once, in one line, that /threats-it moved and how to install it" || bad "no moved line: $out"
profile_same "$H" "$P" && ok "the profile in ~/.claude/threats-it/ is byte-identical and alone" || bad "the profile changed"
out="$(inst "$H")"; ! printf '%s' "$out" | grep -qF "$MOVED" && ok "the next update says nothing more about it" || bad "moved line repeated"

H="$T/changed"; old_install "$H"; P="$(sha "$H/.claude/threats-it/environment.md")"
echo "my note" >> "$H/.claude/commands/threats-it.md"; echo "my note" >> "$H/.claude/make-it/threats-it/references/vex.md"
cmd_h="$(sha "$H/.claude/commands/threats-it.md")"; vex_h="$(sha "$H/.claude/make-it/threats-it/references/vex.md")"
out="$(inst "$H")"; rc=$?
[ $rc -eq 0 ] && [ "$(sha "$H/.claude/commands/threats-it.md")" = "$cmd_h" ] && [ "$(sha "$H/.claude/make-it/threats-it/references/vex.md")" = "$vex_h" ] \
  && ok "a changed command and a changed support file stay where they were, unchanged" || bad "changed files not kept (exit $rc)"
[ ! -e "$H/.claude/make-it/threats-it/scripts/hunt.py" ] && [ ! -e "$H/.claude/make-it/threats-it/scripts/__pycache__" ] \
  && ok "the unchanged files beside them, and Python's cache, are removed" || bad "unchanged files left beside the kept ones"
line="$(printf '%s\n' "$out" | grep -F "$MOVED")"
printf '%s' "$line" | grep -qF "$H/.claude/commands/threats-it.md" && printf '%s' "$line" | grep -qF "references/vex.md" \
  && ok "the moved line names each kept file" || bad "kept files not named: $line"
profile_same "$H" "$P" && ok "the profile is byte-identical when files are kept" || bad "the profile changed"
out="$(inst "$H")"; line="$(printf '%s\n' "$out" | grep -F "$MOVED")"
! printf '%s' "$line" | grep -qF "removed" && printf '%s' "$line" | grep -qF "kept these files" && printf '%s' "$line" | grep -qF "references/vex.md" \
  && printf '%s' "$line" | grep -qF "sealmindset/threats-it/main/install.sh" \
  && ok "the next update, with nothing removed, names the kept files and the install line, and claims no removal" || bad "second run line: $line"
mkdir -p "$H/.claude/threats-it-support"; : > "$H/.claude/threats-it-support/INSTALLED"
out="$(inst "$H")"; ! printf '%s' "$out" | grep -qF "$MOVED" && [ -f "$H/.claude/make-it/threats-it/references/vex.md" ] \
  && ok "once the separate install is there, it says nothing about the move, and the kept file stays" || bad "separate after kept: $out"

H="$T/nomanifest"; old_install "$H"; rm "$H/.claude/make-it/CONTENT_MANIFEST"
out="$(inst "$H")"; [ -f "$H/.claude/commands/threats-it.md" ] && [ -f "$H/.claude/make-it/threats-it/scripts/hunt.py" ] \
  && ok "with no manifest to prove what was installed, nothing of it is removed, and each file is named" || bad "removed without proof"

H="$T/separate"; old_install "$H"; P="$(sha "$H/.claude/threats-it/environment.md")"
mkdir -p "$H/.claude/threats-it-support"; printf 'new /threats-it command\n' > "$H/.claude/commands/threats-it.md"
printf '%s  commands/threats-it.md\n' "$(sha "$H/.claude/commands/threats-it.md")" > "$H/.claude/threats-it-support/INSTALLED"
new_h="$(sha "$H/.claude/commands/threats-it.md")"
out="$(inst "$H")"
[ "$(sha "$H/.claude/commands/threats-it.md")" = "$new_h" ] && [ -f "$H/.claude/threats-it-support/INSTALLED" ] && [ ! -e "$H/.claude/make-it/threats-it" ] \
  && ok "the separate install's command and folder are left alone; make-it's old folder goes" || bad "separate install touched"
! printf '%s' "$out" | grep -qF "$MOVED" && ok "and it says nothing about the move" || bad "separate line: $out"
H="$T/putback"; old_install "$H"; mkdir -p "$H/.claude/threats-it-support"; : > "$H/.claude/threats-it-support/INSTALLED"
out="$(inst "$H")"
[ ! -e "$H/.claude/commands/threats-it.md" ] && [ "$(printf '%s\n' "$out" | grep -cF "which had replaced yours; put yours back with:")" -eq 1 ] \
  && ok "make-it's command put back over the separate install is removed, and one line says to run the separate installer again" || bad "put-back case: $out"
out="$(inst "$H")"; ! printf '%s' "$out" | grep -qE "threats-it has|which had replaced" && ok "and the next update is silent" || bad "put-back repeated: $out"
profile_same "$H" "$P" && ok "the profile is byte-identical beside a separate install" || bad "the profile changed"

H="$T/fresh"; mkdir -p "$H"
out="$(inst "$H")"; [ $? -eq 0 ] && ! printf '%s' "$out" | grep -qF "$MOVED" && [ ! -e "$H/.claude/threats-it" ] \
  && ok "a fresh install says nothing about /threats-it and creates no profile folder" || bad "fresh install: $out"

# --- Part 2: install.ps1 ---------------------------------------------------------------------------
if command -v pwsh >/dev/null 2>&1; then
  # only the two functions are taken from install.ps1 (its own AST), so the rest of the Windows setup never runs
  cat > "$T/plan.ps1" <<'PS'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($args[0], [ref]$null, [ref]$null)
$ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
               $args[0].Name -in "Test-WasInstalled", "Plan-ThreatsItRetirement" }, $true) |
    ForEach-Object { . ([scriptblock]::Create($_.Extent.Text)) }
$CLAUDE_DIR = Join-Path $args[1] ".claude"; $COMMANDS_DIR = Join-Path $CLAUDE_DIR "commands"; $MAKEIT_DIR = Join-Path $CLAUDE_DIR "make-it"
$THREATS_INSTALL = "irm https://raw.githubusercontent.com/sealmindset/threats-it/main/install.ps1 | iex"
$r = Plan-ThreatsItRetirement (Join-Path $args[1] "new")
"drop=$($r.DropCmd)"; "note=$($r.Note)"
PS
  for kind in unchanged changed kept-only separate; do
    H="$T/ps-$kind"; old_install "$H"
    [ "$kind" = changed ] && echo "my note" >> "$H/.claude/make-it/threats-it/references/vex.md"
    if [ "$kind" = kept-only ]; then   # what is left after an earlier update: only the changed file
      rm "$H/.claude/commands/threats-it.md" "$H/.claude/make-it/threats-it/scripts/hunt.py"; echo "my note" >> "$H/.claude/make-it/threats-it/references/vex.md"
    fi
    [ "$kind" = separate ] && { mkdir -p "$H/.claude/threats-it-support"; : > "$H/.claude/threats-it-support/INSTALLED"; }
    mkdir -p "$H/new"
    got="$(pwsh -NoProfile -File "$T/plan.ps1" "$root/install.ps1" "$H" 2>&1)"
    if [ "$kind" = kept-only ]; then
      printf '%s' "$got" | grep -qx 'drop=False' && printf '%s' "$got" | grep -qF "kept these files" && ! printf '%s' "$got" | grep -qF "removed" \
        && printf '%s' "$got" | grep -qF "install.ps1 | iex" && ok "install.ps1: with only kept files left, it names them and the install line, and claims no removal" || bad "install.ps1 kept-only: $got"
    elif [ "$kind" = separate ]; then
      printf '%s' "$got" | grep -qx 'drop=True' && printf '%s' "$got" | grep -qF "which had replaced yours; put yours back with:" \
        && ok "install.ps1: make-it's command put back over the separate install is removed, and it says to run the separate installer again" || bad "install.ps1 separate: $got"
    elif [ "$kind" = unchanged ]; then
      printf '%s' "$got" | grep -qx 'drop=True' && printf '%s' "$got" | grep -qF "note=$MOVED" && printf '%s' "$got" | grep -qF "install.ps1 | iex" \
        && [ -z "$(find "$H/new" -type f)" ] && ok "install.ps1: an unchanged old copy is dropped, with the moved line" || bad "install.ps1 unchanged: $got"
    else
      printf '%s' "$got" | grep -qx 'drop=True' && printf '%s' "$got" | grep -qF "references/vex.md" && [ -f "$H/new/threats-it/references/vex.md" ] \
        && [ ! -e "$H/new/threats-it/scripts/hunt.py" ] && ok "install.ps1: a changed support file is kept in the new folder and named" || bad "install.ps1 changed: $got"
    fi
  done
else
  echo "SKIPPED  install.ps1's removal of the old /threats-it: pwsh is not installed here -- NOT PROVEN on this machine"
  [ -z "${CI:-}" ] || bad "pwsh missing in CI: install.ps1's removal of the old /threats-it went untested"
fi

# --- Part 3: make-it no longer ships it -----------------------------------------------------------
[ ! -e .claude/commands/threats-it.md ] && [ ! -e .claude/make-it/threats-it ] && [ ! -e scripts/threats-it-stand-in ] \
  && [ ! -e .claude/make-it/confluence-docs/17-threats-it.md ] && [ -z "$(ls scripts/test-threats-it-*.sh 2>/dev/null | grep -v moved)" ] \
  && ok "make-it ships none of /threats-it's files" || bad "a /threats-it file is still shipped"
[ "$(grep -c 'threats-it' CONTENT_MANIFEST)" -eq 0 ] && ok "the content manifest lists none of them" || bad "CONTENT_MANIFEST still lists /threats-it"
for f in README.md CLAUDE.md .claude/make-it/README.md .claude/make-it/confluence-docs/00-make-it-framework-overview.md; do
  grep -qF 'https://github.com/sealmindset/threats-it' "$f" && ok "$f points at the new repository" || bad "$f has no pointer"
done
exit $fail
