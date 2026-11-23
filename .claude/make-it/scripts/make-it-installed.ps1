# make-it-installed.ps1 -- print the make-it version installed for one user account, for a device-management
# inventory item. Prints one of three lines, and exits 0 in every case:
#   make-it <version>                        the VERSION file is a regular file whose first line looks like a version
#   make-it installed (version unreadable)   something named VERSION is there, but it is a link, a folder,
#                                            unreadable, or its first line is not a version
#   make-it not installed                    nothing named VERSION is there
#
# Usage:  make-it-installed.ps1 [-HomeDir <folder>]     (default: $env:USERPROFILE)
#
# It reads one file, <folder>\.claude\make-it\VERSION, which make-it's installer writes on every install and update,
# and at most its first 256 bytes. It never follows that file if it is a link (a person could point it at a file
# only SYSTEM can read); a linked make-it folder is fine. It changes nothing and contacts nothing. A
# device-management script usually runs as SYSTEM, whose profile is not the person's: pass each person's folder.
param([string]$HomeDir = $env:USERPROFILE)
$out = "make-it not installed"
if ($HomeDir) {
    $f = Join-Path (Join-Path (Join-Path $HomeDir ".claude") "make-it") "VERSION"
    $item = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    if ($item) {
        $out = "make-it installed (version unreadable)"
        $isLink = $item.LinkType -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
        if (-not $item.PSIsContainer -and -not $isLink) {
            try {
                $fs = [IO.File]::OpenRead($item.FullName)
                try {
                    $buf = New-Object byte[] 256
                    $n = $fs.Read($buf, 0, 256)
                } finally { $fs.Dispose() }
                $line = ([Text.Encoding]::ASCII.GetString($buf, 0, $n) -split "`r?`n")[0].Trim()
                if ($line.Length -le 64 -and $line -cmatch '^[0-9]+(\.[0-9]+){1,3}([-+][0-9A-Za-z.]+)?$') {
                    $out = "make-it $line"
                }
            } catch { }
        }
    }
}
$out
exit 0
