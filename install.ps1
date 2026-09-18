# install.ps1 -- Full Windows setup for Claude Code + /make-it skills
#
# First-time setup (installs everything, handles reboot):
#   1. Open PowerShell
#   2. Run: Set-ExecutionPolicy -Scope Process Bypass
#   3. Run: irm https://raw.githubusercontent.com/sealmindset/make-it/main/install.ps1 | iex
#   4. If prompted to restart, restart your computer, then repeat steps 1-3
#
# From a cloned repo:
#   git clone https://github.com/sealmindset/make-it.git
#   cd make-it; .\install.ps1
#
# Update skills only (already set up):
#   irm https://raw.githubusercontent.com/sealmindset/make-it/main/install.ps1 | iex
#   -- or from inside Claude Code: /make-it update
#
# Check for updates without installing:
#   $env:MAKEIT_ACTION = "check"
#   irm https://raw.githubusercontent.com/sealmindset/make-it/main/install.ps1 | iex
#   -- from a clone: .\install.ps1 check
#
#   An environment variable is needed because $args is EMPTY under
#   `irm ... | iex` -- the pipeline passes no arguments, so `| iex check` is not
#   a thing. Without this, the documented one-liner could only ever run a full
#   install, never a check.
#
# Optional enterprise gateway (Azure AI Foundry / any Anthropic-compatible proxy):
#   $env:MAKEIT_FOUNDRY_BASE_URL = "https://your-gateway.example.com/anthropic"
#   Set it before running, and step 4 wires up token auth for that gateway.
#   Left unset, the installer does not touch your auth config at all and Claude
#   Code signs in normally. Model deployment names can be overridden with
#   MAKEIT_OPUS_MODEL / MAKEIT_SONNET_MODEL / MAKEIT_HAIKU_MODEL.

$ErrorActionPreference = "Stop"

# ===========================================================================
# Constants
# ===========================================================================

$GITHUB_REPO = "sealmindset/make-it"
$GITHUB_BRANCH = "main"
$GITHUB_RAW = "https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH"
$CLAUDE_DIR = Join-Path $env:USERPROFILE ".claude"
$COMMANDS_DIR = Join-Path $CLAUDE_DIR "commands"
$MAKEIT_DIR = Join-Path $CLAUDE_DIR "make-it"
$VERSION_FILE = Join-Path $MAKEIT_DIR "VERSION"
$MANIFEST_FILE = Join-Path $MAKEIT_DIR "CONTENT_MANIFEST"
$CONTENT_VERIFIER = Join-Path (Join-Path $MAKEIT_DIR "scripts") "content-manifest.ps1"
$STATE_FILE = Join-Path $CLAUDE_DIR ".setup-state.json"

# Optional enterprise gateway. Unset by default: this installer must not point a
# stranger's Claude Code at somebody else's endpoint, and install.sh never
# touches auth config at all.
$FOUNDRY_BASE_URL = $env:MAKEIT_FOUNDRY_BASE_URL
$OPUS_MODEL   = if ($env:MAKEIT_OPUS_MODEL)   { $env:MAKEIT_OPUS_MODEL }   else { "claude-opus-5" }
$SONNET_MODEL = if ($env:MAKEIT_SONNET_MODEL) { $env:MAKEIT_SONNET_MODEL } else { "claude-sonnet-5" }
$HAIKU_MODEL  = if ($env:MAKEIT_HAIKU_MODEL)  { $env:MAKEIT_HAIKU_MODEL }  else { "claude-haiku-4-5" }

# ===========================================================================
# Display helpers
# ===========================================================================

function Banner($msg)  { Write-Host ""; Write-Host "==  $msg  ==" -ForegroundColor Cyan; Write-Host "" }
function Step($msg)    { Write-Host "  >> $msg" -ForegroundColor White }
function Info($msg)    { Write-Host "     $msg" }
function Ok($msg)      { Write-Host "  +  $msg" -ForegroundColor Green }
function Warn($msg)    { Write-Host "  !  $msg" -ForegroundColor Yellow }
function Fail($msg)    {
    Write-Host ""
    Write-Host "  ERROR: $msg" -ForegroundColor Red
    Write-Host ""
    # throw, not exit. Under the documented `irm ... | iex` one-liner there is no
    # child scope: `exit` terminates the USER'S PowerShell session, closing the
    # window and taking the error message above with it. A throw stops the
    # script and leaves the session -- and the message -- alive.
    throw $msg
}

function Ask($prompt) {
    Write-Host ""
    Write-Host "  $prompt" -ForegroundColor Yellow -NoNewline
    Write-Host " " -NoNewline
    return Read-Host
}

function PressEnter($msg) {
    Write-Host ""
    Write-Host "  $msg" -ForegroundColor Yellow
    Write-Host "  Press ENTER to continue..." -ForegroundColor Yellow -NoNewline
    Read-Host | Out-Null
}

# ===========================================================================
# State management -- tracks progress across reboots
# ===========================================================================

function Get-SetupState {
    if (Test-Path $STATE_FILE) {
        try {
            return Get-Content $STATE_FILE -Raw | ConvertFrom-Json
        } catch {
            return $null
        }
    }
    return $null
}

function Save-SetupState($state) {
    New-Item -ItemType Directory -Path $CLAUDE_DIR -Force | Out-Null
    $state | ConvertTo-Json -Depth 5 | Set-Content $STATE_FILE -Force
}

function Remove-SetupState {
    if (Test-Path $STATE_FILE) {
        Remove-Item $STATE_FILE -Force
    }
}

function Is-StepDone($state, $stepName) {
    if (-not $state -or -not $state.completed) { return $false }
    return ($state.completed -contains $stepName)
}

function Mark-StepDone($state, $stepName) {
    if (-not $state.completed) {
        $state | Add-Member -NotePropertyName "completed" -NotePropertyValue @() -Force
    }
    $list = [System.Collections.ArrayList]@($state.completed)
    if ($list -notcontains $stepName) {
        $list.Add($stepName) | Out-Null
        $state.completed = $list.ToArray()
    }
    Save-SetupState $state
    return $state
}

# ===========================================================================
# PATH refresh -- avoids "close and reopen PowerShell" for installs
# ===========================================================================

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# ===========================================================================
# Prerequisite checks
# ===========================================================================

function Test-CommandExists($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Get-ContainerRuntime {
    # Returns @{ Found; Name; Cli; How } describing an already-installed Docker
    # Desktop or Rancher Desktop.
    #
    # Why this is more than `Get-Command docker`: a machine can have either
    # product fully installed while `docker` does not resolve in this session --
    # Rancher Desktop only populates ~\.rd\bin on first run, Docker Desktop's
    # PATH entry may post-date this shell, and a machine-wide install done by IT
    # can leave the user's PATH untouched until sign-out. Reading that as
    # "missing" reinstalls a runtime the user already has AND forces a restart
    # they do not need -- the single step of this installer people resent.
    #
    # Checked cheapest-first: PATH, then the two known CLI paths, then the
    # uninstall registry (authoritative, but slower and Windows-only).
    $result = [ordered]@{ Found = $false; Name = ""; Cli = $null; How = "" }

    if (Test-CommandExists "docker") {
        $result.Found = $true
        $result.Name  = "docker CLI"
        $result.Cli   = (Get-Command docker -ErrorAction SilentlyContinue).Source
        $result.How   = "on PATH"
        return [PSCustomObject]$result
    }

    $candidates = @()
    if (${env:ProgramFiles})       { $candidates += @{ Name = "Docker Desktop";  Path = (Join-Path ${env:ProgramFiles} "Docker\Docker\resources\bin\docker.exe") } }
    if (${env:ProgramFiles(x86)})  { $candidates += @{ Name = "Docker Desktop";  Path = (Join-Path ${env:ProgramFiles(x86)} "Docker\Docker\resources\bin\docker.exe") } }
    if ($env:ProgramData)          { $candidates += @{ Name = "Docker Desktop";  Path = (Join-Path $env:ProgramData "DockerDesktop\version-bin\docker.exe") } }
    if (${env:LOCALAPPDATA})       { $candidates += @{ Name = "Docker Desktop";  Path = (Join-Path ${env:LOCALAPPDATA} "Docker\cli-bin\docker.exe") } }
    if ($env:USERPROFILE)          { $candidates += @{ Name = "Rancher Desktop"; Path = (Join-Path $env:USERPROFILE ".rd\bin\docker.exe") } }
    if (${env:LOCALAPPDATA})       { $candidates += @{ Name = "Rancher Desktop"; Path = (Join-Path ${env:LOCALAPPDATA} "Programs\Rancher Desktop\resources\resources\win32\bin\docker.exe") } }

    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c.Path) {
            # Put it on this session's PATH: every later step, and Verify-Setup,
            # asks for `docker` by name. Finding it and then not exposing it
            # would report a runtime the rest of the run cannot use.
            $binDir = Split-Path -Parent $c.Path
            if ($env:Path -notlike "*$binDir*") { $env:Path = "$binDir;$env:Path" }
            $result.Found = $true
            $result.Name  = $c.Name
            $result.Cli   = $c.Path
            $result.How   = "found at $($c.Path)"
            return [PSCustomObject]$result
        }
    }

    # Registry: catches an install whose CLI lives somewhere non-default, and an
    # install that has never been launched.
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($key in $uninstallKeys) {
        try {
            $hit = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
                   Where-Object { $_.DisplayName -match 'Rancher Desktop|Docker Desktop' } |
                   Select-Object -First 1
        } catch { $hit = $null }
        if ($hit) {
            $result.Found = $true
            $result.Name  = $hit.DisplayName
            $result.How   = "registered as installed (CLI not on PATH yet)"
            return [PSCustomObject]$result
        }
    }

    # Service and process evidence. An MSI-less or per-machine Docker Desktop
    # install can miss the per-user uninstall hive this account can read, but the
    # service and the running app are unmissable.
    try {
        if (Get-Service -Name "com.docker.service" -ErrorAction SilentlyContinue) {
            $result.Found = $true
            $result.Name  = "Docker Desktop"
            $result.How   = "com.docker.service present"
            return [PSCustomObject]$result
        }
    } catch {}
    foreach ($proc in @(
        @{ Name = "Docker Desktop";  Process = "Docker Desktop" },
        @{ Name = "Docker Desktop";  Process = "com.docker.backend" },
        @{ Name = "Rancher Desktop"; Process = "Rancher Desktop" }
    )) {
        if (Get-Process -Name $proc.Process -ErrorAction SilentlyContinue) {
            $result.Found = $true
            $result.Name  = $proc.Name
            $result.How   = "$($proc.Process) is running"
            return [PSCustomObject]$result
        }
    }

    return [PSCustomObject]$result
}

function Test-AllPrerequisites {
    $missing = @()
    if (-not (Test-CommandExists "node"))   { $missing += "nodejs" }
    if (-not (Test-CommandExists "git"))    { $missing += "git" }
    if (-not (Test-CommandExists "az"))     { $missing += "azure-cli" }
    if (-not (Get-ContainerRuntime).Found) { $missing += "docker" }
    if (-not (Test-CommandExists "claude")) { $missing += "claude-code" }

    # Check for git-bash path
    $bashPath = [System.Environment]::GetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", "User")
    if (-not $bashPath -or -not (Test-Path $bashPath)) {
        $missing += "git-bash-path"
    }

    # Auth config counts as a prerequisite only when an enterprise gateway was
    # asked for. Without one there is nothing to configure, and treating its
    # absence as "missing" would drag every default install into the full setup
    # flow forever -- including plain skill updates.
    if ($FOUNDRY_BASE_URL) {
        $tokenScript = Join-Path $CLAUDE_DIR "get-claude-token.ps1"
        $settingsFile = Join-Path $CLAUDE_DIR "settings.json"
        if (-not (Test-Path $tokenScript))  { $missing += "token-script" }
        if (-not (Test-Path $settingsFile)) { $missing += "settings-json" }
    }

    return $missing
}

# ===========================================================================
# Content verification -- hash the INSTALLED files against a manifest
# ===========================================================================

# Runs the verifier in a CHILD process, deliberately. content-manifest.ps1 ends
# in `exit`, and calling it in-process under `irm ... | iex` would close the
# user's session. A child process also isolates its $ErrorActionPreference.
#
# Returns: 0 content matches, 1 drift (detail printed), 2 cannot determine.
function Invoke-ContentVerifier($verifier, $manifest, $claudeDir) {
    if (-not $verifier -or -not (Test-Path -LiteralPath $verifier)) { return 2 }
    if (-not (Test-Path -LiteralPath $manifest)) { return 2 }
    if (-not (Test-Path -LiteralPath $claudeDir)) { return 2 }

    $hostExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $psArgs = @("-NoProfile")
    # -ExecutionPolicy is a Windows-only switch; including it on other platforms
    # makes pwsh refuse to start, which would turn "verified" into "unavailable".
    if ($env:OS -eq "Windows_NT") { $psArgs += @("-ExecutionPolicy", "Bypass") }
    $psArgs += @("-File", $verifier, "verify", $manifest, $claudeDir)

    # Write-Host, not bare output: in PowerShell every uncaptured value a function
    # emits becomes part of its return value, so letting the child's stdout flow
    # through would return @("content matches manifest (256 files)", 0) and break
    # every `-eq 0` test at the call sites. The lines are still shown -- they name
    # the drifting files, which is the point of running this.
    $childOutput = & $hostExe @psArgs 2>&1
    foreach ($line in $childOutput) { Write-Host $line }
    if ($null -eq $LASTEXITCODE) { return 2 }
    if ($LASTEXITCODE -eq 0) { return 0 }
    if ($LASTEXITCODE -eq 1) { return 1 }
    return 2
}

function Test-InstalledContent($manifest) {
    return (Invoke-ContentVerifier $CONTENT_VERIFIER $manifest $CLAUDE_DIR)
}

# ===========================================================================
# Step 1: Install software via winget (batched -- one refresh after all)
# ===========================================================================

function Install-Software($state) {
    Banner "Step 1 of 6: Installing required software"

    Info "Checking what's already installed..."
    Refresh-Path

    $needReboot = $false

    # winget is this script's only installer. Windows 11 ships it; Windows 10
    # does not always, and a machine managed by IT can have it stripped. Every
    # `winget ...` call below is a bare command under $ErrorActionPreference =
    # "Stop", so on a machine without it the run died on the first winget line
    # with "The term 'winget' is not recognized" -- before installing anything,
    # and with no hint of what to do. Establish it once, and only demand it if
    # something actually needs installing: a fully provisioned machine has no
    # use for winget and must not be blocked over it.
    $hasWinget = Test-CommandExists "winget"
    $needsInstall = @()
    if (-not (Test-CommandExists "node"))   { $needsInstall += "Node.js" }
    if (-not (Test-CommandExists "git"))    { $needsInstall += "Git for Windows" }
    if (-not (Test-CommandExists "az"))     { $needsInstall += "Azure CLI" }
    if (-not (Get-ContainerRuntime).Found)  { $needsInstall += "a container runtime" }

    if ($needsInstall.Count -gt 0 -and -not $hasWinget) {
        Warn "winget (the Windows package installer) is not available on this machine."
        Info ""
        Info "Still needed: $($needsInstall -join ', ')"
        Info ""
        Info "Install winget by installing 'App Installer' from the Microsoft Store,"
        Info "then run this script again. Or install these by hand:"
        Info "  Node.js LTS       https://nodejs.org"
        Info "  Git for Windows   https://git-scm.com/downloads/win"
        Info "  Azure CLI         https://aka.ms/installazurecliwindows"
        Info "  Rancher Desktop   https://rancherdesktop.io/"
        Fail "winget not available and software is still missing."
    }

    # --- SSL-inspecting proxy check (Zscaler, Netskope, etc.) ---
    # These tools break winget source updates and Docker image pulls.
    $proxyRunning = $false
    $proxyName = ""
    foreach ($name in @("Zscaler", "ZscalerApp", "ZSATunnel", "Netskope", "GlobalProtect", "pangpa")) {
        if (Get-Process -Name $name -ErrorAction SilentlyContinue) {
            $proxyRunning = $true
            $proxyName = $name
            break
        }
    }

    if ($proxyRunning) {
        Warn "Network security tool detected ($proxyName)."
        Info ""
        Info "This tool can block software downloads. If installs fail below, you may"
        Info "need to temporarily pause it:"
        Info "  - Look for the security icon in your system tray (near the clock)"
        Info "  - Right-click it and choose 'Disable' or 'Pause'"
        Info "  - Pick the longest time option"
        Info "  - Run this script again"
        Info "  - Re-enable it when the script finishes"
        Info ""

        # Try to fix winget source index (often corrupted by SSL inspection).
        # Guarded and swallowed: this is opportunistic repair, and an error here
        # used to abort a run that had not yet installed anything.
        if ($hasWinget) {
            Step "Resetting winget package index (sometimes needed with security tools)..."
            try {
                winget source reset --force 2>$null | Out-Null
                winget source update 2>$null | Out-Null
            } catch {
                Warn "Could not refresh the winget index -- continuing anyway."
            }
        }
    }

    # --- Node.js ---
    if (Is-StepDone $state "nodejs") {
        Ok "Node.js -- already done"
    } elseif (Test-CommandExists "node") {
        $ver = (node --version 2>$null)
        Ok "Node.js -- already installed ($ver)"
        $state = Mark-StepDone $state "nodejs"
    } else {
        Step "Installing Node.js (this is the runtime Claude Code needs)..."
        winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements 2>$null
        if ($LASTEXITCODE -ne 0) {
            Warn "winget install failed. Trying alternative method..."
            Info "Please install Node.js LTS manually from https://nodejs.org"
            Info "After installing, run this script again."
            throw "Node.js install failed"
        }
        Refresh-Path
        Ok "Node.js installed"
        $state = Mark-StepDone $state "nodejs"
    }

    # --- Git for Windows ---
    if (Is-StepDone $state "git") {
        Ok "Git for Windows -- already done"
    } elseif (Test-CommandExists "git") {
        $ver = (git --version 2>$null)
        Ok "Git -- already installed ($ver)"
        $state = Mark-StepDone $state "git"
    } else {
        Step "Installing Git for Windows (version control + git-bash shell)..."
        winget install Git.Git --accept-source-agreements --accept-package-agreements 2>$null
        if ($LASTEXITCODE -ne 0) {
            Warn "winget install failed. Please install Git from https://git-scm.com/downloads/win"
            Info "After installing, run this script again."
            throw "Git for Windows install failed"
        }
        Refresh-Path
        Ok "Git for Windows installed"
        $state = Mark-StepDone $state "git"
    }

    # --- Azure CLI ---
    if (Is-StepDone $state "azure-cli") {
        Ok "Azure CLI -- already done"
    } elseif (Test-CommandExists "az") {
        Ok "Azure CLI -- already installed"
        $state = Mark-StepDone $state "azure-cli"
    } else {
        Step "Installing Azure CLI (connects to your organization's AI service)..."
        winget install Microsoft.AzureCLI --accept-source-agreements --accept-package-agreements 2>$null
        if ($LASTEXITCODE -ne 0) {
            Warn "winget install failed. Please install Azure CLI from https://aka.ms/installazurecliwindows"
            Info "After installing, run this script again."
            throw "Azure CLI install failed"
        }
        Refresh-Path
        Ok "Azure CLI installed"
        $state = Mark-StepDone $state "azure-cli"
    }

    # --- Container Runtime (Rancher Desktop or Docker Desktop) ---
    if (Is-StepDone $state "docker") {
        Ok "Container runtime -- already done"
    } else {
        $runtime = Get-ContainerRuntime
        if ($runtime.Found) {
            # Either product works -- /make-it only needs a Docker-compatible CLI.
            # Do NOT install and do NOT set $needReboot: this is the whole point
            # of the check. A user who already runs Docker Desktop gets nothing
            # installed over the top of it and no restart.
            Ok "Container runtime -- already installed: $($runtime.Name) ($($runtime.How))"
            $other = if ($runtime.Name -match "Rancher") { "Docker Desktop" } else { "Rancher Desktop" }
            Info "  Either runtime satisfies /make-it -- $other is NOT required and will not be installed."
            if ($runtime.Cli) {
                $dockerVer = & $runtime.Cli --version 2>$null
                if ($LASTEXITCODE -eq 0 -and $dockerVer) {
                    Ok "  $dockerVer"
                } else {
                    # Installed but not serving: normal when the desktop app has
                    # not been started. Claude Code is unaffected; only container
                    # builds are, so say so and carry on.
                    Warn "  $($runtime.Name) is installed but not responding yet."
                    Info "  Start it from the Start menu before running a /make-it build."
                }
            }
            $state = Mark-StepDone $state "docker"
        }
    }
    if (-not (Is-StepDone $state "docker")) {
        Step "Installing Rancher Desktop (runs your apps in containers)..."
        Info "This may take a few minutes..."

        # Check if WSL is available -- Rancher Desktop needs it
        $wslInstalled = $false
        try {
            $wslOutput = wsl --status 2>$null
            if ($LASTEXITCODE -eq 0) { $wslInstalled = $true }
        } catch {}

        if (-not $wslInstalled) {
            Step "Installing WSL 2 (required by Rancher Desktop)..."
            Info "This may require administrator access. If prompted, click Yes."
            try {
                wsl --install --no-distribution 2>$null
            } catch {
                Warn "WSL install may need administrator access."
                Info "If this failed, right-click PowerShell > 'Run as administrator' and run:"
                Info "  wsl --install"
                Info "Then restart your computer and run this script again."
            }
        }

        winget install suse.RancherDesktop --accept-source-agreements --accept-package-agreements 2>$null
        if ($LASTEXITCODE -ne 0) {
            Warn "winget install failed. Please install Rancher Desktop from https://rancherdesktop.io/"
            Info "After installing, restart your computer and run this script again."
            throw "Rancher Desktop install failed"
        }

        # Configure Rancher Desktop: use dockerd (moby) engine, disable Kubernetes
        $rdSettingsDir = Join-Path $env:APPDATA "rancher-desktop"
        if (-not (Test-Path $rdSettingsDir)) {
            New-Item -ItemType Directory -Path $rdSettingsDir -Force | Out-Null
        }
        $rdSettingsFile = Join-Path $rdSettingsDir "settings.json"
        $rdSettings = @{
            version         = 6
            containerEngine = @{
                name = "moby"
            }
            kubernetes      = @{
                enabled = $false
            }
        } | ConvertTo-Json -Depth 4
        Set-Content -Path $rdSettingsFile -Value $rdSettings -Encoding UTF8
        Ok "Rancher Desktop configured (Docker-compatible mode, Kubernetes off)"

        $needReboot = $true
        $state = Mark-StepDone $state "docker"
    }

    # --- GitHub CLI (optional, install if winget available) ---
    if (-not (Is-StepDone $state "github-cli")) {
        if (Test-CommandExists "gh") {
            Ok "GitHub CLI -- already installed"
            $state = Mark-StepDone $state "github-cli"
        } else {
            Step "Installing GitHub CLI (lets you push code to GitHub)..."
            winget install GitHub.cli --accept-source-agreements --accept-package-agreements 2>$null
            if ($LASTEXITCODE -eq 0) {
                Refresh-Path
                Ok "GitHub CLI installed"
            } else {
                Warn "GitHub CLI install skipped (optional -- you can install it later)"
            }
            $state = Mark-StepDone $state "github-cli"
        }
    }

    # Refresh PATH one final time after all installs
    Refresh-Path

    # --- Handle reboot ---
    if ($needReboot) {
        Save-SetupState $state

        Banner "Restart Required"
        Info "Rancher Desktop was just installed and needs a restart to finish setup."
        Info ""
        Info "Here's what to do:"
        Info "  1. Restart your computer"
        Info "  2. After restarting, open Rancher Desktop from the Start menu"
        Info "     (wait for it to finish starting -- you'll see a green icon near the clock)"
        Info "  3. Open PowerShell"
        Info "  4. Run:  Set-ExecutionPolicy -Scope Process Bypass"
        Info "  5. Run this script again -- it will pick up where it left off"
        Info ""

        if ($PSScriptRoot) {
            Info "  To resume from a cloned repo:"
            Info "    cd $PSScriptRoot"
            Info "    .\install.ps1"
        } else {
            Info "  To resume:"
            Info "    irm https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH/install.ps1 | iex"
        }

        Write-Host ""
        # Stop the run without `exit`, which would close the session under iex.
        $script:RebootPending = $true
        return $state
    }

    return $state
}

# ===========================================================================
# Step 2: Configure git-bash path
# ===========================================================================

function Configure-GitBash($state) {
    if (Is-StepDone $state "git-bash-path") {
        Ok "Git-bash path -- already configured"
        return $state
    }

    Banner "Step 2 of 6: Configuring git-bash path"

    # Check if already set and valid
    $existingPath = [System.Environment]::GetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", "User")
    if ($existingPath -and (Test-Path $existingPath)) {
        Ok "Git-bash path already set: $existingPath"
        $state = Mark-StepDone $state "git-bash-path"
        return $state
    }

    Step "Finding bash.exe on your computer..."

    # Strategy 1: Derive from git.exe location
    $bashPath = $null
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        $gitExe = $gitCmd.Source
        # git.exe is typically at ...\Git\cmd\git.exe -- bash.exe is at ...\Git\bin\bash.exe
        $gitDir = Split-Path (Split-Path $gitExe)
        $candidate = Join-Path (Join-Path $gitDir "bin") "bash.exe"
        if (Test-Path $candidate) {
            $bashPath = $candidate
        }
    }

    # Strategy 2: Search common locations
    if (-not $bashPath) {
        $searchPaths = @(
            "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
            "C:\Program Files\Git\bin\bash.exe",
            "C:\Program Files (x86)\Git\bin\bash.exe"
        )
        foreach ($p in $searchPaths) {
            if (Test-Path $p) {
                $bashPath = $p
                break
            }
        }
    }

    # Strategy 3: Recursive search
    if (-not $bashPath) {
        Step "Searching for bash.exe (this may take a moment)..."
        $found = Get-ChildItem -Path "C:\Program Files", "C:\Program Files (x86)", "$env:LOCALAPPDATA\Programs" `
            -Recurse -Filter "bash.exe" -ErrorAction SilentlyContinue | `
            Where-Object { $_.FullName -like "*\Git\bin\bash.exe" } | `
            Select-Object -First 1
        if ($found) {
            $bashPath = $found.FullName
        }
    }

    if (-not $bashPath) {
        Fail "Could not find git-bash (bash.exe) on your computer. Make sure Git for Windows is installed."
    }

    Info "Found bash.exe at: $bashPath"
    [System.Environment]::SetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", $bashPath, "User")
    $env:CLAUDE_CODE_GIT_BASH_PATH = $bashPath
    Ok "Git-bash path configured"

    $state = Mark-StepDone $state "git-bash-path"
    return $state
}

# ===========================================================================
# Step 3: Install Claude Code
# ===========================================================================

function Install-ClaudeCode($state) {
    if (Is-StepDone $state "claude-code") {
        Ok "Claude Code -- already done"
        return $state
    }

    Banner "Step 3 of 6: Installing Claude Code"

    Refresh-Path

    if (Test-CommandExists "claude") {
        $ver = (claude --version 2>$null)
        Ok "Claude Code already installed ($ver)"
        $state = Mark-StepDone $state "claude-code"
        return $state
    }

    if (-not (Test-CommandExists "npm")) {
        Fail "npm is not available. Make sure Node.js is installed (Step 1) and restart your PowerShell window."
    }

    Step "Installing Claude Code via npm..."
    npm install -g @anthropic-ai/claude-code 2>$null
    if ($LASTEXITCODE -ne 0) {
        Fail "Claude Code install failed. Try running: npm install -g @anthropic-ai/claude-code"
    }

    Refresh-Path
    Ok "Claude Code installed"
    $state = Mark-StepDone $state "claude-code"
    return $state
}

# ===========================================================================
# Step 4: Configure Azure AI Foundry (token script + settings.json)
# ===========================================================================

function Configure-AzureAuth($state) {
    # Opt-in, by design. install.sh configures no auth at all; this installer
    # used to hardcode one organization's staging gateway and its private model
    # deployment names, then write them over the settings.json of anybody who ran
    # the public one-liner. Unless a gateway is named, leave auth alone and let
    # Claude Code sign in the way it normally does.
    if (-not $FOUNDRY_BASE_URL) {
        Banner "Step 4 of 6: Authentication"
        Info "No enterprise gateway configured -- skipping auth setup."
        Info "Claude Code will sign you in on first run."
        Info ""
        Info "If your organization puts Claude behind an Azure AI Foundry gateway,"
        Info "re-run with the gateway set, e.g.:"
        Info "  \$env:MAKEIT_FOUNDRY_BASE_URL = \"https://gateway.example.com/anthropic\""
        Info "  irm $GITHUB_RAW/install.ps1 | iex"
        return $state
    }

    Banner "Step 4 of 6: Configuring gateway authentication"
    Info "Gateway: $FOUNDRY_BASE_URL"

    New-Item -ItemType Directory -Path $CLAUDE_DIR -Force | Out-Null
    $tokenScriptPath = Join-Path $CLAUDE_DIR "get-claude-token.ps1"
    $settingsPath = Join-Path $CLAUDE_DIR "settings.json"

    # --- Token helper script ---
    if (Is-StepDone $state "token-script") {
        Ok "Token helper script -- already done"
    } else {
        Step "Creating token helper script..."
        Info "This script fetches a security token from Azure so Claude Code can"
        Info "connect to your organization's AI service."

        $tokenContent = @'
# get-claude-token.ps1 -- Fetches an Azure AI Foundry token for Claude Code.
# Claude Code sends whatever this prints as: Authorization: Bearer <stdout>
# Run "az login" in PowerShell first if the token has expired.

$ErrorActionPreference = "Stop"
try {
    $token = (az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv) 2>$null
    if (-not $token) { throw "empty token" }
    [Console]::Out.Write($token.Trim())
} catch {
    [Console]::Error.WriteLine("ERROR: Run 'az login' in PowerShell before starting Claude Code.")
    exit 1
}
'@
        Set-Content -Path $tokenScriptPath -Value $tokenContent -Force
        Ok "Token helper script created at: $tokenScriptPath"
        $state = Mark-StepDone $state "token-script"
    }

    # --- Settings file: MERGE, never replace ---
    if (Is-StepDone $state "settings-json") {
        Ok "Settings file -- already done"
    } else {
        # The previous version wrote a fresh settings.json with Set-Content
        # whenever the existing one lacked an apiKeyHelper key -- silently
        # destroying that user's model choice, env, hooks, permissions and
        # plugins. Read, add only what is missing, write back, and keep a backup.
        $desiredEnv = [ordered]@{
            CLAUDE_CODE_USE_FOUNDRY         = "1"
            ANTHROPIC_FOUNDRY_BASE_URL      = $FOUNDRY_BASE_URL
            ANTHROPIC_DEFAULT_OPUS_MODEL    = $OPUS_MODEL
            ANTHROPIC_DEFAULT_SONNET_MODEL  = $SONNET_MODEL
            ANTHROPIC_DEFAULT_HAIKU_MODEL   = $HAIKU_MODEL
        }
        $helperCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$tokenScriptPath`""

        $settings = $null
        if (Test-Path $settingsPath) {
            try {
                $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
            } catch {
                Fail "$settingsPath is not valid JSON. Fix or move it, then re-run -- refusing to overwrite a file I cannot parse."
            }
            $backup = "$settingsPath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
            Copy-Item -LiteralPath $settingsPath -Destination $backup -Force
            Info "Backed up existing settings to $(Split-Path $backup -Leaf)"
        }
        if (-not $settings) { $settings = [PSCustomObject]@{} }

        Step "Updating settings file (preserving your existing settings)..."

        if ($settings.PSObject.Properties.Name -contains "apiKeyHelper") {
            Info "apiKeyHelper already set -- left untouched: $($settings.apiKeyHelper)"
        } else {
            $settings | Add-Member -NotePropertyName "apiKeyHelper" -NotePropertyValue $helperCmd -Force
            Ok "apiKeyHelper set"
        }

        if (-not ($settings.PSObject.Properties.Name -contains "env") -or $null -eq $settings.env) {
            $settings | Add-Member -NotePropertyName "env" -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        foreach ($key in $desiredEnv.Keys) {
            if ($settings.env.PSObject.Properties.Name -contains $key) {
                Info "env.$key already set -- left untouched"
            } else {
                $settings.env | Add-Member -NotePropertyName $key -NotePropertyValue $desiredEnv[$key] -Force
                Ok "env.$key = $($desiredEnv[$key])"
            }
        }

        $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Force
        Ok "Settings merged into: $settingsPath"
        $state = Mark-StepDone $state "settings-json"
    }

    # --- Azure login ---
    if (Is-StepDone $state "azure-login") {
        Ok "Azure login -- already done this session"
    } else {
        Step "Logging in to Azure..."
        Info "A browser window will open. Sign in with your corporate/work account"
        Info "(the same one you use for email and Teams)."
        Info ""

        PressEnter "Ready to open the Azure login page?"

        Refresh-Path

        if (-not (Test-CommandExists "az")) {
            Fail "Azure CLI is not available. Make sure it is installed (Step 1) and restart your PowerShell window."
        }

        az login 2>$null
        if ($LASTEXITCODE -ne 0) {
            Warn "Azure login did not complete. You can try again later by running: az login"
            Warn "Claude Code will not work until you are logged in to Azure."
        } else {
            # Verify token works
            $token = az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv 2>$null
            if ($token) {
                Ok "Azure login successful -- token verified"
            } else {
                Warn "Logged in to Azure, but could not get a Cognitive Services token."
                Warn "Your account may not have access. Contact your Azure administrator."
            }
            $state = Mark-StepDone $state "azure-login"
        }
    }

    return $state
}

# ===========================================================================
# Step 5: Install /make-it skills
# ===========================================================================

function Install-MakeItSkills($state) {
    if (Is-StepDone $state "skills") {
        Ok "/make-it skills -- already done"
        return $state
    }

    Banner "Step 5 of 6: Installing /make-it skills"

    New-Item -ItemType Directory -Path $COMMANDS_DIR -Force | Out-Null
    New-Item -ItemType Directory -Path $MAKEIT_DIR -Force | Out-Null

    # Determine source: local repo or download from GitHub.
    #
    # $PSScriptRoot is only populated when this script is a real FILE on disk.
    # Under `irm ... | iex` -- the install method this repo documents -- it is
    # empty, and the old fallback to Get-Location silently took the CALLER'S cwd
    # as the source repo. A new PowerShell window opens in %USERPROFILE%, which
    # after any previous install contains the .claude\commands + .claude\make-it
    # pair this check looks for. The installer then treated its own TARGET as its
    # SOURCE: Copy-Item refused the self-overwrite and the update died with
    # "Cannot overwrite the item ... with itself", installing nothing. Five lines
    # further down sits `Remove-Item $MAKEIT_DIR -Recurse -Force`, so the only
    # thing standing between that error and a deleted installation was the order
    # of two statements.
    #
    # So: trust $PSScriptRoot only, and never accept the profile or .claude dir.
    # This mirrors detect_source() in install.sh, which carries the same warning.
    $repoDir = $null
    $tmpDir = $null
    $scriptDir = $null
    if ($PSScriptRoot) {
        $candidate = (Resolve-Path -LiteralPath $PSScriptRoot).Path.TrimEnd('\', '/')
        $profileDir = (Resolve-Path -LiteralPath $env:USERPROFILE).Path.TrimEnd('\', '/')
        $claudeResolved = if (Test-Path -LiteralPath $CLAUDE_DIR) {
            (Resolve-Path -LiteralPath $CLAUDE_DIR).Path.TrimEnd('\', '/')
        } else { $CLAUDE_DIR.TrimEnd('\', '/') }

        if ($candidate -ieq $profileDir -or $candidate -ieq $claudeResolved) {
            Warn "Ignoring $candidate as a source tree -- that is the install target."
        } else {
            $scriptDir = $candidate
        }
    }

    $commandsPath = if ($scriptDir) { Join-Path (Join-Path $scriptDir ".claude") "commands" } else { $null }
    $makeitPath   = if ($scriptDir) { Join-Path (Join-Path $scriptDir ".claude") "make-it" } else { $null }

    if ($scriptDir -and (Test-Path $commandsPath) -and (Test-Path $makeitPath)) {
        Info "Installing from local repository..."
        $repoDir = $scriptDir
    } else {
        Step "Downloading latest /make-it skills from GitHub..."
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "make-it-install-$(Get-Random)"
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

        Refresh-Path
        $hasGit = Test-CommandExists "git"
        if ($hasGit) {
            $cloneDest = Join-Path $tmpDir "make-it"
            # core.autocrlf=false / core.eol=lf: Git for Windows defaults to
            # autocrlf=true, which rewrites every text file to CRLF on checkout.
            # That changes their bytes, so (a) every CONTENT_MANIFEST hash would
            # mismatch and report phantom drift forever, and (b) the scaffolds'
            # entrypoint.sh would carry \r into a Linux container and fail to
            # execute. The published content is LF; keep it that way.
            git -c core.autocrlf=false -c core.eol=lf clone --depth 1 --branch $GITHUB_BRANCH `
                "https://github.com/$GITHUB_REPO.git" $cloneDest 2>$null
            if ($LASTEXITCODE -ne 0) {
                Fail "Could not download from GitHub. Check your internet connection."
            }
            $repoDir = $cloneDest
        } else {
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
        $dlCommands = Join-Path (Join-Path $repoDir ".claude") "commands"
        $dlMakeit = Join-Path (Join-Path $repoDir ".claude") "make-it"
        if (-not (Test-Path $dlCommands)) { Fail "Download incomplete -- .claude/commands not found." }
        if (-not (Test-Path $dlMakeit))   { Fail "Download incomplete -- .claude/make-it not found." }
    }

    # Last-resort guard. Source detection above should make this unreachable, but
    # the failure it prevents is destructive (Remove-Item -Recurse on the source),
    # so assert it rather than trust it. Same check as install_skills() in install.sh.
    $srcCommands = Join-Path (Join-Path $repoDir ".claude") "commands"
    $srcMakeit   = Join-Path (Join-Path $repoDir ".claude") "make-it"
    foreach ($pair in @(@($srcCommands, $COMMANDS_DIR), @($srcMakeit, $MAKEIT_DIR))) {
        $a = $pair[0]; $b = $pair[1]
        if ((Test-Path -LiteralPath $a) -and (Test-Path -LiteralPath $b)) {
            $ra = (Resolve-Path -LiteralPath $a).Path.TrimEnd('\', '/')
            $rb = (Resolve-Path -LiteralPath $b).Path.TrimEnd('\', '/')
            if ($ra -ieq $rb) {
                Fail "Refusing to install: source and destination are the same directory.
    source: $repoDir
    target: $CLAUDE_DIR
  The installer could not tell where it was run from. Re-run from a real clone
  (.\install.ps1), or: cd C:\ ; irm $GITHUB_RAW/install.ps1 | iex"
            }
        }
    }

    # Copy skill files
    Step "Copying skill commands..."
    $skillCount = 0
    $cmdFiles = Get-ChildItem -Path (Join-Path (Join-Path $repoDir ".claude") "commands") -Filter "*.md" -File
    foreach ($cmdFile in $cmdFiles) {
        Copy-Item -LiteralPath $cmdFile.FullName -Destination $COMMANDS_DIR -Force
        Ok $cmdFile.Name
        $skillCount++
    }

    if ($skillCount -eq 0) {
        Fail "No skill files found. Download may be corrupt -- try again."
    }

    # Copy references, templates, and scaffolds
    Step "Copying references, templates, and scaffolds..."
    if (Test-Path $MAKEIT_DIR) {
        Remove-Item -Path $MAKEIT_DIR -Recurse -Force
    }
    Copy-Item -Path (Join-Path (Join-Path $repoDir ".claude") "make-it") -Destination $MAKEIT_DIR -Recurse -Force

    # Verify
    $refsDir = Join-Path $MAKEIT_DIR "references"
    if (-not (Test-Path $refsDir)) { Fail "Copy failed -- references directory missing." }

    # Copy nemo-it references if present
    $nemoSrc = Join-Path (Join-Path $repoDir ".claude") "nemo-it"
    if (Test-Path $nemoSrc) {
        $nemoDir = Join-Path $CLAUDE_DIR "nemo-it"
        if (Test-Path $nemoDir) { Remove-Item $nemoDir -Recurse -Force }
        Copy-Item -Path $nemoSrc -Destination $nemoDir -Recurse -Force
    }

    # Write version file
    $repoVersionFile = Join-Path $repoDir "VERSION"
    if (Test-Path $repoVersionFile) {
        Copy-Item -LiteralPath $repoVersionFile -Destination $VERSION_FILE -Force
    } else {
        Set-Content -Path $VERSION_FILE -Value "0.0.0"
    }

    # Install the content manifest, so Check-Update can detect drift by hash
    # instead of trusting the VERSION string. install.sh has done this since the
    # manifest landed; this installer did not, which left every Windows user on
    # version-only update checks -- silently blind to any release that changed
    # content without bumping VERSION.
    $repoManifest = Join-Path $repoDir "CONTENT_MANIFEST"
    if (Test-Path $repoManifest) {
        Copy-Item -LiteralPath $repoManifest -Destination $MANIFEST_FILE -Force
        $verified = Test-InstalledContent $MANIFEST_FILE
        switch ($verified) {
            0 { Ok "Content verified against manifest" }
            1 { Warn "Installed content does not match the manifest it shipped with (see above)." }
            default { Warn "Could not verify installed content (verifier unavailable)." }
        }
    } else {
        Warn "No CONTENT_MANIFEST in source -- update checks will be version-only."
    }

    # Clean up temp directory
    if ($tmpDir -and (Test-Path $tmpDir)) {
        Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Ok "$skillCount skill(s) installed"
    $state = Mark-StepDone $state "skills"
    return $state
}

# ===========================================================================
# Step 6: Final verification
# ===========================================================================

function Verify-Setup($state) {
    Banner "Step 6 of 6: Verifying your setup"

    $allGood = $true

    # Node.js
    if (Test-CommandExists "node") {
        Ok "Node.js: $(node --version 2>$null)"
    } else {
        Warn "Node.js: NOT FOUND"
        $allGood = $false
    }

    # Git
    if (Test-CommandExists "git") {
        Ok "Git: $(git --version 2>$null)"
    } else {
        Warn "Git: NOT FOUND"
        $allGood = $false
    }

    # Azure CLI -- required only for the enterprise gateway path.
    if (Test-CommandExists "az") {
        Ok "Azure CLI: installed"
    } elseif ($FOUNDRY_BASE_URL) {
        Warn "Azure CLI: NOT FOUND (required for the configured gateway)"
        $allGood = $false
    } else {
        Info "  Azure CLI: not installed (only needed for an enterprise gateway)"
    }

    # Docker / Rancher -- same detector as Step 1, so the two cannot disagree.
    $runtime = Get-ContainerRuntime
    if ($runtime.Found) {
        $verText = if ($runtime.Cli) { (& $runtime.Cli --version 2>$null) } else { $null }
        if ($verText) { Ok "Container runtime: $verText" }
        else { Ok "Container runtime: $($runtime.Name) installed ($($runtime.How)) -- start it before a /make-it build" }
    } else {
        Warn "Docker CLI: NOT FOUND (you can still use Claude Code, but /make-it builds need a container runtime)"
        # Don't fail -- Docker is only needed for /make-it builds, not Claude Code itself
    }

    # Claude Code
    if (Test-CommandExists "claude") {
        Ok "Claude Code: installed"
    } else {
        Warn "Claude Code: NOT FOUND"
        $allGood = $false
    }

    # Git-bash path
    $bashPath = [System.Environment]::GetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", "User")
    if ($bashPath -and (Test-Path $bashPath)) {
        Ok "Git-bash: $bashPath"
    } else {
        Warn "Git-bash path: NOT CONFIGURED"
        $allGood = $false
    }

    # Gateway auth -- only a requirement when a gateway was requested. A default
    # install talks to Anthropic directly and has neither file, which is correct,
    # not "misconfigured". Reporting it as a failure sends every default user to
    # the "Setup Incomplete" path over something they never asked for.
    if ($FOUNDRY_BASE_URL) {
        $tokenScript = Join-Path $CLAUDE_DIR "get-claude-token.ps1"
        if (Test-Path $tokenScript) {
            Ok "Token script: $tokenScript"
        } else {
            Warn "Token script: NOT FOUND"
            $allGood = $false
        }

        $settingsFile = Join-Path $CLAUDE_DIR "settings.json"
        if (Test-Path $settingsFile) {
            # Verify username is not placeholder
            $content = Get-Content $settingsFile -Raw
            if ($content -match "YourName") {
                Warn "Settings file: contains 'YourName' placeholder -- needs your real username"
                $allGood = $false
            } else {
                Ok "Settings file: $settingsFile"
            }
        } else {
            Warn "Settings file: NOT FOUND"
            $allGood = $false
        }
    } else {
        Info "  Gateway auth: not configured (direct Anthropic access -- set MAKEIT_FOUNDRY_BASE_URL to change)"
    }

    # Skills
    $skillFiles = Get-ChildItem -Path $COMMANDS_DIR -Filter "*-it.md" -File -ErrorAction SilentlyContinue
    if ($skillFiles -and $skillFiles.Count -gt 0) {
        Ok "Skills installed: $($skillFiles.Count)"
        foreach ($f in $skillFiles) {
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
            Info ("    /{0,-14} -- {1}" -f $cmdName, $desc)
        }
    } else {
        Warn "Skills: NONE FOUND"
        $allGood = $false
    }

    # GitHub CLI (optional)
    if (Test-CommandExists "gh") {
        Ok "GitHub CLI: installed (optional)"
    } else {
        Info "  GitHub CLI: not installed (optional -- install later with: winget install GitHub.cli)"
    }

    return $allGood
}

# ===========================================================================
# Final report
# ===========================================================================

function Show-FinalReport($allGood) {
    if ($allGood) {
        Remove-SetupState

        Banner "Setup Complete!"
        Info "Everything is installed and configured. Here's how to start:"
        Info ""
        Info "  1. Open PowerShell"
        Info "  2. Run:  Set-ExecutionPolicy -Scope Process Bypass"
        if ($FOUNDRY_BASE_URL) {
            Info "  3. Run:  az login"
            Info "  4. Sign in with your corporate account in the browser"
            Info "  5. Run:  cd ~\Documents\GitHub"
            Info "  6. Run:  claude"
            Info "  7. Type: /make-it"
        } else {
            Info "  3. Run:  cd ~\Documents\GitHub"
            Info "  4. Run:  claude"
            Info "  5. Type: /make-it"
        }
        Info ""
        Info "That's it! Describe your app idea and /make-it builds it for you."
        Info ""
        Info "---------------------------------------------------------------"
        Info "  YOUR DAILY WORKFLOW (every time you use Claude Code):"
        Info ""
        Info "    Set-ExecutionPolicy -Scope Process Bypass"
        if ($FOUNDRY_BASE_URL) { Info "    az login" }
        Info "    cd ~\Documents\GitHub"
        Info "    claude"
        Info "---------------------------------------------------------------"
        Info ""
        if ($FOUNDRY_BASE_URL) {
            Info "  Azure tokens expire after ~1-2 hours. If Claude Code stops"
            Info "  working, close it, run 'az login' again, and restart 'claude'."
            Info ""
        }
        Info "  To update skills later:"
        Info "    /make-it update    (from inside Claude Code)"
        Info "    -- or --"
        Info "    irm https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH/install.ps1 | iex"
        Write-Host ""
    } else {
        Banner "Setup Incomplete"
        Warn "Some components are missing or misconfigured (see warnings above)."
        Info ""
        Info "Fix the issues and run this script again -- it will skip completed steps."
        Info ""
        if ($PSScriptRoot) {
            Info "  cd $PSScriptRoot"
            Info "  .\install.ps1"
        } else {
            Info "  irm https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH/install.ps1 | iex"
        }
        Write-Host ""
    }
}

# ===========================================================================
# Check-for-updates mode (called by /make-it update)
# ===========================================================================

# Mirrors check_update() in install.sh, including its reasoning: a matching
# VERSION string is NOT evidence of being current, because a release can change
# content without bumping VERSION and installed files can be edited locally. So
# after the version comparison, compare file hashes against the published
# manifest. This function returns the exit code rather than calling `exit`,
# which would close the session under `irm ... | iex`.
#   0 = current   1 = check failed   2 = update available
function Check-Update {
    $current = "none"
    if (Test-Path $VERSION_FILE) {
        $current = (Get-Content $VERSION_FILE -Raw).Trim()
    }

    $remote = "unknown"
    try {
        $remote = (Invoke-RestMethod -Uri "$GITHUB_RAW/VERSION" -UseBasicParsing).ToString().Trim()
    } catch {}

    if ($remote -eq "unknown") {
        Write-Host "Could not check for updates. Verify your internet connection."
        return 1
    }

    # A version difference is decisive on its own.
    if ($current -ne $remote) {
        Write-Host "Update available: v$current -> v$remote"
        return 2
    }

    # Same version string -- now check content.
    $tmpManifest = Join-Path ([System.IO.Path]::GetTempPath()) "make-it-manifest-$(Get-Random)"
    $tmpVerifier = Join-Path ([System.IO.Path]::GetTempPath()) "make-it-verifier-$(Get-Random).ps1"
    try {
        try {
            Invoke-WebRequest -Uri "$GITHUB_RAW/CONTENT_MANIFEST" -OutFile $tmpManifest -UseBasicParsing
        } catch {
            Write-Host "You're on v$current (matching the latest published version)."
            Write-Host "Note: could not fetch the content manifest, so this is a version-only"
            Write-Host "check -- content changes shipped without a version bump would be missed."
            return 0
        }

        # Fetch the verifier rather than trusting the installed copy: an install
        # that predates this feature has no verifier, and that is exactly the
        # install most likely to be stale. Fall back to the local one if offline.
        $verifier = $CONTENT_VERIFIER
        try {
            Invoke-WebRequest -Uri "$GITHUB_RAW/.claude/make-it/scripts/content-manifest.ps1" `
                -OutFile $tmpVerifier -UseBasicParsing
            if ((Test-Path $tmpVerifier) -and (Get-Item $tmpVerifier).Length -gt 0) { $verifier = $tmpVerifier }
        } catch {}

        $cstat = Invoke-ContentVerifier $verifier $tmpManifest $CLAUDE_DIR
        switch ($cstat) {
            0 {
                Write-Host "You're already on the latest version (v$current), and all content matches."
                return 0
            }
            1 {
                Write-Host "Update available: content differs from the published v$remote release."
                Write-Host "(Version strings match at v$current -- this was found by content hash.)"
                return 2
            }
            default {
                Write-Host "You're on v$current (matching the latest published version)."
                Write-Host "Note: could not verify file content (verifier unavailable) -- this is a"
                Write-Host "version-only check. Re-running the installer will refresh it."
                return 0
            }
        }
    } finally {
        Remove-Item -LiteralPath $tmpManifest -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpVerifier -Force -ErrorAction SilentlyContinue
    }
}

# ===========================================================================
# Skills-only mode (for updates when everything is already set up)
# ===========================================================================

function Update-SkillsOnly {
    $oldVersion = "none"
    if (Test-Path $VERSION_FILE) {
        $oldVersion = (Get-Content $VERSION_FILE -Raw).Trim()
    }
    $action = if ($oldVersion -eq "none") { "install" } else { "update" }

    Write-Host ""
    if ($action -eq "update") {
        Write-Host "Updating /make-it skills (currently v$oldVersion)..."
    } else {
        Write-Host "Installing /make-it skills..."
    }
    Write-Host ""

    # Use a temporary state just for skill install
    $tempState = [PSCustomObject]@{ completed = @() }
    $tempState = Install-MakeItSkills $tempState

    $newVer = "0.0.0"
    if (Test-Path $VERSION_FILE) {
        $newVer = (Get-Content $VERSION_FILE -Raw).Trim()
    }

    Write-Host ""
    if ($action -eq "update") {
        Write-Host "Updated successfully! (v$oldVersion -> v$newVer)" -ForegroundColor Green
    } else {
        Write-Host "Installed successfully! (v$newVer)" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "  IMPORTANT: Restart Claude Code for changes to take effect."
    Write-Host ""
}

# ===========================================================================
# Main
# ===========================================================================

# Handle check mode. Two triggers, because `irm ... | iex` passes no arguments:
#   .\install.ps1 check                      (file invocation)
#   $env:MAKEIT_ACTION = "check"; irm ... | iex   (one-liner)
$requestedAction = if ($args.Count -gt 0) { $args[0] } else { $env:MAKEIT_ACTION }
if ($requestedAction -eq "check") {
    $rc = Check-Update
    # Surface the result without `exit`, which would close the caller's session.
    $global:LASTEXITCODE = $rc
    $script:MakeItCheckExit = $rc
    Write-Host "check_exit=$rc"
    return
}

# Detect mode: full setup vs skills-only update
$missing = Test-AllPrerequisites
$existingState = Get-SetupState

if ($existingState) {
    # Resuming after reboot or previous incomplete run
    Banner "/make-it Setup -- Resuming"
    Info "Found saved progress from a previous run. Picking up where you left off."
    Info ""
    $state = $existingState
} elseif ($missing.Count -eq 0) {
    # Everything is installed -- just update skills
    Update-SkillsOnly
    return
} elseif ($missing.Count -eq 1 -and $missing[0] -eq "claude-code") {
    # Only Claude Code is missing -- probably a fresh npm install needed, not full setup
    # But also check if skills are missing
    $skillFiles = Get-ChildItem -Path $COMMANDS_DIR -Filter "*-it.md" -File -ErrorAction SilentlyContinue
    if ($skillFiles -and $skillFiles.Count -gt 0) {
        # Skills exist, just need Claude Code
        Banner "Installing Claude Code"
        npm install -g @anthropic-ai/claude-code 2>$null
        if ($LASTEXITCODE -eq 0) {
            Ok "Claude Code installed. Run 'claude' to start."
        } else {
            Fail "Claude Code install failed."
        }
        return
    }
    # Fall through to full setup
    $state = [PSCustomObject]@{ completed = @() }
} else {
    # Missing prerequisites -- run full setup
    $state = [PSCustomObject]@{ completed = @() }
}

# Full setup flow
if (-not $existingState) {
    Banner "/make-it Setup for Windows"
    Info "This script installs everything you need to run Claude Code with"
    Info "/make-it skills. It handles Node.js, Git, Azure CLI, Docker, and"
    Info "all configuration automatically."
    Info ""
    Info "If a restart is needed (for Docker), the script saves your progress"
    Info "and picks up where it left off when you run it again."
    Info ""
    PressEnter "Ready to begin?"
}

# Fail() throws rather than calling exit, because under `irm ... | iex` an exit
# closes the user's PowerShell window -- taking the error message with it. This
# catch is the other half of that: it prints the failure and where progress was
# saved, then ends the script normally so the window survives to be read.
try {
    # Step 1: Install all software (batched, one reboot at most)
    $script:RebootPending = $false
    $state = Install-Software $state
    if ($script:RebootPending) {
        # Progress is saved; the reboot message was already printed.
        return
    }

    # Step 2: Configure git-bash path
    $state = Configure-GitBash $state

    # Step 3: Install Claude Code
    $state = Install-ClaudeCode $state

    # Step 4: Configure Azure auth (token script + settings.json + az login)
    $state = Configure-AzureAuth $state

    # Step 5: Install /make-it skills
    $state = Install-MakeItSkills $state

    # Step 6: Verify everything
    $allGood = Verify-Setup $state

    # Final report
    Show-FinalReport $allGood
}
catch {
    Write-Host ""
    Write-Host "  [X] Setup stopped: $($_.Exception.Message)" -ForegroundColor Red
    if (Test-Path $STATE_FILE) {
        Write-Host "      Completed steps are saved in $STATE_FILE -- re-running"
        Write-Host "      this script resumes instead of starting over."
    }
    Write-Host ""
    $global:LASTEXITCODE = 1
}
