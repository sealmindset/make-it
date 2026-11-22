# add-no-force-push-hook.ps1 -- Add (or remove) make-it's no-force-push hook in a Claude Code
# settings.json, keeping everything else. The PowerShell twin of add-no-force-push-hook.py
# (install.sh): same arguments, same outcomes, tested on the same fixtures by
# scripts/test-no-force-push.sh.
#
# Usage: add-no-force-push-hook.ps1 <settings.json> <hook command> <hook file> <state file> [auto|add|remove]
#   exit 0  done, or nothing to do        exit 1  the file can't be read or written: nothing changed
#
# Read as strict UTF-8 (a bad byte stops it; a byte-order mark is read past) and checked as strict
# JSON where .NET can (System.Text.Json: no comments, no trailing commas, no NaN), so it refuses
# what the Python helper refuses. Written as UTF-8 without a byte-order mark (Set-Content in Windows
# PowerShell 5.1 would write the ANSI code page). PowerShell 7.0-7.4 turns date-like strings into
# dates when it reads JSON, so there a file holding one is left alone (7.5+ keeps them as strings).
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Command,
    [Parameter(Mandatory = $true)][string]$HookFile,
    [Parameter(Mandatory = $true)][string]$StateFile,
    [ValidateSet("auto", "add", "remove")][string]$Mode = "auto"
)
$ErrorActionPreference = "Stop"
$mark = "make-it/hooks/no-force-push.sh"

function Stop-Unchanged($why) {
    [Console]::Error.WriteLine("Your Claude settings file $Path $why, so I didn't change it. The guard that stops git push --force is not changed. Fix or move that file, then run the installer again.")
    exit 1
}
function Set-State($value) {
    try {
        $d = Split-Path -Parent $StateFile
        if ($d -and -not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        [System.IO.File]::WriteAllText($StateFile, "$value`n", (New-Object System.Text.UTF8Encoding $false))
    } catch { }
}
function Get-Ours($entry) {
    if ($entry -isnot [System.Management.Automation.PSCustomObject]) { return @() }
    if ($entry.PSObject.Properties.Name -notcontains "hooks") { return @() }
    return @(@($entry.hooks) | Where-Object { $_ -is [System.Management.Automation.PSCustomObject] -and "$($_.command)".Contains($mark) })
}
# Sets $script:left: the PreToolUse entries without make-it's hook (an entry left with no hooks goes)
function Set-Without($pre) {
    $script:left = New-Object System.Collections.ArrayList
    foreach ($entry in $pre) {
        $mine = Get-Ours $entry
        if ($mine.Count -eq 0) { [void]$script:left.Add($entry); continue }
        $rest = @(@($entry.hooks) | Where-Object { $mine -notcontains $_ })
        if ($rest.Count -gt 0) {
            $copy = $entry.PSObject.Copy()
            $copy | Add-Member -NotePropertyName "hooks" -NotePropertyValue $rest -Force
            [void]$script:left.Add($copy)
        }
    }
}
function Write-Settings($data) {
    $dir = Split-Path -Parent $Real
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if ($exists -and (Get-Item -LiteralPath $Real).IsReadOnly) { Stop-Unchanged "is read-only" }
    $json = ($data | ConvertTo-Json -Depth 100) + "`n"
    $tmp = Join-Path $(if ($dir) { $dir } else { "." }) ".settings.$PID.tmp"
    try { [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding $false)) }
    catch { Stop-Unchanged "is in a folder I can't write to" }
    $script:backup = $null
    try {
        if ($exists) {
            $b = "$Real.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"; $n = 1
            while (Test-Path -LiteralPath $b) { $n++; $b = "$Real.bak-$(Get-Date -Format yyyyMMdd-HHmmss)-$n" }
            Copy-Item -LiteralPath $Real -Destination $b
            $script:backup = $b
        }
        Move-Item -LiteralPath $tmp -Destination $Real -Force
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        Stop-Unchanged "couldn't be written ($($_.Exception.Message))"
    }
}

# --- read ---------------------------------------------------------------------------------------
$exists = Test-Path -LiteralPath $Path -PathType Leaf
# A settings file that is a link stays a link: the file it points to is the one changed
$Real = $Path
if ($exists) {
    $it = Get-Item -LiteralPath $Path
    if ($it.LinkType -and $it.Target) {
        $t = @($it.Target)[0]
        if (-not [System.IO.Path]::IsPathRooted($t)) { $t = Join-Path (Split-Path -Parent $Path) $t }
        $Real = [System.IO.Path]::GetFullPath($t)
    }
}
$data = [PSCustomObject]@{}
if ($exists) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $start = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 }
        $text = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes, $start, $bytes.Length - $start)
    } catch { Stop-Unchanged "is not valid JSON (it isn't UTF-8 text)" }
    if ($text.Trim() -ne "") {
        if (-not $text.TrimStart().StartsWith("{")) { Stop-Unchanged "does not hold a JSON object" }
        if ("System.Text.Json.JsonDocument" -as [type]) {
            try { ([System.Text.Json.JsonDocument]::Parse($text)).Dispose() } catch { Stop-Unchanged "is not valid JSON" }
        }
        $v = $PSVersionTable.PSVersion
        $keepsDates = $v.Major -gt 7 -or ($v.Major -eq 7 -and $v.Minor -ge 5)
        if ($v.Major -ge 6 -and -not $keepsDates -and $text -match '"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}') {
            Stop-Unchanged "holds a date this version of PowerShell would rewrite"
        }
        try {
            if ($keepsDates) { $data = $text | ConvertFrom-Json -DateKind String } else { $data = $text | ConvertFrom-Json }
        } catch { Stop-Unchanged "is not valid JSON" }
        if ($data -isnot [System.Management.Automation.PSCustomObject]) { Stop-Unchanged "does not hold a JSON object" }
    }
}
if ($data.PSObject.Properties.Name -contains "hooks") {
    $hooks = $data.hooks
    if ($hooks -isnot [System.Management.Automation.PSCustomObject]) { Stop-Unchanged 'has a "hooks" entry that is not an object' }
} else { $hooks = [PSCustomObject]@{} }
$pre = @()
if ($hooks.PSObject.Properties.Name -contains "PreToolUse") {
    if ($hooks.PreToolUse -isnot [System.Array]) { Stop-Unchanged 'has a "hooks.PreToolUse" entry that is not a list' }
    $pre = @($hooks.PreToolUse)
}
$state = ""
if (Test-Path -LiteralPath $StateFile) { $state = ([System.IO.File]::ReadAllText($StateFile)).Trim() }
$present = @(foreach ($e in $pre) { Get-Ours $e })

# --- decide -------------------------------------------------------------------------------------
if ($Mode -eq "remove") {
    Set-State "removed"
    if ($present.Count -eq 0) { Write-Host "The guard that stops git push --force isn't in $Path; it stays off."; exit 0 }
    Set-Without $pre
    if ($script:left.Count -gt 0) { $hooks.PreToolUse = $script:left.ToArray() }
    else { $hooks.PSObject.Properties.Remove("PreToolUse") }
    if (@($hooks.PSObject.Properties).Count -eq 0) { $data.PSObject.Properties.Remove("hooks") }
    Write-Settings $data
    Write-Host "Removed the guard that stops git push --force from $Path (your old file is kept as $(Split-Path $script:backup -Leaf)). Later installs leave it out."
    exit 0
}
if ($Mode -eq "auto" -and ($state -eq "removed" -or ($state -eq "added" -and $present.Count -eq 0))) {
    Set-State "removed"
    Write-Host "The guard that stops git push --force stays off, as you chose."
    exit 0
}
$exact = $present.Count -eq 1 -and @($present[0].PSObject.Properties).Count -eq 3 -and
    $present[0].type -ceq "command" -and $present[0].command -ceq $Command -and $present[0].onFailure -ceq "block"
if ($exact -and (Test-Path -LiteralPath $HookFile -PathType Leaf)) {
    Set-State "added"
    Write-Host "The guard that stops git push --force is already in $Path."
    exit 0
}
$want = [PSCustomObject][ordered]@{ type = "command"; command = $Command; onFailure = "block" }
$ours = [PSCustomObject][ordered]@{ matcher = "Bash"; hooks = @($want) }
Set-Without $pre
[void]$script:left.Add($ours)
# set in place where the key exists, so the file keeps its order
if ($hooks.PSObject.Properties.Name -contains "PreToolUse") { $hooks.PreToolUse = $script:left.ToArray() }
else { $hooks | Add-Member -NotePropertyName "PreToolUse" -NotePropertyValue $script:left.ToArray() }
if ($data.PSObject.Properties.Name -notcontains "hooks") { $data | Add-Member -NotePropertyName "hooks" -NotePropertyValue $hooks }
Write-Settings $data
Set-State "added"
$verb = if ($present.Count -gt 0) { "Updated" } else { "Added" }
$note = if ($script:backup) { " (your old file is kept as $(Split-Path $script:backup -Leaf))" } else { "" }
Write-Host "$verb the guard that stops git push --force in $Path$note."
exit 0
