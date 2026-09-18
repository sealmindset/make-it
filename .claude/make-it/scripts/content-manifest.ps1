# content-manifest.ps1 -- Windows verifier for the /make-it install surface.
#
# WHY THIS EXISTS
#   content-manifest.sh made content drift detectable on macOS/Linux, but
#   install.ps1 never installed or checked CONTENT_MANIFEST at all. Windows
#   `/make-it update` therefore compared VERSION strings only -- the exact false
#   negative the manifest was built to remove: a release that changes content
#   without bumping VERSION reports "already current" forever.
#
# WHY VERIFY-ONLY, NO `generate`
#   Two generators would be two sources of truth. If this one ordered, excluded
#   or normalized a single path differently from content-manifest.sh, every
#   Windows user would see permanent phantom drift. Manifest PRODUCTION stays in
#   content-manifest.sh (run by maintainers); this script only CONSUMES it. Keep
#   it that way.
#
# LINE ENDINGS
#   Hashes are over bytes, so a CRLF checkout would mismatch every text file.
#   The repo pins LF via .gitattributes and install.ps1 clones with
#   core.autocrlf=false. If you see every file reported DIFFERS, suspect that
#   before suspecting a bad release.
#
# USAGE
#   content-manifest.ps1 verify <manifest> <claude_dir>
#   content-manifest.ps1 digest <manifest>
#
# Manifest lines are "<sha256>  <path relative to .claude/>", so the same file
# describes the repo (<repo>/.claude/...) and the install (~/.claude/...).
#
# Exit codes match content-manifest.sh: 0 = matches, 1 = drift, 2 = cannot run.

param(
    [Parameter(Position = 0)][string]$Command,
    [Parameter(Position = 1)][string]$Arg1,
    [Parameter(Position = 2)][string]$Arg2
)

$ErrorActionPreference = "Stop"

function Get-Sha256($path) {
    # -LiteralPath, not -Path: -Path glob-expands, and the manifest contains
    # Next.js dynamic routes whose names are wildcards to PowerShell --
    # make-it/scaffolds/.../roles/[id]/route.ts and five siblings. With -Path
    # those six return nothing, so every hash comparison on them throws.
    # Lower-cased to match the shasum/sha256sum output the manifest holds.
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Invoke-Verify($manifest, $claudeDir) {
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        Write-Error "ERROR: manifest not found: $manifest"
        return 2
    }
    if (-not (Test-Path -LiteralPath $claudeDir -PathType Container)) {
        Write-Error "ERROR: not a directory: $claudeDir"
        return 2
    }

    $checked = 0; $missing = 0; $differs = 0

    foreach ($line in [System.IO.File]::ReadLines((Resolve-Path -LiteralPath $manifest))) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        # "<hash><two spaces><relative path>". Split on the first run of spaces
        # only: paths cannot contain the separator, but splitting greedily on all
        # whitespace would corrupt any path that ever contains a space.
        $parts = $line -split '\s+', 2
        if ($parts.Count -ne 2) { continue }
        $want = $parts[0].Trim()
        $rel = $parts[1].Trim()
        if (-not $want -or -not $rel) { continue }

        $checked++
        # Manifest paths are POSIX; Join-Path on Windows accepts forward slashes
        # but normalize anyway so the printed output is readable.
        $file = Join-Path $claudeDir ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            Write-Host "  MISSING  $rel"
            $missing++
            continue
        }
        if ((Get-Sha256 $file) -ne $want) {
            Write-Host "  DIFFERS  $rel"
            $differs++
        }
    }

    if (($missing + $differs) -eq 0) {
        Write-Host "content matches manifest ($checked files)"
        return 0
    }
    Write-Host "content drift: $differs changed, $missing missing (of $checked tracked files)"
    return 1
}

function Invoke-Digest($manifest) {
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        Write-Error "ERROR: manifest not found: $manifest"
        return 2
    }
    Write-Host (Get-Sha256 $manifest)
    return 0
}

switch ($Command) {
    "verify" {
        if (-not $Arg1 -or -not $Arg2) { Write-Error "usage: content-manifest.ps1 verify <manifest> <claude_dir>"; exit 2 }
        exit (Invoke-Verify $Arg1 $Arg2)
    }
    "digest" {
        if (-not $Arg1) { Write-Error "usage: content-manifest.ps1 digest <manifest>"; exit 2 }
        exit (Invoke-Digest $Arg1)
    }
    default {
        Write-Host "usage:"
        Write-Host "  content-manifest.ps1 verify <manifest> <claude_dir>"
        Write-Host "  content-manifest.ps1 digest <manifest>"
        Write-Host ""
        Write-Host "Manifest generation lives in content-manifest.sh (single source of truth)."
        exit 2
    }
}
