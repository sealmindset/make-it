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
$STATE_FILE = Join-Path $CLAUDE_DIR ".setup-state.json"

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
    exit 1
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

function Test-AllPrerequisites {
    $missing = @()
    if (-not (Test-CommandExists "node"))   { $missing += "nodejs" }
    if (-not (Test-CommandExists "git"))    { $missing += "git" }
    if (-not (Test-CommandExists "az"))     { $missing += "azure-cli" }
    if (-not (Test-CommandExists "docker")) { $missing += "docker" }
    if (-not (Test-CommandExists "claude")) { $missing += "claude-code" }

    # Check for git-bash path
    $bashPath = [System.Environment]::GetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", "User")
    if (-not $bashPath -or -not (Test-Path $bashPath)) {
        $missing += "git-bash-path"
    }

    # Check for config files
    $tokenScript = Join-Path $CLAUDE_DIR "get-claude-token.ps1"
    $settingsFile = Join-Path $CLAUDE_DIR "settings.json"
    if (-not (Test-Path $tokenScript))  { $missing += "token-script" }
    if (-not (Test-Path $settingsFile)) { $missing += "settings-json" }

    return $missing
}

# ===========================================================================
# Step 1: Install software via winget (batched -- one refresh after all)
# ===========================================================================

function Install-Software($state) {
    Banner "Step 1 of 6: Installing required software"

    Info "Checking what's already installed..."
    Refresh-Path

    $needReboot = $false

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
            exit 1
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
            exit 1
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
            exit 1
        }
        Refresh-Path
        Ok "Azure CLI installed"
        $state = Mark-StepDone $state "azure-cli"
    }

    # --- Docker Desktop ---
    if (Is-StepDone $state "docker") {
        Ok "Docker Desktop -- already done"
    } elseif (Test-CommandExists "docker") {
        Ok "Docker Desktop -- already installed"
        $state = Mark-StepDone $state "docker"
    } else {
        Step "Installing Docker Desktop (runs your apps in containers)..."
        Info "This may take a few minutes..."

        # Check if WSL is available -- Docker needs it
        $wslInstalled = $false
        try {
            $wslOutput = wsl --status 2>$null
            if ($LASTEXITCODE -eq 0) { $wslInstalled = $true }
        } catch {}

        if (-not $wslInstalled) {
            Step "Installing WSL 2 (required by Docker Desktop)..."
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

        winget install Docker.DockerDesktop --accept-source-agreements --accept-package-agreements 2>$null
        if ($LASTEXITCODE -ne 0) {
            Warn "winget install failed. Please install Docker Desktop from https://www.docker.com/products/docker-desktop/"
            Info "After installing, restart your computer and run this script again."
            exit 1
        }

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
        Info "Docker Desktop was just installed and needs a restart to finish setup."
        Info ""
        Info "Here's what to do:"
        Info "  1. Restart your computer"
        Info "  2. After restarting, open Docker Desktop from the Start menu"
        Info "     (wait for it to say 'Docker Desktop is running')"
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
        exit 0
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
    Banner "Step 4 of 6: Configuring Azure AI Foundry authentication"

    New-Item -ItemType Directory -Path $CLAUDE_DIR -Force | Out-Null
    $username = $env:USERNAME
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
# get-claude-token.ps1 -- Fetches Azure AI Foundry token for Claude Code
# Run "az login" in PowerShell BEFORE starting Claude Code if the token has expired.

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

    # --- Settings file ---
    if (Is-StepDone $state "settings-json") {
        Ok "Settings file -- already done"
    } else {
        # Check if settings.json already exists (user may have custom settings)
        if (Test-Path $settingsPath) {
            $existing = Get-Content $settingsPath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($existing -and $existing.apiKeyHelper) {
                Ok "Settings file already exists with apiKeyHelper configured"
                $state = Mark-StepDone $state "settings-json"
                return $state
            }
        }

        Step "Creating settings file..."
        Info "This tells Claude Code how to authenticate with Azure AI Foundry."
        Info "Using your Windows username: $username"

        $escapedPath = "C:\\Users\\$username\\.claude\\get-claude-token.ps1"
        $settingsContent = @"
{
  "apiKeyHelper": "powershell -NoProfile -ExecutionPolicy Bypass -File $escapedPath",
  "env": {
    "CLAUDE_CODE_USE_FOUNDRY": "1",
    "ANTHROPIC_FOUNDRY_BASE_URL": "https://snapistg-scus.azure.sleepnumber.com/anthropic",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "cogdep-aifoundry-dev-eus2-claude-sonnet-4-5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "cogdep-aifoundry-dev-eus2-claude-haiku-4-5",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "cogdep-aifoundry-dev-eus2-claude-opus-4-6"
  }
}
"@
        Set-Content -Path $settingsPath -Value $settingsContent -Force
        Ok "Settings file created at: $settingsPath"
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

    # Determine source: local repo or download from GitHub
    $repoDir = $null
    $tmpDir = $null
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
    $commandsPath = Join-Path (Join-Path $scriptDir ".claude") "commands"
    $makeitPath = Join-Path (Join-Path $scriptDir ".claude") "make-it"

    if ((Test-Path $commandsPath) -and (Test-Path $makeitPath)) {
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
            git clone --depth 1 --branch $GITHUB_BRANCH "https://github.com/$GITHUB_REPO.git" $cloneDest 2>$null
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

    # Copy skill files
    Step "Copying skill commands..."
    $skillCount = 0
    $cmdFiles = Get-ChildItem -Path (Join-Path (Join-Path $repoDir ".claude") "commands") -Filter "*.md" -File
    foreach ($cmdFile in $cmdFiles) {
        Copy-Item -Path $cmdFile.FullName -Destination $COMMANDS_DIR -Force
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
        Copy-Item -Path $repoVersionFile -Destination $VERSION_FILE -Force
    } else {
        Set-Content -Path $VERSION_FILE -Value "0.0.0"
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

    # Azure CLI
    if (Test-CommandExists "az") {
        Ok "Azure CLI: installed"
    } else {
        Warn "Azure CLI: NOT FOUND"
        $allGood = $false
    }

    # Docker
    if (Test-CommandExists "docker") {
        Ok "Docker: $(docker --version 2>$null)"
    } else {
        Warn "Docker: NOT FOUND (you can still use Claude Code, but /make-it builds need Docker)"
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

    # Token script
    $tokenScript = Join-Path $CLAUDE_DIR "get-claude-token.ps1"
    if (Test-Path $tokenScript) {
        Ok "Token script: $tokenScript"
    } else {
        Warn "Token script: NOT FOUND"
        $allGood = $false
    }

    # Settings file
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
        Info "  3. Run:  az login"
        Info "  4. Sign in with your corporate account in the browser"
        Info "  5. Run:  cd ~\Documents\GitHub"
        Info "  6. Run:  claude"
        Info "  7. Type: /make-it"
        Info ""
        Info "That's it! Describe your app idea and /make-it builds it for you."
        Info ""
        Info "---------------------------------------------------------------"
        Info "  YOUR DAILY WORKFLOW (every time you use Claude Code):"
        Info ""
        Info "    Set-ExecutionPolicy -Scope Process Bypass"
        Info "    az login"
        Info "    cd ~\Documents\GitHub"
        Info "    claude"
        Info "---------------------------------------------------------------"
        Info ""
        Info "  Azure tokens expire after ~1-2 hours. If Claude Code stops"
        Info "  working, close it, run 'az login' again, and restart 'claude'."
        Info ""
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

function Check-Update {
    $current = "none"
    if (Test-Path $VERSION_FILE) {
        $current = (Get-Content $VERSION_FILE -Raw).Trim()
    }

    $remote = "unknown"
    try {
        $remote = (Invoke-RestMethod -Uri "$GITHUB_RAW/VERSION" -UseBasicParsing).Trim()
    } catch {}

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

# Handle "check" argument (used by /make-it update internally)
if ($args.Count -gt 0 -and $args[0] -eq "check") {
    Check-Update
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

# Step 1: Install all software (batched, one reboot at most)
$state = Install-Software $state

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
