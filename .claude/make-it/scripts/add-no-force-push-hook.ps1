# add-no-force-push-hook.ps1 -- Add make-it's no-force-push hook to a Claude Code settings.json,
# keeping everything else in it. The PowerShell twin of add-no-force-push-hook.py (install.sh).
#
# Usage: add-no-force-push-hook.ps1 <settings.json> <hook command>
#   exit 0  added, or already there (then nothing is written and nothing is backed up)
#   exit 1  the file can't be read as a JSON object this can merge into: nothing written
#
# Before the first change to an existing file, a copy is kept beside it as settings.json.bak-<time>.
# Read and written as UTF-8 (Set-Content in Windows PowerShell 5.1 would write the ANSI code page).
# PowerShell 7.0-7.4 turns date-like strings into dates when it reads JSON and writes them back in
# another form, so there a file holding one is left alone (7.5+ is told to keep them as strings).
param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Command)
$ErrorActionPreference = "Stop"
$mark = "make-it/hooks/no-force-push.sh"

function Stop-Unchanged($why) {
    [Console]::Error.WriteLine("Your Claude settings file $Path $why, so I didn't change it. The guard that stops git push --force is not added. Fix or move that file, then run the installer again.")
    exit 1
}

$exists = Test-Path -LiteralPath $Path -PathType Leaf
$text = ""
if ($exists) { $text = [System.IO.File]::ReadAllText($Path) }
if ($text.Trim() -eq "") {
    $data = [PSCustomObject]@{}
} else {
    # PowerShell 7 hands back a one-item list as the item itself, so the shape is checked on the text too
    if (-not $text.TrimStart().StartsWith("{")) { Stop-Unchanged "does not hold a JSON object" }
    $v = $PSVersionTable.PSVersion
    if ($v.Major -ge 6 -and -not ($v.Major -eq 7 -and $v.Minor -ge 5) -and $v.Major -lt 8 -and
        $text -match '"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}') {
        Stop-Unchanged "holds a date this version of PowerShell would rewrite"
    }
    try {
        if ($v.Major -gt 7 -or ($v.Major -eq 7 -and $v.Minor -ge 5)) {
            $data = $text | ConvertFrom-Json -DateKind String
        } else {
            $data = $text | ConvertFrom-Json
        }
    } catch { Stop-Unchanged "is not valid JSON" }
    if ($data -isnot [System.Management.Automation.PSCustomObject]) { Stop-Unchanged "does not hold a JSON object" }
}

$names = $data.PSObject.Properties.Name
if ($names -contains "hooks") {
    $hooks = $data.hooks
    if ($hooks -isnot [System.Management.Automation.PSCustomObject]) { Stop-Unchanged 'has a "hooks" entry that is not an object' }
} else {
    $hooks = [PSCustomObject]@{}
}
$pre = @()
if ($hooks.PSObject.Properties.Name -contains "PreToolUse") {
    if ($hooks.PreToolUse -isnot [System.Array]) { Stop-Unchanged 'has a "hooks.PreToolUse" entry that is not a list' }
    $pre = @($hooks.PreToolUse)
}
foreach ($entry in $pre) {
    if ($entry -is [System.Management.Automation.PSCustomObject] -and $entry.PSObject.Properties.Name -contains "hooks") {
        foreach ($h in @($entry.hooks)) {
            if ($h -is [System.Management.Automation.PSCustomObject] -and "$($h.command)".Contains($mark)) {
                Write-Host "The guard that refuses git push --force is already in $Path."
                exit 0
            }
        }
    }
}

$ours = [PSCustomObject]@{ matcher = "Bash"; hooks = @([PSCustomObject]@{ type = "command"; command = $Command }) }
$hooks | Add-Member -NotePropertyName "PreToolUse" -NotePropertyValue (@($pre) + $ours) -Force
$data | Add-Member -NotePropertyName "hooks" -NotePropertyValue $hooks -Force

$backupNote = ""
if ($exists) {
    $backup = "$Path.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    $n = 1
    while (Test-Path -LiteralPath $backup) { $n++; $backup = "$Path.bak-$(Get-Date -Format yyyyMMdd-HHmmss)-$n" }
    Copy-Item -LiteralPath $Path -Destination $backup
    $backupNote = " (your old file is kept as $(Split-Path $backup -Leaf))"
}
$dir = Split-Path -Parent $Path
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$json = $data | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($Path, $json + "`n", (New-Object System.Text.UTF8Encoding $false))
Write-Host "Added a guard to $Path that stops Claude from running git push --force$backupNote."
exit 0
