# make-it-installed.ps1 -- print the make-it version installed for one user account, for a device-management
# inventory item. Prints "make-it <version>" or "make-it not installed", and exits 0 either way.
#
# Usage:  make-it-installed.ps1 [-HomeDir <folder>]     (default: $env:USERPROFILE)
#
# It reads one file, <folder>\.claude\make-it\VERSION, which make-it's installer writes on every install and update.
# It changes nothing and contacts nothing. Only letters, digits, ".", "+" and "-" from the file are printed, at most
# 64 of them: the file is the user's to edit, so its content is never trusted.
# A device-management script usually runs as SYSTEM, whose profile is not the person's: pass each person's folder.
param([string]$HomeDir = $env:USERPROFILE)
$v = ""
if ($HomeDir) {
    $f = Join-Path (Join-Path (Join-Path $HomeDir ".claude") "make-it") "VERSION"
    if (Test-Path -LiteralPath $f -PathType Leaf) {
        $line = Get-Content -LiteralPath $f -TotalCount 1 -ErrorAction SilentlyContinue
        if ($line) {
            $v = ([string]$line) -replace '[^0-9A-Za-z.+-]', ''
            if ($v.Length -gt 64) { $v = $v.Substring(0, 64) }
        }
    }
}
if ($v) { "make-it $v" } else { "make-it not installed" }
exit 0
