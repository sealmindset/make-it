# install.ps1 -- Install or update /make-it skills into Claude Code (Windows)
#
# Install from a cloned repo:
#   git clone https://github.com/sealmindset/make-it.git
#   cd make-it; .\install.ps1
#
# Install via PowerShell (no clone needed):
#   irm https://raw.githubusercontent.com/sealmindset/make-it/main/install.ps1 | iex
#
# Update (same command either way):
#   irm https://raw.githubusercontent.com/sealmindset/make-it/main/install.ps1 | iex
#   -- or from the cloned repo: git pull; .\install.ps1
#   -- or from inside Claude Code: /make-it update

$ErrorActionPreference = "Stop"

$GITHUB_REPO = "sealmindset/make-it"
$GITHUB_BRANCH = "main"
$GITHUB_RAW = "https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH"
$CLAUDE_DIR = Join-Path $env:USERPROFILE ".claude"
$COMMANDS_DIR = Join-Path $CLAUDE_DIR "commands"
$MAKEIT_DIR = Join-Path $CLAUDE_DIR "make-it"
$VERSION_FILE = Join-Path $MAKEIT_DIR "VERSION"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Info($msg)  { Write-Host "  $msg" }
function Ok($msg)    { Write-Host "  + $msg" }
function Warn($msg)  { Write-Host "  WARN: $msg" -ForegroundColor Yellow }
function Fail($msg)  {
    Write-Host ""
    Write-Host "  ERROR: $msg" -ForegroundColor Red
    Write-Host ""
    exit 1
}

function Get-InstalledVersion {
    if (Test-Path $VERSION_FILE) {
        return (Get-Content $VERSION_FILE -Raw).Trim()
    }
    return "none"
}

function Get-RemoteVersion {
    try {
        return (Invoke-RestMethod -Uri "$GITHUB_RAW/VERSION" -UseBasicParsing).Trim()
    } catch {
        return "unknown"
    }
}

# ---------------------------------------------------------------------------
# Determine source: local repo or download from GitHub
# ---------------------------------------------------------------------------

function Detect-Source {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }

    $commandsPath = Join-Path (Join-Path $scriptDir ".claude") "commands"
    $makeitPath = Join-Path (Join-Path $scriptDir ".claude") "make-it"

    if ((Test-Path $commandsPath) -and (Test-Path $makeitPath)) {
        return @{ Source = "local"; RepoDir = $scriptDir }
    }
    return @{ Source = "remote"; RepoDir = "" }
}

# ---------------------------------------------------------------------------
# Download repo to a temp directory (for remote installs)
# ---------------------------------------------------------------------------

function Download-Repo {
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "make-it-install-$(Get-Random)"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    Write-Host ""
    Write-Host "Downloading latest /make-it skills..."
    Write-Host ""

    # Check for git first (preferred)
    $hasGit = Get-Command git -ErrorAction SilentlyContinue
    if ($hasGit) {
        $cloneDest = Join-Path $tmpDir "make-it"
        git clone --depth 1 --branch $GITHUB_BRANCH "https://github.com/$GITHUB_REPO.git" $cloneDest 2>$null
        if ($LASTEXITCODE -ne 0) {
            Fail "Could not download from GitHub. Check your internet connection."
        }
        $repoDir = $cloneDest
    } else {
        # Fallback: download zip (tar.gz is less native on Windows)
        $zipPath = Join-Path $tmpDir "make-it.zip"
        try {
            Invoke-WebRequest -Uri "https://github.com/$GITHUB_REPO/archive/refs/heads/$GITHUB_BRANCH.zip" `
                -OutFile $zipPath -UseBasicParsing
        } catch {
            Fail "Could not download from GitHub. Check your internet connection."
        }
        try {
            Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force
        } catch {
            Fail "Could not extract download."
        }
        $repoDir = Join-Path $tmpDir "make-it-$GITHUB_BRANCH"
    }

    # Verify download
    $commandsPath = Join-Path (Join-Path $repoDir ".claude") "commands"
    $makeitPath = Join-Path (Join-Path $repoDir ".claude") "make-it"
    if (-not (Test-Path $commandsPath)) { Fail "Download incomplete -- .claude/commands not found." }
    if (-not (Test-Path $makeitPath))   { Fail "Download incomplete -- .claude/make-it not found." }

    return @{ RepoDir = $repoDir; TmpDir = $tmpDir }
}

# ---------------------------------------------------------------------------
# Install skills
# ---------------------------------------------------------------------------

function Install-Skills($repoDir) {
    New-Item -ItemType Directory -Path $COMMANDS_DIR -Force | Out-Null
    New-Item -ItemType Directory -Path $MAKEIT_DIR -Force | Out-Null

    # Auto-discover all skill files (*.md) in commands directory
    Write-Host "  Copying skill commands..."
    $skillCount = 0
    $cmdFiles = Get-ChildItem -Path (Join-Path (Join-Path $repoDir ".claude") "commands") -Filter "*.md" -File
    foreach ($cmdFile in $cmdFiles) {
        Copy-Item -Path $cmdFile.FullName -Destination $COMMANDS_DIR -Force
        Ok $cmdFile.Name
        $skillCount++
    }

    if ($skillCount -eq 0) {
        Fail "No skill files found in $repoDir/.claude/commands/"
    }

    # Copy references, templates, and scaffolds
    Write-Host "  Copying references, templates, and scaffolds..."
    if (Test-Path $MAKEIT_DIR) {
        Remove-Item -Path $MAKEIT_DIR -Recurse -Force
    }
    Copy-Item -Path (Join-Path (Join-Path $repoDir ".claude") "make-it") -Destination $MAKEIT_DIR -Recurse -Force

    # Verify
    $refsDir = Join-Path $MAKEIT_DIR "references"
    if (-not (Test-Path $refsDir)) { Fail "Copy failed -- references directory missing." }

    # Write version file
    $repoVersionFile = Join-Path $repoDir "VERSION"
    if (Test-Path $repoVersionFile) {
        Copy-Item -Path $repoVersionFile -Destination $VERSION_FILE -Force
    } else {
        Set-Content -Path $VERSION_FILE -Value "0.0.0"
    }
}

# ---------------------------------------------------------------------------
# Report results
# ---------------------------------------------------------------------------

function Report($action, $oldVersion) {
    $newVer = Get-InstalledVersion

    Write-Host ""
    if ($action -eq "update") {
        Write-Host "Updated successfully! (v$oldVersion -> v$newVer)"
    } else {
        Write-Host "Installed successfully! (v$newVer)"
    }

    Write-Host ""
    Write-Host "  Skills installed:"

    $itFiles = Get-ChildItem -Path $COMMANDS_DIR -Filter "*-it.md" -File -ErrorAction SilentlyContinue
    foreach ($f in $itFiles) {
        $cmdName = $f.BaseName
        $desc = switch ($cmdName) {
            "make-it"     { "Build a new app from scratch" }
            "try-it"      { "Spin up and test your app" }
            "resume-it"   { "Continue working on your app" }
            "retrofit-it" { "Upgrade an existing app with production foundations" }
            "nemo-it"     { "Security attestation (scan any app)" }
            "fix-it"      { "Auto-fix security findings from /nemo-it" }
            default       { "Custom skill" }
        }
        Write-Host ("    /{0,-14} -- {1}" -f $cmdName, $desc)
    }

    Write-Host ""
    Write-Host "  Files copied to:"
    Write-Host "    $COMMANDS_DIR\*.md"
    Write-Host "    $MAKEIT_DIR\ (references, templates, scaffolds)"
    Write-Host ""
    Write-Host "  IMPORTANT: Restart Claude Code for changes to take effect."
    Write-Host ""
    Write-Host "  To get started:"
    Write-Host "    cd ~\Documents\GitHub"
    Write-Host "    claude"
    Write-Host "    /make-it"
    Write-Host ""
    Write-Host "  To update later:"
    Write-Host "    /make-it update    (from inside Claude Code)"
    Write-Host "    -- or --"
    Write-Host "    irm https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH/install.ps1 | iex"
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Check for updates (called by /make-it update)
# ---------------------------------------------------------------------------

function Check-Update {
    $current = Get-InstalledVersion
    $remote = Get-RemoteVersion

    if ($remote -eq "unknown") {
        Write-Host "Could not check for updates. Verify your internet connection."
        exit 1
    }

    if ($current -eq $remote) {
        Write-Host "You're already on the latest version (v$current)."
        exit 0
    }

    Write-Host "Update available: v$current -> v$remote"
    exit 2
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Support being called with "check" argument
if ($args.Count -gt 0 -and $args[0] -eq "check") {
    Check-Update
    return
}

$oldVersion = Get-InstalledVersion
$action = if ($oldVersion -eq "none") { "install" } else { "update" }

Write-Host ""
if ($action -eq "update") {
    Write-Host "Updating /make-it skills (currently v$oldVersion)..."
} else {
    Write-Host "Installing /make-it skills into Claude Code..."
}
Write-Host ""

# Get the source files
$sourceInfo = Detect-Source
$repoDir = $sourceInfo.RepoDir
$tmpDir = $null

if ($sourceInfo.Source -eq "remote") {
    $downloadInfo = Download-Repo
    $repoDir = $downloadInfo.RepoDir
    $tmpDir = $downloadInfo.TmpDir
}

try {
    Install-Skills $repoDir
    Report $action $oldVersion
} finally {
    # Clean up temp directory if we downloaded
    if ($tmpDir -and (Test-Path $tmpDir)) {
        Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
